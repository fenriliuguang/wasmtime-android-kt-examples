/// Outbound TCP loopback echo (host W7 echo pair; port ignored).
/// Return: 4 = wrote/read P3SK; 2+ = step failed.

pub async fn run(background_group : @async-core.TaskGroup[Unit]) -> UInt {
  ignore(background_group)
  let sock = match @create.create_tcp_socket(@create.IpAddressFamily::IPV4) {
    Err(_) => return 2U
    Ok(s) => s
  }
  let addr = @tcp.IpSocketAddress::Ipv4(
    { port: 1U, address: (b'\x7F', b'\x00', b'\x00', b'\x01') },
  )
  match sock.connect(addr) {
    Err(_) => return 3U
    Ok(_) => ()
  }
  let (wstream, wsink) = @async-core.Stream::new()
  let wfut = sock.write_via_stream(wstream)
  let payload : Array[Byte] = [b'P', b'3', b'S', b'K']
  ignore(write_bytes(wsink, payload))
  wsink.close()
  match wfut.get() {
    Err(_) => return 5U
    Ok(_) => ()
  }
  let (rstream, rfut) = sock.read_via_stream()
  let chunk = match rstream.read(4) {
    None => return 6U
    Some(c) => c
  }
  rstream.drop()
  ignore(rfut.get())
  if chunk.length() < 4 || chunk[0] != b'P' || chunk[1] != b'3' || chunk[2] != b'S' ||
    chunk[3] != b'K' {
    return 7U
  }
  ignore(stdout_line("TCP_OK\n"))
  4U
}
