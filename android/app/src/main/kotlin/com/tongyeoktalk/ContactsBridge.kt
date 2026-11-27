package com.tongyeoktalk

import android.Manifest
import android.app.Activity
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.provider.BaseColumns
import android.provider.ContactsContract
import android.provider.ContactsContract.CommonDataKinds.Phone
import android.provider.ContactsContract.PhoneLookup
import android.telephony.PhoneNumberUtils
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.util.concurrent.Executors

internal class ContactsBridge(
    private val activity: Activity,
    messenger: BinaryMessenger,
) : MethodChannel.MethodCallHandler {
    private val channel = MethodChannel(messenger, "tongyeok/contacts")
    private val executor = Executors.newSingleThreadExecutor()
    private var permission: MethodChannel.Result? = null
    private var picker: MethodChannel.Result? = null
    private var pickerColumn = Phone.DISPLAY_NAME
    private val reads = mutableSetOf<MethodChannel.Result>()

    init {
        channel.setMethodCallHandler(this)
    }

    private fun granted() = activity.checkSelfPermission(Manifest.permission.READ_CONTACTS) ==
        PackageManager.PERMISSION_GRANTED

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "status" -> result.success(granted())
            "enable" -> {
                if (granted() || permission != null || picker != null) {
                    result.success(granted())
                    return
                }
                permission = result
                try {
                    activity.requestPermissions(arrayOf(Manifest.permission.READ_CONTACTS), READ)
                } catch (_: RuntimeException) {
                    permission = null
                    result.success(false)
                }
            }
            "pick" -> pick(result, Phone.DISPLAY_NAME)
            "pickPhone" -> pick(result, Phone.NUMBER)
            "lookup" -> {
                val numbers = call.arguments as? Map<*, *>
                if (!granted() || numbers == null || numbers.size > 30 || reads.isNotEmpty()) {
                    result.success(emptyMap<String, String>())
                    return
                }
                background(result, emptyMap<String, String>()) {
                    numbers.mapNotNull { (peer, phone) ->
                        if (peer is String && phone is String && numberPattern.matches(phone)) {
                            exactName(phone)?.let { peer to it }
                        } else null
                    }.toMap()
                }
            }
            else -> result.notImplemented()
        }
    }

    private fun background(result: MethodChannel.Result, fallback: Any?, work: () -> Any?) {
        reads.add(result)
        executor.execute {
            val value = try { work() } catch (_: RuntimeException) { fallback }
            activity.runOnUiThread {
                if (reads.remove(result)) result.success(value)
            }
        }
    }

    private fun exactName(phone: String): String? {
        val region = if (phone.startsWith("+82")) "KR" else "MN"
        val uri = Uri.withAppendedPath(PhoneLookup.CONTENT_FILTER_URI, Uri.encode(phone))
        val contacts = linkedMapOf<Long, String>()
        val fields = arrayOf(BaseColumns._ID, PhoneLookup.DISPLAY_NAME, PhoneLookup.NUMBER)
        activity.contentResolver.query(uri, fields, null, null, null)?.use { cursor ->
            while (cursor.moveToNext()) {
                val name = cursor.getString(1)?.trim()
                val storedNumber = cursor.getString(2)
                if (!name.isNullOrEmpty() && storedNumber != null &&
                    PhoneNumberUtils.formatNumberToE164(storedNumber, region) == phone) {
                    contacts[cursor.getLong(0)] = name
                }
            }
        }
        return contacts.values.singleOrNull()
    }

    @Suppress("DEPRECATION")
    private fun pick(result: MethodChannel.Result, column: String) {
        if (permission != null || picker != null) {
            result.success(null)
            return
        }
        picker = result
        pickerColumn = column
        try {
            activity.startActivityForResult(Intent(Intent.ACTION_PICK, Phone.CONTENT_URI), PICK)
        } catch (_: RuntimeException) {
            picker = null
            result.success(null)
        }
    }

    fun permissionResult(request: Int): Boolean {
        if (request != READ) return false
        val pending = permission
        permission = null
        pending?.success(granted())
        return true
    }

    fun pickerResult(request: Int, status: Int, data: Intent?): Boolean {
        if (request != PICK) return false
        val pending = picker ?: return true
        val column = pickerColumn
        picker = null
        val uri = data?.data
        if (status != Activity.RESULT_OK || uri?.scheme != "content" ||
            uri.authority != ContactsContract.AUTHORITY) {
            pending.success(null)
            return true
        }
        background(pending, null) {
            activity.contentResolver.query(uri, arrayOf(column), null, null, null)
                ?.use { cursor -> if (cursor.moveToFirst()) cursor.getString(0) else null }
        }
        return true
    }

    fun close() {
        channel.setMethodCallHandler(null)
        executor.shutdownNow()
        permission?.success(false)
        picker?.success(null)
        permission = null
        picker = null
        reads.forEach { it.success(null) }
        reads.clear()
    }

    companion object {
        private const val READ = 0x7A21
        private const val PICK = 0x7A22
        private val numberPattern = Regex("\\+(82|976)[0-9]{7,11}")
    }
}
