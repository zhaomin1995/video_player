import XCTest
@testable import Awesome_Player

final class SubtitleParserTests: XCTestCase {
    func testParseBasicSRT() {
        let srt = """
        1
        00:00:01,000 --> 00:00:03,500
        Hello world

        2
        00:01:00,250 --> 00:01:02,000
        Multi
        line caption
        """
        let entries = SubtitleParser.parseSRTString(srt)
        XCTAssertEqual(entries.count, 2)

        XCTAssertEqual(entries[0].startTime, 1.0, accuracy: 0.001)
        XCTAssertEqual(entries[0].endTime, 3.5, accuracy: 0.001)
        XCTAssertEqual(entries[0].text, "Hello world")

        XCTAssertEqual(entries[1].startTime, 60.25, accuracy: 0.001)
        XCTAssertEqual(entries[1].endTime, 62.0, accuracy: 0.001)
        XCTAssertEqual(entries[1].text, "Multi\nline caption")
    }

    func testSRTStripsHTMLTags() {
        let srt = """
        1
        00:00:00,000 --> 00:00:02,000
        <i>Italic <b>bold</b></i> normal
        """
        let entries = SubtitleParser.parseSRTString(srt)
        XCTAssertEqual(entries.first?.text, "Italic bold normal",
                       "HTML tags inside SRT cues should be stripped before display")
    }

    func testSRTMalformedBlockIsSkipped() {
        // First block has wrong arrow; should not break the parser.
        let srt = """
        1
        00:00:00 -- 00:00:02
        Bad time line

        2
        00:00:05,000 --> 00:00:06,000
        Good one
        """
        let entries = SubtitleParser.parseSRTString(srt)
        XCTAssertEqual(entries.count, 1)
        XCTAssertEqual(entries.first?.text, "Good one")
    }

    func testParseVTT() {
        let vtt = """
        WEBVTT

        00:00:00.000 --> 00:00:02.000
        First

        00:00:03.500 --> 00:00:04.000
        Second
        """
        let entries = SubtitleParser.parseContent(vtt, format: "vtt")
        XCTAssertEqual(entries.count, 2)
        XCTAssertEqual(entries[0].text, "First")
        XCTAssertEqual(entries[1].startTime, 3.5, accuracy: 0.001)
    }

    func testEntriesAreSorted() {
        // Out-of-order cues in source — parser should sort by start time.
        let srt = """
        1
        00:00:10,000 --> 00:00:11,000
        Second

        2
        00:00:05,000 --> 00:00:06,000
        First
        """
        let entries = SubtitleParser.parseSRTString(srt)
        XCTAssertEqual(entries.count, 2)
        XCTAssertEqual(entries[0].text, "First")
        XCTAssertEqual(entries[1].text, "Second")
    }

    func testSubtitleManagerBinarySearchLookup() {
        // Regression for the perf fix that replaced linear scan with
        // currentIndex-probe + binary-search. Cues are deliberately many
        // (1000) so a regression to O(n) would be visible in test time.
        var srt = ""
        for i in 0..<1000 {
            let s = Double(i)
            let e = s + 0.5
            srt += """
            \(i+1)
            \(format(time: s)) --> \(format(time: e))
            cue \(i)


            """
        }
        let mgr = SubtitleManager()
        mgr.loadSubtitleFromSRTText(srt)
        XCTAssertEqual(mgr.subtitle(at: 0.0)?.text, "cue 0")
        XCTAssertEqual(mgr.subtitle(at: 500.25)?.text, "cue 500")
        XCTAssertEqual(mgr.subtitle(at: 999.4)?.text, "cue 999")
        // Between cues (gap is 0.5s starting at .5) — no result.
        XCTAssertNil(mgr.subtitle(at: 500.6))
    }

    private func format(time: Double) -> String {
        let h = Int(time / 3600)
        let m = Int(time / 60) % 60
        let s = time.truncatingRemainder(dividingBy: 60)
        return String(format: "%02d:%02d:%06.3f", h, m, s).replacingOccurrences(of: ".", with: ",")
    }

    func testParseASSDialogue() {
        let ass = """
        [Script Info]

        [V4+ Styles]
        Format: Name, Fontname, Fontsize, PrimaryColour, SecondaryColour, OutlineColour, BackColour, Bold
        Style: Default,Arial,24,&H00FFFFFF,&H000000FF,&H00000000,&H00000000,0

        [Events]
        Format: Layer, Start, End, Style, Name, MarginL, MarginR, MarginV, Effect, Text
        Dialogue: 0,0:00:01.00,0:00:03.00,Default,,0,0,0,,Hello\\Nworld
        """
        let entries = SubtitleParser.parseContent(ass, format: "ass")
        XCTAssertEqual(entries.count, 1)
        XCTAssertEqual(entries[0].text, "Hello\nworld",
                       "\\N in ASS Dialogue should become a real newline")
        XCTAssertEqual(entries[0].startTime, 1.0, accuracy: 0.01)
        XCTAssertEqual(entries[0].endTime, 3.0, accuracy: 0.01)
    }
}
