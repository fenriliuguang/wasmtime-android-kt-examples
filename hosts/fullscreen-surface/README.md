# fullscreen-surface

Fullscreen `SurfaceView` host. Draws whatever the loaded guest presents through `wasi-gfx` + `wasi:webgpu`.

## Run

1. Point `local.properties` at the Android SDK and a **wasmtime-android-kt** checkout (see `local.properties.example`).
2. Ensure that checkout has `android/jniLibs/**/libwasmtime_android_kt.so`.
3. Default guest is `guests/rotating-cube/dist/guest.wasm` (committed). Rebuild the cube with its `build.ps1` if you change MoonBit sources.

```powershell
cd hosts/fullscreen-surface
.\gradlew.bat :app:installDebug
```

Another guest:

```powershell
.\gradlew.bat :app:installDebug "-Pguest.wasm=..\..\guests\other\dist\guest.wasm"
```

## Threads

- **GpuThread:** `DawnWasiWebGpuHost.bindCanvasNativeWindow`, compile/instantiate, `callRunConcurrent`.
- **Main:** Surface callbacks + Choreographer `postGfxVsync` (1-slot; drops unconsumed beats).
