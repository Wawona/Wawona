package com.aspauldingcode.wawona

import android.content.Context
import android.content.SharedPreferences
import androidx.activity.compose.BackHandler
import androidx.compose.foundation.background
import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ColumnScope
import androidx.compose.foundation.layout.ExperimentalLayoutApi
import androidx.compose.foundation.layout.FlowRow
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.KeyboardArrowRight
import androidx.compose.material.icons.filled.Add
import androidx.compose.material.icons.filled.CheckCircle
import androidx.compose.material.icons.filled.GridView
import androidx.compose.material.icons.filled.Search
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.FilterChip
import androidx.compose.material3.FilterChipDefaults
import androidx.compose.material3.FloatingActionButton
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.TextField
import androidx.compose.material3.TextFieldDefaults
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.KeyboardCapitalization
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import kotlinx.coroutines.delay

/** Nested Env Vars pages (iOS EnvironmentVariablesView parity). */
sealed class EnvVarsPage {
    data object List : EnvVarsPage()
    data class Detail(val name: String) : EnvVarsPage()
    data object New : EnvVarsPage()
}

/**
 * Global Settings → Env Vars. Matches iOS `EnvironmentVariablesView`:
 * catalog rows by category, search, detail editor with docs, add, reset.
 */
@Composable
fun EnvironmentVariablesScreen(
    prefs: SharedPreferences,
    page: EnvVarsPage,
    onPageChange: (EnvVarsPage) -> Unit,
    modifier: Modifier = Modifier,
) {
    val context = LocalContext.current
    var overrides by remember {
        mutableStateOf(EnvironmentOverrides.loadGlobal(prefs).toMap())
    }
    var confirmResetAll by remember { mutableStateOf(false) }

    fun reload() {
        overrides = EnvironmentOverrides.loadGlobal(prefs).toMap()
    }

    fun persist(next: Map<String, EnvironmentOverrides.Entry>) {
        EnvironmentOverrides.saveGlobal(prefs, next)
        overrides = next
        try {
            WawonaNative.nativeApplyEnvironmentOverrides(
                EnvironmentOverrides.jniPayload(prefs, null),
            )
        } catch (_: Throwable) {
        }
    }

    BackHandler(enabled = page !is EnvVarsPage.List) {
        onPageChange(EnvVarsPage.List)
    }

    when (page) {
        EnvVarsPage.List -> EnvVarsListPage(
            context = context,
            prefs = prefs,
            overrides = overrides,
            onOpenDetail = { onPageChange(EnvVarsPage.Detail(it)) },
            onOpenNew = { onPageChange(EnvVarsPage.New) },
            onResetOne = { name ->
                val next = overrides.toMutableMap()
                next.remove(name)
                persist(next)
            },
            onResetManaged = {
                val next = overrides.toMutableMap()
                EnvironmentOverrides.resetManaged(next)
                persist(next)
            },
            onRequestResetAll = { confirmResetAll = true },
            modifier = modifier,
        )
        is EnvVarsPage.Detail -> EnvVarsDetailPage(
            name = page.name,
            context = context,
            prefs = prefs,
            overrides = overrides,
            onPersist = ::persist,
            onReload = ::reload,
            modifier = modifier,
        )
        EnvVarsPage.New -> EnvVarsNewPage(
            onCancel = { onPageChange(EnvVarsPage.List) },
            onAdd = { name, value ->
                val next = overrides.toMutableMap()
                next[name] = EnvironmentOverrides.Entry.set(value)
                persist(next)
                onPageChange(EnvVarsPage.Detail(name))
            },
            modifier = modifier,
        )
    }

    if (confirmResetAll) {
        AlertDialog(
            onDismissRequest = { confirmResetAll = false },
            title = { Text("Reset all environment overrides?") },
            text = {
                Text("Clears global overrides. Catalog defaults still apply.")
            },
            confirmButton = {
                TextButton(
                    onClick = {
                        persist(emptyMap())
                        confirmResetAll = false
                    },
                    modifier = Modifier.testTag("wwn.settings.environment.resetAll"),
                ) { Text("Reset All") }
            },
            dismissButton = {
                TextButton(onClick = { confirmResetAll = false }) { Text("Cancel") }
            },
        )
    }
}

