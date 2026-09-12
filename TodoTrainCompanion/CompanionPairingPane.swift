import AppKit
import SwiftUI
import TodoTrainSync

struct CompanionPairingPane: View {
    @Environment(CompanionMacRuntime.self) private var runtime

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                cueIcon
                Text(runtime.pairingCue.message)
                    .font(.headline)
                    .foregroundStyle(cueForeground)
                    .fixedSize(horizontal: false, vertical: true)
            }

            ZStack {
                CompanionCameraPreview(
                    onCode: { runtime.ingestOptical($0) },
                    isActive: runtime.pairingCameraActive,
                    scanGeneration: runtime.pairingScanGeneration
                )
                QRViewfinderFrame(color: cueFrameColor)
                    .padding(14)
                VStack {
                    Spacer()
                    if let encoded = runtime.pairingQR?.encoded {
                        CompanionQRCodeView(encoded: encoded, dimension: 148)
                    }
                }
                .padding(16)
            }
            .aspectRatio(1, contentMode: .fit)
            .frame(width: 420, height: 420)
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .strokeBorder(cueFrameColor, lineWidth: 3)
            )
            .shadow(color: cueFrameColor.opacity(runtime.pairingCue == .scanning ? 0 : 0.45), radius: 12)
        }
        .frame(width: 420)
        .onAppear { runtime.pairingUIDidAppear() }
        .onDisappear { runtime.pairingUIDidDisappear() }
        .onChange(of: runtime.pairingCue) { _, cue in
            performHaptic(cue)
        }
    }

    @ViewBuilder
    private var cueIcon: some View {
        switch runtime.pairingCue {
        case .established, .captured, .waitingPeer:
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.green)
        case .failed:
            Image(systemName: "xmark.circle.fill")
                .foregroundStyle(.red)
        case .authenticating:
            Image(systemName: "touchid")
                .foregroundStyle(Color.accentColor)
        case .scanning:
            Image(systemName: "viewfinder")
                .foregroundStyle(.secondary)
        }
    }

    private var cueForeground: Color {
        switch runtime.pairingCue {
        case .established, .captured, .waitingPeer: .green
        case .failed: .red
        default: .primary
        }
    }

    private var cueFrameColor: Color {
        switch runtime.pairingCue {
        case .established, .captured, .waitingPeer: .green
        case .failed: .red
        default: .accentColor
        }
    }

    private func performHaptic(_ cue: PairingCue) {
        let performer = NSHapticFeedbackManager.defaultPerformer
        switch cue {
        case .captured, .waitingPeer, .established, .authenticating:
            performer.perform(.generic, performanceTime: .now)
        case .failed:
            performer.perform(.alignment, performanceTime: .now)
        default:
            break
        }
    }
}
