package com.aspauldingcode.wawona

import android.graphics.Bitmap
import android.graphics.Typeface
import android.util.Base64
import androidx.compose.foundation.Image
import androidx.compose.foundation.gestures.detectTapGestures
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.offset
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.text.BasicTextField
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.focus.FocusRequester
import androidx.compose.ui.focus.focusRequester
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.ImageBitmap
import androidx.compose.ui.graphics.asImageBitmap
import androidx.compose.ui.input.key.onPreviewKeyEvent
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.text.AnnotatedString
import androidx.compose.ui.text.TextRange
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.input.ImeAction
import androidx.compose.ui.text.input.KeyboardCapitalization
import androidx.compose.ui.text.input.TextFieldValue
import androidx.compose.ui.unit.IntOffset
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.wawona.toolbarkeys.LinuxKey
import com.wawona.toolbarkeys.ModifierState

/** Toolbar Keys use Linux keycodes. Arrows must become CSI, not an empty inject. */
internal fun terminalEchoForLinuxKey(keycode: Int): String {
    val ctrl = ModifierState.ctrlActive
    fun arrow(letter: Char): String =
        if (ctrl) "\u001b[1;5$letter" else "\u001b[$letter"
    return when (keycode) {
        LinuxKey.ENTER -> terminalEnterBytes()
        LinuxKey.TAB -> "\t"
        LinuxKey.ESC -> "\u001b"
        LinuxKey.BACKSPACE -> terminalEraseBytes(1)
        LinuxKey.UP -> arrow('A')
        LinuxKey.DOWN -> arrow('B')
        LinuxKey.RIGHT -> arrow('C')
        LinuxKey.LEFT -> arrow('D')
        LinuxKey.HOME -> if (ctrl) "\u001b[1;5H" else "\u001b[H"
        LinuxKey.END -> if (ctrl) "\u001b[1;5F" else "\u001b[F"
        LinuxKey.PAGEUP -> if (ctrl) "\u001b[5;5~" else "\u001b[5~"
        LinuxKey.PAGEDOWN -> if (ctrl) "\u001b[6;5~" else "\u001b[6~"
        LinuxKey.SPACE -> if (ctrl) "\u0000" else " "
        LinuxKey.LEFTCTRL, LinuxKey.LEFTSHIFT, LinuxKey.LEFTALT, LinuxKey.LEFTMETA -> ""
        else -> ""
    }
}

/**
 * Wawona Terminal for Android. Every machine Start presents this surface
 * with the resolved `$ argv` banner and streamed CLI / host logs. Close
 * reveals the compositor (Focus). No auto-dismiss on first frame.
 */
