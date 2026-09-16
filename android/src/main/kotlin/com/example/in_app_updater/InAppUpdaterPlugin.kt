package com.example.in_app_updater

import android.app.Activity
import android.content.Intent
import android.content.IntentSender
import com.google.android.play.core.appupdate.AppUpdateManager
import com.google.android.play.core.appupdate.AppUpdateManagerFactory
import com.google.android.play.core.appupdate.AppUpdateOptions
import com.google.android.play.core.install.InstallStateUpdatedListener
import com.google.android.play.core.install.model.AppUpdateType
import com.google.android.play.core.install.model.InstallStatus
import com.google.android.play.core.install.model.UpdateAvailability
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.embedding.engine.plugins.activity.ActivityAware
import io.flutter.embedding.engine.plugins.activity.ActivityPluginBinding
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.PluginRegistry

private const val METHOD_CHANNEL = "in_app_updater/methods"
private const val EVENT_CHANNEL = "in_app_updater/state"
private const val UPDATE_REQUEST_CODE = 4780

/** Wraps Play Core's In-App Update API and exposes it over a method/event channel. */
class InAppUpdaterPlugin :
    FlutterPlugin,
    ActivityAware,
    MethodChannel.MethodCallHandler,
    EventChannel.StreamHandler,
    PluginRegistry.ActivityResultListener {

    private lateinit var methodChannel: MethodChannel
    private lateinit var eventChannel: EventChannel
    private var appUpdateManager: AppUpdateManager? = null
    private var activity: Activity? = null
    private var eventSink: EventChannel.EventSink? = null
    private var pendingUpdateResult: MethodChannel.Result? = null

    private val installStateListener = InstallStateUpdatedListener { state ->
        eventSink?.success(
            mapOf(
                "status" to state.installStatus().toStatusString(),
                "bytesDownloaded" to state.bytesDownloaded(),
                "totalBytesToDownload" to state.totalBytesToDownload()
            )
        )
    }

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        methodChannel = MethodChannel(binding.binaryMessenger, METHOD_CHANNEL)
        methodChannel.setMethodCallHandler(this)
        eventChannel = EventChannel(binding.binaryMessenger, EVENT_CHANNEL)
        eventChannel.setStreamHandler(this)
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        methodChannel.setMethodCallHandler(null)
        eventChannel.setStreamHandler(null)
    }

    override fun onAttachedToActivity(binding: ActivityPluginBinding) {
        activity = binding.activity
        appUpdateManager = AppUpdateManagerFactory.create(binding.activity)
        binding.addActivityResultListener(this)
    }

    override fun onReattachedToActivityForConfigChanges(binding: ActivityPluginBinding) {
        activity = binding.activity
        binding.addActivityResultListener(this)
        // detachActivity() (called on rotation/config change) unregisters this listener;
        // re-register it so a Dart-side EventChannel subscription started before the
        // config change keeps receiving install state updates afterwards.
        if (eventSink != null) {
            appUpdateManager?.registerListener(installStateListener)
        }
    }

    override fun onDetachedFromActivityForConfigChanges() = detachActivity()

    override fun onDetachedFromActivity() = detachActivity()

    private fun detachActivity() {
        appUpdateManager?.unregisterListener(installStateListener)
        activity = null
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "checkForUpdate" -> checkForUpdate(result)
            "startImmediateUpdate" -> startUpdate(AppUpdateType.IMMEDIATE, result)
            "startFlexibleUpdate" -> startUpdate(AppUpdateType.FLEXIBLE, result)
            "completeFlexibleUpdate" -> completeFlexibleUpdate(result)
            else -> result.notImplemented()
        }
    }

    override fun onListen(arguments: Any?, sink: EventChannel.EventSink) {
        eventSink = sink
        appUpdateManager?.registerListener(installStateListener)
    }

    override fun onCancel(arguments: Any?) {
        appUpdateManager?.unregisterListener(installStateListener)
        eventSink = null
    }

    private fun checkForUpdate(result: MethodChannel.Result) {
        val manager = appUpdateManager
            ?: return result.error("NO_ACTIVITY", "Plugin is not attached to an activity", null)
        manager.appUpdateInfo
            .addOnSuccessListener { info ->
                result.success(
                    mapOf(
                        "updateAvailable" to (info.updateAvailability() == UpdateAvailability.UPDATE_AVAILABLE),
                        "immediateAllowed" to info.isUpdateTypeAllowed(AppUpdateType.IMMEDIATE),
                        "flexibleAllowed" to info.isUpdateTypeAllowed(AppUpdateType.FLEXIBLE),
                        "availableVersionCode" to info.availableVersionCode(),
                        "priority" to info.updatePriority(),
                        "installStatus" to info.installStatus().toStatusString()
                    )
                )
            }
            .addOnFailureListener { e -> result.error("CHECK_FAILED", e.message, null) }
    }

    private fun startUpdate(type: Int, result: MethodChannel.Result) {
        val manager = appUpdateManager
        val currentActivity = activity
        if (manager == null || currentActivity == null) {
            result.error("NO_ACTIVITY", "Plugin is not attached to an activity", null)
            return
        }
        manager.appUpdateInfo
            .addOnSuccessListener { info ->
                if (info.updateAvailability() == UpdateAvailability.UPDATE_AVAILABLE &&
                    info.isUpdateTypeAllowed(type)
                ) {
                    try {
                        pendingUpdateResult = result
                        manager.startUpdateFlowForResult(
                            info,
                            currentActivity,
                            AppUpdateOptions.newBuilder(type).build(),
                            UPDATE_REQUEST_CODE
                        )
                    } catch (e: IntentSender.SendIntentException) {
                        pendingUpdateResult = null
                        result.error("START_FAILED", e.message, null)
                    }
                } else {
                    result.error("UPDATE_NOT_AVAILABLE", "No update of the requested type is available", null)
                }
            }
            .addOnFailureListener { e -> result.error("CHECK_FAILED", e.message, null) }
    }

    private fun completeFlexibleUpdate(result: MethodChannel.Result) {
        appUpdateManager?.completeUpdate()
        result.success(null)
    }

    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?): Boolean {
        if (requestCode == UPDATE_REQUEST_CODE) {
            pendingUpdateResult?.success(resultCode == Activity.RESULT_OK)
            pendingUpdateResult = null
            return true
        }
        return false
    }
}

private fun Int.toStatusString(): String = when (this) {
    InstallStatus.PENDING -> "pending"
    InstallStatus.DOWNLOADING -> "downloading"
    InstallStatus.DOWNLOADED -> "downloaded"
    InstallStatus.INSTALLING -> "installing"
    InstallStatus.INSTALLED -> "installed"
    InstallStatus.FAILED -> "failed"
    InstallStatus.CANCELED -> "canceled"
    else -> "unknown"
}
