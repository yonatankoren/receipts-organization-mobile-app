package com.receipts.app

import android.content.Intent
import androidx.core.content.FileProvider
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File

class MainActivity: FlutterActivity() {
    private val CHANNEL = "com.receipts.app/share"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "sendGmail" -> {
                        val filePath = call.argument<String>("filePath")
                        val recipient = call.argument<String>("recipient")
                        val cc = call.argument<List<String>>("cc") ?: emptyList()
                        val subject = call.argument<String>("subject") ?: ""

                        if (filePath == null || recipient == null) {
                            result.error("INVALID_ARGS", "Missing required arguments", null)
                            return@setMethodCallHandler
                        }

                        try {
                            val file = File(filePath)
                            val uri = FileProvider.getUriForFile(
                                this,
                                "${applicationContext.packageName}.fileprovider",
                                file
                            )

                            val intent = Intent(Intent.ACTION_SEND).apply {
                                type = "application/zip"
                                putExtra(Intent.EXTRA_EMAIL, arrayOf(recipient))
                                if (cc.isNotEmpty()) {
                                    putExtra(Intent.EXTRA_CC, cc.toTypedArray())
                                }
                                putExtra(Intent.EXTRA_SUBJECT, subject)
                                putExtra(Intent.EXTRA_STREAM, uri)
                                setPackage("com.google.android.gm")
                                addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
                            }

                            startActivity(intent)
                            result.success(true)
                        } catch (e: Exception) {
                            result.error("GMAIL_UNAVAILABLE", e.message, null)
                        }
                    }
                    else -> result.notImplemented()
                }
            }
    }
}

