import Cocoa

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate

// Handle CLI file argument for testing (e.g. ./Awesome\ Player /path/to/video.mkv)
if CommandLine.arguments.count > 1 {
    let filePath = CommandLine.arguments[1]
    DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
        print("[main] Opening file from CLI: \(filePath)")
        _ = delegate.application(app, openFile: filePath)
    }
}

app.run()
