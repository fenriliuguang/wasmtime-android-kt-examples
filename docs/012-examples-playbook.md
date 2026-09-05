# 0.1.2 示例 playbook（脚本化）

第三方 consume 钉：Maven Central

```
io.github.fenriliuguang.wasmtime.android:android-webgpu:0.1.2
```

Host：`hosts/fullscreen-surface`。一次只装一个例子（不同 `applicationId`）。不要 `includeBuild` 本地 runtime。

## 0. 机器

- Android SDK（`local.properties` 的 `sdk.dir`）
- JDK 17+（Android Studio JBR 即可）
- 设备 / 模拟器，`adb devices` 一条
- 编 guest：`moon`、`wasm-tools`（已提交的 `dist/*.wasm` 可跳过）

`hosts/fullscreen-surface/local.properties`：

```
sdk.dir=/path/to/Android/sdk
```

## 1. 编并安装一个例子

```bash
./scripts/build-example.sh compute --install
```

Windows：

```powershell
.\scripts\build-example.ps1 compute -Install
```

等价手搓：

```bash
guests/kit/build.sh compute          # 或 http-tcp：guests/http-tcp/build.sh
cd hosts/fullscreen-surface
./gradlew :app:installDebug -Pexample=compute
```

合法 `-Pexample`：`cube` `border2d` `compute` `texture` `pointer` `cli` `fs` `tcp` `http-tcp`。

## 2. 跑并断言

```bash
./scripts/play-example.sh compute 30
```

脚本：`logcat -c` → `am start -W` → 等到

```
EXAMPLE_OK example=compute code=1
```

失败针：`EXAMPLE_FAIL example=…`。超时把该 tag 的 logcat 尾打出来。

| example | applicationId 后缀 | Activity | 期望 code | 超时建议 |
|---------|-------------------|----------|-----------|----------|
| compute | `.compute` | ComputeActivity | 1 | 30s |
| texture | `.texture` | TextureActivity | 1 | 30s |
| pointer | `.pointer` | PointerActivity | 1 | 30s |
| cli | `.cli` | CliActivity | 4 | 15s |
| fs | `.fs` | FsActivity | 4 | 15s |
| tcp | `.tcp` | TcpActivity | 4 | 15s |
| http-tcp | `.httptcp` | HttpTcpActivity | 4 | 30s |
| cube | （无） | MainActivity | 帧数，不断言 | — |

手工：

```bash
adb logcat -c
adb shell am start -W -n io.github.fenriliuguang.wasmtime.android.examples.fullscreen.compute/io.github.fenriliuguang.wasmtime.android.examples.fullscreen.ComputeActivity
adb logcat -s ExampleCompute:I ExampleCompute:E
```

成功底栏也会显示 `EXAMPLE_OK compute 1`（cube / 2d 不上这条，避免脏 color-ratio）。

## 3. 每个例子在钉什么

- **compute**：`get-gpu` → `request-adapter` → `request-device` → storage bind group → compute pass `dispatch-workgroups` → `queue.submit`。无 `present`。
- **texture**：`write-texture` 1×1 RGBA8 → `copy-texture-to-buffer` → `map-async` / `get-mapped-range`，字节 `11 22 33 44`。
- **pointer**：读 `height`/`width`（绑定窗口后非 0）→ `request-set-size(96,80)` → `on-resize.read` → `on-pointer-down.read`（host 在 `callRunConcurrent` 前 `postGfxPointer(1, 12.5, 34.0)` 和 `postGfxKey`）。其余 pin 流 open+drop。
- **cli**：`stdout.write-via-stream("OUT\n")`，返回 4。GPU import 在 world 里但 guest 不用。
- **fs**：`get-directories` → `open-at("..")` 必须失败 → `open-at("p3fs.txt")` 写读 `P3FS`。Host 把 `TMPDIR` 指到 `cacheDir`。
- **tcp**：`create-tcp-socket(ipv4)` → `connect(127.0.0.1:1)`（loopback 走 host echo pair）→ 写读 `P3SK`。
- **http-tcp**：先做 tcp echo，再 `Request` ctor + `set-authority("127.0.0.1:18765")` + `client.send`。Host 在进程内听 18765，回 `HOUT`。产品 linker **没有** request ctor，所以这个 Activity 用 `Linker.createWithFixtureConstructors`。https（`:443`）是 leftover，`send` → `unknown`，guest 返回 **22**。

## 4. 不要一次装全部

每个 `-Pexample` 换 `applicationId` 和唯一 LAUNCHER。可以并存多个后缀包，但 `build-example.sh --install` 一次只装一个。不要把所有 Activity 都标 LAUNCHER。

## 5. MoonBit 告警

`wit-bindgen 0.60` 给 webgpu 绑的 `derive(Show)` 在现行 moon 上会刷 deprecated。忽略。`warn-list` 已放宽。不要为消告警手改 `interface/**`。

## 6. 失败怎么读

| 现象 | 含义 |
|------|------|
| `EXAMPLE_FAIL` + instantiate | world 多 import 了产品 linker 没有的名字（例如 HTTP ctor 却走了 `Linker.create`） |
| compute/texture `code=2` | `request-adapter` none：AAR 没带上 `libwebgpu_dawn.so`，或没 `setWebGpuBackend(dawn())` |
| pointer `code=2` | surface 宽高仍是 0：`bindCanvasNativeWindow` 没发生 |
| pointer `code=5/6` | 没吃到 auto pointer（host 没 `postGfxPointer`） |
| fs `code=3` | `open-at("..")` 没返回 access |
| http-tcp `code=22` | `send` unknown：TLS leftover 或 authority 空/非 IPv4 `host:port` |
| http-tcp `code=21` | `set-authority` 失败 |
| 一直无 `EXAMPLE_OK` | GpuThread 崩了 / run 堵在 `on-frame`（这个 smoke 不该堵；pointer 若没 auto-post 会堵在 `stream.read`） |
