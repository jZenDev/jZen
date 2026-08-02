plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "dev.jzen.zen_demo_client"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "dev.jzen.zen_demo_client"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName

        // The App Link host for the autoVerify intent-filter in AndroidManifest.xml.
        //
        // A placeholder, not a literal, because the host IS the deployed environment: a URL baked
        // in here would outlive the environment it names, and `destroy:cloudrun` cannot edit the
        // repository (STANDARDS "Deployment model"). Supply it with
        //   flutter build apk --dart-define=... -Pzen-applinks-host=app.example.com
        // or leave it unset, which is the default and the local case.
        //
        // The default is deliberately an unresolvable host rather than an empty string: a manifest
        // placeholder cannot be empty, and "invalid" is a reserved TLD (RFC 2606) that can never
        // be registered, so an unconfigured build declares a filter that cannot match anything
        // instead of one that matches something unintended.
        manifestPlaceholders["zenApplinksHost"] =
            (project.findProperty("zen-applinks-host") as String?) ?: "applinks.invalid"
    }

    buildTypes {
        release {
            // TODO: Add your own signing config for the release build.
            // Signing with the debug keys for now, so `flutter run --release` works.
            signingConfig = signingConfigs.getByName("debug")
        }
    }
}

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

flutter {
    source = "../.."
}
