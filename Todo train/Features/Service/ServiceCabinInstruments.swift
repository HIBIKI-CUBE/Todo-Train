//
//  ServiceCabinInstruments.swift
//  Todo train
//
//  Shared dashboard for 運行 boot / shutdown.
//  Density is spectacle. 運行中 and occupancy are the same objects as Hub / Focus.
//

import SwiftUI

struct ServiceCabinInstruments: View {
    var lamp: ServiceCabinLamp
    var occupancyRows: [TimetableOccupancyRow]
    var occupancyMarks: [TimetableOccupancyMark]
    var dayText: String
    var clockText: String
    var statusText: String = "運行中"
    var occupancyActionTitle: String? = nil
    var occupancyAction: (() -> Void)? = nil

    var body: some View {
        VStack(spacing: 12) {
            ServiceCabinLampBank(lamp: lamp)

            HStack(spacing: 12) {
                ServiceCabinWell(powered: lamp >= .lamp, emphasis: lamp >= .lamp) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(lamp >= .lamp ? statusText : "運休")
                            .font(.system(size: 13, weight: .semibold, design: .default))
                            .tracking(3)
                            .foregroundStyle(lamp >= .lamp ? LEDPhosphor.on : FocusPanel.dim)
                        Text(dayText)
                            .font(.system(size: 22, weight: .medium, design: .default))
                            .foregroundStyle(FocusPanel.ink)
                            .minimumScaleFactor(0.7)
                            .lineLimit(1)
                    }
                }

                ServiceCabinWell(powered: lamp >= .lamp) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("時刻")
                            .font(.system(size: 11, weight: .semibold, design: .default))
                            .tracking(2)
                            .foregroundStyle(FocusPanel.dim)
                        Text(clockText)
                            .font(.system(size: 28, weight: .light, design: .default))
                            .monospacedDigit()
                            .foregroundStyle(lamp >= .lamp ? LEDPhosphor.on : FocusPanel.dim)
                            .minimumScaleFactor(0.6)
                            .lineLimit(1)
                    }
                }
                .frame(maxWidth: 148)
            }

            ServiceCabinWell(
                powered: lamp >= .occupancy,
                emphasis: lamp >= .phosphor
            ) {
                occupancy
                    .opacity(lamp >= .phosphor ? 1 : 0.55)
            }

            ServiceCabinWell(powered: lamp >= .boardReady, emphasis: lamp >= .boardReady) {
                GeometryReader { geo in
                    let width = geo.size.width
                    HubDepartLEDSign(
                        canBoard: lamp >= .boardReady,
                        ticketWidth: width,
                        ticketHeight: width * (176.0 / 300.0)
                    )
                }
                .aspectRatio(
                    300 / (176 * MarsTicketSpec.HubStack.departSignHeightRatio),
                    contentMode: .fit
                )
                .frame(maxWidth: .infinity)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(accessibilityLabel)
    }

    @ViewBuilder
    private var occupancy: some View {
        if occupancyRows.isEmpty, occupancyMarks.isEmpty {
            Text("—")
                .font(.system(size: 20, weight: .light, design: .default))
                .foregroundStyle(FocusPanel.dim)
                .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
        } else {
            VStack(alignment: .leading, spacing: 8) {
                if !occupancyMarks.isEmpty {
                    TimetableOccupancyMeter(
                        rows: [],
                        marks: occupancyMarks,
                        chrome: .cabin
                    )
                }
                ForEach(occupancyRows) { row in
                    OccupancyDestinationSign(
                        row: row,
                        surface: .cabin,
                        compact: false,
                        actionTitle: row.id == occupancyRows.first?.id ? occupancyActionTitle : nil,
                        action: row.id == occupancyRows.first?.id ? occupancyAction : nil
                    )
                }
            }
        }
    }

    private var accessibilityLabel: String {
        switch lamp {
        case .dark:
            return "機体は眠っています"
        case .lamp:
            return statusText
        case .occupancy, .phosphor:
            return "占有の計器"
        case .boardReady:
            return "発車できます"
        case .circuits:
            return "切符へ"
        }
    }
}
