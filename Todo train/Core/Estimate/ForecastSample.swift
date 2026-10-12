//
//  ForecastSample.swift
//  Todo train
//
//  予測の到着に入れる乗車。外した乗車の走行時間は変えない。
//

import Foundation
import TodoTrainSync

enum ForecastSample {
    static func eligible(_ rides: [EstimateHeuristic.ArrivedRide]) -> [EstimateHeuristic.ArrivedRide] {
        rides.filter {
            !ForecastExclusion.excludes(
                pauseInputSeconds: $0.pauseInputSeconds,
                activeSeconds: $0.activeSeconds
            )
        }
    }
}