@Composable
@Suppress("CyclomaticComplexMethod", "LongMethod")
internal fun GuestConsoleOverlay(
    term: WawonaAndroidTerm,
    onDismiss: () -> Unit,
    modifier: Modifier = Modifier,
    acceptKeys: Boolean = false,
) {
    val context = LocalContext.current
    val nerd = remember(context) { nerdMonoFamily(context) }
    val generation = term.generation
    val focus = remember { FocusRequester() }
    var draft by remember { mutableStateOf(TextFieldValue(TERM_IME_ANCHOR, TextRange(TERM_IME_ANCHOR.length))) }
    LaunchedEffect(acceptKeys) {
        if (acceptKeys) {
            runCatching { focus.requestFocus() }
        }
    }
    Surface(
        modifier = modifier.testTag(WawonaTestTags.TERMINAL_ROOT),
        color = Color.Black,
    ) {
        Column(
            modifier = Modifier
                .fillMaxSize()
                .then(
                    if (acceptKeys) {
                        Modifier.onPreviewKeyEvent { event ->
                            val bytes = terminalBytesForKey(event.nativeKeyEvent) ?: return@onPreviewKeyEvent false
                            WawonaGuestTerm.feedKeys(bytes)
                            true
                        }
                    } else {
                        Modifier
                    },
                ),
        ) {
            Row(
                modifier = Modifier.fillMaxWidth().padding(horizontal = 12.dp, vertical = 8.dp),
                horizontalArrangement = Arrangement.SpaceBetween,
                verticalAlignment = Alignment.CenterVertically,
            ) {
                Text(
                    term.title,
                    color = Color.White,
                    fontFamily = FontFamily.Monospace,
                    maxLines = 1,
                    modifier = Modifier.weight(1f),
                )
                TextButton(onClick = { term.feed("\u001b[3J") }) {
                    Text("Clear", color = Color.White)
                }
                TextButton(
                    onClick = onDismiss,
                    modifier = Modifier.testTag(WawonaTestTags.TERMINAL_DONE),
                ) {
                    Text("Done", color = Color.White)
                }
            }
            BoxWithConstraints(modifier = Modifier.weight(1f)) {
                val density = LocalDensity.current
                val cell = remember(density) { hostMonoCell(density) }
                val padPx = with(density) { 24.dp.toPx() }
                val cols = with(density) {
                    ((maxWidth.toPx() - padPx) / cell.first).toInt()
                }.coerceIn(20, 512)
                val rows = with(density) { (maxHeight.toPx() / cell.second).toInt() }.coerceIn(8, 256)
                var fitted by remember {
                    mutableStateOf(listOf(WawonaTerminalRow(0, AnnotatedString(""))))
                }
                var pictures by remember { mutableStateOf(emptyList<WawonaTermPicture>()) }
                LaunchedEffect(generation, cols, rows, nerd) {
                    term.resize(cols, rows)
                    term.cellPx(cell.first.toInt().coerceAtLeast(1), cell.second.toInt().coerceAtLeast(1))
                    val document = term.document()
                    fitted = WawonaTerminalRowIds.align(fitted, wawonaTerminalLines(document, nerd))
                    pictures = decodeTermPictures(term.pictures())
                }
                Box(modifier = Modifier.fillMaxSize()) {
                    pictures.filter { it.z < 0 }.forEach { picture ->
                        TermPictureImage(picture, cell)
                    }
                    WawonaTerminalText(
                        rows = fitted,
                        minRowHeight = with(density) { cell.second.toDp() },
                        modifier = Modifier
                            .fillMaxSize()
                            .pointerInput(cols, rows, cell, acceptKeys) {
                                detectTapGestures { offset ->
                                    if (acceptKeys) runCatching { focus.requestFocus() }
                                    val col = (offset.x / cell.first).toInt() + 1
                                    val row = (offset.y / cell.second).toInt() + 1
                                    term.pointer(col.coerceIn(1, cols), row.coerceIn(1, rows))
                                }
                            },
                    )
                    pictures.filter { it.z >= 0 }.forEach { picture ->
                        TermPictureImage(picture, cell)
                    }
                }
            }
            if (acceptKeys) {
                BasicTextField(
                    value = draft,
                    onValueChange = { next ->
                        if (next.composition != null) {
                            draft = next
                            return@BasicTextField
                        }
                        val committed = next.text
                        if (committed.startsWith(TERM_IME_ANCHOR)) {
                            val typed = committed.removePrefix(TERM_IME_ANCHOR)
                            if (typed.isNotEmpty()) WawonaGuestTerm.feedKeys(typed)
                        } else if (committed.isEmpty()) {
                            WawonaGuestTerm.feedKeys(terminalEraseBytes(1))
                        } else {
                            WawonaGuestTerm.feedKeys(committed)
                        }
                        draft = TextFieldValue(TERM_IME_ANCHOR, TextRange(TERM_IME_ANCHOR.length))
                    },
                    textStyle = TextStyle(
                        color = Color.Transparent,
                        fontSize = 16.sp,
                        fontFamily = FontFamily.Monospace,
                    ),
                    keyboardOptions = KeyboardOptions(
                        capitalization = KeyboardCapitalization.None,
                        imeAction = ImeAction.None,
                    ),
                    modifier = Modifier
                        .fillMaxWidth()
                        .padding(horizontal = 12.dp, vertical = 8.dp)
                        .focusRequester(focus)
                        .testTag("wwn.guestConsole.send"),
                )
            }
        }
    }
}

/** Live Rust VT for the Android Guest Console. Deltas go in. The string log does not. */
internal class WawonaAndroidTerm {
    var handle = 0L
    var generation by mutableIntStateOf(0)
    var title by mutableStateOf("Wawona Terminal")

