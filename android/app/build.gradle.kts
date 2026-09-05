import java.io.ByteArrayOutputStream
import java.util.Base64
import org.jetbrains.kotlin.gradle.dsl.JvmTarget

plugins {
    id("com.android.application")
    id("org.jetbrains.kotlin.android")
    id("dev.flutter.flutter-gradle-plugin")
}

fun cleanBase64(raw: String, label: String): String {
    // Branding is stored as UTF-8 base64 because this repository update path
    // cannot write binary resources directly. Keep only the actual payload.
    val start = raw.indexOf("UklG")
    require(start >= 0) { "$label does not contain a WebP base64 payload" }

    return raw.substring(start).filter { ch ->
        ch.isLetterOrDigit() || ch == '+' || ch == '/' || ch == '='
    }
}

fun decodeBase64Chunk(raw: String, label: String): ByteArray {
    val cleaned = cleanBase64(raw, label)
    return try {
        Base64.getDecoder().decode(cleaned)
    } catch (error: IllegalArgumentException) {
        throw GradleException("$label contains invalid base64 data", error)
    }
}

fun requireWebp(bytes: ByteArray, label: String): ByteArray {
    require(
        bytes.size >= 12 &&
            bytes[0].toInt().toChar() == 'R' &&
            bytes[1].toInt().toChar() == 'I' &&
            bytes[2].toInt().toChar() == 'F' &&
            bytes[3].toInt().toChar() == 'F' &&
            bytes[8].toInt().toChar() == 'W' &&
            bytes[9].toInt().toChar() == 'E' &&
            bytes[10].toInt().toChar() == 'B' &&
            bytes[11].toInt().toChar() == 'P'
    ) { "$label decoded, but it is not a valid WebP file" }
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

        val launcherBytes = requireWebp(
            decodeBase64Chunk(
                launcherSource.readText(),
                "iMail launcher artwork",
            ),
            "iMail launcher artwork",
        )
        drawableDir.resolve("imail_launcher.webp").writeBytes(launcherBytes)

        // The splash artwork was committed as two independently base64-encoded
        // binary chunks. Decode each chunk first and then join the bytes. Joining
        // the base64 strings themselves leaves padding in the middle and causes
        // Java's decoder to fail with "wrong 4-byte ending unit".
        val splashOut = ByteArrayOutputStream()
        splashOut.write(
            decodeBase64Chunk(
                splashSource1.readText(),
                "iMail splash artwork part 1",
            )
        )
        splashOut.write(
            decodeBase64Chunk(
                splashSource2.readText(),
                "iMail splash artwork part 2",
            )
        )
        val splashBytes = requireWebp(
            splashOut.toByteArray(),
            "iMail splash artwork",
        )
        drawableDir.resolve("imail_splash.webp").writeBytes(splashBytes)
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
