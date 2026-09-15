pluginManagement {
    val flutterSdkPath =
        run {
            val properties = java.util.Properties()
            file("local.properties").inputStream().use { properties.load(it) }
            val flutterSdkPath = properties.getProperty("flutter.sdk")
            require(flutterSdkPath != null) { "flutter.sdk not set in local.properties" }
            flutterSdkPath
        }

    includeBuild("$flutterSdkPath/packages/flutter_tools/gradle")

    repositories {
        google()
        mavenCentral()
        gradlePluginPortal()
    }
}

plugins {
    id("dev.flutter.flutter-plugin-loader") version "1.0.0"
    // Pinned to AGP 8.x: file_picker 11 + package_info_plus 8.x (the current
    // dependency set) still apply the explicit `kotlin-android` plugin, which
    // AGP 9+ rejects. 8.11.1 is Flutter 3.47's minimum supported AGP.
    // CI builds with Temurin 17; a local JDK newer than 21 also needs
    // `-Dorg.gradle.jvmargs=--enable-native-access=ALL-UNNAMED` for AGP 8.
    id("com.android.application") version "8.11.1" apply false
    id("org.jetbrains.kotlin.android") version "2.2.20" apply false
}

include(":app")