    fun replace(text: String) {
        close()
        open()
        feed(text)
    }

    fun feed(text: String) {
        if (text.isEmpty()) return
        if (handle == 0L) open()
        if (handle == 0L) return
        try {
            WawonaNative.nativeTermFeed(handle, cookNewlines(text))
            val next = WawonaNative.nativeTermTitle(handle).orEmpty()
            if (next.isNotEmpty()) title = next
            generation++
        } catch (_: UnsatisfiedLinkError) {
        }
    }

    fun resize(cols: Int, rows: Int) {
        if (handle == 0L) return
        try {
            WawonaNative.nativeTermResize(handle, cols, rows)
            WawonaGuestTerm.noteShellSize(cols, rows)
        } catch (_: UnsatisfiedLinkError) {
        }
    }

    fun document(): String {
        if (handle == 0L) return "[]"
        return try {
            WawonaNative.nativeTermDocument(handle) ?: "[]"
        } catch (_: UnsatisfiedLinkError) {
            "[]"
        }
    }

    fun cellPx(width: Int, height: Int) {
        if (handle == 0L) return
        try {
            WawonaNative.nativeTermCellPx(handle, width, height)
        } catch (_: UnsatisfiedLinkError) {
        }
    }

    fun pictures(): String {
        if (handle == 0L) return "[]"
        return try {
            WawonaNative.nativeTermImages(handle) ?: "[]"
        } catch (_: UnsatisfiedLinkError) {
            "[]"
        }
    }

    fun pointer(col: Int, row: Int) {
        if (handle == 0L) return
        try {
            WawonaNative.nativeTermPointer(handle, col, row)
        } catch (_: UnsatisfiedLinkError) {
        }
    }

    fun close() {
        if (handle == 0L) return
        try {
            WawonaNative.nativeTermClose(handle)
        } catch (_: UnsatisfiedLinkError) {
        }
        handle = 0L
    }

    private fun open() {
        handle = try {
            WawonaNative.nativeTermOpen(80, 28)
        } catch (_: UnsatisfiedLinkError) {
            0L
        }
    }
}

/** xterm F1-F12. Null when the code is not a function key. */
@Suppress("CyclomaticComplexMethod", "ReturnCount")
private fun functionKeyBytes(code: Int, param: Int): String? {
    val n = code - android.view.KeyEvent.KEYCODE_F1 + 1
    if (n !in 1..12) return null
    if (param != 1) {
        return when (n) {
            1 -> "\u001b[1;${param}P"
            2 -> "\u001b[1;${param}Q"
            3 -> "\u001b[1;${param}R"
            4 -> "\u001b[1;${param}S"
            5 -> "\u001b[15;${param}~"
            6 -> "\u001b[17;${param}~"
            7 -> "\u001b[18;${param}~"
            8 -> "\u001b[19;${param}~"
            9 -> "\u001b[20;${param}~"
            10 -> "\u001b[21;${param}~"
            11 -> "\u001b[23;${param}~"
            else -> "\u001b[24;${param}~"
        }
    }
    return when (n) {
        1 -> "\u001bOP"
        2 -> "\u001bOQ"
        3 -> "\u001bOR"
        4 -> "\u001bOS"
        5 -> "\u001b[15~"
        6 -> "\u001b[17~"
        7 -> "\u001b[18~"
        8 -> "\u001b[19~"
        9 -> "\u001b[20~"
        10 -> "\u001b[21~"
        11 -> "\u001b[23~"
        else -> "\u001b[24~"
    }
}

/** Keeps the IME field non-empty so Backspace still produces a change. */
private const val TERM_IME_ANCHOR = "\u200B"

/** Live zsh echoes erase. Local VT does not, so that path paints BS, space, BS. */
internal fun terminalEraseBytes(count: Int): String {
    if (count <= 0) return ""
    return if (WawonaGuestTerm.shellRunning) "\u007f".repeat(count) else "\u0008 \u0008".repeat(count)
}

internal fun terminalEnterBytes(): String =
    if (WawonaGuestTerm.shellRunning) "\r" else "\n"

