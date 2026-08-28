# Hosts

Android shells that load `assets/guest.wasm` and drive the product runtime:

1. `Engine.create` → `Component.compile` → `Linker.create` (product linker, no fixture `get-device`)
2. `Store.create` + explicit `setWebGpuBackend(HostWebGpuBackend(...))`
3. `Instance.callRunConcurrent(store)` on **GpuThread**
4. UI thread: Surface lifecycle + `Choreographer` → `store.postGfxVsync()`
5. `surfaceDestroyed` → `store.closeGfxOnFrame()` so guest `run` unblocks

Swap guests with `-Pguest.wasm=/path/to/guest.wasm` at Gradle assemble/install time.

Local JDK: Android Studio JBR (`JAVA_HOME` pointing at `Android Studio/jbr`). The Red Hat Java extension JRE lacks `jlink` and will fail AGP.

| Host | Notes |
|------|--------|
| [fullscreen-surface](fullscreen-surface) | Fullscreen Surface for guest rendering |
| [native-webgpu](native-webgpu) | Minimal pure-`androidx.webgpu` repro of the `onSubmittedWorkDone` JNI global-ref leak (upstream issue repro; no Wasmtime) |
