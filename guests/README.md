# Guests

Wasm **components** that export:

```wit
export run: async func() -> u32;
```

The host calls `Instance.callRunConcurrent`. Return value is guest-defined (the cube returns presented frame count; `2`/`3` mean adapter/device setup failed).

Optional imports for on-screen guests:

- `wasi:webgpu/webgpu@0.3.0-rc.2`
- `wasi-gfx:surface/surface@0.2.0` (`on-frame` stream; guest **pulls**, no JS-style callback)
- `wasi-gfx:surface/surface-webgpu@0.2.0`

Commit `dist/guest.wasm` so a host can install without the guest toolchain.

| Guest | Language | Notes |
|-------|----------|--------|
| [rotating-cube](rotating-cube) | MoonBit | Perspective X/Y/Z tumble; own `sincos` ([trig notes](../docs/moonbit-guest-math.md)) |
| [boundary-2d](boundary-2d) | MoonBit | 2D square looping the screen border; same guest `sincos` |
