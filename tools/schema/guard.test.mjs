import assert from "node:assert/strict";
import { test } from "node:test";
import {
  declarationsIn,
  fingerprintFromSources,
  fingerprintOf,
  frozenBodiesChanged,
  latestSchema,
  modelSources,
  readAppSchema,
  readFingerprint,
} from "./fingerprint.mjs";
import { FROZEN_CHANGED, MODEL_CHANGED, judge } from "./guard.mjs";

const v4 = { name: "AppSchemaV4", version: "4.0.0" };

const v3Source = `
@Model
final class Ticket {
    var id: UUID = UUID()
    var title: String = ""
    var estimatedSeconds: Int = 0
    var closureKind: ClosureKind? {
        get { closureKindRaw.flatMap(ClosureKind.init(rawValue:)) }
        set { closureKindRaw = newValue?.rawValue }
    }
    var isOpen: Bool { closedAt == nil }
}

@Model
final class WorkSession {
    var id: UUID = UUID()
    var startedAt: Date = Date.now
    var endedAt: Date?
    var outcomeRaw: String?
    var isOpen: Bool { endedAt == nil }
    func elapsedSeconds(at now: Date) -> TimeInterval {
        let unused = 1
        return unused
    }
}
`;

const pr71Source = `
@Model
final class Ticket {
    var id: UUID = UUID()
    var title: String = ""
    var estimatedSeconds: Int = 0
    var reservedAt: Date?
    var reservedFromRideId: UUID?
    var reservedViaRaw: String?
    var closureKind: ClosureKind? {
        get { closureKindRaw.flatMap(ClosureKind.init(rawValue:)) }
        set { closureKindRaw = newValue?.rawValue }
    }
    var isOpen: Bool { closedAt == nil }
}

@Model
final class WorkSession {
    var id: UUID = UUID()
    var startedAt: Date = Date.now
    var endedAt: Date?
    var outcomeRaw: String?
    var arrivalActionRaw: String?
    var arrivalStampedAt: Date?
    var startedFromRaw: String = RideStartOrigin.other.rawValue
    var isOpen: Bool { endedAt == nil }
    func elapsedSeconds(at now: Date) -> TimeInterval {
        let unused = 1
        return unused
    }
}
`;

function sourceFile(source) {
  return [{ path: "Models.swift", source }];
}

test("V4 の今のモデルで検査が通る", () => {
  const head = readFingerprint();
  const latest = latestSchema(readAppSchema());
  const computed = fingerprintOf();
  assert.equal(head.name, "AppSchemaV4");
  assert.equal(head.version, "4.0.0");
  assert.equal(head.fingerprint, computed);
  assert.equal(latest.name, head.name);
  assert.equal(latest.version, head.version);
  assert.deepEqual(judge({ computed, head, latest, base: null }), []);
});

test("指紋がファイルと違うと落ちる", () => {
  const errors = judge({
    computed: "ccc",
    head: { ...v4, fingerprint: "bbb" },
    latest: v4,
    base: { ...v4, fingerprint: "aaa" },
  });
  assert.deepEqual(errors, [MODEL_CHANGED]);
});

test("指紋だけを書き換えて版を上げないと落ちる", () => {
  const errors = judge({
    computed: "bbb",
    head: { ...v4, fingerprint: "bbb" },
    latest: v4,
    base: { ...v4, fingerprint: "aaa" },
  });
  assert.deepEqual(errors, [MODEL_CHANGED]);
});

test("版を上げて指紋を更新すると通る", () => {
  const errors = judge({
    computed: "bbb",
    head: { name: "AppSchemaV5", version: "5.0.0", fingerprint: "bbb" },
    latest: { name: "AppSchemaV5", version: "5.0.0" },
    base: { ...v4, fingerprint: "aaa" },
  });
  assert.deepEqual(errors, []);
});

test("base に指紋が無くても、ファイルと最新の版が合えば通る", () => {
  const errors = judge({
    computed: "aaa",
    head: { ...v4, fingerprint: "aaa" },
    latest: v4,
    base: null,
  });
  assert.deepEqual(errors, []);
});

