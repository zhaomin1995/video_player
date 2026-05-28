import XCTest
@testable import Awesome_Player

final class ConvertProfileTests: XCTestCase {
    func testSoftwareEncoderProducesNoVencHint() {
        let p = ConvertProfile(name: "test", videoCodec: "h264", audioCodec: "mp3",
                               container: "mp4", fileExtension: "mp4")
        let s = p.soutOption(outputPath: "/tmp/out.mp4", useHardwareEncoder: false)
        XCTAssertTrue(s.contains("vcodec=h264"))
        XCTAssertFalse(s.contains("venc="), "Software path must not emit a venc= override")
        XCTAssertTrue(s.contains("mux=mp4"))
        XCTAssertTrue(s.contains("dst=/tmp/out.mp4"))
    }

    func testHardwareEncoderEmitsVideoToolboxForH264() {
        let p = ConvertProfile(name: "test", videoCodec: "h264", audioCodec: "mp3",
                               container: "mp4", fileExtension: "mp4")
        let s = p.soutOption(outputPath: "/tmp/out.mp4", useHardwareEncoder: true)
        XCTAssertTrue(s.contains("venc=avcodec{codec=h264_videotoolbox}"),
                      "Got: \(s)")
    }

    func testHardwareEncoderFallsBackForUnsupportedCodec() {
        // VP80 has no VideoToolbox bridge — silently fall back to software.
        let p = ConvertProfile(name: "test", videoCodec: "VP80", audioCodec: "vorb",
                               container: "webm", fileExtension: "webm")
        let s = p.soutOption(outputPath: "/tmp/out.webm", useHardwareEncoder: true)
        XCTAssertFalse(s.contains("venc="),
                       "VP80 should not emit a VT encoder hint; sout: \(s)")
    }

    func testAudioOnlyProfileEmitsVcodecNone() {
        let p = ConvertProfile(name: "audio", videoCodec: nil, audioCodec: "flac",
                               container: "raw", fileExtension: "flac")
        let s = p.soutOption(outputPath: "/tmp/out.flac", useHardwareEncoder: true)
        XCTAssertTrue(s.contains("vcodec=none"))
        XCTAssertFalse(s.contains("venc="))
    }
}
