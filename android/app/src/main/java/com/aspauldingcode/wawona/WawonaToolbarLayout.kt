package com.aspauldingcode.wawona

import android.content.Context
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import org.json.JSONArray
import org.json.JSONObject

/**
 * Host port of ToolbarKeys (github.com/Wawona/ToolbarKeys). Same stable ids,
 * layout version 14, phone/pad defaults, and press_built_in values as the crate.
 * Android draws Compose slots; UniFFI is not linked on this NDK path yet.
 */
data class ToolbarCustomKey(
    val id: String,
    val label: String,
    val text: String,
)

enum class ToolbarKeyKind {
    KEY,
    SHIFTED,
    MOD,
    ACTION,
    TOGGLE,
}

data class ToolbarKeySpec(
    val id: String,
    val label: String,
    val kind: ToolbarKeyKind,
    val keycode: Int = 0,
    val mod: String = "",
)

object ToolbarCatalog {
    const val LAYOUT_VERSION = 14

    val phoneMain = listOf(
        "dismiss", "tabSwitcher", "esc", "ctrl", "writingAssistance", "shift", "tab",
        "arrowDrawerToggle", "drawerToggle", "toolbarSettings",
    )
    val phoneDrawer = listOf(
        "alt", "cmd", "backtick", "tilde", "caret", "underscore", "backslash", "pipe",
        "leftBracket", "rightBracket", "leftBrace", "rightBrace", "slash", "questionMark",
        "dash", "equals", "singleQuote", "doubleQuote", "leftParen", "rightParen", "atSign",
        "hash", "dollar", "percent", "semicolon", "colon", "lessThan", "greaterThan",
        "ampersand", "asterisk", "paste", "compose", "voiceAgent", "toggleFullScreen",
        "toggleTabBar", "newConnection", "toggleMouseCapture", "aiAgent", "brightnessBoost",
        "clipboardManager", "appSettings",
    )
    private val padExtra = listOf(
        "alt", "cmd", "backtick", "dash", "slash", "singleQuote", "semicolon",
        "leftBracket", "rightBracket",
    )
    val padMain = phoneMain + padExtra
    val padDrawer = listOf(
        "tilde", "caret", "underscore", "backslash", "pipe", "leftBrace", "rightBrace",
        "lessThan", "greaterThan", "questionMark", "equals", "doubleQuote", "colon",
        "leftParen", "rightParen", "atSign", "hash", "dollar", "percent", "ampersand",
        "asterisk", "paste", "compose", "voiceAgent", "toggleFullScreen", "toggleTabBar",
        "newConnection", "toggleMouseCapture", "aiAgent", "brightnessBoost", "clipboardManager",
        "appSettings",
    )

    /** press_built_in values. Null means modifier/action (host handles). */
    private val builtInValues: Map<String, String> = mapOf(
        "tab" to "\t",
        "arrowUp" to "\u001b[A",
        "arrowDown" to "\u001b[B",
        "arrowLeft" to "\u001b[D",
        "arrowRight" to "\u001b[C",
        "backtick" to "`",
        "tilde" to "~",
        "caret" to "^",
        "underscore" to "_",
        "backslash" to "\\",
        "pipe" to "|",
        "leftBracket" to "[",
        "rightBracket" to "]",
        "leftBrace" to "{",
        "rightBrace" to "}",
        "lessThan" to "<",
        "greaterThan" to ">",
        "slash" to "/",
        "questionMark" to "?",
        "dash" to "-",
        "equals" to "=",
        "singleQuote" to "'",
        "doubleQuote" to "\"",
        "semicolon" to ";",
        "colon" to ":",
        "leftParen" to "(",
        "rightParen" to ")",
        "atSign" to "@",
        "hash" to "#",
        "dollar" to "$",
        "percent" to "%",
        "ampersand" to "&",
        "asterisk" to "*",
    )