test("PR #71 の列を V3 起点の指紋に足すと落ちる", () => {
  const origin = fingerprintFromSources(sourceFile(v3Source));
  const added = fingerprintFromSources(sourceFile(pr71Source));
  assert.notEqual(origin, added);
  const ticket = declarationsIn(pr71Source).find((model) => model.name === "Ticket");
  const session = declarationsIn(pr71Source).find((model) => model.name === "WorkSession");
  for (const name of ["reservedAt", "reservedFromRideId", "reservedViaRaw"]) {
    assert.equal(ticket.properties.some((property) => property.includes(`var ${name}:`)), true, name);
  }
  for (const name of ["arrivalActionRaw", "arrivalStampedAt", "startedFromRaw"]) {
    assert.equal(session.properties.some((property) => property.includes(`var ${name}:`)), true, name);
  }
  assert.equal(ticket.properties.some((property) => property.includes("isOpen")), false);
  const base = { name: "AppSchemaV3", version: "3.0.0", fingerprint: origin };
  const latest = { name: "AppSchemaV3", version: "3.0.0" };
  assert.deepEqual(
    judge({ computed: added, head: { ...base }, latest, base }),
    [MODEL_CHANGED],
  );
  assert.deepEqual(
    judge({
      computed: added,
      head: { ...latest, fingerprint: added },
      latest,
      base,
    }),
    [MODEL_CHANGED],
  );
  assert.deepEqual(
    judge({
      computed: added,
      head: { name: "AppSchemaV3_1", version: "3.1.0", fingerprint: added },
      latest: { name: "AppSchemaV3_1", version: "3.1.0" },
      base,
    }),
    [],
  );
});

test("格納プロパティを 1 つ足すと落ち、版を足して指紋を更新すると通る", () => {
  const sources = modelSources();
  const before = fingerprintFromSources(sources);
  const after = fingerprintFromSources(sources.map((file) => {
    if (!file.path.endsWith("Ticket.swift")) return file;
    return {
      ...file,
      source: file.source.replace(
        'var title: String = ""',
        'var title: String = ""\n    var platformNote: String = ""',
      ),
    };
  }));
  assert.notEqual(before, after);
  const base = { ...v4, fingerprint: before };
  assert.deepEqual(
    judge({ computed: after, head: base, latest: v4, base }),
    [MODEL_CHANGED],
  );
  assert.deepEqual(
    judge({
      computed: after,
      head: { name: "AppSchemaV5", version: "5.0.0", fingerprint: after },
      latest: { name: "AppSchemaV5", version: "5.0.0" },
      base,
    }),
    [],
  );
});

test("計算プロパティ・Transient・メソッドの変更では落ちない", () => {
  const sources = modelSources();
  const before = fingerprintFromSources(sources);
  const mutated = sources.map((file) => {
    if (file.path.endsWith("Ticket.swift")) {
      return {
        ...file,
        source: file.source
          .replace(
            "var isOpen: Bool { closedAt == nil }",
            "var isOpen: Bool { closedAt == nil && title.isEmpty }",
          )
          .replace("static let maxEstimatedSeconds = 3600", "static let maxEstimatedSeconds = 7200")
          .replace(
            'var title: String = ""',
            '// 題名\nvar   title:   String = ""\n    @Transient\n    var draftTitle: String = ""',
          ),
      };
    }
    if (file.path.endsWith("WorkSession.swift")) {
      return {
        ...file,
        source: file.source.replace(
          "func elapsedSeconds(at now: Date) -> TimeInterval {",
          "func elapsedSeconds(at now: Date) -> TimeInterval {\n        let marker = 1\n",
        ),
      };
    }
    return file;
  });
  const ticket = mutated.find((file) => file.path.endsWith("Ticket.swift")).source;
  const session = mutated.find((file) => file.path.endsWith("WorkSession.swift")).source;
  assert.match(ticket, /draftTitle/);
  assert.match(ticket, /maxEstimatedSeconds = 7200/);
  assert.match(ticket, /title\.isEmpty/);
  assert.match(session, /let marker = 1/);
  const ticketBefore = declarationsIn(sources.find((file) => file.path.endsWith("Ticket.swift")).source);
  const ticketAfter = declarationsIn(ticket);
  assert.deepEqual(ticketAfter, ticketBefore);
  assert.equal(fingerprintFromSources(mutated), before);
});

