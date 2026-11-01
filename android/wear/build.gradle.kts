plugins { id("com.android.application") }

android {
    namespace = "com.swiftmusic.swift_music"
    compileSdk = 36
    defaultConfig {
        applicationId = "com.swiftmusic.swift_music"
        minSdk = 30
        targetSdk = 36
        versionCode = 5
        versionName = "1.3.0"
    }
    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }
    buildTypes { release { signingConfig = signingConfigs.getByName("debug") } }
}
dependencies { implementation("com.google.android.gms:play-services-wearable:20.0.1") }
