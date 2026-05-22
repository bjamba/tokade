import SwiftUI

/// First-run / new-town flow. Lists every repo the user has worked in
/// (detected from `UsageStore.events.cwd` → walked up to the nearest
/// project marker via `Region.projectRoot`). Type-to-filter shrinks the
/// list. Selecting a row scans the folder; "Start Town →" commits.
@MainActor
struct NewTownView: View {
    @Bindable var store: TokeyoTownStore
    @Bindable var usage: UsageStore
    var notifier: Notifier
    var onCancel: () -> Void

    @State private var query: String = ""
    @State private var selectedPath: String?
    @State private var scan: RepoScanner.ScanResult?
    @State private var scanning = false
    @State private var error: String?

    var body: some View {
        GameScreen(crtMode: notifier.crtMode) {
            VStack(alignment: .leading, spacing: 10) {
                header
                Rectangle().fill(Color(white: 0.3)).frame(height: 1)
                if discoveredRepos.isEmpty {
                    emptyState
                } else {
                    contentBody
                }
            }
            .padding(12)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var discoveredRepos: [DiscoveredRepos.Entry] {
        DiscoveredRepos.from(events: usage.events)
    }

    private var filteredRepos: [DiscoveredRepos.Entry] {
        DiscoveredRepos.filter(discoveredRepos, query: query)
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

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("No repos detected yet.")
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(.white)
            Text("Use Claude Code in a folder with a project marker (.git, Package.swift, package.json, etc.) and it'll show up here on the next refresh.")
                .font(.system(.caption2, design: .monospaced))
                .foregroundStyle(.white.opacity(0.65))
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var contentBody: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Pick a repo to theme your town after. The biome, era, and starting lushness come from the codebase. Nothing leaves your machine.")
                .font(.system(.caption2, design: .monospaced))
                .foregroundStyle(.white.opacity(0.65))
                .fixedSize(horizontal: false, vertical: true)

            filterField

            repoList

            if let error {
                Text(error)
                    .font(.system(.caption2, design: .monospaced))
                    .foregroundStyle(Color(red: 0.95, green: 0.42, blue: 0.42))
            }

            if scanning {
                HStack(spacing: 6) {
                    ProgressView().controlSize(.small)
                    Text("Scanning…")
                        .font(.system(.caption2, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.7))
                }
            } else if let scan {
                previewView(scan: scan)
            }

            Spacer(minLength: 0)
            buttonRow
        }
    }

    private var filterField: some View {
        HStack(spacing: 6) {
            Text("🔎")
                .font(.system(size: 11))
                .foregroundStyle(.white.opacity(0.6))
            TextField("filter…", text: $query)
                .textFieldStyle(.plain)
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(.white)
        }
        .padding(.horizontal, 8).padding(.vertical, 6)
        .background(Color(red: 0.10, green: 0.10, blue: 0.14))
        .overlay(Rectangle().stroke(Color(white: 0.3), lineWidth: 1))
    }

    private var repoList: some View {
        ScrollView {
            VStack(spacing: 0) {
                ForEach(filteredRepos) { entry in
                    repoRow(entry)
                }
                if filteredRepos.isEmpty {
                    Text("no matches")
                        .font(.system(.caption2, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.4))
                        .padding(.vertical, 8)
                }
            }
        }
        .frame(maxHeight: 160)
        .background(Color(red: 0.08, green: 0.08, blue: 0.12))
        .overlay(Rectangle().stroke(Color(white: 0.25), lineWidth: 1))
    }

    private func repoRow(_ entry: DiscoveredRepos.Entry) -> some View {
        let isSelected = selectedPath == entry.path
        return Button {
            select(entry)
        } label: {
            HStack(spacing: 8) {
                Text(entry.displayName)
                    .font(.system(.caption, design: .monospaced)).fontWeight(.bold)
                    .foregroundStyle(.white)
                Spacer()
                Text(shortPath(entry.path))
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.45))
                    .lineLimit(1)
                    .truncationMode(.head)
            }
            .padding(.horizontal, 8).padding(.vertical, 5)
            .background(isSelected
                ? Color(red: 0.95, green: 0.85, blue: 0.30).opacity(0.18)
                : Color.clear)
            .overlay(alignment: .leading) {
                Rectangle()
                    .fill(isSelected
                        ? Color(red: 0.95, green: 0.85, blue: 0.30)
                        : Color.clear)
                    .frame(width: 2)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func shortPath(_ p: String) -> String {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        if p.hasPrefix(home + "/") {
            return "~/" + p.dropFirst(home.count + 1)
        }
        return p
    }

    private func previewView(scan: RepoScanner.ScanResult) -> some View {
        let info = BiomeCatalog.info(scan.biome)
        return VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Circle().fill(info.groundColor).frame(width: 10, height: 10)
                    .overlay(Circle().stroke(.white.opacity(0.4), lineWidth: 0.5))
                Text(scan.displayName.uppercased())
                    .font(.system(.caption, design: .monospaced)).fontWeight(.bold)
                    .foregroundStyle(.white)
                Spacer()
                Text("\(info.displayName) · \(scan.era.rawValue)")
                    .font(.system(.caption2, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.6))
            }
            HStack(spacing: 10) {
                statChip("LOC", "\(scan.loc)")
                statChip("AGE", "\(scan.ageInDays)d")
                statChip("MAP", "\(scan.mapSize)²")
                statChip("CONTRIB", "\(scan.contributorCount)")
                statChip("LUSH", String(format: "%.0f%%", scan.lushness * 100))
            }
        }
        .padding(8)
        .background(Color(red: 0.10, green: 0.10, blue: 0.14))
        .overlay(Rectangle().stroke(Color(white: 0.25), lineWidth: 1))
    }

    private func statChip(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(label)
                .font(.system(size: 8, design: .monospaced))
                .foregroundStyle(.white.opacity(0.5))
            Text(value)
                .font(.system(.caption2, design: .monospaced))
                .foregroundStyle(.white)
        }
    }

    private var buttonRow: some View {
        HStack(spacing: 8) {
            Spacer()
            if let scan, let path = selectedPath {
                Button("Start Town →") {
                    Task {
                        await store.startNewTown(at: URL(fileURLWithPath: path), scan: scan)
                    }
                }
                .buttonStyle(.plain)
                .padding(.vertical, 6).padding(.horizontal, 12)
                .background(Color(red: 0.95, green: 0.85, blue: 0.30))
                .foregroundStyle(.black)
                .overlay(Rectangle().stroke(.black, lineWidth: 1))
                .font(.system(.caption, design: .monospaced)).fontWeight(.bold)
            }
        }
    }

    private func select(_ entry: DiscoveredRepos.Entry) {
        selectedPath = entry.path
        scan = nil
        error = nil
        scanning = true
        let url = URL(fileURLWithPath: entry.path)
        Task.detached {
            do {
                let result = try RepoScanner.scan(url)
                await MainActor.run {
                    // Guard against the user clicking another row while
                    // this scan was in flight.
                    if self.selectedPath == entry.path {
                        self.scan = result
                        self.scanning = false
                    }
                }
            } catch {
                await MainActor.run {
                    if self.selectedPath == entry.path {
                        self.error = "Couldn't scan that folder: \(error)"
                        self.scanning = false
                    }
                }
            }
        }
    }
}
