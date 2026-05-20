import AppKit
import SwiftUI

/// First-run / new-town flow: pick a folder, preview the scan, confirm.
@MainActor
struct NewTownView: View {
    @Bindable var store: TokeyoTownStore
    var notifier: Notifier
    var onCancel: () -> Void

    @State private var picked: URL?
    @State private var scan: RepoScanner.ScanResult?
    @State private var scanning = false
    @State private var error: String?

    var body: some View {
        GameScreen(crtMode: notifier.crtMode) {
            VStack(alignment: .leading, spacing: 12) {
                header
                Rectangle().fill(Color(white: 0.3)).frame(height: 1)

                if let scan {
                    previewView(scan: scan)
                } else if scanning {
                    HStack(spacing: 8) {
                        ProgressView().controlSize(.small)
                        Text("Scanning…")
                            .font(.system(.caption, design: .monospaced))
                            .foregroundStyle(.white.opacity(0.7))
                    }
                } else {
                    placeholderView
                }

                if let error {
                    Text(error)
                        .font(.system(.caption2, design: .monospaced))
                        .foregroundStyle(Color(red: 0.95, green: 0.42, blue: 0.42))
                }

                Spacer(minLength: 0)
                buttonRow
            }
            .padding(12)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var header: some View {
        HStack {
            Text("TOKEYO TOWN")
                .font(.system(.title3, design: .monospaced)).fontWeight(.bold)
                .foregroundStyle(Color(red: 0.95, green: 0.85, blue: 0.30))
            Spacer()
            Button("← Back") { onCancel() }
                .buttonStyle(.plain)
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(.white.opacity(0.7))
        }
    }

    private var placeholderView: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Pick a local folder. Each town is themed after a repo on your machine — the language, age, and commit cadence decide your biome and starting lushness.")
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(.white.opacity(0.8))
                .fixedSize(horizontal: false, vertical: true)
            Text("Nothing leaves your machine. The folder is read, never written to.")
                .font(.system(.caption2, design: .monospaced))
                .foregroundStyle(.white.opacity(0.5))
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func previewView(scan: RepoScanner.ScanResult) -> some View {
        let info = BiomeCatalog.info(scan.biome)
        return VStack(alignment: .leading, spacing: 6) {
            Text("PREVIEW")
                .font(.system(.caption2, design: .monospaced))
                .foregroundStyle(.white.opacity(0.5))
            HStack(spacing: 6) {
                Circle().fill(info.groundColor).frame(width: 12, height: 12)
                    .overlay(Circle().stroke(.white.opacity(0.4), lineWidth: 0.5))
                Text(scan.displayName.uppercased())
                    .font(.system(.callout, design: .monospaced)).fontWeight(.bold)
                    .foregroundStyle(.white)
            }
            row("Biome", "\(info.displayName) (\(scan.primaryLanguage))")
            row("Era", scan.era.rawValue)
            row("Age", "\(scan.ageInDays) days")
            row("LOC", "\(scan.loc)")
            row("Map", "\(scan.mapSize) × \(scan.mapSize)")
            row("Contributors", "\(scan.contributorCount)")
            row("Lushness", String(format: "%.0f%%", scan.lushness * 100))
            Text(info.blurb)
                .font(.system(.caption2, design: .monospaced))
                .foregroundStyle(.white.opacity(0.65))
                .padding(.top, 4)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(8)
        .background(Color(red: 0.10, green: 0.10, blue: 0.14))
        .overlay(Rectangle().stroke(Color(white: 0.25), lineWidth: 1))
    }

    private func row(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label.uppercased())
                .font(.system(.caption2, design: .monospaced))
                .foregroundStyle(.white.opacity(0.55))
            Spacer()
            Text(value)
                .font(.system(.caption2, design: .monospaced))
                .foregroundStyle(.white)
        }
    }

    private var buttonRow: some View {
        HStack(spacing: 8) {
            Button(picked == nil ? "Pick Folder…" : "Pick Different…") { pick() }
                .buttonStyle(.plain)
                .padding(.vertical, 6).padding(.horizontal, 10)
                .background(Color(red: 0.20, green: 0.20, blue: 0.25))
                .foregroundStyle(.white)
                .overlay(Rectangle().stroke(Color(white: 0.4), lineWidth: 1))
                .font(.system(.caption, design: .monospaced))

            if let scan, let picked {
                Button("Start Town →") {
                    Task { await store.startNewTown(at: picked, scan: scan) }
                }
                .buttonStyle(.plain)
                .padding(.vertical, 6).padding(.horizontal, 10)
                .background(Color(red: 0.95, green: 0.85, blue: 0.30))
                .foregroundStyle(.black)
                .overlay(Rectangle().stroke(.black, lineWidth: 1))
                .font(.system(.caption, design: .monospaced)).fontWeight(.bold)
            }
        }
    }

    private func pick() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.message = "Choose a local folder to theme your town after."
        guard panel.runModal() == .OK, let url = panel.url else { return }
        picked = url
        scan = nil
        error = nil
        scanning = true
        Task.detached {
            do {
                let result = try RepoScanner.scan(url)
                await MainActor.run {
                    self.scan = result
                    self.scanning = false
                }
            } catch {
                await MainActor.run {
                    self.error = "Couldn't scan that folder: \(error)"
                    self.scanning = false
                }
            }
        }
    }
}
