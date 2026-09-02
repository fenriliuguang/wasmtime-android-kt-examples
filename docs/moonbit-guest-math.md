# MoonBit guest trig (no libc `sin`/`cos`)

**English** | [中文](#中文)

MoonBit’s core library does not expose a libc-quality `sin`/`cos`. These guests
ship their own helpers in `gen/world/guest/math.mbt`. Two bugs in that math
looked like a compositor rewind on the Android cube. They are **guest-only**.
The runtime vsync → NativeGpu present path was already 1:1; do not re-open host
keep-N / Fifo / timestamp knobs for this.

Code: [`guests/rotating-cube/gen/world/guest/math.mbt`](../guests/rotating-cube/gen/world/guest/math.mbt),
[`guests/boundary-2d/gen/world/guest/math.mbt`](../guests/boundary-2d/gen/world/guest/math.mbt).

## 1. Taylor + wrap to ±π (~5 s small pop)

The first `sin_d` / `cos_d` wrapped the argument into ±π, then used a Taylor
polynomial through \(x^7\).

At ±π the polynomial is about **0.075** off true sin. Crossing the wrap jumps
sin by ~**0.15** (~8–9°). Cube `rad_per_sec` is 1.5, so the wrap period is
\(2π/1.5 ≈ 4.19\) s — the “every ~5 s” eye pop.

A translate-only cube never called `rotate_*`, so it never popped. The pure
androidx cube uses platform trig, so it never popped. The same helpers were in
the 2D spin guest.

**Fix:** Cody–Waite reduction to \(|r| ≤ π/4\), then fdlibm `k_sin` / `k_cos`.
`sin` and `cos` share one `(n, r)` so the pair stays continuous at ±π/2 and ±π.

## 2. Fold a shared Euler clock (`fold_pi`)

After restoring perspective tumble on **X / Y / Z** from one clock `θ`
(`Ry(θ)`, `Rx(0.35θ)`, `Rz(0.21θ)`), folding `θ` into ±π each frame is wrong.

- `Ry(θ + 2π) = Ry(θ)`
- `Rx(0.35(θ + 2π))` snaps ~**126°**
- `Rz(0.21(θ + 2π))` snaps ~**76°**

That snap hit once per Y revolution (green going / yellow coming).

**Fix (cube):** do **not** fold the shared `θ`. Let each axis reduce inside
`sincos_d`. Angle only advances.

**OK (2D):** `boundary-2d` still `fold_pi`s a **single** spin angle. One axis,
so `R(θ+2π)=R(θ)`.

## 中文

MoonBit 核心库没有可用的 libc 级 `sin`/`cos`。演示 guest 自己写了一套
（`math.mbt`）。下面两处会让立方体看起来像合成器回退，**只属于 guest**。
Host 节拍（Choreographer → NativeGpu present）当时已经是 1:1，不要为此再拧
runtime 的 keep-N / Fifo / 时间戳。

1. **泰勒 + 折到 ±π：** 在 ±π 处多项式大约偏 0.075，折回时 sin 跳约 0.15
   （8–9°）。立方体角速度 1.5 rad/s，周期约 4.19 s。只做平移、或走平台
   三角函数的 androidx 立方体都不会弹。
2. **共享欧拉角再 `fold_pi`：** 三轴共用 `θ` 时，把 `θ` 折进 ±π 会让
   `Rx(0.35θ)` / `Rz(0.21θ)` 各跳一大截（约 126° / 76°）。立方体不要折共享
   `θ`。2D 单轴旋转仍可以折。
