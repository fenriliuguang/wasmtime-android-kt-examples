# wasmtime-android-kt-examples

Out-of-tree **scriptable** demos for [wasmtime-android-kt](https://github.com/fenriliuguang/wasmtime-android-kt) **0.1.2**. This is the P010-DEMO linked example repo, not a product. `:smoke-app` in the runtime stays instruments.

Hosts consume Maven Central (no local `includeBuild`):

```kotlin
implementation("io.github.fenriliuguang.wasmtime.android:android-webgpu:0.1.2")
```

Plan / playbook: [`docs/012-examples-plan.md`](docs/012-examples-plan.md), [`docs/012-examples-playbook.md`](docs/012-examples-playbook.md).

## Layout

```
hosts/fullscreen-surface   Surface host; one launcher per -Pexample
guests/kit                 0.1.2 product-world MoonBit scenarios
guests/http-tcp            HTTP GET (fixture request ctor) + TCP
guests/rotating-cube       original present demo
guests/boundary-2d         original 2D demo
scripts/                   build-example / play-example
docs/                      0.1.2 plan + playbook
```

## One example per install

```bash
./scripts/build-example.sh compute --install
./scripts/play-example.sh compute 30
```

`-Pexample` values: `cube` `border2d` `compute` `texture` `pointer` `cli` `fs` `tcp` `http-tcp`. Each APK has a **single** LAUNCHER and a distinct `applicationId`. Do not pack every guest into one install.

Needle in logcat: `EXAMPLE_OK example=<name> code=<u32>`.

## Guest contract

Export `run: async func() -> u32`. Host calls `Instance.callRunConcurrent`. Kit guests share one generated WIT binding tree (full product pin). HTTP GET is a second tree because product `Linker.create` omits `[constructor]request`.

MoonBit `derive(Show)` warnings from wit-bindgen are ignored.

## License

Apache-2.0, matching the runtime.
