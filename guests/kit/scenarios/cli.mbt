/// CLI stdout smoke. Surface host still loads this guest; GPU imports stay unused.
/// Return: 4 = wrote OUT\\n (same as runtime cli_stdout fixture).

pub async fn run(background_group : @async-core.TaskGroup[Unit]) -> UInt {
  ignore(background_group)
  let (stream, sink) = @async-core.Stream::new()
  let fut = @stdout.write_via_stream(stream)
  let data : Array[Byte] = [b'O', b'U', b'T', b'\n']
  ignore(write_bytes(sink, data))
  sink.close()
  match fut.get() {
    Ok(_) => 4U
    Err(_) => 9U
  }
}
