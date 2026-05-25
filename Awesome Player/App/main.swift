import Cocoa

VLCPlayerEngine.preload()

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate

if CommandLine.arguments.count > 1 {
    let filePath = CommandLine.arguments[1]
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
        _ = delegate.application(app, openFile: filePath)
    }
}

app.run()
