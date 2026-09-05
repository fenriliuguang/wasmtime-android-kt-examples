# fullscreen-surface

Fullscreen `SurfaceView` host. Consumes **Maven** `android-webgpu:0.1.2` (Dawn NativeGpu packed in the AAR). One guest wasm + one launcher per install.

## Run

`local.properties` only needs the Android SDK:

```
sdk.dir=/path/to/Android/sdk
```

```bash
# from repo root
./scripts/build-example.sh compute --install
./scripts/play-example.sh compute 30
```

Or:

```powershell
cd hosts/fullscreen-surface
.\gradlew.bat :app:installDebug "-Pexample=compute"
```

`-Pexample` (default `cube`): `cube` `border2d` `compute` `texture` `pointer` `cli` `fs` `tcp` `http-tcp`.

Needle: logcat `EXAMPLE_OK example=<name> code=<u32>`. Playbook: [`docs/012-examples-playbook.md`](../../docs/012-examples-playbook.md).

`http-tcp` uses `Linker.createWithFixtureConstructors` (guest imports HTTP request ctor). Other examples use product `Linker.create`.

## Threads

- **GpuThread:** `GpuBackends.dawn()` + `bindCanvasNativeWindow`, compile/instantiate, `callRunConcurrent`.
- **Main:** Surface + Choreographer `postGfxVsync` + touch/key → `postGfxPointer` / `postGfxKey`.

`TMPDIR` is pinned to `cacheDir` so `wasi:filesystem` preopen is app-private. Cleartext is allowed (local HTTP smoke on `127.0.0.1:18765`).
