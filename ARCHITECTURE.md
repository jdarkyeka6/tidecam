# TideCam architecture

TideCam is designed as a computational capture system, not a skin over the system camera.

## Capture layer
`CameraManager` owns AVFoundation session configuration, physical camera capability detection, focus/exposure control and still capture.

## Modes
- **PHOTO**: high-quality single-frame capture.
- **PRO**: manual capture controls with RAW where the device exposes it.
- **DETAIL**: captures a locked burst, ranks frames, and optionally aligns/fuses up to 5 source frames with Vision translation alignment and motion-masked temporal denoising. It falls back to the strongest frame on motion, registration failure or storage errors.
- **3D**: reserved for guided Object Capture / depth-assisted scanning on supported hardware.
- **VIDEO**: reserved for the movie capture pipeline.

## Detail pipeline
Current:
1. lock focus/exposure/white balance
2. capture 4–30 frames
3. compute exposure sanity
4. compute Laplacian sharpness score
5. reject weaker candidates by score and exposure mismatch
6. optionally register the top candidates to the strongest frame using Vision
7. average stable regions with a per-pixel motion mask; keep original pixels in moving regions
8. save the original source in TideLibrary; save the fused derivative to Photos
9. restore continuous camera controls

Target:
1. optical-flow/local motion alignment for parallax and subject movement
2. robust colour/brightness/exposure normalisation
3. HDR-aware fusion
4. sub-pixel reconstruction
5. optional *trained* super-resolution with an explicit reconstructed/enhanced label
6. quality benchmarking on actual phones

## Camera recipes
Recipes are capture configurations rather than destructive filters. They can control RAW, ISO, focus and Detail burst depth. Later recipes can include shutter, white balance, exposure compensation, processing profile and preferred lens.

## Rule
TideCam must never claim generated pixels are optical detail. Reconstructed and AI-enhanced output should be labelled accurately.
