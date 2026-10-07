package com.aspauldingcode.wawona

import android.content.Context
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import org.json.JSONArray
import org.json.JSONObject

/**
 * Phone toolbar document. Same stable ids as ToolbarKeys (`defaults` phone form).
 * Android persists the document in SharedPreferences. It does not invent a second catalog.
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
}

data class ToolbarKeySpec(
    val id: String,
    val label: String,
    val kind: ToolbarKeyKind,
    val keycode: Int = 0,
    val mod: String = "",
)

object ToolbarCatalog {
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

    private val specs = listOf(
        spec("dismiss", "Hide", ToolbarKeyKind.ACTION),
        spec("tabSwitcher", "Tabs", ToolbarKeyKind.ACTION),
        spec("esc", "Esc", ToolbarKeyKind.KEY, LinuxKey.ESC),
        spec("ctrl", "Ctrl", ToolbarKeyKind.MOD, mod = "ctrl"),
        spec("writingAssistance", "Aa", ToolbarKeyKind.ACTION),
        spec("shift", "Shift", ToolbarKeyKind.MOD, mod = "shift"),
        spec("tab", "Tab", ToolbarKeyKind.KEY, LinuxKey.TAB),
        spec("arrowDrawerToggle", "Arrows", ToolbarKeyKind.ACTION),
        spec("drawerToggle", "More", ToolbarKeyKind.ACTION),
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
        spec("appSettings", "App", ToolbarKeyKind.ACTION),
        spec("arrowUp", "Up", ToolbarKeyKind.KEY, LinuxKey.UP),
        spec("arrowDown", "Down", ToolbarKeyKind.KEY, LinuxKey.DOWN),
        spec("arrowLeft", "Left", ToolbarKeyKind.KEY, LinuxKey.LEFT),
        spec("arrowRight", "Right", ToolbarKeyKind.KEY, LinuxKey.RIGHT),
    ).associateBy { it.id }

    fun spec(id: String): ToolbarKeySpec =
        specs[id] ?: ToolbarKeySpec(id, id, ToolbarKeyKind.ACTION)

    private fun spec(
        id: String,
        label: String,
        kind: ToolbarKeyKind,
        keycode: Int = 0,
        mod: String = "",
    ) = ToolbarKeySpec(id, label, kind, keycode, mod)
}

class ToolbarLayoutStore(context: Context) {
    private val prefs = context.applicationContext.getSharedPreferences(PREFS, Context.MODE_PRIVATE)

    var main by mutableStateOf(ToolbarCatalog.phoneMain)
        private set
    var drawers by mutableStateOf(listOf(ToolbarCatalog.phoneDrawer))
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
        main = ToolbarCatalog.phoneMain
        drawers = listOf(ToolbarCatalog.phoneDrawer)
        hidden = emptyList()
        customs = emptyList()
        drawerOpenByDefault = false
        drawerToggleMode = "stack"
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
        main = json.optJSONArray("main")?.toStrings()?.ifEmpty { null } ?: ToolbarCatalog.phoneMain
        val drawerJson = json.optJSONArray("drawers")
        drawers = if (drawerJson == null) {
            listOf(ToolbarCatalog.phoneDrawer)
        } else {
            (0 until drawerJson.length()).map { i ->
                drawerJson.optJSONArray(i)?.toStrings().orEmpty()
            }.ifEmpty { listOf(emptyList()) }
        }
        hidden = json.optJSONArray("hidden")?.toStrings().orEmpty()
        customs = json.optJSONArray("customs")?.let { array ->
            (0 until array.length()).mapNotNull { i ->
                val item = array.optJSONObject(i) ?: return@mapNotNull null
                val id = item.optString("id")
                val label = item.optString("label")
                val text = item.optString("text")
                if (id.isEmpty() || label.isEmpty()) null else ToolbarCustomKey(id, label, text)
            }
        }.orEmpty()
        drawerOpenByDefault = json.optBoolean("drawerOpenByDefault", false)
        drawerToggleMode = json.optString("drawerToggleMode", "stack")
    }

    private fun save() {
        val json = JSONObject()
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