    private val specs = listOf(
        spec("dismiss", "Hide", ToolbarKeyKind.ACTION),
        spec("tabSwitcher", "Tabs", ToolbarKeyKind.ACTION),
        spec("esc", "Esc", ToolbarKeyKind.KEY, LinuxKey.ESC),
        spec("ctrl", "Ctrl", ToolbarKeyKind.MOD, mod = "ctrl"),
        spec("writingAssistance", "Aa", ToolbarKeyKind.ACTION),
        spec("shift", "Shift", ToolbarKeyKind.MOD, mod = "shift"),
        spec("tab", "Tab", ToolbarKeyKind.KEY, LinuxKey.TAB),
        spec("arrowDrawerToggle", "Arrows", ToolbarKeyKind.ACTION),
        spec("drawerToggle", "More", ToolbarKeyKind.TOGGLE),
        spec("toolbarSettings", "Gear", ToolbarKeyKind.ACTION),
        spec("alt", "Alt", ToolbarKeyKind.MOD, mod = "alt"),
        spec("cmd", "Cmd", ToolbarKeyKind.MOD, mod = "super"),
        spec("backtick", "`", ToolbarKeyKind.KEY, LinuxKey.GRAVE),
        spec("tilde", "~", ToolbarKeyKind.SHIFTED, LinuxKey.GRAVE),
        spec("caret", "^", ToolbarKeyKind.SHIFTED, LinuxKey.KEY_6),
        spec("underscore", "_", ToolbarKeyKind.SHIFTED, LinuxKey.MINUS),
        spec("backslash", "\\", ToolbarKeyKind.KEY, LinuxKey.BACKSLASH),
        spec("pipe", "|", ToolbarKeyKind.SHIFTED, LinuxKey.BACKSLASH),
        spec("leftBracket", "[", ToolbarKeyKind.KEY, LinuxKey.LEFTBRACE),
        spec("rightBracket", "]", ToolbarKeyKind.KEY, LinuxKey.RIGHTBRACE),
        spec("leftBrace", "{", ToolbarKeyKind.SHIFTED, LinuxKey.LEFTBRACE),
        spec("rightBrace", "}", ToolbarKeyKind.SHIFTED, LinuxKey.RIGHTBRACE),
        spec("slash", "/", ToolbarKeyKind.KEY, LinuxKey.SLASH),
        spec("questionMark", "?", ToolbarKeyKind.SHIFTED, LinuxKey.SLASH),
        spec("dash", "-", ToolbarKeyKind.KEY, LinuxKey.MINUS),
        spec("equals", "=", ToolbarKeyKind.KEY, LinuxKey.EQUAL),
        spec("singleQuote", "'", ToolbarKeyKind.KEY, LinuxKey.APOSTROPHE),
        spec("doubleQuote", "\"", ToolbarKeyKind.SHIFTED, LinuxKey.APOSTROPHE),
        spec("leftParen", "(", ToolbarKeyKind.SHIFTED, LinuxKey.KEY_9),
        spec("rightParen", ")", ToolbarKeyKind.SHIFTED, LinuxKey.KEY_0),
        spec("atSign", "@", ToolbarKeyKind.SHIFTED, LinuxKey.KEY_2),
        spec("hash", "#", ToolbarKeyKind.SHIFTED, LinuxKey.KEY_3),
        spec("dollar", "$", ToolbarKeyKind.SHIFTED, LinuxKey.KEY_4),
        spec("percent", "%", ToolbarKeyKind.SHIFTED, LinuxKey.KEY_5),
        spec("semicolon", ";", ToolbarKeyKind.KEY, LinuxKey.SEMICOLON),
        spec("colon", ":", ToolbarKeyKind.SHIFTED, LinuxKey.SEMICOLON),
        spec("lessThan", "<", ToolbarKeyKind.SHIFTED, LinuxKey.COMMA),
        spec("greaterThan", ">", ToolbarKeyKind.SHIFTED, LinuxKey.DOT),
        spec("ampersand", "&", ToolbarKeyKind.SHIFTED, LinuxKey.KEY_7),
        spec("asterisk", "*", ToolbarKeyKind.SHIFTED, LinuxKey.KEY_8),
        spec("paste", "Paste", ToolbarKeyKind.ACTION),
        spec("compose", "Compose", ToolbarKeyKind.ACTION),
        spec("voiceAgent", "Voice", ToolbarKeyKind.ACTION),
        spec("toggleFullScreen", "Full", ToolbarKeyKind.ACTION),
        spec("toggleTabBar", "Tabs bar", ToolbarKeyKind.ACTION),
        spec("newConnection", "New", ToolbarKeyKind.ACTION),
        spec("toggleMouseCapture", "Mouse", ToolbarKeyKind.ACTION),
        spec("aiAgent", "AI", ToolbarKeyKind.ACTION),
        spec("brightnessBoost", "Bright", ToolbarKeyKind.ACTION),
        spec("clipboardManager", "Clip", ToolbarKeyKind.ACTION),
        spec("appSettings", "App", ToolbarKeyKind.ACTION),
        spec("arrowUp", "Up", ToolbarKeyKind.KEY, LinuxKey.UP),
        spec("arrowDown", "Down", ToolbarKeyKind.KEY, LinuxKey.DOWN),
        spec("arrowLeft", "Left", ToolbarKeyKind.KEY, LinuxKey.LEFT),
        spec("arrowRight", "Right", ToolbarKeyKind.KEY, LinuxKey.RIGHT),
    ).associateBy { it.id }

