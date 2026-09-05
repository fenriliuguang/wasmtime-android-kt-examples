# Guests

Wasm **components** that export:

```wit
export run: async func() -> u32;
```

The host calls `Instance.callRunConcurrent`. Return value is the scriptable code (`EXAMPLE_OK … code=`).

| Guest | Language | Notes |
|-------|----------|--------|
| [kit](kit) | MoonBit | Shared product WIT; `build.sh compute\|texture\|pointer\|cli\|fs\|tcp` |
| [http-tcp](http-tcp) | MoonBit | TCP + HTTP GET; needs fixture request ctor |
| [rotating-cube](rotating-cube) | MoonBit | Present cube (legacy demo) |
| [boundary-2d](boundary-2d) | MoonBit | Border-loop 2D (legacy demo) |

`dist/*.wasm` is committed so a host can install without MoonBit.
