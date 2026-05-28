# Awesome PlayerTests

Initial XCTest suite for the Awesome Player app. The test files exist on disk
but the **test target is not yet registered in the Xcode project** — adding it
is a 3-click step in the Xcode UI (safer than hand-editing project.pbxproj).

## One-time setup (in Xcode)

1. Open `Awesome Player.xcodeproj`.
2. File → New → Target → **macOS / Unit Testing Bundle** → Next.
3. Settings:
   - Product Name: `Awesome PlayerTests`
   - Team / Org: same as the app target
   - Project: `Awesome Player`
   - Target to be Tested: `Awesome Player`
   - Press **Finish**.
4. Xcode will create an empty `Awesome PlayerTests/` group. Delete the
   default placeholder file it generates. **Right-click the group →
   Add Files to "Awesome Player"…** and select every `.swift` in this
   directory. Make sure "Add to targets: Awesome PlayerTests" is checked.
5. In the test target's **Build Settings**, set
   `INFOPLIST_FILE = Awesome PlayerTests/Info.plist`.
6. Cmd+U to run.

Once the target exists, the GitHub Actions workflow at
`.github/workflows/build.yml` will detect it via `xcodebuild -list` and
run the tests automatically on every push/PR.

## What's covered

| File                          | Coverage                                                |
|-------------------------------|---------------------------------------------------------|
| `DefaultsTests.swift`         | `Defaults.registerDefaults` keys, numeric ranges, namespacing |
| `KeyBindingManagerTests.swift`| Preset enumeration, `applyPreset`, modifier matching     |
| `LanguageManagerTests.swift`  | English source-key short-circuit, language round-trip    |
| `ConvertProfileTests.swift`   | `soutOption` SW vs HW emission, audio-only fallback      |
| `UpdateCheckerTests.swift`    | Auto-check disable flag, throttle window                  |
