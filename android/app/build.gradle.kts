plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "com.example.appleonemore"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        // ✅ 2. 开启核心库脱糖 (Desugaring)，支持旧版安卓预约通知
        isCoreLibraryDesugaringEnabled = true

        // 官方建议设为 Java 11 以获得最佳兼容性，如果你需要 Java 17 也可以保留
        sourceCompatibility = JavaVersion.VERSION_11
        targetCompatibility = JavaVersion.VERSION_11
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_11.toString()
    }

    defaultConfig {
        applicationId = "com.example.appleonemore"
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName

        // ✅ 3. 开启 MultiDex，防止引入通知库后方法数超限
        multiDexEnabled = true
    }

    buildTypes {
        release {
            signingConfig = signingConfigs.getByName("debug")
            // 如果你之后要发布，在这里配置混淆规则
            // proguardFiles(getDefaultProguardFile("proguard-android-optimize.txt"), "proguard-rules.pro")
        }
    }
}

flutter {
    source = "../.."
}

dependencies {
    // ✅ 4. 必须添加：核心库脱糖依赖
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")

    // ✅ 5. 必须添加：防止 Android 12L+ 崩溃的稳定性库
    implementation("androidx.window:window:1.0.0")
    implementation("androidx.window:window-java:1.0.0")

    implementation("com.squareup.okhttp3:okhttp:4.12.0")
}