package ru.ganj4craft.aux.aux_player

import android.os.Build
import android.os.Bundle
import android.view.WindowManager
import com.ryanheise.audioservice.AudioServiceActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : AudioServiceActivity() {
    private val CHANNEL = "ru.ganj4craft.aux/display"

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        setHighRefreshRate()
        requestNotificationPermission()
    }

    private fun requestNotificationPermission() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            if (checkSelfPermission(android.Manifest.permission.POST_NOTIFICATIONS) != android.content.pm.PackageManager.PERMISSION_GRANTED) {
                requestPermissions(arrayOf(android.Manifest.permission.POST_NOTIFICATIONS), 1001)
            }
        }
    }

    override fun onResume() {
        super.onResume()
        setHighRefreshRate()
    }

    override fun onAttachedToWindow() {
        super.onAttachedToWindow()
        setHighRefreshRate()
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "setHighRefreshRate" -> {
                    setHighRefreshRate()
                    result.success(true)
                }
                "getRefreshRate" -> {
                    val rate = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
                        display?.refreshRate ?: 60f
                    } else {
                        @Suppress("DEPRECATION")
                        windowManager.defaultDisplay?.refreshRate ?: 60f
                    }
                    result.success(rate.toDouble())
                }
                "installApk" -> {
                    val filePath = call.argument<String>("filePath")
                    if (filePath != null) {
                        installApk(filePath)
                        result.success(true)
                    } else {
                        result.error("INVALID_PATH", "File path is null", null)
                    }
                }
                else -> result.notImplemented()
            }
        }
    }

    private fun installApk(filePath: String) {
        try {
            val file = java.io.File(filePath)
            if (!file.exists()) return

            val uri = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
                androidx.core.content.FileProvider.getUriForFile(
                    this,
                    "${applicationContext.packageName}.fileprovider",
                    file
                )
            } else {
                android.net.Uri.fromFile(file)
            }

            val intent = android.content.Intent(android.content.Intent.ACTION_VIEW).apply {
                setDataAndType(uri, "application/vnd.android.package-archive")
                flags = android.content.Intent.FLAG_ACTIVITY_NEW_TASK or
                        android.content.Intent.FLAG_GRANT_READ_URI_PERMISSION
            }
            startActivity(intent)
        } catch (e: Exception) {
            e.printStackTrace()
        }
    }

    private fun setHighRefreshRate() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            try {
                val disp = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
                    display
                } else {
                    @Suppress("DEPRECATION")
                    windowManager.defaultDisplay
                }

                val modes = disp?.supportedModes
                if (!modes.isNullOrEmpty()) {
                    // Ищем режим дисплея с максимальной частотой кадров (144Hz / 120Hz)
                    val maxMode = modes.maxByOrNull { it.refreshRate }
                    if (maxMode != null) {
                        val params = window.attributes
                        params.preferredDisplayModeId = maxMode.modeId
                        @Suppress("DEPRECATION")
                        params.preferredRefreshRate = maxMode.refreshRate
                        window.attributes = params
                    }
                }
            } catch (e: Exception) {
                e.printStackTrace()
            }
        }
    }
}

