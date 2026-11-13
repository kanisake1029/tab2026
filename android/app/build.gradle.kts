import java.util.Properties

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// 配布版（pub）の署名：android/key.properties があれば、その鍵で署名する。無いときは今までどおりデバッグ鍵。
//  dev / dbg は、いつもデバッグ鍵のまま。鍵を変えると、いま入っているアプリに上書きインストール（adb install -r）できず、セーブが消えるため。
//  key.properties の中身（このファイルと鍵は GitHub に上げない。android/.gitignore で除外済み）：
//    storeFile=C:/鍵の場所/tab-release.jks / storePassword=… / keyAlias=… / keyPassword=…
val keystoreProperties = Properties().apply {
    val f = rootProject.file("key.properties")
    if (f.exists()) f.inputStream().use { load(it) }
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

    signingConfigs {
        if (keystoreProperties.isNotEmpty()) {
            create("pubRelease") {
                keyAlias = keystoreProperties["keyAlias"] as String
                keyPassword = keystoreProperties["keyPassword"] as String
                storeFile = file(keystoreProperties["storeFile"] as String)
                storePassword = keystoreProperties["storePassword"] as String
            }
        }
    }

    // 版の作り分け（S25 に並べて入れる）
    //  dev：開発者版。いまのセーブが入っているアプリと同じ ID。AI寸評あり
    //  dbg：デバッグ版。別の ID（別アプリとして並ぶ・セーブも別）。AI寸評なし
    //  pub：配布版（GitHub Releases）。AI寸評なし
    flavorDimensions += "edition"
    productFlavors {
        create("dev") {
            dimension = "edition"
            signingConfig = signingConfigs.getByName("debug")
            manifestPlaceholders["appLabel"] = "TAB 開発者版"
            manifestPlaceholders["launcherLabel"] = "TAB 開発者版"
        }
        create("dbg") {
            dimension = "edition"
            signingConfig = signingConfigs.getByName("debug")
            applicationIdSuffix = ".dbg"
            manifestPlaceholders["appLabel"] = "TAB デバッグ"
            manifestPlaceholders["launcherLabel"] = "TAB デバッグ"
        }
        create("pub") {
            dimension = "edition"
            signingConfig = signingConfigs.findByName("pubRelease") ?: signingConfigs.getByName("debug")
            manifestPlaceholders["appLabel"] = "The Authentic Baseball 2026"
            manifestPlaceholders["launcherLabel"] = "TAB 2026"
        }
    }

    // 署名は版（flavor）ごとに決める（上の signingConfigs と productFlavors）
    buildTypes {
        release {
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
