package dev.saifmukhtar.kinetic

import android.os.Build
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File

class MainActivity : FlutterActivity() {

    private val ATTESTATION_CHANNEL = "dev.saifmukhtar.kinetic/attestation"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            ATTESTATION_CHANNEL
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "verifyDevice" -> result.success(verifyDevice())
                else -> result.notImplemented()
            }
        }
    }

    /**
     * Lightweight root/tamper detection that works without any external SDK.
     * Returns one of: MEETS_STRONG_INTEGRITY, MEETS_BASIC_INTEGRITY, INTEGRITY_UNAVAILABLE
     */
    private fun verifyDevice(): String {
        // 1. Check for known root binaries in common install paths.
        val rootBinaries = listOf(
            "/system/app/Superuser.apk",
            "/sbin/su",
            "/system/bin/su",
            "/system/xbin/su",
            "/data/local/xbin/su",
            "/data/local/bin/su",
            "/system/sd/xbin/su",
            "/system/bin/failsafe/su",
            "/data/local/su",
            "/su/bin/su",
            "/system/xbin/busybox",
        )
        val hasRootFiles = rootBinaries.any { File(it).exists() }
        if (hasRootFiles) return "INTEGRITY_UNAVAILABLE"

        // 2. Check test-keys build tag — real retail devices use "release-keys".
        val buildTags = Build.TAGS ?: ""
        if (buildTags.contains("test-keys")) return "INTEGRITY_UNAVAILABLE"

        // 3. Check if the build is a known emulator.
        val isEmulator = Build.FINGERPRINT.startsWith("generic")
            || Build.FINGERPRINT.startsWith("unknown")
            || Build.MODEL.contains("Emulator")
            || Build.MODEL.contains("Android SDK built for x86")
            || Build.MANUFACTURER.contains("Genymotion")
            || Build.BRAND.startsWith("generic") && Build.DEVICE.startsWith("generic")
            || Build.PRODUCT == "google_sdk"
        // Emulators get BASIC so developers can still use local nodes.
        if (isEmulator) return "MEETS_BASIC_INTEGRITY"

        // 4. All checks passed — this is likely a stock, unrooted retail device.
        return "MEETS_STRONG_INTEGRITY"
    }
}
