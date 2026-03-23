plugins {
    id("com.android.application")
    id("org.jetbrains.kotlin.android")
    id("com.google.gms.google-services")
    // Flutter plugin must be applied last
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "com.bookmytables.bookmytables"

    // Use Flutter-provided sdk versions
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
        // ✅ required by flutter_local_notifications and other Java 8+ APIs
        isCoreLibraryDesugaringEnabled = true
    }
    kotlinOptions {
        jvmTarget = "17"
    }

    defaultConfig {
        applicationId = "com.bookmytables.bookmytables"
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
        multiDexEnabled = true
    }

    buildTypes {
        debug {
            // fast builds
            isMinifyEnabled = false
            isShrinkResources = false
        }
        release {
            // TODO: replace with your real signing config when ready
            signingConfig = signingConfigs.getByName("debug")
            isMinifyEnabled = false
            isShrinkResources = false
        }
    }

    packaging {
        resources {
            excludes += setOf(
                "META-INF/LICENSE*",
                "META-INF/NOTICE*",
                "META-INF/AL2.0",
                "META-INF/LGPL2.1"
            )
        }
    }
}

dependencies {
    // Firebase BoM + Analytics (your existing lines)
    implementation(platform("com.google.firebase:firebase-bom:33.4.0"))
    implementation("com.google.firebase:firebase-analytics")

    // ✅ Bump desugar lib to a compatible version (2.1.4 or newer)
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.5")

    // implementation("androidx.multidex:multidex:2.0.1") // only if minSdk < 21
}

flutter {
    source = "../.."
}