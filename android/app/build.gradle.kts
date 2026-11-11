plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "com.example.npb_pennant_app"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = "27.0.12077973"

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "com.example.npb_pennant_app"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        // Uses the version code from pubspec.yaml. When using split APKs, 1000 * ABI_VERSION
        // is added automatically by Flutter. (https://developer.android.com/studio/build/configure-apk-splits#configure-APK-versions)
        // You can force using the value of versionCode by specifying the `-P force-version-code-ignoring-abi=true`
        // flag during build.
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    // 版の作り分け（S25 に並べて入れる）
    //  dev：開発者版。いまのセーブが入っているアプリと同じ ID。AI寸評あり
    //  dbg：デバッグ版。別の ID（別アプリとして並ぶ・セーブも別）。AI寸評なし
    //  pub：配布版（GitHub Releases）。AI寸評なし
    flavorDimensions += "edition"
    productFlavors {
        create("dev") {
            dimension = "edition"
            manifestPlaceholders["appLabel"] = "TAB 開発者版"
            manifestPlaceholders["launcherLabel"] = "TAB 開発者版"
        }
        create("dbg") {
            dimension = "edition"
            applicationIdSuffix = ".dbg"
            manifestPlaceholders["appLabel"] = "TAB デバッグ"
            manifestPlaceholders["launcherLabel"] = "TAB デバッグ"
        }
        create("pub") {
            dimension = "edition"
            manifestPlaceholders["appLabel"] = "The Authentic Baseball 2026"
            manifestPlaceholders["launcherLabel"] = "TAB 2026"
        }
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
