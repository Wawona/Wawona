package com.aspauldingcode.wawona

import android.content.SharedPreferences
import androidx.compose.ui.graphics.Color
import org.json.JSONArray
import org.json.JSONObject
import java.util.UUID

/** Finder-style color tag for machines (iOS `WWNMachineTag` parity). */
data class MachineTag(
    val id: String = UUID.randomUUID().toString(),
    val name: String,
    val colorHex: String,
)

object MachineTagPalette {
    val hexes: List<String> = listOf(
        "FF3B30", "FF9500", "FFCC00", "34C759", "00C7A6", "30B0C7",
        "007AFF", "5856D6", "AF52DE", "FF2D55", "A2845E", "8E8E93",
    )

    fun color(hex: String): Color {
        val cleaned = hex.trim().removePrefix("#")
        if (cleaned.length != 6) return Color.Gray
        val value = cleaned.toLongOrNull(16) ?: return Color.Gray
        return Color(
            red = ((value shr 16) and 0xFF) / 255f,
            green = ((value shr 8) and 0xFF) / 255f,
            blue = (value and 0xFF) / 255f,
        )
    }
}

/**
 * Shared store for machine tags + assignments. Persists in SharedPreferences
 * (same keys as iOS UserDefaults intent: per-app tag sets).
 */
class MachineTagStore(private val prefs: SharedPreferences) {
    private val tagsKey = "wawona.machines.tags"
    private val assignmentsKey = "wawona.machines.tagAssignments"

    fun loadTags(): List<MachineTag> {
        val raw = prefs.getString(tagsKey, null) ?: return emptyList()
        return runCatching {
            val arr = JSONArray(raw)
            buildList {
                for (i in 0 until arr.length()) {
                    val obj = arr.getJSONObject(i)
                    val name = obj.optString("name").trim()
                    if (name.isEmpty()) continue
                    add(
                        MachineTag(
                            id = obj.optString("id").ifBlank { UUID.randomUUID().toString() },
                            name = name,
                            colorHex = obj.optString("colorHex", "8E8E93"),
                        )
                    )
                }
            }
        }.getOrDefault(emptyList())
    }

    fun loadAssignments(): Map<String, List<String>> {
        val raw = prefs.getString(assignmentsKey, null) ?: return emptyMap()
        return runCatching {
            val obj = JSONObject(raw)
            buildMap {
                obj.keys().forEach { machineId ->
                    val arr = obj.optJSONArray(machineId) ?: return@forEach
                    put(
                        machineId,
                        buildList {
                            for (i in 0 until arr.length()) {
                                val id = arr.optString(i).trim()
                                if (id.isNotEmpty()) add(id)
                            }
                        },
                    )
                }
            }
        }.getOrDefault(emptyMap())
    }

    fun tagsFor(machineId: String, tags: List<MachineTag>, assignments: Map<String, List<String>>): List<MachineTag> {
        val ids = assignments[machineId].orEmpty()
        return tags.filter { it.id in ids }
    }

    fun saveTags(tags: List<MachineTag>) {
        val arr = JSONArray()
        tags.forEach { tag ->
            arr.put(
                JSONObject()
                    .put("id", tag.id)
                    .put("name", tag.name)
                    .put("colorHex", tag.colorHex),
            )
        }
        prefs.edit().putString(tagsKey, arr.toString()).apply()
    }

    fun saveAssignments(assignments: Map<String, List<String>>) {
        val obj = JSONObject()
        assignments.forEach { (machineId, ids) ->
            if (ids.isEmpty()) return@forEach
            obj.put(machineId, JSONArray(ids))
        }
        prefs.edit().putString(assignmentsKey, obj.toString()).apply()
    }

    fun createTag(name: String, colorHex: String, existing: List<MachineTag>): List<MachineTag> {
        val trimmed = name.trim()
        if (trimmed.isEmpty()) return existing
        val next = existing + MachineTag(name = trimmed, colorHex = colorHex)
        saveTags(next)
        return next
    }

    fun updateTag(tag: MachineTag, existing: List<MachineTag>): List<MachineTag> {
        val next = existing.map { if (it.id == tag.id) tag.copy(name = tag.name.trim()) else it }
        saveTags(next)
        return next
    }

    fun deleteTag(id: String, existing: List<MachineTag>, assignments: Map<String, List<String>>): Pair<List<MachineTag>, Map<String, List<String>>> {
        val nextTags = existing.filterNot { it.id == id }
        val nextAssign = assignments.mapValues { (_, ids) -> ids.filterNot { it == id } }
            .filterValues { it.isNotEmpty() }
        saveTags(nextTags)
        saveAssignments(nextAssign)
        return nextTags to nextAssign
    }

    fun toggleAssignment(
        tagId: String,
        machineId: String,
        assignments: Map<String, List<String>>,
    ): Map<String, List<String>> {
        val current = assignments[machineId].orEmpty()
        val nextIds = if (tagId in current) current - tagId else current + tagId
        val next = assignments.toMutableMap()
        if (nextIds.isEmpty()) next.remove(machineId) else next[machineId] = nextIds
        saveAssignments(next)
        return next
    }

