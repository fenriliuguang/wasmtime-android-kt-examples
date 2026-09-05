/// Filesystem preopen + open-at + r/w. open-at("..") must be access.
/// Return: 4 = wrote and read P3FS; 2+ = step failed.

pub async fn run(background_group : @async-core.TaskGroup[Unit]) -> UInt {
  ignore(background_group)
  let dirs = @preopens.get_directories()
  if dirs.length() == 0 {
    return 2U
  }
  let (dir, _name) = dirs[0]
  match dir.open_at("..") {
    Ok(_) => return 3U
    Err(_) => ()
  }
  let child = match dir.open_at("p3fs.txt") {
    Err(_) => return 4U
    Ok(c) => c
  }
  let (wstream, wsink) = @async-core.Stream::new()
  let wfut = child.write_via_stream(wstream, 0UL)
  let payload : Array[Byte] = [b'P', b'3', b'F', b'S']
  ignore(write_bytes(wsink, payload))
  wsink.close()
  match wfut.get() {
    Err(_) => return 5U
    Ok(_) => ()
  }
  let (rstream, rfut) = child.read_via_stream(0UL)
  let chunk = match rstream.read(4) {
    None => return 6U
    Some(c) => c
  }
  rstream.drop()
  ignore(rfut.get())
  if chunk.length() < 4 || chunk[0] != b'P' || chunk[1] != b'3' || chunk[2] != b'F' ||
    chunk[3] != b'S' {
    return 7U
  }
  ignore(stdout_line("FS_OK\n"))
  4U
}