/** Hardware keys for the interactive terminal. Soft letters stay on the text field. */
@Suppress("LongMethod", "MagicNumber", "CyclomaticComplexMethod", "ReturnCount")
internal fun terminalBytesForKey(event: android.view.KeyEvent): String? {
    if (event.action != android.view.KeyEvent.ACTION_DOWN) return null
    val soft = event.flags and android.view.KeyEvent.FLAG_SOFT_KEYBOARD != 0
    if (soft) {
        return when (event.keyCode) {
            android.view.KeyEvent.KEYCODE_DEL -> terminalEraseBytes(1)
            android.view.KeyEvent.KEYCODE_FORWARD_DEL -> "\u001b[3~"
            android.view.KeyEvent.KEYCODE_ENTER,
            android.view.KeyEvent.KEYCODE_NUMPAD_ENTER -> terminalEnterBytes()
            else -> null
        }
    }
    val unicode = event.unicodeChar
    val ctrl = event.isCtrlPressed ||
        (event.metaState and android.view.KeyEvent.META_CTRL_ON) != 0
    val alt = event.isAltPressed ||
        (event.metaState and android.view.KeyEvent.META_ALT_ON) != 0
    val shift = event.isShiftPressed ||
        (event.metaState and android.view.KeyEvent.META_SHIFT_ON) != 0
    val param = 1 + (if (shift) 1 else 0) + (if (alt) 2 else 0) + (if (ctrl) 4 else 0)
    if (ctrl) {
        val baseMeta = if (shift) android.view.KeyEvent.META_SHIFT_ON else 0
        val base = Character.toUpperCase(event.getUnicodeChar(baseMeta))
        if (base in 0x40..0x5F) {
            val byte = (base and 0x1F).toChar()
            return if (alt) "\u001b$byte" else byte.toString()
        }
        val code = event.keyCode
        val extra = when (code) {
            android.view.KeyEvent.KEYCODE_2 -> 0x00
            android.view.KeyEvent.KEYCODE_3,
            android.view.KeyEvent.KEYCODE_LEFT_BRACKET -> 0x1B
            android.view.KeyEvent.KEYCODE_4,
            android.view.KeyEvent.KEYCODE_BACKSLASH -> 0x1C
            android.view.KeyEvent.KEYCODE_5,
            android.view.KeyEvent.KEYCODE_RIGHT_BRACKET -> 0x1D
            android.view.KeyEvent.KEYCODE_6 -> 0x1E
            android.view.KeyEvent.KEYCODE_7,
            android.view.KeyEvent.KEYCODE_MINUS -> 0x1F
            android.view.KeyEvent.KEYCODE_8 -> 0x7F
            android.view.KeyEvent.KEYCODE_SLASH -> if (shift) 0x7F else 0x1F
            in android.view.KeyEvent.KEYCODE_A..android.view.KeyEvent.KEYCODE_Z ->
                code - android.view.KeyEvent.KEYCODE_A + 1
            else -> -1
        }
        if (extra >= 0) {
            val byte = extra.toChar()
            return if (alt) "\u001b$byte" else byte.toString()
        }
    }
    functionKeyBytes(event.keyCode, param)?.let { return it }
    return when (event.keyCode) {
        android.view.KeyEvent.KEYCODE_ENTER,
        android.view.KeyEvent.KEYCODE_NUMPAD_ENTER ->
            if (alt) "\u001b${terminalEnterBytes()}" else terminalEnterBytes()
        android.view.KeyEvent.KEYCODE_DEL -> {
            if (!WawonaGuestTerm.shellRunning) return terminalEraseBytes(1)
            val byte = if (ctrl) "\u0008" else "\u007f"
            if (alt) "\u001b$byte" else byte
        }
        android.view.KeyEvent.KEYCODE_FORWARD_DEL -> csiTilde('3', "\u001b[3~", param)
        android.view.KeyEvent.KEYCODE_INSERT -> csiTilde('2', "\u001b[2~", param)
        android.view.KeyEvent.KEYCODE_MENU ->
            if (param == 1) "\u001b[29~" else "\u001b[29;$param~"
        android.view.KeyEvent.KEYCODE_SEARCH -> csiTilde('1', "\u001b[1~", param)
        android.view.KeyEvent.KEYCODE_HELP ->
            if (param == 1) "\u001b[28~" else "\u001b[28;$param~"
        android.view.KeyEvent.KEYCODE_NUMPAD_8 -> numpadNav(unicode, csiLetter('A', "\u001b[A", param))
        android.view.KeyEvent.KEYCODE_NUMPAD_2 -> numpadNav(unicode, csiLetter('B', "\u001b[B", param))
        android.view.KeyEvent.KEYCODE_NUMPAD_6 -> numpadNav(unicode, csiLetter('C', "\u001b[C", param))
        android.view.KeyEvent.KEYCODE_NUMPAD_4 -> numpadNav(unicode, csiLetter('D', "\u001b[D", param))
        android.view.KeyEvent.KEYCODE_NUMPAD_7 -> numpadNav(unicode, csiLetter('H', "\u001b[H", param))
        android.view.KeyEvent.KEYCODE_NUMPAD_1 -> numpadNav(unicode, csiLetter('F', "\u001b[F", param))
        android.view.KeyEvent.KEYCODE_NUMPAD_9 -> numpadNav(unicode, csiTilde('5', "\u001b[5~", param))
        android.view.KeyEvent.KEYCODE_NUMPAD_3 -> numpadNav(unicode, csiTilde('6', "\u001b[6~", param))
        android.view.KeyEvent.KEYCODE_NUMPAD_0 -> numpadNav(unicode, csiTilde('2', "\u001b[2~", param))
        android.view.KeyEvent.KEYCODE_NUMPAD_DOT -> numpadNav(unicode, csiTilde('3', "\u001b[3~", param))
        android.view.KeyEvent.KEYCODE_NUMPAD_5 -> numpadNav(unicode, "\u001b[E")
        android.view.KeyEvent.KEYCODE_NUMPAD_DIVIDE -> numpadNav(unicode, "/")
        android.view.KeyEvent.KEYCODE_NUMPAD_MULTIPLY -> numpadNav(unicode, "*")
        android.view.KeyEvent.KEYCODE_NUMPAD_SUBTRACT -> numpadNav(unicode, "-")
        android.view.KeyEvent.KEYCODE_NUMPAD_ADD -> numpadNav(unicode, "+")
        android.view.KeyEvent.KEYCODE_NUMPAD_EQUALS -> numpadNav(unicode, "=")
        android.view.KeyEvent.KEYCODE_NUMPAD_COMMA -> numpadNav(unicode, ",")
        android.view.KeyEvent.KEYCODE_TAB ->
            if (shift) "\u001b[Z" else if (alt) "\u001b\t" else "\t"
        android.view.KeyEvent.KEYCODE_ESCAPE -> "\u001b"
        android.view.KeyEvent.KEYCODE_SPACE -> when {
            ctrl && alt -> "\u001b\u0000"
            ctrl -> "\u0000"
            alt -> "\u001b "
            else -> " "
        }
        android.view.KeyEvent.KEYCODE_DPAD_UP -> csiLetter('A', "\u001b[A", param)
        android.view.KeyEvent.KEYCODE_DPAD_DOWN -> csiLetter('B', "\u001b[B", param)
        android.view.KeyEvent.KEYCODE_DPAD_RIGHT -> csiLetter('C', "\u001b[C", param)
        android.view.KeyEvent.KEYCODE_DPAD_LEFT -> csiLetter('D', "\u001b[D", param)
        android.view.KeyEvent.KEYCODE_MOVE_HOME -> csiLetter('H', "\u001b[H", param)
        android.view.KeyEvent.KEYCODE_MOVE_END -> csiLetter('F', "\u001b[F", param)
        android.view.KeyEvent.KEYCODE_PAGE_UP -> csiTilde('5', "\u001b[5~", param)
        android.view.KeyEvent.KEYCODE_PAGE_DOWN -> csiTilde('6', "\u001b[6~", param)
        else -> {
            if (alt && event.keyCode in android.view.KeyEvent.KEYCODE_A..android.view.KeyEvent.KEYCODE_Z) {
                val ch = (event.keyCode - android.view.KeyEvent.KEYCODE_A + 'a'.code).toChar()
                return "\u001b$ch"
            }
            if (unicode == 0) null else String(Character.toChars(unicode))
        }
    }
}

