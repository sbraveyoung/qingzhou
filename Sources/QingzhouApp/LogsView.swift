import SwiftUI
import QingzhouLogging

public struct LogsView: View {
    @Bindable var state: AppState
    @State private var keyword: String = ""
    @State private var level: LogLevel = .all
    @State private var entries: [LogEntry] = []

    public init(state: AppState) { self.state = state }

    public var body: some View {
        VStack(spacing: 0) {
            HStack {
                Picker("级别", selection: $level) {
                    ForEach(LogLevel.allCases, id: \.self) { l in
                        Text(l.rawValue).tag(l)
                    }
                }
                .pickerStyle(.segmented)
            }
            .padding(.horizontal)

            List(entries) { entry in
                VStack(alignment: .leading, spacing: 2) {
                    HStack {
                        Text(entry.level.rawValue)
                            .font(.caption2.monospaced())
                            .foregroundStyle(color(for: entry.level))
                        Text(entry.category)
                            .font(.caption2.monospaced())
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text(entry.timestamp, style: .time)
                            .font(.caption2.monospaced())
                            .foregroundStyle(.secondary)
                    }
                    Text(entry.message).font(.system(.caption, design: .monospaced))
                }
            }
        }
        .navigationTitle("日志")
        .searchable(text: $keyword)
        .onAppear { refresh() }
        .onChange(of: keyword) { _, _ in refresh() }
        .onChange(of: level) { _, _ in refresh() }
    }

    private func refresh() {
        entries = state.logger.search(level: level, keyword: keyword).reversed()
    }

    private func color(for level: LogLevel) -> Color {
        switch level {
        case .error: return .red
        case .warn:  return .orange
        case .info:  return .primary
        case .debug: return .secondary
        case .all:   return .secondary
        }
    }
}
