import LumenstreamData
import SwiftUI

/// One TWS notice: severity icon, code, message and age.
public struct NoticeRow: View {
    private let notice: ServerNotice

    public init(notice: ServerNotice) {
        self.notice = notice
    }

    public var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: LumenstreamTheme.compactSpacing) {
            Image(systemName: notice.isInformational ? "info.circle" : "exclamationmark.triangle.fill")
                .foregroundStyle(notice.isInformational ? Color.secondary : Color.orange)
                .accessibilityLabel(notice.isInformational ? "Status" : "Error")
            VStack(alignment: .leading, spacing: 2) {
                Text(notice.message)
                    .font(.subheadline)
                HStack {
                    Text(verbatim: "\(notice.code)")
                        .monospacedDigit()
                    if notice.requestID >= 0 {
                        Text("Request \(notice.requestID)")
                    }
                    Spacer()
                    Text(notice.receivedAt, style: .relative)
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

#Preview(traits: .sampleData) {
    @Previewable @Environment(LumenstreamModel.self) var model
    List(model.notices) { NoticeRow(notice: $0) }
}
