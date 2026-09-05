plugins {
    alias(libs.plugins.android.application)
}

data class ExampleSpec(
    val activity: String,
    val label: String,
    val wasm: String,
    val applicationIdSuffix: String?,
)

val exampleName = providers.gradleProperty("example").orElse("cube").get()
val exampleSpecs = mapOf(
    "cube" to ExampleSpec(".MainActivity", "fullscreen-cube", "../../guests/rotating-cube/dist/guest.wasm", null),
    "border2d" to ExampleSpec(".Border2dActivity", "fullscreen-2d", "../../guests/boundary-2d/dist/guest.wasm", ".border2d"),
    "compute" to ExampleSpec(".ComputeActivity", "fullscreen-compute", "../../guests/kit/dist/compute.wasm", ".compute"),
    "texture" to ExampleSpec(".TextureActivity", "fullscreen-texture", "../../guests/kit/dist/texture.wasm", ".texture"),
    "pointer" to ExampleSpec(".PointerActivity", "fullscreen-pointer", "../../guests/kit/dist/pointer.wasm", ".pointer"),
    "cli" to ExampleSpec(".CliActivity", "fullscreen-cli", "../../guests/kit/dist/cli.wasm", ".cli"),
    "fs" to ExampleSpec(".FsActivity", "fullscreen-fs", "../../guests/kit/dist/fs.wasm", ".fs"),
    "tcp" to ExampleSpec(".TcpActivity", "fullscreen-tcp", "../../guests/kit/dist/tcp.wasm", ".tcp"),
    "http-tcp" to ExampleSpec(".HttpTcpActivity", "fullscreen-http-tcp", "../../guests/http-tcp/dist/guest.wasm", ".httptcp"),
)
val spec = exampleSpecs[exampleName]
    ?: error(
        "Unknown -Pexample=$exampleName. Want: ${exampleSpecs.keys.sorted().joinToString()}",
    )
val guestWasmPath = providers.gradleProperty("guest.wasm").orElse(
    rootProject.layout.projectDirectory.file(spec.wasm).asFile.absolutePath,
)

val copyGuestWasm = tasks.register<Copy>("copyGuestWasm") {
    val src = rootProject.file(guestWasmPath.get())
    onlyIf { src.isFile }
    from(src)
    rename { "guest.wasm" }
    into(layout.projectDirectory.dir("src/main/assets"))
}

tasks.named("preBuild").configure {
    dependsOn(copyGuestWasm)
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
        spec.applicationIdSuffix?.let { applicationIdSuffix = it }
        minSdk = 24
        targetSdk = 36
        versionCode = 2
        versionName = "0.1.2"

        ndk {
            abiFilters += listOf("arm64-v8a", "x86_64")
        }

        manifestPlaceholders["launcherActivity"] = spec.activity
        manifestPlaceholders["launcherLabel"] = spec.label
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
