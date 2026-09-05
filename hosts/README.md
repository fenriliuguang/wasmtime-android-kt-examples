# Hosts

Android shells that load `assets/guest.wasm` and drive the **Maven** 0.1.2 runtime:

1. `Engine.create` → `Component.compile` → `Linker.create` (product linker; http-tcp uses fixture ctors)
2. `Store.create` + `setWebGpuBackend(GpuBackends.dawn())` + `Store.bindCanvasNativeWindow`
3. `Instance.callRunConcurrent(store)` on **GpuThread**
4. UI thread: Surface + `Choreographer` → `store.postGfxVsync()`; pointer/key → `postGfxPointer` / `postGfxKey`
5. `surfaceDestroyed` → `store.closeGfxOnFrame()`

Swap the packed guest with `-Pexample=` (see [`docs/012-examples-playbook.md`](../docs/012-examples-playbook.md)). Optional `-Pguest.wasm=/path/to.wasm` still overrides the file copied to `assets/guest.wasm`.

| Host | Notes |
|------|--------|
| [fullscreen-surface](fullscreen-surface) | 0.1.2 consume host. One launcher per `-Pexample` |
| [native-webgpu](native-webgpu) | Pure `androidx.webgpu` JNI leak repro (no Wasmtime) |
