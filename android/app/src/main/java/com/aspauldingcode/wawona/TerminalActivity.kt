package com.aspauldingcode.wawona

import android.app.Activity
import android.content.Context
import android.content.Intent
import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Surface
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import java.lang.ref.WeakReference

/**
 * One Android task for Wawona Terminal when Start is New Window.
 * New Tab stays in [MainActivity]. API 24+ only, same gate as [SessionActivity].
 */
class TerminalActivity : ComponentActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        WawonaGuestTerm.attachWindow(this)
        title = intent.getStringExtra(EXTRA_TITLE) ?: "Wawona Terminal"
        setContent {
            MaterialTheme {
                Surface(modifier = Modifier.fillMaxSize(), color = Color.Black) {
                    TerminalWindow()
                }
            }
        }
    }

    override fun onDestroy() {
        WawonaGuestTerm.detachWindow(this)
        super.onDestroy()
    }

    companion object {
        private const val EXTRA_TITLE = "title"

        fun createIntent(context: Context, title: String): Intent =
            Intent(context, TerminalActivity::class.java).apply {
                putExtra(EXTRA_TITLE, title)
                addFlags(
                    Intent.FLAG_ACTIVITY_NEW_TASK or
                        Intent.FLAG_ACTIVITY_MULTIPLE_TASK or
                        Intent.FLAG_ACTIVITY_LAUNCH_ADJACENT,
                )
            }
    }
}

/** Process-wide terminal. MainActivity and [TerminalActivity] share one VT. */
internal object WawonaGuestTerm {
    val term: WawonaAndroidTerm by lazy { WawonaAndroidTerm() }
    var inOwnWindow by mutableStateOf(false)
    var acceptsKeys by mutableStateOf(false)
    private var windowRef: WeakReference<Activity>? = null
    private var lastKey = ""
    private var lastKeyNs = 0L
    private var shellFd = -1
    private var shellPump: Thread? = null
    private val shellKeys = ArrayDeque<ByteArray>()

    internal val shellRunning: Boolean get() = shellFd >= 0

    /** Spawn bundled zsh. Output stays in the PTY until [pumpShell]. */
    fun ensureShell() {
        if (shellFd >= 0) return
        val fd = try {
            WawonaNative.nativeTermShellStart()
        } catch (_: UnsatisfiedLinkError) {
            -1
        }
        if (fd >= 0) shellFd = fd
    }

    /** Whole UTF-8 characters, plus a 1-3 byte tail that the next read must finish. */
    private fun decodeShellUtf8(carry: ByteArray, chunk: ByteArray, n: Int): Pair<String, ByteArray> {
        val joined = ByteArray(carry.size + n)
        if (carry.isNotEmpty()) carry.copyInto(joined)
        chunk.copyInto(joined, carry.size, 0, n)
        var i = 0
        var cut = 0
        while (i < joined.size) {
            val lead = joined[i].toInt() and 0xFF
            val need = when {
                lead and 0x80 == 0 -> 1
                lead and 0xE0 == 0xC0 -> 2
                lead and 0xF0 == 0xE0 -> 3
                lead and 0xF8 == 0xF0 -> 4
                else -> 1
            }
            if (i + need > joined.size) break
            i += need
            cut = i
        }
        val text = if (cut == 0) "" else String(joined, 0, cut, Charsets.UTF_8)
        val rest = if (cut == joined.size) ByteArray(0) else joined.copyOfRange(cut, joined.size)
        return text to rest
    }

