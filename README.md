# TideCam

A next-generation native camera for iPhone.

## v0.1

The first milestone is a real, usable camera foundation rather than a UI mockup.

- Native SwiftUI interface
- AVFoundation camera session
- Live camera preview
- Quality-first full-resolution photo capture
- Hardware-aware native lens presets (for example 0.5x / 1x / 2x when those cameras exist)
- Press-and-hold rapid burst capture
- Front/rear camera switching
- Tap-to-focus and exposure
- Flash Auto / On / Off
- Camera permission handling
- Photo Library saving
- Architecture ready for Pro, Detail, Night and 3D modes

## Roadmap

### v0.2 Pro
Manual ISO, shutter, focus, white balance, histogram, focus peaking and exposure tools.

### v0.3 Detail
Multi-frame capture and image-fusion experiments for higher-detail output.

### v0.4 3D
Guided spatial/object capture and reconstruction on supported devices.

### Later
Night stacking, HDR fusion, RAW workflows, recipes and advanced computational photography.

## Requirements

- iOS 17+
- Xcode 16+
- Physical iPhone recommended

> TideCam v0.1 is the foundation. Advanced computational modes will be added incrementally and capability-checked per device.

## Zoom and photo-quality improvements (v0.2 preview)

- Hardware-aware lens switches and a continuous zoom slider up to the device-supported limit (capped at 20× in this build).
- Native virtual-camera photo fusion is requested when the phone supports it.
- Optional **Zoom Enhance** for processed captures at 1.5× or higher. Uses conservative Core Image denoising and luminance sharpening, **not** a trained AI super-resolution model. It cannot restore genuine detail that the lens did not capture.
- Original source photo is preserved privately in TideLibrary whenever enhancement succeeds; the enhanced version is saved to Apple Photos. Disable Zoom Enhance to save the untouched photo directly.
- Detail mode still picks the strongest frame; its scoring now downsamples only for analysis and keeps original sensor-resolution data. It does not yet align or fuse multiple frames.
- RAW captures and rapid bursts remain unmodified.

**Testing:** Requires the iOS Simulator build in GitHub Actions and a physical iPhone for lens switching, zoom image comparisons, memory use and EXIF/orientation checks. Do not promote to TestFlight before physical-device review.

## v0.2+ Smart Fusion in Detail mode

- **SMART FUSION ON:** TideCam ranks its burst, filters blurry/exposure-mismatched frames, aligns up to four additional photos using Apple's Vision translation registration, and blends stable areas using a per-pixel motion mask. Movement and parallax are handled conservatively, not perfectly.
- **SMART FUSION OFF:** Keep the previous best-frame-only Detail workflow.
- The original, sharpest source shot is stored in private TideLibrary before a fused or zoom-enhanced derivative is saved to Apple Photos. If original backup or fusion fails, the best source is saved directly instead.
- The number of frames *actually fused* is shown in the Detail status. Requested frames and fused frames are different.
- Smart Fusion is computational denoising at original resolution. **No neural super-resolution model is included**, and results vary by scene, lighting, movement, and camera hardware.