    fun defaultMain(form: String): List<String> =
        if (form == "pad") padMain else phoneMain

    fun defaultDrawer(form: String): List<String> =
        if (form == "pad") padDrawer else phoneDrawer

    fun formForWidthDp(widthDp: Int): String = if (widthDp >= 600) "pad" else "phone"

    fun spec(id: String): ToolbarKeySpec =
        specs[id] ?: ToolbarKeySpec(id, id, ToolbarKeyKind.ACTION)

    fun pressBuiltInValue(id: String): String? = builtInValues[id]

    /** Symbol ids commit text via press_built_in; esc/tab/arrows stay key inject. */
    fun isSymbolCommit(id: String): Boolean =
        id in builtInValues && id !in setOf("tab", "arrowUp", "arrowDown", "arrowLeft", "arrowRight")

    private fun spec(
        id: String,
        label: String,
        kind: ToolbarKeyKind,
        keycode: Int = 0,
        mod: String = "",
    ) = ToolbarKeySpec(id, label, kind, keycode, mod)
}

class ToolbarLayoutStore(context: Context, formFactor: String? = null) {
    private val prefs = context.applicationContext.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
    private val resolvedForm = formFactor ?: run {
        val dm = context.resources.displayMetrics
        val widthDp = (dm.widthPixels / dm.density).toInt()
        ToolbarCatalog.formForWidthDp(widthDp)
    }

    var form by mutableStateOf(resolvedForm)
        private set
    var version by mutableStateOf(ToolbarCatalog.LAYOUT_VERSION)
        private set
    var main by mutableStateOf(ToolbarCatalog.defaultMain(resolvedForm))
        private set
    var drawers by mutableStateOf(listOf(ToolbarCatalog.defaultDrawer(resolvedForm)))
        private set
    var hidden by mutableStateOf(emptyList<String>())
        private set
    var customs by mutableStateOf(emptyList<ToolbarCustomKey>())
        private set
    var drawerOpenByDefault by mutableStateOf(false)
        private set
    var drawerToggleMode by mutableStateOf("stack")
        private set

    init {
        load()
    }