    fun pumpShell() {
        val fd = shellFd
        synchronized(shellKeys) {
            if (fd < 0 || shellPump?.isAlive == true) return
            val worker = Thread {
                try {
                    val buf = ByteArray(4096)
                    val main = android.os.Handler(android.os.Looper.getMainLooper())
                    var carry = ByteArray(0)
                    while (shellFd == fd) {
                        drainShellKeys(fd)
                        val n = try {
                            WawonaNative.nativeTermShellRead(fd, buf)
                        } catch (_: UnsatisfiedLinkError) {
                            -1
                        }
                        when {
                            n > 0 -> {
                                val (text, rest) = decodeShellUtf8(carry, buf, n)
                                carry = rest
                                if (text.isNotEmpty()) main.post { term.feed(text) }
                            }
                            n == -2 || n < 0 -> {
                                if (carry.isNotEmpty()) {
                                    val tail = String(carry, Charsets.UTF_8)
                                    carry = ByteArray(0)
                                    main.post { term.feed(tail) }
                                }
                                if (n == -2) main.post { term.feed("\r\nzsh exited.\n") }
                                shellFd = -1
                                synchronized(shellKeys) { shellKeys.clear() }
                                try {
                                    WawonaNative.nativeTermShellStop()
                                } catch (_: UnsatisfiedLinkError) {
                                }
                                break
                            }
                            else -> try {
                                Thread.sleep(16)
                            } catch (_: InterruptedException) {
                                break
                            }
                        }
                    }
                } finally {
                    synchronized(shellKeys) {
                        if (shellPump === Thread.currentThread()) shellPump = null
                    }
                }
            }
            worker.isDaemon = true
            worker.name = "wawona-term-shell"
            shellPump = worker
            worker.start()
        }
    }

    fun stopShell() {
        shellFd = -1
        shellPump = null
        synchronized(shellKeys) { shellKeys.clear() }
        try {
            WawonaNative.nativeTermShellStop()
        } catch (_: UnsatisfiedLinkError) {
        }
    }

    /** Pump thread owns the master write. A full PTY buffer must not drop the tail. */
    private fun drainShellKeys(fd: Int) {
        while (shellFd == fd) {
            val chunk = synchronized(shellKeys) { shellKeys.firstOrNull() } ?: return
            val n = try {
                WawonaNative.nativeTermShellWrite(fd, chunk)
            } catch (_: UnsatisfiedLinkError) {
                return
            }
            when {
                n >= chunk.size -> synchronized(shellKeys) {
                    if (shellFd != fd || shellKeys.isEmpty()) return
                    shellKeys.removeFirst()
                }
                n > 0 -> synchronized(shellKeys) {
                    if (shellFd != fd || shellKeys.isEmpty()) return
                    shellKeys.removeFirst()
                    shellKeys.addFirst(chunk.copyOfRange(n, chunk.size))
                }
                else -> return
            }
        }
    }

    fun noteShellSize(cols: Int, rows: Int) {
        val fd = shellFd
        if (fd < 0) return
        try {
            WawonaNative.nativeTermShellResize(fd, cols, rows)
        } catch (_: UnsatisfiedLinkError) {
        }
    }

    /** Drop the same key payload when the IME and the view both deliver it. */
    fun feedKeys(text: String) {
        if (text.isEmpty()) return
        val now = System.nanoTime()
        if (text == lastKey && now - lastKeyNs < 15_000_000L) return
        lastKey = text
        lastKeyNs = now
        if (shellFd >= 0) {
            synchronized(shellKeys) { shellKeys.addLast(text.toByteArray(Charsets.UTF_8)) }
            return
        }
        term.feed(text)
    }

    fun attachWindow(activity: Activity) {
        windowRef = WeakReference(activity)
        inOwnWindow = true
    }

    fun detachWindow(activity: Activity) {
        if (windowRef?.get() !== activity) return
        windowRef = null
        if (!activity.isChangingConfigurations) {
            inOwnWindow = false
        }
    }

    fun finishWindow() {
        inOwnWindow = false
        windowRef?.get()?.finish()
    }

    fun open(context: Context, title: String) {
        inOwnWindow = true
        val existing = windowRef?.get()
        if (existing != null && !existing.isFinishing) {
            context.startActivity(
                Intent(context, TerminalActivity::class.java).addFlags(
                    Intent.FLAG_ACTIVITY_REORDER_TO_FRONT or Intent.FLAG_ACTIVITY_NEW_TASK,
                ),
            )
            return
        }
        context.startActivity(TerminalActivity.createIntent(context, title))
    }
}

@Composable
private fun TerminalWindow() {
    GuestConsoleOverlay(
        term = WawonaGuestTerm.term,
        onDismiss = { WawonaGuestTerm.finishWindow() },
        acceptKeys = WawonaGuestTerm.acceptsKeys,
        modifier = Modifier.fillMaxSize(),
    )
}
