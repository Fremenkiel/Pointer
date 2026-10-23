import Foundation

/// The name of a shared PDF (D-143).
enum PDFFileName {
    /// The longest name in UTF-8 bytes, with ".pdf": the name limit of APFS (`NAME_MAX`).
    static let maxBytes = 255
    private static let fileExtension = ".pdf"

    /// Returns the name of the PDF of a canvas: the title of its card, or the title of its
    /// workspace on the root canvas and for a card without a title, plus ".pdf".
    ///
    /// A slash, a colon, and a control character become "-", because file names do not allow
    /// them. A name over `maxBytes` loses characters at its end.
    ///
    /// - Returns: The name, or `nil` if no title exists.
    static func name(cardTitle: String?, workspaceTitle: String?) -> String? {
        let card = cardTitle?.trimmingCharacters(in: .whitespacesAndNewlines)
        let title = card?.isEmpty == false ? card : workspaceTitle
        guard let title, !title.isEmpty else { return nil }
        var base = String(String.UnicodeScalarView(title.unicodeScalars.map(replaced)))
        let limit = maxBytes - fileExtension.utf8.count
        // Each pass drops one character, so the title bounds the loop (FLOW-03).
        for _ in 0..<title.count where base.utf8.count > limit {
            base.removeLast()
        }
        assert(base.utf8.count <= limit, "The name fits \(maxBytes) bytes")
        return base + fileExtension
    }

    /// Returns "-" for a scalar that file names do not allow, or the scalar.
    private static func replaced(_ scalar: Unicode.Scalar) -> Unicode.Scalar {
        let isAllowed =
            scalar != "/" && scalar != ":" && scalar.properties.generalCategory != .control
        return isAllowed ? scalar : "-"
    }
}
