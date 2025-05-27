plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "com.example.casttotvscreen"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_11
        targetCompatibility = JavaVersion.VERSION_11
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_11.toString()
    }

    defaultConfig {
        applicationId = "com.example.casttotvscreen"
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
        // Enable multidex for older Android versions if needed by dependencies
        multiDexEnabled = true 
    }

    buildTypes {
        release {
            // Enable code shrinking, obfuscation, and optimization
            isMinifyEnabled = true
            isShrinkResources = true // Remove unused resources
            
            // Specify ProGuard rules file
            proguardFiles(getDefaultProguardFile("proguard-android-optimize.txt"), "proguard-rules.pro")

            // TODO: Add your own signing config for the release build.
            // Signing with the debug keys for now, so `flutter run --release` works.
            // Replace this with your actual signing configuration for production release.
            signingConfig = signingConfigs.getByName("debug") 
        }
        // Debug build type (usually default)
        debug {
            // Debug specific settings if needed
        }
    }
}

flutter {
    source = "../.."
}

// Add dependencies block if missing (though usually present)
// dependencies {
//    implementation("androidx.multidex:multidex:2.0.1") // Add if multiDexEnabled is true
// }