private fun csiLetter(letter: Char, plain: String, param: Int): String =
    if (param == 1) plain else "\u001b[1;$param$letter"

private fun csiTilde(code: Char, plain: String, param: Int): String =
    if (param == 1) plain else "\u001b[$code;$param~"

private fun numpadNav(unicode: Int, nav: String): String =
    if (unicode == 0) nav else String(Character.toChars(unicode))

private fun cookNewlines(raw: String): ByteArray {
    val cooked = StringBuilder(raw.length + 8)
    for (ch in raw) {
        if (ch == '\n' && (cooked.isEmpty() || cooked.last() != '\r')) {
            cooked.append('\r')
        }
        cooked.append(ch)
    }
    return cooked.toString().toByteArray(Charsets.UTF_8)
}

private fun nerdMonoFamily(context: android.content.Context): FontFamily {
    return try {
        val face = Typeface.createFromAsset(
            context.assets,
            "fonts/truetype/DejaVuSansMNerdFontMono-Regular.ttf",
        )
        FontFamily(face)
    } catch (_: RuntimeException) {
        FontFamily.Monospace
    }
}

private fun hostMonoCell(density: androidx.compose.ui.unit.Density): Pair<Float, Float> {
    val paint = android.graphics.Paint().apply {
        typeface = Typeface.MONOSPACE
        textSize = with(density) { 13.sp.toPx() }
        isAntiAlias = true
    }
    val width = paint.measureText("M").coerceAtLeast(1f)
    val metrics = paint.fontMetrics
    val height = (metrics.descent - metrics.ascent).coerceAtLeast(1f)
    return width to height
}

