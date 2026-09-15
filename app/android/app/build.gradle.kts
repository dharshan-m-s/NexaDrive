import java.io.FileInputStream
import java.util.Properties

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// Release signing material. In CI the workflow decodes the KEYSTORE_BASE64 secret
// into a .jks file and writes app/android/key.properties (both gitignored). Locally a
// developer can do the same by hand. When no keystore is present the release build
// falls back to the debug key so that `flutter build apk --release` never hard-fails.
val keystorePropertiesFile = rootProject.file("key.properties")
val keystoreProperties = Properties()
if (keystorePropertiesFile.exists()) {
    keystoreProperties.load(FileInputStream(keystorePropertiesFile))
}

fun signingProp(key: String): String? =
    keystoreProperties.getProperty(key) ?: System.getenv(key)

android {
    namespace = "io.nexadrive.app"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        applicationId = "io.nexadrive.app"
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        // Versions flow through from pubspec.yaml (see flutter.versionCode / versionName).
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        create("release") {
            val storeFileValue = signingProp("storeFile")
            val storePasswordValue = signingProp("storePassword")
            val keyAliasValue = signingProp("keyAlias")
            val keyPasswordValue = signingProp("keyPassword")
            if (storeFileValue != null && storePasswordValue != null &&
                keyAliasValue != null && keyPasswordValue != null
            ) {
                storeFile = rootProject.file(storeFileValue)
                storePassword = storePasswordValue
                keyAlias = keyAliasValue
                keyPassword = keyPasswordValue
            }
        }
    }

    buildTypes {
        release {
            val releaseSigning = signingConfigs.getByName("release")
            signingConfig = if (releaseSigning.storeFile?.exists() == true) {
                releaseSigning
            } else {
                signingConfigs.getByName("debug")
            }
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