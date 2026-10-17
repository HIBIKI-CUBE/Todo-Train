#!/usr/bin/env python3
"""Leave-one-out errors from a todotrain.pdca.v0 export.

Uses only the export. Titles and tag names are not in the file.
Eligible rides are arrived, at least 60 active seconds, and not
excludedFromForecast. For each eligible ride, priors are eligible rides
that started earlier (same start time breaks ties by ride id).

Estimators:
  global median of prior active seconds
  median of priors that share at least one tag id
  median of the first 3 and first 5 similarityCandidates (device order)
  the   rider's estimatedSecondsAtStart
  the latest committed reestimate on the ride (judgment estimate)

Usage:
  python3 tools/pdca/leave_one_out.py export.json
  python3 tools/pdca/leave_one_out.py --self-test
"""

from __future__ import annotations

import json
import sys
from pathlib import Path

MIN_ACTIVE_SECONDS = 60


def median(values: list[float]) -> float | None:
    if not values:
        return None
    ordered = sorted(values)
    mid = len(ordered) // 2
    if len(ordered) % 2 == 0:
        return (ordered[mid - 1] + ordered[mid]) / 2
    return ordered[mid]


def is_prior(candidate: dict, subject: dict) -> bool:
    if candidate["id"] == subject["id"]:
        return False
    if candidate["startedAt"] != subject["startedAt"]:
        return candidate["startedAt"] < subject["startedAt"]
    return candidate["id"] < subject["id"]


def eligible(ride: dict) -> bool:
    if ride.get("outcome") != "arrived":
        return False
    active = ride.get("accumulatedActiveSeconds")
    if not isinstance(active, (int, float)) or active < MIN_ACTIVE_SECONDS:
        return False
    return ride.get("excludedFromForecast") is False


def load_rides(document: dict) -> list[dict]:
    rides = document.get("rides")
    if not isinstance(rides, list):
        raise SystemExit("rides が配列ではない")
    by_ride: dict[str, list[dict]] = {}
    for row in document.get("reestimates") or []:
        if not isinstance(row, dict):
            continue
        ride_id = row.get("rideId")
        if isinstance(ride_id, str):
            by_ride.setdefault(ride_id, []).append(row)
    enriched = []
    for ride in rides:
        if not isinstance(ride, dict) or "id" not in ride:
            continue
        copy = dict(ride)
        copy["reestimates"] = by_ride.get(ride["id"], [])
        enriched.append(copy)
    return enriched


def errors_for(rides: list[dict]) -> dict[str, list[float]]:
    by_id = {ride["id"]: ride for ride in rides if "id" in ride}
    pool = [ride for ride in rides if eligible(ride)]
    named = {
        "global": [],
        "tag": [],
        "top3": [],
        "top5": [],
        "rider": [],
        "judgment": [],
    }
    for subject in pool:
        actual = float(subject["accumulatedActiveSeconds"])
        priors = [ride for ride in pool if is_prior(ride, subject)]
        prior_seconds = [float(ride["accumulatedActiveSeconds"]) for ride in priors]
        if (value := median(prior_seconds)) is not None:
            named["global"].append(abs(value - actual))

        tags = set(subject.get("tagIds") or [])
        if tags:
            tagged = [
                float(ride["accumulatedActiveSeconds"])
                for ride in priors
                if tags.intersection(ride.get("tagIds") or [])
            ]
            if (value := median(tagged)) is not None:
                named["tag"].append(abs(value - actual))

        candidates = subject.get("similarityCandidates") or []
        candidate_seconds = []
        for candidate in candidates:
            ride_id = candidate.get("rideId")
            source = by_id.get(ride_id)
            if source is None or not eligible(source):
                continue
            active = source.get("accumulatedActiveSeconds")
            if isinstance(active, (int, float)):
                candidate_seconds.append(float(active))
        if (value := median(candidate_seconds[:3])) is not None:
            named["top3"].append(abs(value - actual))
        if (value := median(candidate_seconds[:5])) is not None:
            named["top5"].append(abs(value - actual))

        estimate = subject.get("estimatedSecondsAtStart")
        if isinstance(estimate, (int, float)):
            named["rider"].append(abs(float(estimate) - actual))

        judgment = judgment_estimate_seconds(subject)
        if judgment is not None:
            named["judgment"].append(abs(judgment - actual))
    return named


