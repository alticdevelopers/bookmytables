pluginManagement {
    val flutterSdkPath = run {
        val props = java.util.Properties()
        file("local.properties").inputStream().use { props.load(it) }
        val sdk = props.getProperty("flutter.sdk")
        require(sdk != null) { "flutter.sdk not set in local.properties" }
        sdk
    }

    includeBuild("$flutterSdkPath/packages/flutter_tools/gradle")

    repositories {
        google()
        mavenCentral()
        gradlePluginPortal()
    }
}

dependencyResolutionManagement {
    // allow plugin + settings repos (Flutter plugin needs this)
    repositoriesMode.set(RepositoriesMode.PREFER_SETTINGS)

    repositories {
        google()
        mavenCentral()
        gradlePluginPortal()

        // ✅ Flutter's public Maven (hosts io.flutter:* artifacts)
        maven { url = uri("https://storage.googleapis.com/download.flutter.io") }

        // ✅ Flutter engine repo from SDK (uses local.properties -> flutter.sdk)
        val props = java.util.Properties().apply {
            file("local.properties").inputStream().use { load(it) }
        }
        val flutterSdkPath = props.getProperty("flutter.sdk") ?: ""
        if (flutterSdkPath.isNotEmpty()) {
            maven { url = uri("$flutterSdkPath/bin/cache/artifacts/engine/android") }
        }

        // (optional) locally-built host repo if present
        val hostRepo = file("${rootDir}/../build/host/outputs/repo")
        if (hostRepo.exists()) {
            maven { url = hostRepo.toURI() }
        }
    }
}

plugins {
    id("dev.flutter.flutter-plugin-loader") version "1.0.0"
    id("com.android.application") version "8.9.1" apply false
    id("com.google.gms.google-services") version "4.4.2" apply false
    id("org.jetbrains.kotlin.android") version "2.1.0" apply false
}

include(":app")