Subset that the wasmtime-android-kt product linker actually implements
(constructor + on-frame). Extra pin methods (resize/pointer/keys) are not
linked; importing them makes instantiate fail.