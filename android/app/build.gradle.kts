import java.util.Base64
import org.jetbrains.kotlin.gradle.dsl.JvmTarget

plugins {
    id("com.android.application")
    id("org.jetbrains.kotlin.android")
    id("dev.flutter.flutter-gradle-plugin")
}

val generatedIMailResDir = layout.buildDirectory.dir("generated/imailBranding/res")

val generateIMailBrandingResources by tasks.registering {
    val launcherSource = file("src/main/branding/imail_launcher.webp.b64")
    val splashSource1 = file("src/main/branding/imail_splash.webp.b64.part1")
    val splashSource2 = file("src/main/branding/imail_splash.webp.b64.part2")

    inputs.files(launcherSource, splashSource1, splashSource2)
    outputs.dir(generatedIMailResDir)

    doLast {
        val drawableDir = generatedIMailResDir.get().dir("drawable-nodpi").asFile
        drawableDir.mkdirs()
        val decoder = Base64.getDecoder()

        drawableDir.resolve("imail_launcher.webp").writeBytes(
            decoder.decode(launcherSource.readText().trim())
        )

        val splashBase64 = buildString {
            append(splashSource1.readText().trim())
            append(splashSource2.readText().trim())
        }
        drawableDir.resolve("imail_splash.webp").writeBytes(
            decoder.decode(splashBase64)
        )
    }
}

android {
    namespace = "ls.co.ithute.imail"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        applicationId = "ls.co.ithute.imail"
        minSdk = 23
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    sourceSets.getByName("main").res.srcDir(generatedIMailResDir)

    buildTypes {
        release {
            // Replace with a Play signing config before publishing.
            signingConfig = signingConfigs.getByName("debug")
        }
    }
}

kotlin {
    compilerOptions {
        jvmTarget.set(JvmTarget.JVM_17)
    }
}

tasks.named("preBuild").configure {
    dependsOn(generateIMailBrandingResources)
}

flutter { source = "../.." }
