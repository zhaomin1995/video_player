import Cocoa

struct SubtitleEntry {
    let startTime: TimeInterval
    let endTime: TimeInterval
    let text: String
    let attributedText: NSAttributedString?
}

class SubtitleParser {
    static func parse(url: URL) -> [SubtitleEntry] {
        let ext = url.pathExtension.lowercased()
        guard let content = try? String(contentsOf: url, encoding: .utf8) else {
            if let data = try? Data(contentsOf: url) {
                if let str = String(data: data, encoding: .isoLatin1) {
                    return parseContent(str, format: ext)
                }
            }
            return []
        }
        return parseContent(content, format: ext)
    }

    static func parseSRTString(_ content: String) -> [SubtitleEntry] {
        return parseSRT(content)
    }

    static func parseContent(_ content: String, format: String) -> [SubtitleEntry] {
        switch format {
        case "srt":
            return parseSRT(content)
        case "vtt", "webvtt":
            return parseVTT(content)
        case "ass", "ssa":
            return parseASS(content)
        default:
            return []
        }
    }

    // MARK: - SRT Parser

    private static func parseSRT(_ content: String) -> [SubtitleEntry] {
        var entries: [SubtitleEntry] = []
        let blocks = content.components(separatedBy: "\n\n")

        for block in blocks {
            let lines = block.trimmingCharacters(in: .whitespacesAndNewlines).components(separatedBy: "\n")
            guard lines.count >= 3 else { continue }

            let timeLine = lines[1]
            guard let (start, end) = parseSRTTimeLine(timeLine) else { continue }

            let text = lines[2...].joined(separator: "\n")
                .replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)

            entries.append(SubtitleEntry(startTime: start, endTime: end, text: text, attributedText: nil))
        }