def judgment_estimate_seconds(ride: dict) -> float | None:
    """Active + last committed reestimate remaining; else estimatedSecondsAtStart."""
    reestimates = ride.get("reestimates") or []
    committed = [
        item
        for item in reestimates
        if isinstance(item, dict) and not item.get("undoneAt")
    ]
    if committed:
        last = max(committed, key=lambda item: item.get("committedAt", ""))
        active = last.get("activeSeconds")
        remaining = last.get("committedRemainingSeconds")
        if isinstance(active, (int, float)) and isinstance(remaining, (int, float)):
            return float(active) + float(remaining)
    estimate = ride.get("estimatedSecondsAtStart")
    if isinstance(estimate, (int, float)):
        return float(estimate)
    return None


def summarize(samples: list[float]) -> tuple[float | None, float | None, int]:
    if not samples:
        return None, None, 0
    mae = sum(samples) / len(samples) / 60
    med = (median(samples) or 0) / 60
    return mae, med, len(samples)


def format_report(named: dict[str, list[float]]) -> str:
    labels = [
        ("global", "全体の中央値"),
        ("tag", "タグで絞った中央値"),
        ("top3", "上位3件の中央値"),
        ("top5", "上位5件の中央値"),
        ("rider", "乗務員の見積もり"),
        ("judgment", "判定に使った見積もり"),
    ]
    lines = ["誤差は分。件数は、その推定が計算できた乗車。", ""]
    lines.append(f"{'推定':<16}{'平均誤差':>10}{'中央誤差':>10}{'件数':>8}")
    for key, label in labels:
        mae, med, count = summarize(named[key])
        mae_text = "—" if mae is None else f"{mae:.1f}"
        med_text = "—" if med is None else f"{med:.1f}"
        lines.append(f"{label:<16}{mae_text:>10}{med_text:>10}{count:>8}")
    return "\n".join(lines)


def self_test() -> None:
    rides = [
        {
            "id": "a",
            "startedAt": "2026-01-05T09:00:00+09:00",
            "outcome": "arrived",
            "accumulatedActiveSeconds": 600,
            "estimatedSecondsAtStart": 600,
            "excludedFromForecast": False,
            "tagIds": ["t1"],
            "similarityCandidates": [],
        },
        {
            "id": "b",
            "startedAt": "2026-01-05T10:00:00+09:00",
            "outcome": "arrived",
            "accumulatedActiveSeconds": 1200,
            "estimatedSecondsAtStart": 900,
            "excludedFromForecast": False,
            "tagIds": ["t1"],
            "similarityCandidates": [{"rideId": "a", "score": 1}],
        },
        {
            "id": "c",
            "startedAt": "2026-01-05T11:00:00+09:00",
            "outcome": "arrived",
            "accumulatedActiveSeconds": 1800,
            "estimatedSecondsAtStart": 1800,
            "excludedFromForecast": False,
            "tagIds": ["t2"],
            "similarityCandidates": [
                {"rideId": "b", "score": 0.4},
                {"rideId": "a", "score": 0.2},
            ],
        },
        {
            "id": "short",
            "startedAt": "2026-01-05T08:00:00+09:00",
            "outcome": "arrived",
            "accumulatedActiveSeconds": 30,
            "estimatedSecondsAtStart": 30,
            "excludedFromForecast": False,
            "tagIds": ["t1"],
            "similarityCandidates": [],
        },
    ]
    named = errors_for(rides)
    # b: |600-1200|=600, c: |900-1800|=900 → mean 750s = 12.5 min
    mae, med, count = summarize(named["global"])
    assert count == 2, count
    assert mae == 12.5, mae
    # tag only for b (c shares no tag): |600-1200|=600 → 10 min
    mae, _, count = summarize(named["tag"])
    assert count == 1, count
    assert mae == 10, mae
    # top3: b uses a (600), c uses b then a → median 900
    mae, _, count = summarize(named["top3"])
    assert count == 2, count
    assert mae == 12.5, mae
    # rider: b |900-1200|=300, c 0, a 0 → mean 100s
    mae, _, count = summarize(named["rider"])
    assert count == 3, count
    assert abs(mae - (100 / 60)) < 1e-9, mae
    print("self-test ok")


def main(argv: list[str]) -> None:
    if len(argv) == 2 and argv[1] == "--self-test":
        self_test()
        return
    if len(argv) != 2:
        raise SystemExit("使い方: python3 tools/pdca/leave_one_out.py export.json")
    document = json.loads(Path(argv[1]).read_text())
    if document.get("schema") != "todotrain.pdca.v0":
        raise SystemExit(f"schema が todotrain.pdca.v0 ではない: {document.get('schema')}")
    print(format_report(errors_for(load_rides(document))))


if __name__ == "__main__":
    main(sys.argv)
