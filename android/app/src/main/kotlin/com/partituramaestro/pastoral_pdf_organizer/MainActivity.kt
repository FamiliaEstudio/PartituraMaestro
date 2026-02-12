package com.partituramaestro.pastoral_pdf_organizer

import android.app.Activity
import android.content.Intent
import android.net.Uri
import android.provider.DocumentsContract
import androidx.documentfile.provider.DocumentFile
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val uriChannelName = "partituramaestro/uri_access"
    private val documentChannelName = "partituramaestro/document_browser"
    private val treePickerRequestCode = 8404
    private var pendingTreePickerResult: MethodChannel.Result? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, uriChannelName).setMethodCallHandler { call, result ->
            when (call.method) {
                "persistUriPermission" -> {
                    val uriString = call.argument<String>("uri")
                    if (uriString.isNullOrBlank()) {
                        result.success(false)
                        return@setMethodCallHandler
                    }

                    val granted = persistUriPermission(uriString)
                    result.success(granted)
                }

                "openUriBytes" -> {
                    val uriString = call.argument<String>("uri")
                    if (uriString.isNullOrBlank()) {
                        result.success(null)
                        return@setMethodCallHandler
                    }

                    val bytes = openUriBytes(uriString)
                    result.success(bytes)
                }

                "listTreeDocumentsRecursively" -> {
                    val treeUriString = call.argument<String>("treeUri")
                    if (treeUriString.isNullOrBlank()) {
                        result.success(emptyList<Map<String, Any?>>())
                        return@setMethodCallHandler
                    }

                    val docs = listTreeDocumentsRecursively(treeUriString)
                    result.success(docs)
                }

                else -> result.notImplemented()
            }
        }

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, documentChannelName).setMethodCallHandler { call, result ->
            when (call.method) {
                "pickDocumentTree" -> pickDocumentTree(result)
                "listDocumentChildren" -> listDocumentChildren(call, result)
                else -> result.notImplemented()
            }
        }
    }

    private fun pickDocumentTree(result: MethodChannel.Result) {
        if (pendingTreePickerResult != null) {
            result.error("picker_in_progress", "Já existe uma seleção de pasta em andamento.", null)
            return
        }

        pendingTreePickerResult = result
        val intent = Intent(Intent.ACTION_OPEN_DOCUMENT_TREE).apply {
            addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
            addFlags(Intent.FLAG_GRANT_PERSISTABLE_URI_PERMISSION)
            addFlags(Intent.FLAG_GRANT_PREFIX_URI_PERMISSION)
        }
        startActivityForResult(intent, treePickerRequestCode)
    }

    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode != treePickerRequestCode) return

        val callback = pendingTreePickerResult
        pendingTreePickerResult = null

        if (callback == null) return
        if (resultCode != Activity.RESULT_OK || data?.data == null) {
            callback.success(null)
            return
        }

        val treeUri = data.data!!
        try {
            contentResolver.takePersistableUriPermission(
                treeUri,
                Intent.FLAG_GRANT_READ_URI_PERMISSION
            )
        } catch (_: SecurityException) {
        }
        callback.success(treeUri.toString())
    }

    private fun listDocumentChildren(call: MethodCall, result: MethodChannel.Result) {
        val treeUriString = call.argument<String>("treeUri")
        val parentUriString = call.argument<String>("parentUri")
        if (treeUriString.isNullOrBlank() || parentUriString.isNullOrBlank()) {
            result.success(emptyList<Map<String, Any?>>())
            return
        }

        try {
            val treeUri = Uri.parse(treeUriString)
            val parentUri = Uri.parse(parentUriString)
            val parent = if (parentUri == treeUri) {
                DocumentFile.fromTreeUri(this, treeUri)
            } else {
                DocumentFile.fromSingleUri(this, parentUri)
            }

            val childDocs = parent?.listFiles()?.toList() ?: emptyList()
            val mapped = childDocs.map { doc ->
                mapOf(
                    "uri" to doc.uri.toString(),
                    "name" to (doc.name ?: "Sem nome"),
                    "isDirectory" to doc.isDirectory,
                    "isFile" to doc.isFile,
                    "mimeType" to doc.type
                )
            }.sortedBy { (it["name"] as String).lowercase() }

            result.success(mapped)
        } catch (ex: Exception) {
            result.error("list_failed", ex.message, null)
        }
    }


    private fun listTreeDocumentsRecursively(treeUriString: String): List<Map<String, Any?>> {
        return try {
            val treeUri = Uri.parse(treeUriString)
            val root = DocumentFile.fromTreeUri(this, treeUri) ?: return emptyList()
            val out = mutableListOf<Map<String, Any?>>()

            fun walk(node: DocumentFile) {
                if (node.isFile) {
                    out.add(
                        mapOf(
                            "displayName" to (node.name ?: "Sem nome"),
                            "uri" to node.uri.toString(),
                            "size" to if (node.length() >= 0) node.length() else null,
                            "mimeType" to node.type,
                        )
                    )
                    return
                }
                if (!node.isDirectory) return

                node.listFiles().forEach { child -> walk(child) }
            }

            walk(root)
            out.sortedBy { (it["displayName"] as String).lowercase() }
        } catch (_: Exception) {
            emptyList()
        }
    }

    private fun persistUriPermission(uriString: String): Boolean {
        return try {
            val uri = Uri.parse(uriString)
            val persisted = contentResolver.persistedUriPermissions.any {
                it.uri == uri && it.isReadPermission
            }
            if (persisted) {
                true
            } else {
                contentResolver.takePersistableUriPermission(uri, Intent.FLAG_GRANT_READ_URI_PERMISSION)
                true
            }
        } catch (_: SecurityException) {
            false
        } catch (_: UnsupportedOperationException) {
            false
        } catch (_: IllegalArgumentException) {
            false
        }
    }

    private fun openUriBytes(uriString: String): ByteArray? {
        return try {
            val uri = Uri.parse(uriString)
            val normalizedUri = if (DocumentsContract.isTreeUri(uri)) {
                DocumentsContract.buildDocumentUriUsingTree(uri, DocumentsContract.getTreeDocumentId(uri))
            } else {
                uri
            }
            contentResolver.openInputStream(normalizedUri)?.use { stream -> stream.readBytes() }
        } catch (_: SecurityException) {
            null
        } catch (_: IllegalArgumentException) {
            null
        }
    }
}