private data class WawonaTermPicture(
    val id: Int,
    val col: Int,
    val row: Int,
    val columns: Int,
    val rows: Int,
    val z: Int,
    val image: ImageBitmap,
)

@Composable
private fun TermPictureImage(picture: WawonaTermPicture, cell: Pair<Float, Float>) {
    val density = androidx.compose.ui.platform.LocalDensity.current
    Image(
        bitmap = picture.image,
        contentDescription = null,
        modifier = Modifier
            .offset { IntOffset((picture.col * cell.first).toInt(), (picture.row * cell.second).toInt()) }
            .size(
                with(density) { (picture.columns * cell.first).toDp() },
                with(density) { (picture.rows * cell.second).toDp() },
            ),
    )
}

private fun decodeTermPictures(json: String): List<WawonaTermPicture> {
    val out = ArrayList<WawonaTermPicture>()
    val array = try {
        org.json.JSONArray(json)
    } catch (_: org.json.JSONException) {
        return out
    }
    for (i in 0 until array.length()) {
        val item = array.optJSONObject(i) ?: continue
        val w = item.optInt("w")
        val h = item.optInt("h")
        if (w < 1 || h < 1) continue
        val raw = try {
            Base64.decode(item.optString("rgba"), Base64.DEFAULT)
        } catch (_: IllegalArgumentException) {
            continue
        }
        if (raw.size < w * h * 4) continue
        val pixels = IntArray(w * h)
        var p = 0
        for (n in pixels.indices) {
            val r = raw[p].toInt() and 255
            val g = raw[p + 1].toInt() and 255
            val b = raw[p + 2].toInt() and 255
            val a = raw[p + 3].toInt() and 255
            pixels[n] = (a shl 24) or (r shl 16) or (g shl 8) or b
            p += 4
        }
        val bmp = Bitmap.createBitmap(w, h, Bitmap.Config.ARGB_8888)
        bmp.setPixels(pixels, 0, w, 0, 0, w, h)
        out.add(
            WawonaTermPicture(
                id = item.optInt("n"),
                col = item.optInt("col"),
                row = item.optInt("row"),
                columns = item.optInt("cols").coerceAtLeast(1),
                rows = item.optInt("rows").coerceAtLeast(1),
                z = item.optInt("z"),
                image = bmp.asImageBitmap(),
            ),
        )
    }
    return out
}