    /**
     * Matches ToolbarStore::effective: pack main to width, overflow into drawer[0],
     * keep drawerToggle on the main row when any drawer content exists.
     */
    private fun effectivePack(
        availableWidthPx: Float,
        buttonWidthPx: Float,
    ): Pair<List<String>, List<List<String>>> {
        val capacity = if (buttonWidthPx > 0f) {
            (availableWidthPx / buttonWidthPx).toInt().coerceAtLeast(1)
        } else {
            main.size.coerceAtLeast(1)
        }
        val mainValid = main.filter { it !in hidden }
        val visible = mainValid.take(capacity).toMutableList()
        val overflow = mainValid.drop(capacity).toMutableList()
        val drawerRows = drawers.map { row -> row.filter { it !in hidden } }.toMutableList()
        if (drawerRows.isEmpty()) drawerRows.add(emptyList())
        val anyDrawer = overflow.isNotEmpty() || drawerRows.any { it.isNotEmpty() }
        val toggle = "drawerToggle"
        if (anyDrawer && toggle !in visible && toggle !in hidden) {
            overflow.removeAll { it == toggle }
            if (visible.isNotEmpty()) {
                val last = visible.removeAt(visible.lastIndex)
                if (last != toggle) overflow.add(0, last)
                visible.add(toggle)
            } else {
                visible.add(toggle)
            }
        } else {
            overflow.removeAll { it == toggle }
        }
        drawerRows[0] = overflow + drawerRows[0]
        return visible to drawerRows
    }

    fun effectiveMain(availableWidthPx: Float, buttonWidthPx: Float): List<String> =
        effectivePack(availableWidthPx, buttonWidthPx).first

    fun effectiveDrawers(availableWidthPx: Float, buttonWidthPx: Float): List<List<String>> =
        effectivePack(availableWidthPx, buttonWidthPx).second

    fun hide(id: String) {
        if (id == "drawerToggle" || id == "toolbarSettings") return
        main = main.filter { it != id }
        drawers = drawers.map { row -> row.filter { it != id } }
        if (!hidden.contains(id)) hidden = hidden + id
        save()
    }

    fun unhide(id: String) {
        hidden = hidden.filter { it != id }
        val first = drawers.firstOrNull().orEmpty() + id
        drawers = listOf(first) + drawers.drop(1).ifEmpty { emptyList() }
        if (drawers.isEmpty()) drawers = listOf(listOf(id))
        save()
    }

    fun move(id: String, section: String, direction: Int) {
        if (section == "main") {
            main = moveIn(main, id, direction)
        } else {
            val index = section.removePrefix("drawer").toIntOrNull() ?: return
            drawers = drawers.mapIndexed { i, row ->
                if (i == index) moveIn(row, id, direction) else row
            }
        }
        save()
    }

    fun moveTo(id: String, from: String, to: String) {
        val removed = removeFrom(from, id)
        if (!removed) return
        if (to == "main") {
            main = main + id
        } else {
            val index = to.removePrefix("drawer").toIntOrNull() ?: 0
            drawers = drawers.mapIndexed { i, row ->
                if (i == index) listOf(id) + row.filter { it != id } else row
            }
        }
        save()
    }

    fun setDrawerRowCount(count: Int) {
        val target = count.coerceIn(1, 5)
        val rows = drawers.toMutableList()
        if (target > rows.size) {
            repeat(target - rows.size) { rows.add(emptyList()) }
        } else if (target < rows.size) {
            val overflow = rows.drop(target).flatten()
            while (rows.size > target) rows.removeAt(rows.lastIndex)
            rows[target - 1] = rows[target - 1] + overflow
        }
        drawers = rows
        save()
    }

    fun updateDrawerOpenByDefault(open: Boolean) {
        drawerOpenByDefault = open
        save()
    }

    fun updateDrawerToggleMode(mode: String) {
        drawerToggleMode = if (mode == "cycle") "cycle" else "stack"
        save()
    }

    fun addCustom(label: String, text: String) {
        val trimmed = label.trim()
        if (trimmed.isEmpty() || text.isEmpty()) return
        val key = ToolbarCustomKey("custom:" + System.currentTimeMillis(), trimmed, text)
        customs = customs + key
        val first = drawers.firstOrNull().orEmpty() + key.id
        drawers = if (drawers.isEmpty()) listOf(first) else listOf(first) + drawers.drop(1)
        save()
    }

    fun custom(id: String): ToolbarCustomKey? = customs.firstOrNull { it.id == id }

    fun reset() {
        main = ToolbarCatalog.defaultMain(form)
        drawers = listOf(ToolbarCatalog.defaultDrawer(form))
        hidden = emptyList()
        customs = emptyList()
        drawerOpenByDefault = false
        drawerToggleMode = "stack"
        version = ToolbarCatalog.LAYOUT_VERSION
        save()
    }

