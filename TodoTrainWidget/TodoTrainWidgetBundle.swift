//
//  TodoTrainWidgetBundle.swift
//  TodoTrainWidget
//
//  AlarmKit countdown Live Activity only (home screen widget is a follow-up).
//

import SwiftUI
import WidgetKit

@main
struct TodoTrainWidgetBundle: WidgetBundle {
    var body: some Widget {
        TodoTrainAlarmLiveActivity()
    }
}
