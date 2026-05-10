package com.pocketledger.companion

import android.content.Intent
import app.tauri.annotation.Command
import app.tauri.annotation.TauriPlugin
import app.tauri.plugin.Invoke
import app.tauri.plugin.Plugin

@TauriPlugin
class PrintPlugin(private val activity: android.app.Activity) : Plugin(activity) {

    @Command
    fun startService(invoke: Invoke) {
        val intent = Intent(activity, PrintService::class.java)
        activity.startForegroundService(intent)
        invoke.resolve()
    }

    @Command
    fun stopService(invoke: Invoke) {
        val intent = Intent(activity, PrintService::class.java)
        activity.stopService(intent)
        invoke.resolve()
    }
}
