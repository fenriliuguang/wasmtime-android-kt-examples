# 0.1.2 示例仓推进计划

本仓是 [wasmtime-android-kt](https://github.com/fenriliuguang/wasmtime-android-kt) 的**仓外脚本化示例**，不是正式产品。目标：第三方只吃 Maven `android-webgpu:0.1.2`，用 fullscreen host 跑一组可脚本化 guest。

## 立刻（已做）

1. Host 去掉 `includeBuild` 本地 runtime，依赖

   `io.github.fenriliuguang.wasmtime.android:android-webgpu:0.1.2`

2. 每个例子独立 wasm；绑定只生成一次（`guests/kit` 产品 world；`guests/http-tcp` 另生成，因为要 import `[constructor]request`）。
3. `-Pexample=…` 一次只装一个 launcher / 一个 `applicationId`，不在同一次安装里塞全部例子。
4. 固定 logcat 针：`EXAMPLE_OK example=<name> code=<u32>`。`scripts/play-example.sh` 按表断言。

## Guest 覆盖（0.1.2 claim）

| 例子 | wasm | 钉 | 期望 `code` | linker |
|------|------|----|-------------|--------|
| compute | `guests/kit/dist/compute.wasm` | adapter/device/queue/compute pass，无 present | 1 | product `Linker.create` |
| texture | `texture.wasm` | write-texture / copy-texture-to-buffer / map-async | 1 | product |
| pointer | `pointer.wasm` | height/width/`request-set-size`/on-resize + pointer/key 流 | 1 | product；host 自动 `postGfxPointer`/`postGfxKey` |
| cli | `cli.wasm` | `wasi:cli/stdout` `write-via-stream` | 4 | product（仍走 Surface host） |
| fs | `fs.wasm` | preopen + `open-at("..")`→access + `p3fs.txt` r/w | 4 | product；host `TMPDIR=cacheDir` |
| tcp | `tcp.wasm` | 出站 TCP loopback echo（W7 pair） | 4 | product |
| http-tcp | `guests/http-tcp/dist/guest.wasm` | TCP echo + `client.send` GET `127.0.0.1:18765` | 4 | **fixture** `createWithFixtureConstructors`（HCTOR leftover） |

每个 kit wasm 的 world 是**同一份全量产品 WIT**（webgpu 全 pin + 全量 wasi-gfx surface + clocks + cli/fs/sockets）。MoonBit `derive(Show)` 告警忽略。

https / TLS 是 named leftover：把 authority 改成 `host:443` 时 `send` → `unknown`（期望 `code=22`）。不要当产品路径。

## 不在本刀

- 不把 cube / 2d 改成 kit world（旧 demo 仍各自一份绑定）。
- 不上 G-fs-full（stat / dir stream / append）。
- 不宣称 CTS / 完整 WASI 0.3。
- Cloud 无真机；play 脚本在有 `adb` 的机器上跑。

## 目录

```
guests/kit/           产品 world + 6 个 scenario run（compute/texture/pointer/cli/fs/tcp）
guests/http-tcp/      HTTP ctor + sockets（独立绑定）
hosts/fullscreen-surface/   唯一 0.1.2 consume host
scripts/build-example.sh    guest + 单例 APK
scripts/play-example.sh     am start + EXAMPLE_OK
docs/012-examples-playbook.md
```

下一步若要加例子：在 `guests/kit/scenarios/` 加 `run`，`build.sh` 的 case 和 host `-Pexample` 表各加一行。不要新开一份 webgpu 绑定。
