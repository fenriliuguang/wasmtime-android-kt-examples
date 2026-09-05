# kit guests (0.1.2 product world)

One MoonBit module (`example/kit`). Bindings generated once from **product-complete WIT** (full `wasi:webgpu@0.3.0-rc.2`, full `wasi-gfx:surface@0.2.0` pin, clocks, cli stdout, filesystem preopen/`open-at`, sockets TCP). Each scenario is a different `run` compiled to a different wasm.

```bash
./build.sh compute   # dist/compute.wasm
./build.sh texture
./build.sh pointer
./build.sh cli
./build.sh fs
./build.sh tcp
```

`run.mbt` is copied from `scenarios/<name>.mbt` at build time. Do not edit `interface/**` to silence moonbit `derive(Show)` warnings.

HTTP GET with `[constructor]request` is **not** in this world (product linker omits it). See `../http-tcp`.
