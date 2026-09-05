# First Mac build

The GitHub-side source can be built out from a phone, but Apple's compiler/signing toolchain still needs Xcode on macOS.

When a Mac is available:

1. Create a new iOS App project named `TideCam` using SwiftUI and Swift.
2. Set the deployment target to iOS 17 or later.
3. Add the existing files in `TideCam/` to the app target.
4. Add `TideCamTests/DetailProcessorTests.swift` to the test target.
5. Ensure the camera and add-only photo-library usage descriptions from `Info.plist` are present in the target.
6. Choose the Apple development team and a unique bundle identifier.
7. Run on a physical iPhone first. Camera behaviour cannot be validated meaningfully in Simulator.
8. Fix compile/API availability issues before merging PR #1.
9. Verify: permission flow, preview, tap focus, camera switching, normal photo, RAW on supported hardware, Pro ISO/focus, Detail 4/12/30-frame bursts, Photos saving, interruption/resume.
10. Once green, replace the guarded CI workflow with a fixed scheme and simulator destination.

Do not submit to TestFlight until the physical-device smoke test passes.