@OptIn(ExperimentalMaterial3Api::class, ExperimentalLayoutApi::class)
@Composable
private fun EnvVarsListPage(
    context: Context,
    prefs: SharedPreferences,
    overrides: Map<String, EnvironmentOverrides.Entry>,
    onOpenDetail: (String) -> Unit,
    onOpenNew: () -> Unit,
    onResetOne: (String) -> Unit,
    onResetManaged: () -> Unit,
    onRequestResetAll: () -> Unit,
    modifier: Modifier = Modifier,
) {
    var search by remember { mutableStateOf("") }
    var selectedCategory by remember { mutableStateOf<EnvironmentCategory?>(null) }
    val rows = remember(overrides, prefs) {
        EnvironmentCatalog.resolveRows(context, prefs, overrides)
    }
    val filtered = remember(rows, search, selectedCategory) {
        rows.filter { row ->
            if (selectedCategory != null && row.category != selectedCategory) return@filter false
            val q = search.trim()
            if (q.isEmpty()) return@filter true
            row.name.contains(q, ignoreCase = true) ||
                (row.value ?: "").contains(q, ignoreCase = true) ||
                (row.help ?: "").contains(q, ignoreCase = true) ||
                row.documentation.summary.contains(q, ignoreCase = true)
        }
    }
    val activeCategories = remember(rows) {
        val present = rows.map { it.category }.toSet()
        EnvironmentCategory.entries.filter { it in present }
    }
    val scheme = MaterialTheme.colorScheme

    Box(modifier.fillMaxSize().testTag(WawonaTestTags.SETTINGS_ENVIRONMENT)) {
        Column(
            Modifier
                .fillMaxSize()
                .verticalScroll(rememberScrollState())
                .padding(horizontal = 16.dp, vertical = 8.dp)
                .padding(bottom = 88.dp),
        ) {
            TextField(
                value = search,
                onValueChange = { search = it },
                modifier = Modifier.fillMaxWidth(),
                placeholder = { Text("Search variables") },
                leadingIcon = { Icon(Icons.Filled.Search, contentDescription = null) },
                singleLine = true,
                shape = MaterialTheme.shapes.large,
                colors = TextFieldDefaults.colors(
                    focusedContainerColor = scheme.surfaceContainerHigh,
                    unfocusedContainerColor = scheme.surfaceContainerHigh,
                    disabledContainerColor = scheme.surfaceContainerHigh,
                    focusedIndicatorColor = Color.Transparent,
                    unfocusedIndicatorColor = Color.Transparent,
                ),
            )
            Spacer(Modifier.height(10.dp))
            Row(
                Modifier
                    .fillMaxWidth()
                    .horizontalScroll(rememberScrollState())
                    .testTag("wwn.settings.environment.category"),
                horizontalArrangement = Arrangement.spacedBy(8.dp),
            ) {
                FilterChip(
                    selected = selectedCategory == null,
                    onClick = { selectedCategory = null },
                    label = { Text("All") },
                    leadingIcon = {
                        Icon(Icons.Filled.GridView, null, Modifier.size(18.dp))
                    },
                    colors = FilterChipDefaults.filterChipColors(
                        selectedContainerColor = scheme.secondaryContainer,
                    ),
                )
                activeCategories.forEach { cat ->
                    FilterChip(
                        selected = selectedCategory == cat,
                        onClick = { selectedCategory = cat },
                        label = { Text(cat.displayName) },
                        leadingIcon = {
                            Icon(cat.icon, null, Modifier.size(18.dp), tint = cat.accent)
                        },
                        colors = FilterChipDefaults.filterChipColors(
                            selectedContainerColor = cat.accent.copy(alpha = 0.18f),
                        ),
                    )
                }
            }
            Spacer(Modifier.height(12.dp))

            if (filtered.isEmpty()) {
                Text(
                    "No Variables Found",
                    style = MaterialTheme.typography.titleMedium,
                    fontWeight = FontWeight.SemiBold,
                )
                Text(
                    "No environment variables match your search or filter.",
                    style = MaterialTheme.typography.bodyMedium,
                    color = scheme.onSurfaceVariant,
                )
            } else if (selectedCategory == null && search.isBlank()) {
                activeCategories.forEach { category ->
                    val categoryRows = filtered.filter { it.category == category }
                    if (categoryRows.isEmpty()) return@forEach
                    EnvCategoryHeader(category)
                    EnvVarsGroup {
                        categoryRows.forEach { row ->
                            EnvVarRow(
                                row = row,
                                onClick = { onOpenDetail(row.name) },
                                onReset = if (row.isOverridden || row.isUnset) {
                                    { onResetOne(row.name) }
                                } else {
                                    null
                                },
                            )
                        }
                    }
                    Spacer(Modifier.height(12.dp))
                }
            } else {
                EnvVarsGroup {
                    filtered.forEach { row ->
                        EnvVarRow(
                            row = row,
                            onClick = { onOpenDetail(row.name) },
                            onReset = if (row.isOverridden || row.isUnset) {
                                { onResetOne(row.name) }
                            } else {
                                null
                            },
                        )
                    }
                }
                Spacer(Modifier.height(12.dp))
            }

            EnvVarsGroup {
                Surface(
                    onClick = onResetManaged,
                    modifier = Modifier
                        .fillMaxWidth()
                        .testTag("wwn.settings.environment.resetManaged"),
                    color = Color.Transparent,
                ) {
                    Text(
                        "Reset Wawona Defaults",
                        Modifier.padding(horizontal = 16.dp, vertical = 14.dp),
                        style = MaterialTheme.typography.bodyLarge,
                        color = scheme.primary,
                    )
                }
                Surface(
                    onClick = onRequestResetAll,
                    modifier = Modifier.fillMaxWidth(),
                    color = Color.Transparent,
                ) {
                    Text(
                        "Reset All Overrides",
                        Modifier.padding(horizontal = 16.dp, vertical = 14.dp),
                        style = MaterialTheme.typography.bodyLarge,
                        color = scheme.error,
                    )
                }
            }
            Text(
                "Wawona manages core Wayland and graphics environment variables automatically.",
                style = MaterialTheme.typography.bodySmall,
                color = scheme.onSurfaceVariant,
                modifier = Modifier.padding(horizontal = 8.dp, vertical = 8.dp),
            )
        }

        FloatingActionButton(
            onClick = onOpenNew,
            modifier = Modifier
                .align(Alignment.BottomEnd)
                .padding(20.dp)
                .testTag("wwn.settings.environment.new"),
            containerColor = scheme.primaryContainer,
            contentColor = scheme.onPrimaryContainer,
        ) {
            Icon(Icons.Filled.Add, contentDescription = "Add Variable")
        }
    }
}

