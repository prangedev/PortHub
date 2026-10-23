package io.github.porthub

import android.app.Activity
import android.content.ActivityNotFoundException
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.provider.DocumentsContract
import android.provider.OpenableColumns
import io.flutter.plugin.common.MethodChannel
import java.io.FileInputStream

/**
 * Arquivos de jogos para emuladores (ISOs de vários GB) via Storage Access
 * Framework: nada é copiado — o PortHub guarda o `content://` com permissão
 * persistente, lê só os setores necessários e repassa a URI ao emulador.
 */
class RomFiles(private val activity: Activity) {
    private var pending: MethodChannel.Result? = null
    private var pendingExtensions: List<String> = emptyList()

    companion object {
        const val REQ_FILES = 7101
        const val REQ_TREE = 7102
        private const val PERSIST = Intent.FLAG_GRANT_READ_URI_PERMISSION
    }

    fun pickFiles(result: MethodChannel.Result) {
        if (!begin(result)) return
        val intent = Intent(Intent.ACTION_OPEN_DOCUMENT).apply {
            addCategory(Intent.CATEGORY_OPENABLE)
            type = "*/*"
            putExtra(Intent.EXTRA_ALLOW_MULTIPLE, true)
            addFlags(PERSIST or Intent.FLAG_GRANT_PERSISTABLE_URI_PERMISSION)
        }
        activity.startActivityForResult(intent, REQ_FILES)
    }

    fun pickFolder(extensions: List<String>, result: MethodChannel.Result) {
        if (!begin(result)) return
        pendingExtensions = extensions.map { it.lowercase() }
        val intent = Intent(Intent.ACTION_OPEN_DOCUMENT_TREE).apply {
            addFlags(PERSIST or Intent.FLAG_GRANT_PERSISTABLE_URI_PERMISSION)
        }
        activity.startActivityForResult(intent, REQ_TREE)
    }

    private fun begin(result: MethodChannel.Result): Boolean {
        if (pending != null) {
            result.error("busy", "Seletor de arquivos já aberto", null)
            return false
        }
        pending = result
        return true
    }

    /** Retorna true se o resultado era nosso. */
    fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?): Boolean {
        if (requestCode != REQ_FILES && requestCode != REQ_TREE) return false
        val result = pending ?: return true
        pending = null
        if (resultCode != Activity.RESULT_OK || data == null) {
            result.success(emptyList<Map<String, Any?>>())
            return true
        }
        Thread {
            val files = try {
                if (requestCode == REQ_FILES) {
                    val uris = buildList {
                        data.clipData?.let { clip -> for (i in 0 until clip.itemCount) add(clip.getItemAt(i).uri) }
                        if (isEmpty()) data.data?.let { add(it) }
                    }
                    uris.mapNotNull { persist(it); describe(it) }
                } else {
                    val tree = data.data!!
                    persist(tree)
                    scanTree(tree, pendingExtensions)
                }
            } catch (e: Exception) {
                activity.runOnUiThread { result.error("pick_failed", e.message, null) }
                return@Thread
            }
            activity.runOnUiThread { result.success(files) }
        }.start()
        return true
    }

    private fun persist(uri: Uri) {
        try {
            activity.contentResolver.takePersistableUriPermission(uri, PERSIST)
        } catch (_: SecurityException) {
            // Alguns provedores não oferecem permissão persistente; vale até reiniciar.
        }
    }

    private fun describe(uri: Uri): Map<String, Any?>? =
        activity.contentResolver.query(uri, arrayOf(OpenableColumns.DISPLAY_NAME, OpenableColumns.SIZE), null, null, null)
            ?.use { c ->
                if (!c.moveToFirst()) return null
                mapOf("uri" to uri.toString(), "name" to c.getString(0), "size" to if (c.isNull(1)) null else c.getLong(1))
            }

    /** Lista recursivamente os arquivos da pasta escolhida com as extensões pedidas. */
    private fun scanTree(tree: Uri, extensions: List<String>, maxDepth: Int = 4): List<Map<String, Any?>> {
        val out = mutableListOf<Map<String, Any?>>()
        val cr = activity.contentResolver
        fun walk(docId: String, depth: Int) {
            val children = DocumentsContract.buildChildDocumentsUriUsingTree(tree, docId)
            cr.query(
                children,
                arrayOf(
                    DocumentsContract.Document.COLUMN_DOCUMENT_ID,
                    DocumentsContract.Document.COLUMN_DISPLAY_NAME,
                    DocumentsContract.Document.COLUMN_MIME_TYPE,
                    DocumentsContract.Document.COLUMN_SIZE,
                ),
                null, null, null,
            )?.use { c ->
                while (c.moveToNext()) {
                    val id = c.getString(0)
                    val name = c.getString(1) ?: continue
                    if (c.getString(2) == DocumentsContract.Document.MIME_TYPE_DIR) {
                        if (depth < maxDepth) walk(id, depth + 1)
                    } else if (extensions.any { name.lowercase().endsWith(it) }) {
                        val uri = DocumentsContract.buildDocumentUriUsingTree(tree, id)
                        out.add(mapOf("uri" to uri.toString(), "name" to name, "size" to if (c.isNull(3)) null else c.getLong(3)))
                    }
                }
            }
        }
        walk(DocumentsContract.getTreeDocumentId(tree), 0)
        return out
    }

    /** Lê [length] bytes a partir de [offset] — o ISO nunca é carregado inteiro. */
    fun read(uri: String, offset: Long, length: Int): ByteArray {
        activity.contentResolver.openFileDescriptor(Uri.parse(uri), "r").use { pfd ->
            FileInputStream(pfd!!.fileDescriptor).channel.use { ch ->
                val buf = java.nio.ByteBuffer.allocate(length)
                var pos = offset
                while (buf.hasRemaining()) {
                    val n = ch.read(buf, pos)
                    if (n <= 0) break
                    pos += n
                }
                return buf.array().copyOf(buf.position())
            }
        }
    }

    fun size(uri: String): Long? =
        activity.contentResolver.openFileDescriptor(Uri.parse(uri), "r")?.use { it.statSize.takeIf { s -> s >= 0 } }

    fun canRead(uri: String): Boolean = try {
        activity.contentResolver.openFileDescriptor(Uri.parse(uri), "r")?.close()
        true
    } catch (_: Exception) {
        false
    }

    fun release(uri: String) {
        try {
            activity.contentResolver.releasePersistableUriPermission(Uri.parse(uri), PERSIST)
        } catch (_: SecurityException) {
        }
    }

    /**
     * Abre o jogo direto no emulador. A URI vai como `data` com permissão de
     * leitura temporária: o XenDroid resolve o caminho real quando pode e, sem
     * acesso ao armazenamento, lê pelo descritor (`/proc/self/fd`).
     */
    fun launch(context: Context, pkg: String, activityClass: String, uri: String, action: String): String? {
        val intent = Intent(action).apply {
            component = ComponentName(pkg, activityClass)
            setDataAndType(Uri.parse(uri), "application/octet-stream")
            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_GRANT_READ_URI_PERMISSION)
        }
        return try {
            context.startActivity(intent)
            null
        } catch (e: ActivityNotFoundException) {
            "Emulador não encontrado ($pkg)"
        } catch (e: SecurityException) {
            e.message ?: "Permissão negada"
        }
    }
}
