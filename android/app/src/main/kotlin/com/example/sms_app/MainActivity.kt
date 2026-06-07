package com.example.sms_app

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.os.Build
import android.os.Environment
import android.os.Handler
import android.os.Looper
import android.provider.Telephony
import android.telephony.SubscriptionManager
import io.flutter.embedding.android.FlutterActivity
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel
import java.io.File

class MainActivity : FlutterActivity() {
    private val STORAGE_CHANNEL = "storage_channel"
    private val SIM_CHANNEL = "sim_sms_channel"
    private val SIM_EVENTS = "sim_sms_events"
    private val SMS_RECEIVED_ACTION = "android.provider.Telephony.SMS_RECEIVED"

    private var smsReceiver: BroadcastReceiver? = null

    override fun configureFlutterEngine(flutterEngine: io.flutter.embedding.engine.FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        val messenger = flutterEngine.dartExecutor.binaryMessenger

        // --- Existing storage channel (unchanged) ---
        MethodChannel(messenger, STORAGE_CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "getDownloadsPath" -> {
                    val downloadsDir: File = Environment.getExternalStoragePublicDirectory(Environment.DIRECTORY_DOWNLOADS)
                    result.success(downloadsDir.absolutePath)
                }
                "getExternalStorageRoots" -> {
                    val externalDirs = getExternalFilesDirs(null)
                    val roots = mutableListOf<String>()
                    for (dir in externalDirs) {
                        if (dir != null) {
                            val path = dir.absolutePath
                            val index = path.indexOf("/Android/data")
                            if (index != -1) {
                                roots.add(path.substring(0, index))
                            }
                        }
                    }
                    result.success(roots)
                }
                else -> result.notImplemented()
            }
        }

        // --- SIM + SMS method channel ---
        MethodChannel(messenger, SIM_CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "getActiveSims" -> result.success(getActiveSims())
                "queryInbox" -> {
                    val address = call.argument<String>("address") ?: ""
                    result.success(queryInbox(address))
                }
                else -> result.notImplemented()
            }
        }

        // --- Incoming SMS event stream ---
        EventChannel(messenger, SIM_EVENTS).setStreamHandler(object : EventChannel.StreamHandler {
            override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
                registerSmsReceiver(events)
            }

            override fun onCancel(arguments: Any?) {
                unregisterSmsReceiver()
            }
        })
    }

    private fun getActiveSims(): List<Map<String, Any?>> {
        val sims = mutableListOf<Map<String, Any?>>()
        try {
            val sm = getSystemService(Context.TELEPHONY_SUBSCRIPTION_SERVICE) as SubscriptionManager
            val infoList = sm.activeSubscriptionInfoList ?: return sims
            for (info in infoList) {
                val number: String? = try { info.number } catch (e: SecurityException) { null }
                sims.add(
                    mapOf(
                        "subId" to info.subscriptionId,
                        "slotIndex" to info.simSlotIndex,
                        "number" to (number ?: ""),
                        "displayName" to (info.displayName?.toString() ?: ""),
                        "carrierName" to (info.carrierName?.toString() ?: "")
                    )
                )
            }
        } catch (e: Exception) {
            // ignore - return whatever we have
        }
        return sims
    }

    private fun queryInbox(address: String): List<Map<String, Any?>> {
        val messages = mutableListOf<Map<String, Any?>>()
        val subIdColumn = "sub_id"
        val projection = arrayOf(
            Telephony.Sms.ADDRESS,
            Telephony.Sms.BODY,
            Telephony.Sms.DATE,
            subIdColumn
        )
        val selection: String?
        val selectionArgs: Array<String>?
        if (address.isNotEmpty()) {
            selection = "${Telephony.Sms.ADDRESS} LIKE ?"
            selectionArgs = arrayOf("%$address")
        } else {
            selection = null
            selectionArgs = null
        }
        try {
            val cursor = contentResolver.query(
                Telephony.Sms.Inbox.CONTENT_URI,
                projection,
                selection,
                selectionArgs,
                "${Telephony.Sms.DATE} DESC"
            )
            cursor?.use {
                val addressIdx = it.getColumnIndex(Telephony.Sms.ADDRESS)
                val bodyIdx = it.getColumnIndex(Telephony.Sms.BODY)
                val dateIdx = it.getColumnIndex(Telephony.Sms.DATE)
                val subIdx = it.getColumnIndex(subIdColumn)
                while (it.moveToNext()) {
                    messages.add(
                        mapOf(
                            "address" to if (addressIdx >= 0) it.getString(addressIdx) else "",
                            "body" to if (bodyIdx >= 0) it.getString(bodyIdx) else "",
                            "date" to if (dateIdx >= 0) it.getLong(dateIdx) else 0L,
                            "subId" to if (subIdx >= 0) it.getInt(subIdx) else -1
                        )
                    )
                }
            }
        } catch (e: Exception) {
            // ignore - return whatever we collected
        }
        return messages
    }

    private fun registerSmsReceiver(events: EventChannel.EventSink?) {
        unregisterSmsReceiver()
        val handler = Handler(Looper.getMainLooper())
        smsReceiver = object : BroadcastReceiver() {
            override fun onReceive(context: Context?, intent: Intent?) {
                if (intent == null || intent.action != SMS_RECEIVED_ACTION) return
                try {
                    val msgs = Telephony.Sms.Intents.getMessagesFromIntent(intent) ?: return
                    if (msgs.isEmpty()) return
                    val body = StringBuilder()
                    for (m in msgs) {
                        body.append(m.messageBody ?: m.displayMessageBody ?: "")
                    }
                    val address = msgs[0].originatingAddress ?: ""
                    val timestamp = msgs[0].timestampMillis

                    var subId = intent.getIntExtra("subscription", -1)
                    if (subId == -1 && Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
                        subId = intent.getIntExtra(SubscriptionManager.EXTRA_SUBSCRIPTION_INDEX, -1)
                    }

                    val payload = mapOf(
                        "address" to address,
                        "body" to body.toString(),
                        "date" to timestamp,
                        "subId" to subId
                    )
                    handler.post { events?.success(payload) }
                } catch (e: Exception) {
                    // ignore malformed broadcasts
                }
            }
        }
        val filter = IntentFilter(SMS_RECEIVED_ACTION)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            registerReceiver(smsReceiver, filter, Context.RECEIVER_EXPORTED)
        } else {
            @Suppress("UnspecifiedRegisterReceiverFlag")
            registerReceiver(smsReceiver, filter)
        }
    }

    private fun unregisterSmsReceiver() {
        smsReceiver?.let {
            try {
                unregisterReceiver(it)
            } catch (e: IllegalArgumentException) {
                // wasn't registered
            }
        }
        smsReceiver = null
    }

    override fun onDestroy() {
        unregisterSmsReceiver()
        super.onDestroy()
    }
}
