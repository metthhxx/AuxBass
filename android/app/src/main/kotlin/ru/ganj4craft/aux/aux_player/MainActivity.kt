package ru.ganj4craft.aux.aux_player

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.os.PowerManager
import android.provider.Settings
import android.view.WindowManager
import com.ryanheise.audioservice.AudioServiceActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : AudioServiceActivity() {
    private val CHANNEL = "ru.ganj4craft.aux/display"
    private val NOTIFICATION_CHANNEL_ID = "ru.ganj4craft.aux.channel.audio"

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        setHighRefreshRate()
        createNotificationChannel()
        requestNotificationPermission()
    }

    private fun createNotificationChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channelName = "AuxBass Music"
            val manager = getSystemService(NotificationManager::class.java)
            val existing = manager?.getNotificationChannel(NOTIFICATION_CHANNEL_ID)
            if (existing == null) {
                val channel = NotificationChannel(
                    NOTIFICATION_CHANNEL_ID,
                    channelName,
                    NotificationManager.IMPORTANCE_LOW
                ).apply {
                    description = "Воспроизведение музыки AuxBass"
                    setShowBadge(false)
                    lockscreenVisibility = Notification.VISIBILITY_PUBLIC
                }
                manager?.createNotificationChannel(channel)
            }
        }
    }

    private fun requestNotificationPermission() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            if (checkSelfPermission(android.Manifest.permission.POST_NOTIFICATIONS) != android.content.pm.PackageManager.PERMISSION_GRANTED) {
                requestPermissions(arrayOf(android.Manifest.permission.POST_NOTIFICATIONS), 1001)
            }
        }
    }

    private fun areNotificationsEnabled(): Boolean {
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            checkSelfPermission(android.Manifest.permission.POST_NOTIFICATIONS) == android.content.pm.PackageManager.PERMISSION_GRANTED
        } else if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
            val manager = getSystemService(NotificationManager::class.java)
            manager?.areNotificationsEnabled() ?: true
        } else {
            true
        }
    }

    private fun openNotificationSettings() {
        try {
            val intent = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                Intent(Settings.ACTION_APP_NOTIFICATION_SETTINGS).apply {
                    putExtra(Settings.EXTRA_APP_PACKAGE, packageName)
                }
            } else {
                Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS).apply {
                    data = Uri.fromParts("package", packageName, null)
                }
            }
            intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            startActivity(intent)
        } catch (e: Exception) {
            e.printStackTrace()
        }
    }

    private fun isIgnoringBatteryOptimizations(): Boolean {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            val powerManager = getSystemService(Context.POWER_SERVICE) as? PowerManager
            return powerManager?.isIgnoringBatteryOptimizations(packageName) ?: true
        }
        return true
    }

    private fun requestIgnoreBatteryOptimizations() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            try {
                val intent = Intent(Settings.ACTION_REQUEST_IGNORE_BATTERY_OPTIMIZATIONS).apply {
                    data = Uri.parse("package:$packageName")
                    addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                }
                startActivity(intent)
            } catch (e: Exception) {
                try {
                    val fallback = Intent(Settings.ACTION_IGNORE_BATTERY_OPTIMIZATION_SETTINGS).apply {
                        addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                    }
                    startActivity(fallback)
                } catch (e2: Exception) {
                    e2.printStackTrace()
                }
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
                "areNotificationsEnabled" -> {
                    result.success(areNotificationsEnabled())
                }
                "requestNotificationPermission" -> {
                    requestNotificationPermission()
                    result.success(true)
                }
                "openNotificationSettings" -> {
                    openNotificationSettings()
                    result.success(true)
                }
                "isIgnoringBatteryOptimizations" -> {
                    result.success(isIgnoringBatteryOptimizations())
                }
                "requestIgnoreBatteryOptimizations" -> {
                    requestIgnoreBatteryOptimizations()
                    result.success(true)
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

            val intent = Intent(Intent.ACTION_VIEW).apply {
                setDataAndType(uri, "application/vnd.android.package-archive")
                flags = Intent.FLAG_ACTIVITY_NEW_TASK or
                        Intent.FLAG_GRANT_READ_URI_PERMISSION
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
