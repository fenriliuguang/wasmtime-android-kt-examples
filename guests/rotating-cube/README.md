# rotating-cube

MoonBit guest: a continuously rotating colorful cube using **`wasi:webgpu`** and **`wasi-gfx`**.

Requires:

- [MoonBit](https://www.moonbitlang.com/) (`moon`)
- `wit-bindgen-cli` (regenerate bindings only)
- `wasm-tools` (`component embed` + `component new`)

Bindings under `gen/`, `interface/`, and `async-core/` were generated with:

```powershell
wit-bindgen moonbit wit --out-dir . --derive-eq --derive-show --derive-error
```

WIT pin matches the runtime: `wasi:webgpu@0.3.0-rc.2`, `wasi-gfx@0.2.0`, `wasi:clocks/monotonic-clock@0.3.0#now`. Pin `frame-event` is `{ nothing: bool }` (not rAF). Rotation uses `clocks.now` delta, same role as a web `requestAnimationFrame` timestamp. The vendored `wit/deps/wasi-gfx` files are a **linker subset** (constructor + `on-frame` + context configure/get-current-texture/present). The product host does not implement resize/pointer/keys; importing those names makes `Linker.instantiate` fail.

## Build

```powershell
.\build.ps1
```

Produces `dist/guest.wasm` (Wasm component, UTF-16 ABI from MoonBit). That file is committed so Android hosts work without MoonBit.

## Android / Dawn notes (Vivo V2458A, Mali-G925)

- Product linker implements `surface` **constructor + `on-frame` only**. Importing `width` / pointer / keys makes `instantiate` fail.
- Do **not** pass `alpha-mode: opaque` — this GPU rejects `CompositeAlphaMode::Opaque` for the window surface. Leave `alpha-mode` unset.
- Skip a depth attachment for now: `create-texture` with `depth24plus` was observed as `RGBA8Unorm` on the host path.
- Index buffer on this path was observed as size 0 (`Index range … does not fit in index buffer size (0)`). Guest uses non-indexed `draw(36)` with duplicated verts.

### Continuous present: hitching then native crash (runtime bug)

**Visual:** while the cube rotates, motion **stutters**. Stutter **frequency increases** until the process dies.

**Native:** after about **10–13 s**, **GpuThread** `SIGSEGV` at `fault addr 0x20` inside `Java_…_nativeCallRunConcurrent` / `libwasmtime_android_kt.so`.

**Why GFXV did not catch it:** `WasiGfxFrameLoopInstrumentedTest` closes the on-frame stream after **500 ms**. The leak needs seconds of `get-current-texture` → submit → present.

**Cause (wasmtime-android-kt, not this guest):** the product canvas path (`gpu-canvas-context.get-current-texture`) inserted a new Dawn `HandleTable` `GPUTexture` every frame. `queue.submit` / `context.present` **presented** but did **not** close/drop that texture (or views created from it). Track A `surfaceGetCurrentTextureView` already recycled View↔Texture pairs so Dawn could return the BLAST image. The product WIT path did not. Mali then held more and more swapchain images → waits/hitches → use of a null native object (`0x20`). Guest `resource.drop` never reached Dawn either (CM dtor only removed the Wasmtime table entry).

A later hitch + **fast spin at launch** was vsync alignment: this guest used `angle += const` per consumed `on-frame` beat. Pin `frame-event` has no timestamp. Rotation now uses `wasi:clocks/monotonic-clock#now` delta. V2458A Choreographer is 120 Hz. The runtime does **not** cap `postGfxVsync` at 60 Hz (that caused every-other-beat jitter). Remaining visual hitch: runtime `docs/mapping/gfx-hitch-checklist.md`.

**Fix so far:** (1) runtime recycles canvas textures after GPU work of the oldest in-flight frame (keep 3), without waiting that fence on the vsync→present path. (2) Guest must `drop()` per-frame WIT resources. See runtime `docs/mapping/gap-webgpu-wit-androidx.md` §5.

