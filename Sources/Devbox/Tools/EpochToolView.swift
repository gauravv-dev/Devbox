import Foundation
import SwiftUI

/// Unix timestamp converter: live "now" clock plus Epoch → Date and Date → Epoch panels.
struct EpochToolView: View {
    @State private var epochInput = ""
    @State private var pickerDate = Date()
    @State private var useUTC = false

    var body: some View {
        ToolContainer(title: "Epoch", subtitle: "Unix timestamp ⇄ date converter — values above 1e11 are treated as milliseconds") {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    nowSection
                    Divider()
                    epochToDateSection
                    Divider()
                    dateToEpochSection
                }
                .padding(.vertical, 4)
            }
        }
    }

    // MARK: - Now

    private var nowSection: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            let seconds = Int64(context.date.timeIntervalSince1970)
            HStack(spacing: 12) {
                Text("Now")
                    .font(.headline)
                Text("\(seconds)")
                    .font(.system(.body, design: .monospaced))
                    .textSelection(.enabled)
                Text("s")
                    .foregroundStyle(.secondary)
                Text("\(seconds * 1000)")
                    .font(.system(.body, design: .monospaced))
                    .textSelection(.enabled)
                Text("ms")
                    .foregroundStyle(.secondary)
                Spacer(minLength: 8)
                CopyButton(text: { "\(seconds)" }, label: "Copy seconds")
                CopyButton(text: { "\(seconds * 1000)" }, label: "Copy ms")
            }
        }
    }

    // MARK: - Epoch → Date

    private var epochToDateSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            PaneHeader(title: "Epoch → Date") { EmptyView() }
            HStack(spacing: 8) {
                TextField("Timestamp, e.g. 1700000000", text: $epochInput)
                    .textFieldStyle(.roundedBorder)
                    .frame(maxWidth: 280)
                if !epochInput.isEmpty {
                    ToolButton(title: "Clear", systemImage: "xmark.circle") {
                        epochInput = ""
                    }
                }
            }
            if let error = epochError {
                StatusBadge(message: error, isError: true)
            } else if let conversion = epochConversion {
                VStack(alignment: .leading, spacing: 6) {
                    resultRow("Local", conversion.local)
                    resultRow("UTC", conversion.utc)
                    resultRow("ISO 8601", conversion.iso8601)
                    resultRow("Relative", conversion.relative)
                }
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.gray.opacity(0.08))
                .clipShape(RoundedRectangle(cornerRadius: 6))
            }
        }
    }

    // MARK: - Date → Epoch

    private var dateToEpochSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            PaneHeader(title: "Date → Epoch") { EmptyView() }
            HStack(spacing: 12) {
                DatePicker("Date", selection: $pickerDate,
                           displayedComponents: [.date, .hourAndMinute])
                    .environment(\.timeZone, useUTC ? TimeZone(identifier: "UTC")! : .current)
                    .labelsHidden()
                Toggle("UTC", isOn: $useUTC)
            }
            VStack(alignment: .leading, spacing: 6) {
                let seconds = Int64(pickerDate.timeIntervalSince1970)
                resultRow("Seconds", "\(seconds)")
                resultRow("Milliseconds", "\(seconds * 1000)")
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.gray.opacity(0.08))
            .clipShape(RoundedRectangle(cornerRadius: 6))
            Text(useUTC
                 ? "The picker is read as UTC wall-clock time."
                 : "The picker is read as local time (system time zone).")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private func resultRow(_ label: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(label)
                .foregroundStyle(.secondary)
                .frame(width: 84, alignment: .leading)
            Text(value)
                .font(.system(.body, design: .monospaced))
                .textSelection(.enabled)
                .lineLimit(1)
                .truncationMode(.tail)
            Spacer(minLength: 8)
            CopyButton(text: { value })
        }
    }

    // MARK: - Epoch parsing

    private struct EpochConversion {
        let local: String
        let utc: String
        let iso8601: String
        let relative: String
    }

    /// Error message for invalid epoch input, nil when empty or parseable.
    private var epochError: String? {
        let trimmed = epochInput.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return nil }
        guard Int64(trimmed) != nil else {
            return "Invalid timestamp — enter an integer (values above 1e11 are read as milliseconds)."
        }
        return nil
    }

    /// Parses the epoch input. Empty or invalid → nil; values above 1e11 are treated as milliseconds.
    private var epochConversion: EpochConversion? {
        let trimmed = epochInput.trimmingCharacters(in: .whitespaces)
        guard let value = Int64(trimmed) else { return nil }
        let isMilliseconds = Double(value) > 1e11
        let seconds = isMilliseconds ? Double(value) / 1000 : Double(value)
        let date = Date(timeIntervalSince1970: seconds)
        let fractional = seconds - floor(seconds)

        let localFormatter = DateFormatter()
        localFormatter.dateFormat = "yyyy-MM-dd HH:mm:ss zzz"
        localFormatter.timeZone = .current
        let localString = localFormatter.string(from: date)

        let utcFormatter = DateFormatter()
        utcFormatter.dateFormat = "yyyy-MM-dd HH:mm:ss zzz"
        utcFormatter.timeZone = TimeZone(identifier: "UTC")
        let utcString = utcFormatter.string(from: date)

        let isoFormatter = ISO8601DateFormatter()
        isoFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        isoFormatter.timeZone = TimeZone(identifier: "UTC")
        var isoString = isoFormatter.string(from: date)
        if fractional == 0 { isoString = isoString.replacingOccurrences(of: ".000", with: "") }

        let relative = Self.relativeFormatter.localizedString(for: date, relativeTo: Date())

        return EpochConversion(local: localString,
                               utc: utcString,
                               iso8601: isoString,
                               relative: relative + (isMilliseconds ? " (input read as milliseconds)" : ""))
    }

    private static let relativeFormatter: RelativeDateTimeFormatter = {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .full
        return formatter
    }()
}
