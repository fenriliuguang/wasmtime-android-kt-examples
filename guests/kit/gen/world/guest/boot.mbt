/// Shared helpers for kit scenarios. `run.mbt` is swapped per wasm.

fn ascii_bytes(s : String) -> Array[Byte] {
  let out : Array[Byte] = []
  let mut i = 0
  while i < s.length() {
    out.push(s[i].to_int().to_byte())
    i = i + 1
  }
  out
}

async fn write_bytes(sink : @async-core.Sink[Byte], data : Array[Byte]) -> Bool {
  sink.write_all(data[:])
}

async fn stdout_line(text : String) -> Bool {
  let (stream, sink) = @async-core.Stream::new()
  let fut = @stdout.write_via_stream(stream)
  let ok = write_bytes(sink, ascii_bytes(text))
  sink.close()
  match fut.get() {
    Ok(_) => ok
    Err(_) => false
  }
}

async fn boot_device() -> @webgpu.GpuDevice? {
  let gpu = @webgpu.get_gpu()
  let adapter = match gpu.request_adapter(None) {
    None => return None
    Some(a) => a
  }
  match adapter.request_device(None) {
    Err(_) => None
    Ok(d) => Some(d)
  }
}
