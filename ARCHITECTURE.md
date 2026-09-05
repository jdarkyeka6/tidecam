# TideCam architecture

TideCam is designed as a computational capture system, not a skin over the system camera.

## Capture layer
`CameraManager` owns AVFoundation session configuration, physical camera capability detection, focus/exposure control and still capture.

## Modes
- **PHOTO**: high-quality single-frame capture.
- **PRO**: manual capture controls with RAW where the device exposes it.
- **DETAIL**: captures a locked burst and analyses frame quality. v0.1 selects the strongest source frame; alignment and fusion are the next processing milestone.
- **3D**: reserved for guided Object Capture / depth-assisted scanning on supported hardware.
- **VIDEO**: reserved for the movie capture pipeline.

## Detail pipeline
Current:
1. lock focus/exposure/white balance
2. capture 4–30 frames
3. compute exposure sanity
4. compute Laplacian sharpness score
5. reject weaker candidates by score
6. save strongest source frame
7. restore continuous camera controls

Target:
1. motion/blur rejection
2. geometric frame registration
3. local alignment
4. robust temporal denoise
5. HDR-aware fusion
6. sub-pixel reconstruction
7. optional super-resolution with an explicit reconstructed/enhanced label

## Camera recipes
Recipes are capture configurations rather than destructive filters. They can control RAW, ISO, focus and Detail burst depth. Later recipes can include shutter, white balance, exposure compensation, processing profile and preferred lens.

## Rule
TideCam must never claim generated pixels are optical detail. Reconstructed and AI-enhanced output should be labelled accurately.
