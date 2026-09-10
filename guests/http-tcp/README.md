# http-tcp guest

Outbound TCP echo + `wasi:http/client@0.3.0#send` GET to `127.0.0.1:18765`.

This world **imports** `[constructor]request`. Product `Linker.create` will fail instantiate. The fullscreen `HttpTcpActivity` uses `Linker.createWithFixtureConstructors` (P010-HCTOR leftover). HTTPS is named leftover (`send` → `TLS-protocol-error`, guest `code=22`).

```bash
./build.sh   # dist/guest.wasm
```

`wit-bindgen` 0.60 still emits async-lower for `client.send`. After regenerating, restore the sync import in `interface/wasi/http/client` (host `func_wrap`, not concurrent).
