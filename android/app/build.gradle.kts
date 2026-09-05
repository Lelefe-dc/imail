import java.util.Base64
import org.jetbrains.kotlin.gradle.dsl.JvmTarget

plugins {
    id("com.android.application")
    id("org.jetbrains.kotlin.android")
    id("dev.flutter.flutter-gradle-plugin")
}

fun decodeWebpBase64(raw: String, label: String): ByteArray {
    // The branding files are stored as UTF-8 base64 text because GitHub's
    // contents API cannot write binary assets through this workflow. Be
    // tolerant of accidental wrappers/whitespace introduced by tooling, but
    // only decode the actual WebP payload beginning with the RIFF/WebP prefix.
    val start = raw.indexOf("UklG")
    require(start >= 0) { "$label does not contain a WebP base64 payload" }

    val fromPayload = raw.substring(start)
    val paddedEnd = fromPayload.lastIndexOf('=')
    val payloadRegion = if (paddedEnd >= 0) {
        fromPayload.substring(0, paddedEnd + 1)
    } else {
        fromPayload
    }
    val cleaned = payloadRegion.filter { ch ->
        ch.isLetterOrDigit() || ch == '+' || ch == '/' || ch == '='
    }

    val bytes = Base64.getDecoder().decode(cleaned)
    require(bytes.size >= 12 &&
            bytes[0].toInt().toChar() == 'R' &&
            bytes[1].toInt().toChar() == 'I' &&
            bytes[2].toInt().toChar() == 'F' &&
            bytes[3].toInt().toChar() == 'F' &&
            bytes[8].toInt().toChar() == 'W' &&
            bytes[9].toInt().toChar() == 'E' &&
            bytes[10].toInt().toChar() == 'B' &&
            bytes[11].toInt().toChar() == 'P') {
        "$label decoded, but it is not a valid WebP file"
    }
    return bytes
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

        drawableDir.resolve("imail_launcher.webp").writeBytes(
            decodeWebpBase64(
                launcherSource.readText(),
                "iMail launcher artwork",
            )
        )

        val splashBase64 = buildString {
            append(splashSource1.readText())
            append(splashSource2.readText())
        }
        drawableDir.resolve("imail_splash.webp").writeBytes(
            decodeWebpBase64(
                splashBase64,
                "iMail splash artwork",
            )
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
