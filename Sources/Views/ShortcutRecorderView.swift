import SwiftUI
import AppKit

/// A minimal "click to record" control for SnapText's global capture
/// shortcut — Pro-only (see `SettingsView`). Installs a local key-down
/// monitor while recording, captures the next key combo, converts it to
/// Carbon's modifier mask via `HotKeyPreference.carbonModifiers`, and
/// hands the result back through `onRecorded`.
struct ShortcutRecorderView: View {
    @Binding var keyCode: UInt32
    @Binding var modifiers: UInt32
    var onRecorded: (UInt32, UInt32) -> Void

    @State private var isRecording = false
    @State private var monitor: Any?

    var body: some View {
        HStack(spacing: 8) {
            Text(HotKeyPreference.displayString(keyCode: keyCode, modifiers: modifiers))
                .appFont(.body, weight: .medium)
                .monospaced()
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(Color(.controlBackgroundColor))
                .cornerRadius(6)
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(isRecording ? Color.accentColor : Color.secondary.opacity(0.3), lineWidth: isRecording ? 2 : 1)
                )

            Button(isRecording ? "Press a shortcut…" : "Record") {
                isRecording ? stopRecording() : startRecording()
            }
            .buttonStyle(.bordered)

            if HotKeyPreference.isCustomized {
                Button("Reset") {
                    HotKeyPreference.resetToDefault()
                    keyCode = HotKeyPreference.defaultKeyCode
                    modifiers = HotKeyPreference.defaultModifiers
                }
                .buttonStyle(.borderless)
                .appFont(.caption)
            }
        }
        .onDisappear { stopRecording() }
    }

    private func startRecording() {
        isRecording = true
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            // Esc cancels without changing anything.
            guard event.keyCode != 53 else {
                stopRecording()
                return nil
            }
            let newModifiers = HotKeyPreference.carbonModifiers(from: event.modifierFlags)
            // Require at least one modifier — a bare letter key would
            // swallow normal typing everywhere else on the system.
            guard newModifiers != 0 else { return nil }
            let newKeyCode = UInt32(event.keyCode)
            keyCode = newKeyCode
            modifiers = newModifiers
            onRecorded(newKeyCode, newModifiers)
            stopRecording()
            return nil
        }
    }

    private func stopRecording() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        isRecording = false
    }
}