    private fun removeFrom(section: String, id: String): Boolean {
        if (section == "main") {
            if (!main.contains(id)) return false
            main = main.filter { it != id }
            return true
        }
        val index = section.removePrefix("drawer").toIntOrNull() ?: return false
        if (drawers.getOrNull(index)?.contains(id) != true) return false
        drawers = drawers.mapIndexed { i, row -> if (i == index) row.filter { it != id } else row }
        return true
    }

    private fun moveIn(row: List<String>, id: String, direction: Int): List<String> {
        val index = row.indexOf(id)
        if (index < 0) return row
        val next = index + direction
        if (next !in row.indices) return row
        val copy = row.toMutableList()
        val item = copy.removeAt(index)
        copy.add(next, item)
        return copy
    }

    private fun load() {
        val raw = prefs.getString(KEY, null) ?: return
        val json = try {
            JSONObject(raw)
        } catch (_: Exception) {
            return
        }
        val savedForm = json.optString("form", form).ifBlank { form }
        val savedVersion = json.optInt("version", 0)
        if (savedForm != form || savedVersion < ToolbarCatalog.LAYOUT_VERSION) {
            // Form change or old document: adopt crate defaults for current form.
            form = resolvedForm
            version = ToolbarCatalog.LAYOUT_VERSION
            main = ToolbarCatalog.defaultMain(form)
            drawers = listOf(ToolbarCatalog.defaultDrawer(form))
            hidden = json.optJSONArray("hidden")?.toStrings().orEmpty()
            customs = parseCustoms(json.optJSONArray("customs"))
            drawerOpenByDefault = json.optBoolean("drawerOpenByDefault", false)
            drawerToggleMode = json.optString("drawerToggleMode", "stack")
            save()
            return
        }
        form = savedForm
        version = savedVersion
        main = json.optJSONArray("main")?.toStrings()?.ifEmpty { null }
            ?: ToolbarCatalog.defaultMain(form)
        val drawerJson = json.optJSONArray("drawers")
        drawers = if (drawerJson == null) {
            listOf(ToolbarCatalog.defaultDrawer(form))
        } else {
            (0 until drawerJson.length()).map { i ->
                drawerJson.optJSONArray(i)?.toStrings().orEmpty()
            }.ifEmpty { listOf(emptyList()) }
        }
        hidden = json.optJSONArray("hidden")?.toStrings().orEmpty()
        customs = parseCustoms(json.optJSONArray("customs"))
        drawerOpenByDefault = json.optBoolean("drawerOpenByDefault", false)
        drawerToggleMode = json.optString("drawerToggleMode", "stack")
    }

    private fun parseCustoms(array: JSONArray?): List<ToolbarCustomKey> {
        if (array == null) return emptyList()
        return (0 until array.length()).mapNotNull { i ->
            val item = array.optJSONObject(i) ?: return@mapNotNull null
            val id = item.optString("id")
            val label = item.optString("label")
            val text = item.optString("text")
            if (id.isEmpty() || label.isEmpty()) null else ToolbarCustomKey(id, label, text)
        }
    }

    private fun save() {
        val json = JSONObject()
        json.put("version", version)
        json.put("form", form)
        json.put("main", JSONArray(main))
        json.put("drawers", JSONArray().apply {
            drawers.forEach { row -> put(JSONArray(row)) }
        })
        json.put("hidden", JSONArray(hidden))
        json.put("customs", JSONArray().apply {
            customs.forEach { key ->
                put(JSONObject().put("id", key.id).put("label", key.label).put("text", key.text))
            }
        })
        json.put("drawerOpenByDefault", drawerOpenByDefault)
        json.put("drawerToggleMode", drawerToggleMode)
        prefs.edit().putString(KEY, json.toString()).apply()
    }

    private fun JSONArray.toStrings(): List<String> =
        (0 until length()).mapNotNull { i -> optString(i).takeIf { it.isNotEmpty() } }

    companion object {
        private const val PREFS = "wawona_toolbar_keys"
        private const val KEY = "document"
    }
}