        return entries.sorted { $0.startTime < $1.startTime }
    }

    private static func parseSRTTimeLine(_ line: String) -> (TimeInterval, TimeInterval)? {
        let parts = line.components(separatedBy: " --> ")
        guard parts.count == 2 else { return nil }
        guard let start = parseSRTTime(parts[0].trimmingCharacters(in: .whitespaces)),
              let end = parseSRTTime(parts[1].trimmingCharacters(in: .whitespaces).components(separatedBy: " ").first ?? "") else {
            return nil
        }
        return (start, end)
    }

    private static func parseSRTTime(_ str: String) -> TimeInterval? {
        let clean = str.replacingOccurrences(of: ",", with: ".")
        let parts = clean.components(separatedBy: ":")
        guard parts.count == 3 else { return nil }
        guard let hours = Double(parts[0]),
              let minutes = Double(parts[1]),
              let seconds = Double(parts[2]) else { return nil }
        return hours * 3600 + minutes * 60 + seconds
    }

    // MARK: - WebVTT Parser

    private static func parseVTT(_ content: String) -> [SubtitleEntry] {
        var entries: [SubtitleEntry] = []
        let lines = content.components(separatedBy: "\n")
        var i = 0

        while i < lines.count {
            if lines[i].contains("-->") {
                guard let (start, end) = parseSRTTimeLine(lines[i]) else {
                    i += 1
                    continue
                }

                var textLines: [String] = []
                i += 1
                while i < lines.count && !lines[i].trimmingCharacters(in: .whitespaces).isEmpty {
                    textLines.append(lines[i])
                    i += 1
                }

                let text = textLines.joined(separator: "\n")
                    .replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)

                entries.append(SubtitleEntry(startTime: start, endTime: end, text: text, attributedText: nil))
            } else {
                i += 1
            }
        }

        return entries.sorted { $0.startTime < $1.startTime }
    }

    // MARK: - ASS/SSA Parser

    private static var assStyles: [String: ASSStyle] = [:]

    struct ASSStyle {
        var fontName: String = ""
        var fontSize: CGFloat = 24
        var primaryColor: NSColor = .white
        var bold: Bool = false
        var italic: Bool = false
    }

    private static func parseASSStyles(_ content: String) {
        assStyles.removeAll()
        let lines = content.components(separatedBy: "\n")
        var inStyles = false

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.hasPrefix("[V4+ Styles]") || trimmed.hasPrefix("[V4 Styles]") {
                inStyles = true; continue
            }
            if trimmed.hasPrefix("[") { inStyles = false; continue }
            if !inStyles || !trimmed.hasPrefix("Style:") { continue }

            let fields = trimmed.dropFirst("Style:".count).components(separatedBy: ",")
            guard fields.count >= 7 else { continue }
            let name = fields[0].trimmingCharacters(in: .whitespaces)
            var style = ASSStyle()
            style.fontName = fields[1].trimmingCharacters(in: .whitespaces)
            style.fontSize = CGFloat(Double(fields[2].trimmingCharacters(in: .whitespaces)) ?? 24)
            style.primaryColor = parseASSColor(fields[3].trimmingCharacters(in: .whitespaces))
            style.bold = fields[6].trimmingCharacters(in: .whitespaces) == "-1"
            style.italic = fields.count > 7 && fields[7].trimmingCharacters(in: .whitespaces) == "-1"
            assStyles[name] = style
        }
    }

    private static func parseASSColor(_ str: String) -> NSColor {
        var hex = str.replacingOccurrences(of: "&H", with: "").replacingOccurrences(of: "&", with: "")
        while hex.count < 8 { hex = "0" + hex }
        // ASS color format: &HAABBGGRR (alpha, blue, green, red)
        guard let val = UInt64(hex, radix: 16) else { return .white }
        let r = CGFloat(val & 0xFF) / 255.0
        let g = CGFloat((val >> 8) & 0xFF) / 255.0
        let b = CGFloat((val >> 16) & 0xFF) / 255.0
        return NSColor(red: r, green: g, blue: b, alpha: 1.0)
    }

    private static func parseASS(_ content: String) -> [SubtitleEntry] {
        parseASSStyles(content)

        var entries: [SubtitleEntry] = []
        let lines = content.components(separatedBy: "\n")

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard trimmed.hasPrefix("Dialogue:") else { continue }

            let parts = trimmed.dropFirst("Dialogue:".count).trimmingCharacters(in: .whitespaces)
            let fields = parts.components(separatedBy: ",")
            guard fields.count >= 10 else { continue }

            guard let start = parseASSTime(fields[1].trimmingCharacters(in: .whitespaces)),
                  let end = parseASSTime(fields[2].trimmingCharacters(in: .whitespaces)) else {
                continue
            }

            let styleName = fields[3].trimmingCharacters(in: .whitespaces)
            let rawText = fields[9...].joined(separator: ",")
                .replacingOccurrences(of: "\\N", with: "\n")
                .replacingOccurrences(of: "\\n", with: "\n")

            let plainText = rawText.replacingOccurrences(of: "\\{[^}]*\\}", with: "", options: .regularExpression)
            let attributed = buildAttributedString(rawText, styleName: styleName)

            entries.append(SubtitleEntry(startTime: start, endTime: end, text: plainText, attributedText: attributed))
        }

        return entries.sorted { $0.startTime < $1.startTime }
    }

    private static func buildAttributedString(_ rawText: String, styleName: String) -> NSAttributedString {
        let style = assStyles[styleName] ?? ASSStyle()
        let cleanText = rawText.replacingOccurrences(of: "\\{[^}]*\\}", with: "", options: .regularExpression)

        var traits: NSFontDescriptor.SymbolicTraits = []
        if style.bold { traits.insert(.bold) }
        if style.italic { traits.insert(.italic) }

        let baseFont: NSFont
        if !style.fontName.isEmpty, let f = NSFont(name: style.fontName, size: style.fontSize) {
            baseFont = f
        } else {
            baseFont = .systemFont(ofSize: style.fontSize, weight: style.bold ? .bold : .regular)
        }

        let descriptor = baseFont.fontDescriptor.withSymbolicTraits(traits)
        let font = NSFont(descriptor: descriptor, size: style.fontSize) ?? baseFont

        let attrs: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: style.primaryColor,
        ]
        return NSAttributedString(string: cleanText, attributes: attrs)
    }

    private static func parseASSTime(_ str: String) -> TimeInterval? {
        let parts = str.components(separatedBy: ":")
        guard parts.count == 3 else { return nil }
        guard let hours = Double(parts[0]),
              let minutes = Double(parts[1]),
              let seconds = Double(parts[2]) else { return nil }
        return hours * 3600 + minutes * 60 + seconds
    }
}
