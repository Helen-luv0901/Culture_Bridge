import java.util.Properties

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// Release signing key (C-18): android/key.properties points to the upload keystore. Neither
// file is committed. Without them a release build stops, rather than quietly signing with the
// debug key (Google Play rejects that, and it can't be updated later). To try a release build
// on a phone without the key: CB_ALLOW_DEBUG_SIGNING=1 flutter run --release
val keystoreProperties = Properties().apply {
    val file = rootProject.file("key.properties")
    if (file.exists()) file.inputStream().use { load(it) }
}
val hasUploadKey = keystoreProperties.containsKey("storeFile")
val allowDebugSigning = System.getenv("CB_ALLOW_DEBUG_SIGNING") == "1"

android {
    namespace = "com.culturebridge.culture_bridge"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        // Still to be decided (C-3) before the first Play upload; it can never change after.
        applicationId = "com.culturebridge.culture_bridge"
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
        if (hasUploadKey) {
            create("upload") {
                storeFile = file(keystoreProperties.getProperty("storeFile"))
                storePassword = keystoreProperties.getProperty("storePassword")
                keyAlias = keystoreProperties.getProperty("keyAlias")
                keyPassword = keystoreProperties.getProperty("keyPassword")
            }
        }
    }

    buildTypes {
        release {
            signingConfig = signingConfigs.findByName("upload")
                ?: if (allowDebugSigning) signingConfigs.getByName("debug") else null
            // R8: drops unused code and resources and shortens names (smaller download, harder
            // to read back). Flutter, Firebase and AndroidX ship their own keep rules.
            isMinifyEnabled = true
            isShrinkResources = true
            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro",
            )
        }
    }
}

gradle.taskGraph.whenReady {
    val release = allTasks.any { task ->
        task.project == project && task.name.matches(Regex("""(assemble|bundle)\w*Release"""))
    }
    if (release && !hasUploadKey && !allowDebugSigning) {
        throw GradleException(
            "No upload key: create android/key.properties (docs/runbooks/c2-android-build.md), " +
                "or set CB_ALLOW_DEBUG_SIGNING=1 for a build that is never uploaded."
        )
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
