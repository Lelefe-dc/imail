package ls.co.ithute.imail

import android.app.Activity
import android.app.KeyguardManager
import android.content.Context
import android.content.Intent
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val securityChannel = "ls.co.ithute.imail/security"
    private val unlockRequestCode = 9911
    private var pendingUnlockResult: MethodChannel.Result? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            securityChannel,
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "authenticate" -> authenticateDevice(result)
                else -> result.notImplemented()
            }
        }
    }

    private fun authenticateDevice(result: MethodChannel.Result) {
        if (pendingUnlockResult != null) {
            result.error("busy", "An iMail unlock request is already active.", null)
            return
        }

        val keyguard = getSystemService(Context.KEYGUARD_SERVICE) as KeyguardManager
        if (!keyguard.isDeviceSecure) {
            result.error(
                "not_secure",
                "Set a device screen lock before enabling iMail app lock.",
                null,
            )
            return
        }

        @Suppress("DEPRECATION")
        val intent = keyguard.createConfirmDeviceCredentialIntent(
            "Unlock iMail",
            "Confirm your device screen lock to open your mail",
        )
        if (intent == null) {
            result.error("unavailable", "Device credential confirmation is unavailable.", null)
            return
        }

        pendingUnlockResult = result
        @Suppress("DEPRECATION")
        startActivityForResult(intent, unlockRequestCode)
    }

    @Deprecated("Deprecated by Android, retained for the device credential compatibility flow")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode != unlockRequestCode) return
        val result = pendingUnlockResult
        pendingUnlockResult = null
        result?.success(resultCode == Activity.RESULT_OK)
    }
}
