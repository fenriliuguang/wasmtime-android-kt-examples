plugins {
    alias(libs.plugins.android.application)
}

val guestWasmPath = providers.gradleProperty("guest.wasm").orElse(
    rootProject.layout.projectDirectory.file("../../guests/rotating-cube/dist/guest.wasm").asFile.absolutePath,
)
val border2dWasmPath = providers.gradleProperty("border2d.wasm").orElse(
    rootProject.layout.projectDirectory.file("../../guests/boundary-2d/dist/guest.wasm").asFile.absolutePath,
)

val copyGuestWasm = tasks.register<Copy>("copyGuestWasm") {
    val src = rootProject.file(guestWasmPath.get())
    onlyIf { src.isFile }
    from(src)
    rename { "guest.wasm" }
    into(layout.projectDirectory.dir("src/main/assets"))
}

val copyBorder2dWasm = tasks.register<Copy>("copyBorder2dWasm") {
    val src = rootProject.file(border2dWasmPath.get())
    onlyIf { src.isFile }
    from(src)
    rename { "border2d.wasm" }
    into(layout.projectDirectory.dir("src/main/assets"))
}

tasks.named("preBuild").configure {
    dependsOn(copyGuestWasm, copyBorder2dWasm)
}

android {
    namespace = "io.github.fenriliuguang.wasmtime.android.examples.fullscreen"
    compileSdk {
        version = release(36) {
            minorApiLevel = 1
        }
    }

    defaultConfig {
        applicationId = "io.github.fenriliuguang.wasmtime.android.examples.fullscreen"
        minSdk = 24
        targetSdk = 36
        versionCode = 1
        versionName = "0.1.0"

        ndk {
            abiFilters += listOf("arm64-v8a", "x86_64")
        }
    }

    buildTypes {
        release {
            optimization {
                enable = false
            }
        }
    }

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_11
        targetCompatibility = JavaVersion.VERSION_11
    }

    packaging {
        jniLibs {
            useLegacyPackaging = true
            // ND-DEFAULT: NativeGpu is the product Dawn. Do not pack androidx leftover.
            excludes += "**/libwebgpu_c_bundled.so"
        }
    }
}

dependencies {
    implementation(libs.wasmtime.android.webgpu)
    implementation(libs.androidx.core.ktx)
}
