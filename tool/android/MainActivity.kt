package __PACKAGE__

import android.app.Activity
import android.content.Intent
import android.net.Uri
import androidx.core.content.FileProvider
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File

// FlutterFragmentActivity is needed for fingerprint unlock (local_auth).
// The "gamex/files" channel shares a file with other apps and picks a file
// (backup restore) without extra plugins.
class MainActivity : FlutterFragmentActivity() {
    private var pendingPick: MethodChannel.Result? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "gamex/files").setMethodCallHandler { call, result ->
            when (call.method) {
                "share" -> {
                    try {
                        val file = File(call.argument<String>("path")!!)
                        val uri = FileProvider.getUriForFile(this, "$packageName.files", file)
                        val send = Intent(Intent.ACTION_SEND).apply {
                            type = call.argument<String>("mime") ?: "application/octet-stream"
                            putExtra(Intent.EXTRA_STREAM, uri)
                            call.argument<String>("text")?.let { putExtra(Intent.EXTRA_TEXT, it) }
                            call.argument<String>("subject")?.let { putExtra(Intent.EXTRA_SUBJECT, it) }
                            addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
                        }
                        startActivity(Intent.createChooser(send, call.argument<String>("title") ?: "Share"))
                        result.success(true)
                    } catch (e: Exception) {
                        result.error("share", e.message, null)
                    }
                }
                "pick" -> {
                    pendingPick?.success(null)
                    pendingPick = result
                    val pick = Intent(Intent.ACTION_OPEN_DOCUMENT).apply {
                        addCategory(Intent.CATEGORY_OPENABLE)
                        type = "*/*"
                    }
                    startActivityForResult(pick, PICK_REQUEST)
                }
                else -> result.notImplemented()
            }
        }
    }

    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode != PICK_REQUEST) return
        val result = pendingPick ?: return
        pendingPick = null
        val uri: Uri? = data?.data
        if (resultCode != Activity.RESULT_OK || uri == null) {
            result.success(null)
            return
        }
        try {
            val out = File(cacheDir, "picked-${System.currentTimeMillis()}")
            contentResolver.openInputStream(uri)!!.use { input -> out.outputStream().use { input.copyTo(it) } }
            result.success(out.absolutePath)
        } catch (e: Exception) {
            result.error("pick", e.message, null)
        }
    }

    companion object {
        private const val PICK_REQUEST = 4711
    }
}