    fun pruneAssignments(validMachineIds: Set<String>, assignments: Map<String, List<String>>): Map<String, List<String>> {
        val next = assignments.filterKeys { it in validMachineIds }
        if (next.size != assignments.size) saveAssignments(next)
        return next
    }
}

enum class MachineSortKey(val label: String) {
    DATE_CREATED("Date Created"),
    DATE_LAST_USED("Date Last Used"),
    NAME("Name"),
    KIND("Kind"),
}

/** Pin + sort prefs (iOS `WWNMachinesViewModel` cap of 6 pins). */
object MachineCatalogPrefs {
    private const val PINNED_KEY = "wawona.machines.pinnedMachineIds"
    private const val SORT_KEY = "wawona.machines.sortKey"
    private const val SORT_ASC_KEY = "wawona.machines.sortAscending"
    const val MAX_PINNED = 6

    fun loadPinned(prefs: SharedPreferences): Set<String> {
        val raw = prefs.getString(PINNED_KEY, null) ?: return emptySet()
        return raw.split(',').map { it.trim() }.filter { it.isNotEmpty() }.take(MAX_PINNED).toSet()
    }

    fun savePinned(prefs: SharedPreferences, ids: Set<String>) {
        prefs.edit().putString(PINNED_KEY, ids.take(MAX_PINNED).joinToString(",")).apply()
    }

    fun togglePin(prefs: SharedPreferences, machineId: String, current: Set<String>): Set<String> {
        val next = current.toMutableSet()
        if (machineId in next) {
            next.remove(machineId)
        } else if (next.size < MAX_PINNED) {
            next.add(machineId)
        }
        savePinned(prefs, next)
        return next
    }

    fun loadSortKey(prefs: SharedPreferences): MachineSortKey {
        val raw = prefs.getString(SORT_KEY, null) ?: return MachineSortKey.DATE_CREATED
        return when (raw) {
            "dateLastUsed", "DATE_LAST_USED" -> MachineSortKey.DATE_LAST_USED
            "name", "NAME" -> MachineSortKey.NAME
            "kind", "KIND" -> MachineSortKey.KIND
            else -> MachineSortKey.DATE_CREATED
        }
    }

    fun loadSortAscending(prefs: SharedPreferences): Boolean =
        if (!prefs.contains(SORT_ASC_KEY)) true else prefs.getBoolean(SORT_ASC_KEY, true)

    fun saveSort(prefs: SharedPreferences, key: MachineSortKey, ascending: Boolean) {
        val raw = when (key) {
            MachineSortKey.DATE_CREATED -> "dateCreated"
            MachineSortKey.DATE_LAST_USED -> "dateLastUsed"
            MachineSortKey.NAME -> "name"
            MachineSortKey.KIND -> "kind"
        }
        prefs.edit().putString(SORT_KEY, raw).putBoolean(SORT_ASC_KEY, ascending).apply()
    }

    fun ordered(
        profiles: List<MachineProfile>,
        pinned: Set<String>,
        sortKey: MachineSortKey,
        ascending: Boolean,
    ): List<MachineProfile> {
        fun comparator(): Comparator<MachineProfile> {
            val base = when (sortKey) {
                MachineSortKey.NAME -> compareBy<MachineProfile> { it.name.lowercase() }
                MachineSortKey.KIND -> compareBy<MachineProfile> { it.type.selectablePivot().ordinal }
                    .thenBy { it.name.lowercase() }
                MachineSortKey.DATE_LAST_USED -> compareBy<MachineProfile> { it.updatedAtMs }
                MachineSortKey.DATE_CREATED -> compareBy { it.createdAtMs }
            }
            return if (ascending) base else base.reversed()
        }
        val pinnedList = profiles.filter { it.id in pinned }.sortedWith(comparator())
        val unpinned = profiles.filter { it.id !in pinned }.sortedWith(comparator())
        return pinnedList + unpinned
    }
}

/** Highlight fuzzy-matched characters in [name] for search (iOS card parity). */
fun highlightSearchSpans(name: String, query: String): List<Pair<String, Boolean>> {
    val needle = query.trim().lowercase().filter { !it.isWhitespace() }.toCharArray()
    if (needle.isEmpty()) return listOf(name to false)
    var ni = 0
    val spans = mutableListOf<Pair<String, Boolean>>()
    val buf = StringBuilder()
    var matching = false
    fun flush(isMatch: Boolean) {
        if (buf.isEmpty()) return
        spans.add(buf.toString() to isMatch)
        buf.clear()
    }
    for (ch in name) {
        val isMatch = ni < needle.size && ch.lowercaseChar() == needle[ni]
        if (isMatch != matching) {
            flush(matching)
            matching = isMatch
        }
        buf.append(ch)
        if (isMatch) ni++
    }
    flush(matching)
    return spans.ifEmpty { listOf(name to false) }
}
