# boundary-2d

MoonBit guest: a **2D** yellow square travels the screen-border rectangle (NDC, clockwise). Same `wasi:webgpu` + `wasi-gfx` `on-frame` + `clocks.now` delta as the cube. Rotation uses the same `sincos_d` as the cube; a **single-axis** `fold_pi` is OK. Guest trig notes: [`docs/moonbit-guest-math.md`](../../docs/moonbit-guest-math.md).

NativeGpu `gpu-texture.width` / `height` currently return **1**. Do not size the sprite from those getters (64/1 filled the screen yellow-green). Use a fixed NDC half-extent instead.

## Build

```powershell
.\build.ps1
```

Produces `dist/guest.wasm`. The fullscreen host copies it to `assets/border2d.wasm`.
