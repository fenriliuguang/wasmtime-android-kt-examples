# wasmtime-android-kt-examples

Out-of-tree demos for [wasmtime-android-kt](https://github.com/fenriliuguang/wasmtime-android-kt) (`0.1.0` product subset). This repo is the P010-DEMO linked example: **guest wasm → Android runtime → present**.

`:smoke-app` in the runtime repo is instruments, not this demo.

## Layout

```
hosts/     Android host apps (Surface, later other shells)
guests/    Wasm component guests (any language that can target the contract)
docs/      Guest-side notes (MoonBit trig, androidx leak report)
```

Any host can pair with any guest. Hosts load `assets/guest.wasm`. Override the guest when assembling the APK:

```powershell
cd hosts/fullscreen-surface
.\gradlew.bat :app:installDebug "-Pguest.wasm=D:\path\to\other-guest\dist\guest.wasm"
```

Default guest for `fullscreen-surface` is `guests/rotating-cube/dist/guest.wasm`.

## Guest contract

Guests should:

1. Export `run: async func() -> u32` (host calls `Instance.callRunConcurrent`).
2. Import only what they need. The first cube guest uses:
   - `wasi:webgpu/webgpu@0.3.0-rc.2`
   - `wasi-gfx:surface/surface@0.2.0`
   - `wasi-gfx:surface/surface-webgpu@0.2.0`

A CLI-only guest that just returns from `run` can still be loaded by a Surface host (the GPU/vsync wiring stays unused).

## First pair

| Role | Example | What it does |
|------|---------|----------------|
| Host | [`hosts/fullscreen-surface`](hosts/fullscreen-surface) | Fullscreen `SurfaceView`; NativeGpu + Choreographer vsync on GpuThread |
| Guest | [`guests/rotating-cube`](guests/rotating-cube) | MoonBit translating cube + ticks (`wasi:webgpu` + `wasi-gfx`) |
| Guest | [`guests/boundary-2d`](guests/boundary-2d) | MoonBit 2D square looping the screen border |

## Runtime dependency

Hosts `includeBuild` a local **wasmtime-android-kt** checkout (Maven Central may not have a press yet). Set in `hosts/*/local.properties`:

```
sdk.dir=...
wasmtime.android.kt.dir=C:/path/to/wasmtime-android-kt
```

Native `libwasmtime_android_kt.so` must already exist under that checkout’s `android/jniLibs/` (see the runtime `scripts/build-native-android.ps1`).

Coordinate: `io.github.fenriliuguang.wasmtime.android:android-webgpu:0.2.0` (`GpuBackends.dawn()` = NativeGpu).

## License

Apache-2.0, matching the runtime.
