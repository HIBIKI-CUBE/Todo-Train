//
//  TodoTrainWidgetBundle.swift
//  TodoTrainWidget
//

import SwiftUI
import WidgetKit

@main
struct TodoTrainWidgetBundle: WidgetBundle {
    var body: some Widget {
        TodoTrainHomeWidget()
        TodoTrainSessionLiveActivity()
        TodoTrainAlarmLiveActivity()
        BoardReservedRideControl()
        ContinueRideControl()
        PauseRideControl()
        ResumeRideControl()
        ArriveRideControl()
    }
}