test("@Relationship と既定値は指紋に入る", () => {
  const sources = modelSources();
  const before = fingerprintFromSources(sources);
  const relationship = fingerprintFromSources(sources.map((file) => {
    if (!file.path.endsWith("Ticket.swift")) return file;
    return {
      ...file,
      source: file.source.replace("deleteRule: .cascade", "deleteRule: .nullify"),
    };
  }));
  const fallback = fingerprintFromSources(sources.map((file) => {
    if (!file.path.endsWith("WorkSession.swift")) return file;
    return {
      ...file,
      source: file.source.replace(
        "var startedFromRaw: String = RideStartOrigin.other.rawValue",
        'var startedFromRaw: String = ""',
      ),
    };
  }));
  assert.notEqual(relationship, before);
  assert.notEqual(fallback, before);
});

test("いまのモデルは保存される列だけを拾う", () => {
  const byName = new Map();
  for (const file of modelSources()) {
    for (const model of declarationsIn(file.source)) byName.set(model.name, model.properties);
  }
  assert.deepEqual(
    [...byName.keys()].sort(),
    [
      "PassengerRide",
      "ServiceDay",
      "SessionExtension",
      "SessionPause",
      "Tag",
      "TaskLineage",
      "Ticket",
      "TimetableBlock",
      "TimetableGuard",
      "TimetableSeriesRule",
      "WorkSession",
    ],
  );
  const ticket = byName.get("Ticket").join("\n");
  assert.match(ticket, /var reservedAt: Date\?/);
  assert.doesNotMatch(ticket, /isOpen|closureKind:|maxEstimatedSeconds|func /);
  const session = byName.get("WorkSession").join("\n");
  assert.match(session, /var arrivalActionRaw: String\?/);
  assert.match(session, /var arrivalStampedAt: Date\?/);
  assert.match(session, /var startedFromRaw: String = RideStartOrigin\.other\.rawValue/);
  assert.match(session, /var nudgeFiredStagesRaw: \[String\] = \[\]/);
  assert.doesNotMatch(session, /isOpen|elapsedSeconds|func /);
  assert.match(byName.get("SessionPause").join("\n"), /var heldByRaw: String\?/);
});

test("凍結した版の型を書き換えると落ちる", () => {
  const source = readAppSchema();
  assert.equal(frozenBodiesChanged(source, source), false);

  const color = source.replace(
    'var colorHex: String = "#888888"',
    'var colorHex: String = "#000000"',
  );
  assert.notEqual(color, source);
  assert.equal(frozenBodiesChanged(source, color), true);

  const v31 = source.replace(
    "var startedFromRaw: String = RideStartOrigin.other.rawValue",
    'var startedFromRaw: String = ""',
  );
  assert.notEqual(v31, source);
  assert.equal(frozenBodiesChanged(source, v31), true);

  const v1 = source.replace("Schema.Version(1, 0, 0)", "Schema.Version(1, 0, 1)");
  assert.equal(frozenBodiesChanged(source, v1), true);

  const current = source.replace(
    "enum AppSchemaV4: VersionedSchema {\n    static var versionIdentifier: Schema.Version { Schema.Version(4, 0, 0) }",
    "enum AppSchemaV4: VersionedSchema {\n    static var versionIdentifier: Schema.Version { Schema.Version(4, 0, 0) } // x",
  );
  assert.notEqual(current, source);
  assert.equal(frozenBodiesChanged(source, current), false);

  const migration = source.replace(
    "予約と検札の列を足す。既定値があるので軽量で足りる。",
    "予約と検札の列を足す。",
  );
  assert.notEqual(migration, source);
  assert.equal(frozenBodiesChanged(source, migration), false);

  const head = { ...v4, fingerprint: "aaa" };
  assert.deepEqual(
    judge({ computed: "aaa", head, latest: v4, base: head, frozenChanged: true }),
    [FROZEN_CHANGED],
  );
  assert.deepEqual(
    judge({ computed: "bbb", head, latest: v4, base: head, frozenChanged: true }),
    [MODEL_CHANGED, FROZEN_CHANGED],
  );
});

test("指紋の計算は 1 秒以内", () => {
  const start = Date.now();
  for (let i = 0; i < 20; i += 1) fingerprintOf();
  assert.ok(Date.now() - start < 1000);
});
