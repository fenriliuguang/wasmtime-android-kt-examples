/// Outbound TCP loopback echo, then wasi:http client.send GET to 127.0.0.1:18765.
/// HTTPS / TLS is a named leftover (send → unknown). Product linker omits
/// [constructor]request; this guest needs Linker.createWithFixtureConstructors.
/// Return: 4 = HTTP body 4 bytes after TCP echo; 2–7 TCP fail; 21+ HTTP fail.

pub async fn run(background_group : @async-core.TaskGroup[Unit]) -> UInt {
  ignore(background_group)
  match tcp_echo() {
    4U => ()
    other => return other
  }
  let req = @http.Request::request()
  match req.set_authority("127.0.0.1:18765") {
    Err(_) => return 21U
    Ok(_) => ()
  }
  let resp = match @client.send(req) {
    Err(_) => return 22U
    Ok(r) => r
  }
  if resp.status_code() != 200U {
    return 23U
  }
  let (body, fut) = @http.Response::consume_body(resp)
  let chunk = match body.read(4) {
    None => return 24U
    Some(c) => c
  }
  body.drop()
  ignore(fut.get())
  if chunk.length() < 4 {
    return 25U
  }
  4U
}

async fn tcp_echo() -> UInt {
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
  ignore(wsink.write_all(payload[:]))
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
  4U
}
