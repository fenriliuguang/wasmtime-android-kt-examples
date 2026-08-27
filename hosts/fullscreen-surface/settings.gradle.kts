pluginManagement {
    repositories {
        google {
            content {
                includeGroupByRegex("com\\.android.*")
                includeGroupByRegex("com\\.google.*")
                includeGroupByRegex("androidx.*")
            }
        }
        mavenCentral()
        gradlePluginPortal()
    }
}

plugins {
    id("org.gradle.toolchains.foojay-resolver-convention") version "1.0.0"
}

val localProps = java.util.Properties()
val localFile = file("local.properties")
if (localFile.exists()) {
    localFile.reader(Charsets.ISO_8859_1).use { localProps.load(it) }
}
val runtimeDir =
    providers.gradleProperty("wasmtime.android.kt.dir").orNull
        ?: localProps.getProperty("wasmtime.android.kt.dir")
        ?: error(
            "Set wasmtime.android.kt.dir in local.properties (or gradle.properties) " +
                "to a wasmtime-android-kt checkout. Hosts consume it via includeBuild.",
        )
includeBuild(runtimeDir)

dependencyResolutionManagement {
    repositoriesMode.set(RepositoriesMode.FAIL_ON_PROJECT_REPOS)
    repositories {
        google()
        mavenCentral()
    }
}

rootProject.name = "fullscreen-surface"
include(":app")
