/// Product `wasi:clocks/monotonic-clock@0.3.0#now` (u64 ns, process Instant).
/// Pin `frame-event` is `{ nothing: bool }` — not an rAF timestamp.

fn wasmImportMonotonicNow() -> UInt64 = "wasi:clocks/monotonic-clock@0.3.0" "now"

fn monotonic_now_ns() -> UInt64 {
  wasmImportMonotonicNow()
}

/// Seconds since [prev_ns]. First sample uses 1/60 s. Clamp 50 ms like a
/// typical rAF hitch guard.
fn frame_delta_sec(prev_ns : UInt64, now_ns : UInt64) -> Double {
  if prev_ns == 0UL {
    return 1.0 / 60.0
  }
  let mut ns = now_ns - prev_ns
  if ns > 50000000UL {
    ns = 50000000UL
  }
  ns.to_double() / 1000000000.0
}
