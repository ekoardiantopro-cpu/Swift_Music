plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

dependencies {
    implementation("com.google.android.gms:play-services-wearable:20.0.1")
}

android {
    namespace = "com.swiftmusic.swift_music"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "com.swiftmusic.swift_music"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = 24
        targetSdk = flutter.targetSdkVersion
        // Uses the version code from pubspec.yaml. When using split APKs, 1000 * ABI_VERSION
        // is added automatically by Flutter. (https://developer.android.com/studio/build/configure-apk-splits#configure-APK-versions)
        // You can force using the value of versionCode by specifying the `-P force-version-code-ignoring-abi=true`
        // flag during build.
        versionCode = flutter.versionCode
        versionName = flutter.versionName
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

val spotifyRustDir = file("src/main/rust")
val spotifyJniLibs = file("src/main/jniLibs")
val cargoNdk = rootProject.file(
    "../build-tools/cargo-ndk/cargo-ndk-x86_64-pc-windows-msvc-v4.1.2/cargo-ndk.exe",
)
val androidExtension = extensions.getByName("android") as com.android.build.gradle.BaseExtension
val spotifyNdk = File(androidExtension.sdkDirectory, "ndk/${androidExtension.ndkVersion}")

val buildSpotifyConnectNative by tasks.registering(Exec::class) {
    group = "build"
    description = "Build the librespot Spotify Connect Android bridge."
    workingDir(spotifyRustDir)
    commandLine(
        "cargo", "ndk", "-t", "arm64-v8a",
        "-t", "x86_64",
        "-P", "26",
        "-o", spotifyJniLibs.absolutePath,
        "build", "--release",
    )
    environment("ANDROID_NDK_HOME", spotifyNdk.absolutePath)
    environment("ANDROID_NDK_ROOT", spotifyNdk.absolutePath)
    environment(
        "PATH",
        "C:/Program Files (x86)/Microsoft Visual Studio/2022/BuildTools/VC/Tools/MSVC/14.44.35207/bin/Hostx64/x64;" +
            "C:/Program Files (x86)/Microsoft Visual Studio/2022/BuildTools/Common7/IDE/CommonExtensions/Microsoft/CMake/CMake/bin;" +
            System.getenv("PATH"),
    )
    inputs.dir(spotifyRustDir)
    inputs.dir(rootProject.file("../third_party/librespot-dev"))
    outputs.dir(spotifyJniLibs)
    doFirst {
        if (!cargoNdk.isFile) {
            val installer = rootProject.file("../tool/ensure_cargo_ndk.ps1")
            val process = ProcessBuilder(
                "powershell", "-NoProfile", "-ExecutionPolicy", "Bypass", "-File", installer.absolutePath,
            ).directory(rootProject.projectDir.parentFile).inheritIO().start()
            check(process.waitFor() == 0) { "Pengunduhan cargo-ndk gagal." }
        }
        check(cargoNdk.isFile) { "cargo-ndk belum tersedia: ${cargoNdk.absolutePath}" }
        check(spotifyNdk.isDirectory) { "Android NDK tidak ditemukan: ${spotifyNdk.absolutePath}" }
    }
}

tasks.named("preBuild").configure {
    dependsOn(buildSpotifyConnectNative)
}