@Composable
private fun EnvCategoryHeader(category: EnvironmentCategory) {
    Row(
        Modifier.padding(horizontal = 4.dp, vertical = 6.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Icon(category.icon, null, Modifier.size(18.dp), tint = category.accent)
        Spacer(Modifier.width(8.dp))
        Text(
            category.displayName,
            style = MaterialTheme.typography.titleSmall,
            fontWeight = FontWeight.SemiBold,
            color = category.accent,
        )
    }
}

@Composable
private fun EnvVarsGroup(content: @Composable ColumnScope.() -> Unit) {
    Surface(
        modifier = Modifier.fillMaxWidth(),
        shape = MaterialTheme.shapes.extraLarge,
        color = MaterialTheme.colorScheme.surfaceContainer,
        tonalElevation = 0.dp,
        shadowElevation = 0.dp,
    ) {
        Column(Modifier.fillMaxWidth(), content = content)
    }
}

@Composable
private fun EnvVarRow(
    row: ResolvedEnvironmentEntry,
    onClick: () -> Unit,
    onReset: (() -> Unit)?,
) {
    val scheme = MaterialTheme.colorScheme
    Surface(
        onClick = onClick,
        modifier = Modifier
            .fillMaxWidth()
            .testTag("wwn.settings.environment.row.${row.name}"),
        color = Color.Transparent,
    ) {
        Row(
            Modifier
                .fillMaxWidth()
                .padding(horizontal = 14.dp, vertical = 12.dp),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            Box(
                Modifier
                    .size(32.dp)
                    .clip(RoundedCornerShape(8.dp))
                    .background(row.category.accent.copy(alpha = 0.15f)),
                contentAlignment = Alignment.Center,
            ) {
                Icon(
                    row.category.icon,
                    contentDescription = null,
                    tint = row.category.accent,
                    modifier = Modifier.size(18.dp),
                )
            }
            Spacer(Modifier.width(12.dp))
            Column(Modifier.weight(1f)) {
                Text(
                    row.name,
                    fontFamily = FontFamily.Monospace,
                    fontWeight = FontWeight.SemiBold,
                    maxLines = 1,
                    overflow = TextOverflow.Ellipsis,
                )
                Text(
                    row.displayValue,
                    style = MaterialTheme.typography.bodySmall,
                    fontFamily = FontFamily.Monospace,
                    color = when {
                        row.isUnset -> scheme.error
                        row.isOverridden -> scheme.onSurface
                        else -> scheme.onSurfaceVariant
                    },
                    maxLines = 1,
                    overflow = TextOverflow.Ellipsis,
                )
            }
            if (row.isOverridden && !row.isUnset) {
                StatusPill("Custom", Color(0xFFFF9500))
            } else if (row.isUnset) {
                StatusPill("Unset", scheme.error)
            }
            Spacer(Modifier.width(4.dp))
            if (onReset != null) {
                TextButton(onClick = onReset) { Text("Reset") }
            } else {
                Icon(
                    Icons.AutoMirrored.Filled.KeyboardArrowRight,
                    contentDescription = null,
                    tint = scheme.onSurfaceVariant,
                )
            }
        }
    }
}

@Composable
private fun StatusPill(label: String, color: Color) {
    Text(
        label,
        style = MaterialTheme.typography.labelSmall,
        fontWeight = FontWeight.Medium,
        color = color,
        modifier = Modifier
            .clip(CircleShape)
            .background(color.copy(alpha = 0.15f))
            .padding(horizontal = 8.dp, vertical = 3.dp),
    )
}

@Composable
private fun EnvVarsDetailPage(
    name: String,
    context: Context,
    prefs: SharedPreferences,
    overrides: Map<String, EnvironmentOverrides.Entry>,
    onPersist: (Map<String, EnvironmentOverrides.Entry>) -> Unit,
    onReload: () -> Unit,
    modifier: Modifier = Modifier,
) {
    val row = remember(overrides, prefs, name) {
        EnvironmentCatalog.resolveRows(context, prefs, overrides).firstOrNull { it.name == name }
    }
    val doc = row?.documentation ?: EnvironmentCatalog.documentation(name)
    var currentValue by remember(name, row?.value, row?.isUnset) {
        mutableStateOf(if (row?.isUnset == true) "" else row?.value.orEmpty())
    }
    var showSaved by remember { mutableStateOf(false) }
    val scheme = MaterialTheme.colorScheme
    val accent = row?.category?.accent ?: EnvironmentCategory.XDG.accent

    LaunchedEffect(showSaved) {
        if (showSaved) {
            delay(2000)
            showSaved = false
        }
    }

    fun save(value: String) {
        val next = overrides.toMutableMap()
        next[name] = EnvironmentOverrides.Entry.set(value)
        onPersist(next)
        showSaved = true
        onReload()
    }

    fun revert() {
        val next = overrides.toMutableMap()
        next.remove(name)
        onPersist(next)
        onReload()
    }

    Column(
        modifier
            .fillMaxSize()
            .verticalScroll(rememberScrollState())
            .padding(horizontal = 16.dp, vertical = 12.dp)
            .testTag("wwn.settings.environment.detail"),
    ) {
        FlowRow(
            horizontalArrangement = Arrangement.spacedBy(8.dp),
            verticalArrangement = Arrangement.spacedBy(8.dp),
        ) {
            row?.category?.let { cat ->
                StatusPill(cat.displayName, cat.accent)
            }
            when {
                row?.isOverridden == true && row.isUnset -> StatusPill("Unset", scheme.error)
                row?.isOverridden == true -> StatusPill("Custom Override", Color(0xFFFF9500))
                else -> StatusPill("Default", scheme.onSurfaceVariant)
            }
        }
        Spacer(Modifier.height(12.dp))

        EnvVarsGroup {
            Column(Modifier.padding(16.dp), verticalArrangement = Arrangement.spacedBy(10.dp)) {
                Text("Value", style = MaterialTheme.typography.labelLarge, color = accent)
                OutlinedTextField(
                    value = currentValue,
                    onValueChange = { currentValue = it },
                    modifier = Modifier
                        .fillMaxWidth()
                        .testTag("wwn.settings.environment.edit.value"),
                    placeholder = {
                        Text(
                            doc.typicalDefault.ifEmpty { "Enter value" },
                            fontFamily = FontFamily.Monospace,
                        )
                    },
                    textStyle = MaterialTheme.typography.bodyLarge.copy(fontFamily = FontFamily.Monospace),
                    singleLine = false,
                    maxLines = 4,
                    keyboardOptions = KeyboardOptions(capitalization = KeyboardCapitalization.None),
                )
                Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                    TextButton(
                        onClick = { save(currentValue.trim()) },
                        modifier = Modifier.testTag("wwn.settings.environment.detail.save"),
                    ) { Text("Save") }
                    if (row?.isOverridden == true) {
                        TextButton(onClick = {
                            revert()
                            currentValue = row.typicalDefault.takeIf {
                                !it.startsWith("(")
                            }.orEmpty()
                        }) { Text("Revert to Default") }
                    }
                }
                if (showSaved) {
                    Row(verticalAlignment = Alignment.CenterVertically) {
                        Icon(
                            Icons.Filled.CheckCircle,
                            contentDescription = null,
                            tint = Color(0xFF34C759),
                            modifier = Modifier.size(18.dp),
                        )
                        Spacer(Modifier.width(6.dp))
                        Text("Saved", color = Color(0xFF34C759), style = MaterialTheme.typography.bodySmall)
                    }
                }
            }
        }

        if (doc.summary.isNotEmpty() || doc.details.isNotEmpty()) {
            Spacer(Modifier.height(12.dp))
            EnvVarsGroup {
                Column(Modifier.padding(16.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
                    Text("Documentation", style = MaterialTheme.typography.labelLarge, color = accent)
                    if (doc.summary.isNotEmpty()) {
                        Text(doc.summary, style = MaterialTheme.typography.titleSmall, fontWeight = FontWeight.Medium)
                    }
                    if (doc.details.isNotEmpty()) {
                        Text(doc.details, style = MaterialTheme.typography.bodyMedium, color = scheme.onSurfaceVariant)
                    }
                }
            }
        }

        if (doc.typicalDefault.isNotEmpty()) {
            Spacer(Modifier.height(12.dp))
            EnvVarsGroup {
                Column(Modifier.padding(16.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
                    Text("Typical Default", style = MaterialTheme.typography.labelLarge, color = accent)
                    Row(verticalAlignment = Alignment.CenterVertically) {
                        Text(
                            doc.typicalDefault,
                            fontFamily = FontFamily.Monospace,
                            modifier = Modifier.weight(1f),
                        )
                        TextButton(onClick = {
                            currentValue = doc.typicalDefault
                            save(doc.typicalDefault)
                        }) { Text("Use Default") }
                    }
                }
            }
        }

        if (doc.examples.isNotEmpty()) {
            Spacer(Modifier.height(12.dp))
            EnvVarsGroup {
                Column(Modifier.padding(16.dp), verticalArrangement = Arrangement.spacedBy(4.dp)) {
                    Text(
                        "Examples",
                        style = MaterialTheme.typography.labelLarge,
                        color = accent,
                        modifier = Modifier.padding(bottom = 4.dp),
                    )
                    doc.examples.forEach { example ->
                        Row(
                            Modifier.fillMaxWidth().padding(vertical = 4.dp),
                            verticalAlignment = Alignment.CenterVertically,
                        ) {
                            Text(
                                example,
                                fontFamily = FontFamily.Monospace,
                                style = MaterialTheme.typography.bodySmall,
                                modifier = Modifier.weight(1f),
                            )
                            TextButton(onClick = {
                                currentValue = example
                                save(example)
                            }) { Text("Use") }
                        }
                    }
                }
            }
        }

        Spacer(Modifier.height(12.dp))
        EnvVarsGroup {
            Column(Modifier.padding(16.dp), verticalArrangement = Arrangement.spacedBy(10.dp)) {
                Text("Details", style = MaterialTheme.typography.labelLarge, color = accent)
                DetailLine("Variable Name", name)
                row?.category?.let { DetailLine("Category", it.displayName) }
                row?.mutability?.let { DetailLine("Mutability", it.name.lowercase().replaceFirstChar { c -> c.uppercase() }) }
                row?.ownedBy?.takeIf { it.isNotEmpty() }?.let { DetailLine("Managed By", it) }
                DetailLine("Scope", "Global Preference")
            }
        }
        Spacer(Modifier.height(24.dp))
    }
}

@Composable
private fun DetailLine(label: String, value: String) {
    Row(Modifier.fillMaxWidth()) {
        Text(
            label,
            style = MaterialTheme.typography.bodyMedium,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
            modifier = Modifier.weight(0.4f),
        )
        Text(
            value,
            style = MaterialTheme.typography.bodyMedium,
            fontFamily = if (label == "Variable Name") FontFamily.Monospace else FontFamily.Default,
            modifier = Modifier.weight(0.6f),
        )
    }
}

@Composable
private fun EnvVarsNewPage(
    onCancel: () -> Unit,
    onAdd: (String, String) -> Unit,
    modifier: Modifier = Modifier,
) {
    var name by remember { mutableStateOf("") }
    var value by remember { mutableStateOf("") }
    val accent = EnvironmentCategory.XDG.accent
    val canAdd = name.trim().isNotEmpty()

    Column(
        modifier
            .fillMaxSize()
            .verticalScroll(rememberScrollState())
            .padding(16.dp),
    ) {
        EnvVarsGroup {
            Column(Modifier.padding(16.dp), verticalArrangement = Arrangement.spacedBy(10.dp)) {
                Text("Variable Identity", style = MaterialTheme.typography.labelLarge, color = accent)
                OutlinedTextField(
                    value = name,
                    onValueChange = { name = it },
                    modifier = Modifier
                        .fillMaxWidth()
                        .testTag("wwn.settings.environment.new.name"),
                    label = { Text("VARIABLE_NAME") },
                    placeholder = { Text("e.g. MOZ_ENABLE_WAYLAND") },
                    textStyle = MaterialTheme.typography.bodyLarge.copy(fontFamily = FontFamily.Monospace),
                    singleLine = true,
                    keyboardOptions = KeyboardOptions(capitalization = KeyboardCapitalization.Characters),
                )
            }
        }
        Spacer(Modifier.height(12.dp))
        EnvVarsGroup {
            Column(Modifier.padding(16.dp), verticalArrangement = Arrangement.spacedBy(10.dp)) {
                Text("Initial Value", style = MaterialTheme.typography.labelLarge, color = accent)
                OutlinedTextField(
                    value = value,
                    onValueChange = { value = it },
                    modifier = Modifier
                        .fillMaxWidth()
                        .testTag("wwn.settings.environment.new.value"),
                    label = { Text("Value") },
                    placeholder = { Text("e.g. 1") },
                    textStyle = MaterialTheme.typography.bodyLarge.copy(fontFamily = FontFamily.Monospace),
                    singleLine = true,
                    keyboardOptions = KeyboardOptions(capitalization = KeyboardCapitalization.None),
                )
            }
        }
        Spacer(Modifier.height(16.dp))
        Row(horizontalArrangement = Arrangement.spacedBy(12.dp)) {
            TextButton(onClick = onCancel) { Text("Cancel") }
            TextButton(
                onClick = {
                    val trimmed = name.trim()
                    if (trimmed.isNotEmpty()) onAdd(trimmed, value)
                },
                enabled = canAdd,
                modifier = Modifier.testTag("wwn.settings.environment.new.confirm"),
            ) { Text("Add") }
        }
    }
}
