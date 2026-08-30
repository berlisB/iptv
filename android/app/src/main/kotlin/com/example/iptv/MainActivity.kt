package com.example.iptv

import android.app.PictureInPictureParams
import android.content.res.Configuration
import android.os.Build
import android.util.Rational
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val pipChannelName = "com.example.iptv/pip"
    private var pipChannel: MethodChannel? = null

    /** Piloté par Flutter : true seulement quand une lecture est en cours. */
    private var pipEligible = false

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        pipChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, pipChannelName)
        pipChannel?.setMethodCallHandler { call, result ->
            when (call.method) {
                "enterPiP" -> {
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                        enterPictureInPictureMode(buildPipParams())
                        result.success(true)
                    } else {
                        result.error("UNSUPPORTED", "PiP requires Android 8+", null)
                    }
                }
                "setPipEligible" -> {
                    pipEligible = call.arguments == true
                    // API 31+ : autoEnterEnabled donne une transition fluide sur
                    // le geste "swipe up to home" (onUserLeaveHint n'est pas
                    // toujours appelé avec la navigation gestuelle).
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                        try {
                            setPictureInPictureParams(buildPipParams())
                        } catch (_: Exception) {
                        }
                    }
                    result.success(true)
                }
                else -> result.notImplemented()
            }
        }
    }

    private fun buildPipParams(): PictureInPictureParams {
        val builder = PictureInPictureParams.Builder()
            .setAspectRatio(Rational(16, 9))
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            builder.setAutoEnterEnabled(pipEligible)
        }
        return builder.build()
    }

    override fun onUserLeaveHint() {
        super.onUserLeaveHint()
        // PiP au bouton Home UNIQUEMENT si une lecture est en cours — sinon
        // l'app entière (grille, réglages…) se retrouverait dans la vignette.
        if (pipEligible && Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            try {
                enterPictureInPictureMode(buildPipParams())
            } catch (_: Exception) {
            }
        }
    }

    override fun onPictureInPictureModeChanged(
        isInPictureInPictureMode: Boolean,
        newConfig: Configuration,
    ) {
        super.onPictureInPictureModeChanged(isInPictureInPictureMode, newConfig)
        // Flutter masque les contrôles dans la vignette et les restaure après.
        pipChannel?.invokeMethod("pipChanged", isInPictureInPictureMode)
    }
}
