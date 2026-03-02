import Foundation

nonisolated protocol SessionSummaryParsing {
    func parse(
        _ url: URL,
        archived: Bool,
        modifiedAt: Date,
        fileSizeBytes: Int64
    ) -> SessionFileSummary
}
