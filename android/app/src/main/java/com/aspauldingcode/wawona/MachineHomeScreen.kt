package com.aspauldingcode.wawona

import android.content.Context
import android.os.Build
import android.widget.Toast
import androidx.compose.animation.AnimatedContent
import androidx.compose.animation.AnimatedVisibility
import androidx.compose.animation.SizeTransform
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.animation.scaleIn
import androidx.compose.animation.slideInHorizontally
import androidx.compose.animation.slideOutHorizontally
import androidx.compose.animation.togetherWith
import androidx.compose.foundation.BorderStroke
import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ExperimentalLayoutApi
import androidx.compose.foundation.layout.FlowRow
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.material.icons.filled.Close
import androidx.compose.material.icons.filled.Error
import androidx.compose.material.icons.filled.PauseCircle
import androidx.compose.material.icons.filled.Search
import androidx.compose.material.icons.filled.Sync
import androidx.compose.material.icons.filled.Warning
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.FilledTonalButton
import androidx.compose.material3.FloatingActionButton
import androidx.compose.material3.FloatingActionButtonDefaults
import androidx.compose.material3.TopAppBarDefaults
import androidx.compose.ui.input.nestedscroll.nestedScroll
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.platform.testTag
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.RowScope
import androidx.compose.foundation.layout.defaultMinSize
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.ScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.BasicText
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.foundation.text.TextAutoSize
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.filled.Add
import androidx.compose.material.icons.filled.CheckCircle
import androidx.compose.material.icons.filled.Computer
import androidx.compose.material.icons.filled.Delete
import androidx.compose.material.icons.filled.Edit
import androidx.compose.material.icons.filled.PlayArrow
import androidx.compose.material.icons.filled.RadioButtonUnchecked
import androidx.compose.material.icons.filled.Settings
import androidx.compose.material.icons.filled.Stop
import androidx.compose.material.icons.filled.Terminal
import androidx.compose.material.icons.outlined.CenterFocusStrong
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Button
import androidx.compose.material3.Card
import androidx.compose.material3.CardDefaults
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.ExposedDropdownMenuBox
import androidx.compose.material3.ExposedDropdownMenuDefaults
import androidx.compose.material3.FilterChip
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Surface
import androidx.compose.material3.Switch
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.TextField
import androidx.compose.material3.TextFieldDefaults
import androidx.compose.material3.TopAppBar
import androidx.compose.material3.rememberTopAppBarState
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.focus.FocusRequester
import androidx.compose.ui.focus.focusRequester
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.asImageBitmap
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.platform.LocalConfiguration
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.text.input.PasswordVisualTransformation
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.compose.foundation.lazy.grid.GridCells
import androidx.compose.foundation.lazy.grid.GridItemSpan
import androidx.compose.foundation.lazy.grid.LazyVerticalGrid
import androidx.compose.foundation.lazy.grid.items
import androidx.compose.material3.IconButton
import androidx.compose.material3.AssistChip
import androidx.compose.material3.DrawerValue
import androidx.compose.material3.ModalDrawerSheet
import androidx.compose.material3.ModalNavigationDrawer
import androidx.compose.material3.VerticalDivider
import androidx.compose.material3.rememberDrawerState
import androidx.compose.material.icons.automirrored.filled.Sort
import androidx.compose.material.icons.filled.Check
import androidx.compose.material.icons.filled.Menu
import androidx.compose.material.icons.filled.PushPin
import androidx.compose.material.icons.outlined.PushPin
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.ui.text.SpanStyle
import androidx.compose.ui.text.buildAnnotatedString
import androidx.compose.ui.text.withStyle
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import android.net.Uri
import org.json.JSONObject
import java.io.File

private val compactButtonPadding = PaddingValues(horizontal = 8.dp, vertical = 4.dp)

private fun readBoolOverride(overrides: JSONObject?, key: String, globalDefault: Boolean): Boolean {
    if (overrides == null || !overrides.has(key)) return globalDefault
    return when (val raw = overrides.opt(key)) {
        is JSONObject -> when (raw.optString("type", "")) {
            "boolean" -> raw.optBoolean("value", globalDefault)
            else -> globalDefault
        }
        is Boolean -> raw
        else -> globalDefault
    }
}

private fun writeBoolOverride(overrides: JSONObject, key: String, value: Boolean, globalDefault: Boolean) {
    if (value == globalDefault) {
        overrides.remove(key)
    } else {
        overrides.put(
            key,
            JSONObject().apply {
                put("type", "boolean")
                put("value", value)
            }
        )
    }
}

private fun readStringOverride(overrides: JSONObject?, key: String, globalDefault: String): String {
    if (overrides == null || !overrides.has(key)) return globalDefault
    return when (val raw = overrides.opt(key)) {
        is JSONObject -> when (raw.optString("type", "")) {
            "string" -> raw.optString("value", globalDefault)
            else -> globalDefault
        }
        is String -> raw
        else -> globalDefault
    }
}

private fun writeStringOverride(overrides: JSONObject, key: String, value: String, globalDefault: String) {
    if (value == globalDefault) {
        overrides.remove(key)
    } else {
        overrides.put(
            key,
            JSONObject().apply {
                put("type", "string")
                put("value", value)
            }
        )
    }
}

@OptIn(ExperimentalMaterial3Api::class, ExperimentalLayoutApi::class)
@Composable
fun MachineWelcomeScreen(
    profiles: List<MachineProfile>,
    thumbnailRevision: Int,
    activeMachineId: String?,
    machineStatusFor: (String) -> MachineStatus,
    onCreate: (MachineProfile) -> Unit,
    onUpdate: (MachineProfile) -> Unit,
    onDelete: (MachineProfile) -> Unit,
    onConnect: (MachineProfile) -> Unit,
    onFocus: (MachineProfile) -> Unit,
    onStop: (MachineProfile) -> Unit,
    onOpenSettings: () -> Unit
) {
    var editorProfile by remember { mutableStateOf<MachineProfile?>(null) }
    var creating by remember { mutableStateOf(false) }
    var searchQuery by remember { mutableStateOf("") }
    var searchExpanded by remember { mutableStateOf(false) }
    val listBottomPadding = 72.dp
    val scrollBehavior = TopAppBarDefaults.pinnedScrollBehavior(rememberTopAppBarState())

    val catalogContext = LocalContext.current
    val catalogPrefs = remember {
        catalogContext.getSharedPreferences("wawona_prefs", Context.MODE_PRIVATE)
    }
    val tagStore = remember { MachineTagStore(catalogPrefs) }
    var tags by remember { mutableStateOf(tagStore.loadTags()) }
    var assignments by remember { mutableStateOf(tagStore.loadAssignments()) }
    var pinnedIds by remember { mutableStateOf(MachineCatalogPrefs.loadPinned(catalogPrefs)) }
    var sortKey by remember { mutableStateOf(MachineCatalogPrefs.loadSortKey(catalogPrefs)) }
    var sortAscending by remember { mutableStateOf(MachineCatalogPrefs.loadSortAscending(catalogPrefs)) }
    var navDest by remember { mutableStateOf<MachinesNavDest>(MachinesNavDest.Machines) }
    var showCreateTag by remember { mutableStateOf(false) }
    var editingTag by remember { mutableStateOf<MachineTag?>(null) }
    val catalogTitle = remember(navDest, tags) {
        when (val dest = navDest) {
            is MachinesNavDest.Machines -> "Machine Configuration"
            is MachinesNavDest.TabOverview -> "Tab Overview"
            is MachinesNavDest.Tag -> tags.firstOrNull { it.id == dest.tagId }?.name ?: "Tag"
        }
    }
    var sortMenuExpanded by remember { mutableStateOf(false) }
    val drawerState = rememberDrawerState(DrawerValue.Closed)
    val drawerScope = rememberCoroutineScope()
    val isWide = LocalConfiguration.current.screenWidthDp >= 840

    LaunchedEffect(profiles) {
        assignments = tagStore.pruneAssignments(profiles.map { it.id }.toSet(), assignments)
        val validPins = pinnedIds.filter { id -> profiles.any { it.id == id } }.toSet()
        if (validPins != pinnedIds) {
            pinnedIds = validPins
            MachineCatalogPrefs.savePinned(catalogPrefs, validPins)
        }
    }
    LaunchedEffect(tags, navDest) {
        val dest = navDest
        if (dest is MachinesNavDest.Tag && tags.none { it.id == dest.tagId }) {
            navDest = MachinesNavDest.Machines
        }
    }

    val visibleProfiles = remember(
        profiles, searchQuery, navDest, assignments, pinnedIds, sortKey, sortAscending,
    ) {
        val dest = navDest
        val tagFiltered = if (dest is MachinesNavDest.Tag) {
            profiles.filter { dest.tagId in assignments[it.id].orEmpty() }
        } else {
            profiles
        }
        val searched = MachineSearch.fuzzyFilter(tagFiltered, searchQuery, MachineSearch::searchableText)
        if (searchQuery.isBlank()) {
            MachineCatalogPrefs.ordered(searched, pinnedIds, sortKey, sortAscending)
        } else {
            // Keep fuzzy relevance order; only float pinned machines to the front.
            searched.filter { it.id in pinnedIds } + searched.filter { it.id !in pinnedIds }
        }
    }

    val sidebarContent: @Composable (onPicked: () -> Unit) -> Unit = { onPicked ->
        MachinesConfigurationSidebar(
            tags = tags,
            selected = navDest,
            onSelect = {
                navDest = it
                onPicked()
            },
            onCreateTag = {
                onPicked()
                showCreateTag = true
            },
            onEditTag = { tag ->
                onPicked()
                editingTag = tag
            },
            onDeleteTag = { tag ->
                val (nextTags, nextAssignments) = tagStore.deleteTag(tag.id, tags, assignments)
                tags = nextTags
                assignments = nextAssignments
                val dest = navDest
                if (dest is MachinesNavDest.Tag && dest.tagId == tag.id) {
                    navDest = MachinesNavDest.Machines
                }
            },
        )
    }

    ModalNavigationDrawer(
        drawerState = drawerState,
        gesturesEnabled = !isWide,
        drawerContent = {
            if (!isWide) {
                ModalDrawerSheet {
                    sidebarContent { drawerScope.launch { drawerState.close() } }
                }
            }
        },
    ) {
    Scaffold(
        modifier = Modifier
            .nestedScroll(scrollBehavior.nestedScrollConnection)
            .testTag(WawonaTestTags.MACHINES_ROOT),
        containerColor = MaterialTheme.colorScheme.background,
        topBar = {
            TopAppBar(
                title = {
                    if (searchExpanded) {
                        val searchFocus = remember { FocusRequester() }
                        LaunchedEffect(Unit) { searchFocus.requestFocus() }
                        TextField(
                            value = searchQuery,
                            onValueChange = { searchQuery = it },
                            modifier = Modifier
                                .fillMaxWidth()
                                .focusRequester(searchFocus),
                            placeholder = { Text("Search machines") },
                            singleLine = true,
                            colors = TextFieldDefaults.colors(
                                focusedContainerColor = Color.Transparent,
                                unfocusedContainerColor = Color.Transparent,
                                focusedIndicatorColor = Color.Transparent,
                                unfocusedIndicatorColor = Color.Transparent,
                            ),
                        )
                    } else {
                        Text(
                            catalogTitle,
                            style = MaterialTheme.typography.titleLarge,
                        )
                    }
                },
                scrollBehavior = scrollBehavior,
                colors = TopAppBarDefaults.topAppBarColors(
                    containerColor = MaterialTheme.colorScheme.surface.copy(alpha = 0.92f),
                    scrolledContainerColor = MaterialTheme.colorScheme.surfaceContainer,
                    titleContentColor = MaterialTheme.colorScheme.onSurface,
                    actionIconContentColor = MaterialTheme.colorScheme.onSurfaceVariant,
                    navigationIconContentColor = MaterialTheme.colorScheme.onSurfaceVariant,
                ),
                navigationIcon = {
                    if (searchExpanded) {
                        IconButton(onClick = {
                            searchExpanded = false
                            searchQuery = ""
                        }) {
                            Icon(
                                Icons.AutoMirrored.Filled.ArrowBack,
                                contentDescription = "Close search",
                            )
                        }
                    } else if (!isWide) {
                        IconButton(onClick = { drawerScope.launch { drawerState.open() } }) {
                            Icon(Icons.Filled.Menu, contentDescription = "Open sidebar")
                        }
                    }
                },
                actions = {
                    if (searchExpanded) {
                        if (searchQuery.isNotEmpty()) {
                            IconButton(onClick = { searchQuery = "" }) {
                                Icon(Icons.Filled.Close, contentDescription = "Clear search")
                            }
                        }
                    } else {
                        IconButton(onClick = { searchExpanded = true }) {
                            Icon(Icons.Filled.Search, contentDescription = "Search machines")
                        }
                        Box {
                            IconButton(onClick = { sortMenuExpanded = true }) {
                                Icon(Icons.AutoMirrored.Filled.Sort, contentDescription = "Sort machines")
                            }
                            DropdownMenu(
                                expanded = sortMenuExpanded,
                                onDismissRequest = { sortMenuExpanded = false },
                            ) {
                                MachineSortKey.entries.forEach { key ->
                                    DropdownMenuItem(
                                        text = { Text(key.label) },
                                        trailingIcon = {
                                            if (key == sortKey) {
                                                Icon(Icons.Filled.Check, contentDescription = null)
                                            }
                                        },
                                        onClick = {
                                            sortKey = key
                                            MachineCatalogPrefs.saveSort(catalogPrefs, key, sortAscending)
                                            sortMenuExpanded = false
                                        },
                                    )
                                }
                                HorizontalDivider()
                                listOf(true to "Ascending", false to "Descending").forEach { (asc, label) ->
                                    DropdownMenuItem(
                                        text = { Text(label) },
                                        trailingIcon = {
                                            if (asc == sortAscending) {
                                                Icon(Icons.Filled.Check, contentDescription = null)
                                            }
                                        },
                                        onClick = {
                                            sortAscending = asc
                                            MachineCatalogPrefs.saveSort(catalogPrefs, sortKey, asc)
                                            sortMenuExpanded = false
                                        },
                                    )
                                }
                            }
                        }
                        IconButton(
                            onClick = onOpenSettings,
                            modifier = Modifier.testTag(WawonaTestTags.MACHINES_SETTINGS),
                        ) {
                            Icon(Icons.Filled.Settings, contentDescription = "Settings")
                        }
                    }
                },
            )
        },
        floatingActionButton = {
            if (navDest !is MachinesNavDest.TabOverview) {
                FloatingActionButton(
                    onClick = { creating = true },
                    modifier = Modifier.testTag(WawonaTestTags.MACHINES_ADD),
                    shape = MaterialTheme.shapes.large,
                    containerColor = MaterialTheme.colorScheme.primaryContainer,
                    contentColor = MaterialTheme.colorScheme.onPrimaryContainer,
                    elevation = FloatingActionButtonDefaults.elevation(
                        defaultElevation = 4.dp,
                        pressedElevation = 6.dp,
                    ),
                ) {
                    Icon(
                        Icons.Filled.Add,
                        contentDescription = "Add Machine",
                    )
                }
            }
        },
    ) { padding ->
        val motion = MaterialTheme.motionScheme
        Row(
            modifier = Modifier
                .fillMaxSize()
                .padding(padding),
        ) {
        if (isWide) {
            sidebarContent {}
            VerticalDivider(Modifier.fillMaxHeight())
        }
        Box(
            modifier = Modifier
                .weight(1f)
                .fillMaxHeight(),
        ) {
            if (navDest is MachinesNavDest.TabOverview) {
                TabOverviewPlaceholder(
                    profiles = profiles,
                    activeMachineId = activeMachineId,
                    machineStatusFor = machineStatusFor,
                    onFocus = onFocus,
                )
            } else {
            LazyVerticalGrid(
                columns = GridCells.Adaptive(minSize = 280.dp),
                modifier = Modifier.fillMaxSize(),
                contentPadding = PaddingValues(
                    start = 16.dp,
                    top = 12.dp,
                    end = 16.dp,
                    bottom = listBottomPadding,
                ),
                verticalArrangement = Arrangement.spacedBy(16.dp),
                horizontalArrangement = Arrangement.spacedBy(16.dp),
            ) {
                if (visibleProfiles.isEmpty()) {
                    item(span = { GridItemSpan(maxLineSpan) }) {
                        Column(
                            modifier = Modifier
                                .fillMaxWidth()
                                .padding(top = 30.dp, bottom = 24.dp),
                            horizontalAlignment = Alignment.CenterHorizontally,
                        ) {
                            Icon(
                                Icons.Filled.Search,
                                contentDescription = null,
                                modifier = Modifier.size(48.dp),
                                tint = MaterialTheme.colorScheme.onSurfaceVariant,
                            )
                            Spacer(Modifier.height(12.dp))
                            Text(
                                "No Matching Machines",
                                style = MaterialTheme.typography.titleMedium,
                                fontWeight = FontWeight.SemiBold,
                            )
                            Spacer(Modifier.height(6.dp))
                            Text(
                                "Adjust search or add a new machine profile.",
                                style = MaterialTheme.typography.bodySmall,
                                color = MaterialTheme.colorScheme.onSurfaceVariant,
                            )
                        }
                    }
                } else {
                    val renderCard: @Composable (MachineProfile) -> Unit = { profile ->
                        MachineCardEntrance {
                            MachineGridCard(
                                profile = profile,
                                thumbnailRevision = thumbnailRevision,
                                status = machineStatusFor(profile.id),
                                isActive = profile.id == activeMachineId,
                                onEdit = { editorProfile = profile },
                                onDelete = { onDelete(profile) },
                                onConnect = { onConnect(profile) },
                                onFocus = { onFocus(profile) },
                                onStop = { onStop(profile) },
                                searchQuery = searchQuery,
                                tags = tagStore.tagsFor(profile.id, tags, assignments),
                                isPinned = profile.id in pinnedIds,
                                allTags = tags,
                                onTogglePin = {
                                    if (profile.id !in pinnedIds &&
                                        pinnedIds.size >= MachineCatalogPrefs.MAX_PINNED
                                    ) {
                                        Toast.makeText(
                                            catalogContext,
                                            "Pin limit reached (6)",
                                            Toast.LENGTH_SHORT,
                                        ).show()
                                    } else {
                                        pinnedIds = MachineCatalogPrefs.togglePin(
                                            catalogPrefs,
                                            profile.id,
                                            pinnedIds,
                                        )
                                    }
                                },
                                onToggleTag = { tag ->
                                    assignments = tagStore.toggleAssignment(tag.id, profile.id, assignments)
                                },
                            )
                        }
                    }
                    val pinnedVisible = visibleProfiles.filter { it.id in pinnedIds }
                    val otherVisible = visibleProfiles.filter { it.id !in pinnedIds }
                    if (pinnedVisible.isNotEmpty()) {
                        item(key = "header-pinned", span = { GridItemSpan(maxLineSpan) }) {
                            MachineSectionHeader("Pinned")
                        }
                        items(pinnedVisible, key = { it.id }) { profile -> renderCard(profile) }
                    }
                    if (otherVisible.isNotEmpty()) {
                        if (pinnedVisible.isNotEmpty()) {
                            item(key = "header-others", span = { GridItemSpan(maxLineSpan) }) {
                                MachineSectionHeader("Machines")
                            }
                        }
                        items(otherVisible, key = { it.id }) { profile -> renderCard(profile) }
                    }
                }
            }
            }

            Box(
                modifier = Modifier
                    .align(Alignment.TopCenter)
                    .fillMaxWidth()
                    .height(20.dp)
                    .background(
                        Brush.verticalGradient(
                            colors = listOf(
                                MaterialTheme.colorScheme.background.copy(alpha = 0.95f),
                                Color.Transparent,
                            ),
                        ),
                    ),
            )
            Box(
                modifier = Modifier
                    .align(Alignment.BottomCenter)
                    .fillMaxWidth()
                    .height(28.dp)
                    .background(
                        Brush.verticalGradient(
                            colors = listOf(
                                Color.Transparent,
                                MaterialTheme.colorScheme.background.copy(alpha = 0.95f),
                            ),
                        ),
                    ),
            )
        }
        }
    }
    }

    if (showCreateTag) {
        TagEditorDialog(
            onDismiss = { showCreateTag = false },
            onSave = { name, colorHex ->
                tags = tagStore.createTag(name, colorHex, tags)
                showCreateTag = false
            },
        )
    }

    editingTag?.let { tag ->
        TagEditorDialog(
            initialTag = tag,
            onDismiss = { editingTag = null },
            onSave = { name, colorHex ->
                tags = tagStore.updateTag(
                    tag.copy(name = name.trim(), colorHex = colorHex),
                    tags,
                )
                editingTag = null
            },
            onDelete = {
                val (nextTags, nextAssignments) = tagStore.deleteTag(tag.id, tags, assignments)
                tags = nextTags
                assignments = nextAssignments
                val dest = navDest
                if (dest is MachinesNavDest.Tag && dest.tagId == tag.id) {
                    navDest = MachinesNavDest.Machines
                }
                editingTag = null
            },
        )
    }

    if (creating || editorProfile != null) {
        MachineEditorSheet(
            title = if (creating) "Add Machine Profile" else "Edit Machine Profile",
            initial = editorProfile,
            onDismiss = {
                creating = false
                editorProfile = null
            },
            onSave = { saved ->
                if (editorProfile == null) onCreate(saved) else onUpdate(saved)
                creating = false
                editorProfile = null
            },
            onOpenSettings = onOpenSettings
        )
    }
}

@Composable
private fun MachineCardEntrance(content: @Composable () -> Unit) {
    val motion = MaterialTheme.motionScheme
    AnimatedVisibility(
        visible = true,
        enter = fadeIn(animationSpec = motion.defaultEffectsSpec()) +
            scaleIn(
                initialScale = 0.96f,
                animationSpec = motion.defaultSpatialSpec(),
            ),
    ) {
        content()
    }
}

@Composable
private fun MachineSectionHeader(title: String) {
    Text(
        title,
        style = MaterialTheme.typography.titleSmall,
        fontWeight = FontWeight.SemiBold,
        color = MaterialTheme.colorScheme.onSurfaceVariant,
        modifier = Modifier
            .fillMaxWidth()
            .padding(top = 4.dp),
    )
}

@Composable
private fun TagDot(tag: MachineTag, size: androidx.compose.ui.unit.Dp) {
    Box(
        Modifier
            .size(size)
            .clip(CircleShape)
            .background(MachineTagPalette.color(tag.colorHex)),
    )
}

@OptIn(ExperimentalLayoutApi::class)
@Composable
private fun TagEditorDialog(
    onDismiss: () -> Unit,
    onSave: (name: String, colorHex: String) -> Unit,
    initialTag: MachineTag? = null,
    onDelete: (() -> Unit)? = null,
) {
    var name by remember(initialTag) { mutableStateOf(initialTag?.name ?: "") }
    var colorHex by remember(initialTag) {
        mutableStateOf(initialTag?.colorHex ?: MachineTagPalette.hexes[6])
    }
    val isEdit = initialTag != null
    AlertDialog(
        onDismissRequest = onDismiss,
        title = { Text(if (isEdit) "Edit Tag" else "New Tag") },
        text = {
            Column(verticalArrangement = Arrangement.spacedBy(12.dp)) {
                OutlinedTextField(
                    value = name,
                    onValueChange = { name = it },
                    label = { Text("Name") },
                    singleLine = true,
                    modifier = Modifier.fillMaxWidth(),
                )
                FlowRow(
                    horizontalArrangement = Arrangement.spacedBy(10.dp),
                    verticalArrangement = Arrangement.spacedBy(10.dp),
                ) {
                    MachineTagPalette.hexes.forEach { hex ->
                        val selected = hex == colorHex
                        Box(
                            Modifier
                                .size(32.dp)
                                .clip(CircleShape)
                                .background(MachineTagPalette.color(hex))
                                .border(
                                    width = if (selected) 3.dp else 0.dp,
                                    color = MaterialTheme.colorScheme.onSurface,
                                    shape = CircleShape,
                                )
                                .clickable { colorHex = hex },
                        )
                    }
                }
            }
        },
        confirmButton = {
            TextButton(
                onClick = { onSave(name, colorHex) },
                enabled = name.isNotBlank(),
            ) { Text(if (isEdit) "Save" else "Create") }
        },
        dismissButton = {
            Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                if (isEdit && onDelete != null) {
                    TextButton(onClick = onDelete) { Text("Delete") }
                }
                TextButton(onClick = onDismiss) { Text("Cancel") }
            }
        },
    )
}

@OptIn(ExperimentalLayoutApi::class)
@Composable
private fun MachineGridCard(
    profile: MachineProfile,
    thumbnailRevision: Int,
    status: MachineStatus,
    isActive: Boolean,
    onEdit: () -> Unit,
    onDelete: () -> Unit,
    onConnect: () -> Unit,
    onFocus: () -> Unit,
    onStop: () -> Unit,
    searchQuery: String = "",
    tags: List<MachineTag> = emptyList(),
    isPinned: Boolean = false,
    allTags: List<MachineTag> = emptyList(),
    onTogglePin: () -> Unit = {},
    onToggleTag: (MachineTag) -> Unit = {},
) {
    val context = LocalContext.current
    var tagMenuExpanded by remember { mutableStateOf(false) }
    val thumbnailBitmap = remember(profile.id, thumbnailRevision) {
        MachineThumbnailStore.load(context, profile.id)
    }
    val capabilities = profile.capabilities()
    val isRunning = status == MachineStatus.CONNECTED || status == MachineStatus.CONNECTING
    val statusColor = statusColorFor(status)
    val subtitle = machineSubtitle(profile)
    val summary = configurationSummary(profile)
    val cardShape = MaterialTheme.shapes.extraLarge
    val scheme = MaterialTheme.colorScheme

    Card(
        modifier = Modifier
            .fillMaxWidth()
            .testTag(WawonaTestTags.machinesCard(profile.id)),
        shape = cardShape,
        colors = CardDefaults.cardColors(
            containerColor = scheme.surfaceContainerHigh,
        ),
        elevation = CardDefaults.cardElevation(defaultElevation = 1.dp),
        border = BorderStroke(1.dp, scheme.outlineVariant),
    ) {
        Column(
            modifier = Modifier
                .fillMaxWidth()
                .padding(16.dp),
            verticalArrangement = Arrangement.spacedBy(12.dp)
        ) {
            MachineCardBanner(
                profileName = profile.name,
                subtitle = subtitle,
                statusColor = statusColor,
                thumbnailBitmap = thumbnailBitmap,
                searchQuery = searchQuery,
            )

            Row(
                modifier = Modifier.fillMaxWidth(),
                verticalAlignment = Alignment.CenterVertically,
            ) {
                FlowRow(
                    modifier = Modifier.weight(1f),
                    horizontalArrangement = Arrangement.spacedBy(6.dp),
                    verticalArrangement = Arrangement.spacedBy(4.dp),
                ) {
                    tags.forEach { tag ->
                        AssistChip(
                            onClick = { onToggleTag(tag) },
                            label = { Text(tag.name, maxLines = 1, overflow = TextOverflow.Ellipsis) },
                            leadingIcon = { TagDot(tag, 10.dp) },
                        )
                    }
                }
                Box {
                    TextButton(onClick = { tagMenuExpanded = true }) { Text("Tags") }
                    DropdownMenu(
                        expanded = tagMenuExpanded,
                        onDismissRequest = { tagMenuExpanded = false },
                    ) {
                        if (allTags.isEmpty()) {
                            DropdownMenuItem(
                                text = { Text("No tags. Create one from the sidebar.") },
                                enabled = false,
                                onClick = {},
                            )
                        } else {
                            allTags.forEach { tag ->
                                DropdownMenuItem(
                                    text = { Text(tag.name) },
                                    leadingIcon = { TagDot(tag, 12.dp) },
                                    trailingIcon = {
                                        if (tags.any { it.id == tag.id }) {
                                            Icon(Icons.Filled.Check, contentDescription = null)
                                        }
                                    },
                                    onClick = { onToggleTag(tag) },
                                )
                            }
                        }
                    }
                }
                IconButton(onClick = onTogglePin) {
                    Icon(
                        if (isPinned) Icons.Filled.PushPin else Icons.Outlined.PushPin,
                        contentDescription = if (isPinned) "Unpin machine" else "Pin machine",
                        tint = if (isPinned) scheme.primary else scheme.onSurfaceVariant,
                    )
                }
            }

            Row(
                modifier = Modifier.fillMaxWidth(),
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.spacedBy(6.dp),
            ) {
                Icon(
                    statusIconFor(status),
                    contentDescription = null,
                    tint = statusColor,
                    modifier = Modifier.size(18.dp),
                )
                FittingBadgeText(
                    text = status.displayTitle,
                    style = MaterialTheme.typography.labelLarge,
                    fontWeight = FontWeight.SemiBold,
                    color = statusColor,
                    modifier = Modifier.weight(1f, fill = false),
                )
                Spacer(Modifier.weight(1f))
                StatusChip(
                    machineScopeLabel(profile),
                    modifier = Modifier.weight(1f, fill = false),
                )
                StatusChip(
                    typeChipLabel(profile),
                    modifier = Modifier.weight(1f, fill = false),
                )
                if (isActive) {
                    StatusChip("ACTIVE", modifier = Modifier.weight(1f, fill = false))
                }
            }

            Text(
                summary,
                style = MaterialTheme.typography.bodySmall,
                color = scheme.onSurfaceVariant,
                maxLines = 3,
                overflow = TextOverflow.Ellipsis
            )

            MachineActionButtonRow {
                if (isRunning) {
                    CompactTonalButton(
                        onClick = onFocus,
                        modifier = Modifier.testTag(WawonaTestTags.MACHINES_FOCUS),
                    ) {
                        MachineActionContent(
                            icon = { Icon(Icons.Outlined.CenterFocusStrong, contentDescription = null, modifier = Modifier.size(machineActionIconSize())) },
                            title = "Focus",
                        )
                    }
                    CompactFilledButton(
                        onClick = onStop,
                        modifier = Modifier.testTag(WawonaTestTags.MACHINES_STOP),
                        colors = ButtonDefaults.buttonColors(
                            containerColor = scheme.error,
                            contentColor = scheme.onError,
                        ),
                    ) {
                        MachineActionContent(
                            icon = { Icon(Icons.Filled.Stop, contentDescription = null, modifier = Modifier.size(machineActionIconSize())) },
                            title = "Stop",
                        )
                    }
                } else {
                    CompactFilledButton(
                        onClick = onConnect,
                        modifier = Modifier.testTag(WawonaTestTags.MACHINES_START),
                        enabled = capabilities.launchSupported && status != MachineStatus.CONNECTING,
                        colors = ButtonDefaults.buttonColors(
                            containerColor = scheme.primary,
                            contentColor = scheme.onPrimary,
                        ),
                    ) {
                        MachineActionContent(
                            icon = { Icon(Icons.Filled.PlayArrow, contentDescription = null, modifier = Modifier.size(machineActionIconSize())) },
                            title = if (status == MachineStatus.CONNECTING) "Starting…" else "Start",
                        )
                    }
                }
                CompactTonalButton(
                    onClick = onEdit,
                    modifier = Modifier.testTag(WawonaTestTags.MACHINES_EDIT),
                ) {
                    MachineActionContent(
                        icon = { Icon(Icons.Filled.Edit, contentDescription = null, modifier = Modifier.size(machineActionIconSize())) },
                        title = "Edit",
                    )
                }
                CompactOutlinedButton(
                    onClick = onDelete,
                    enabled = !isRunning,
                    modifier = Modifier.testTag(WawonaTestTags.MACHINES_DELETE),
                    contentColor = scheme.error,
                    borderColor = scheme.error.copy(alpha = 0.5f),
                ) {
                    MachineActionContent(
                        icon = { Icon(Icons.Filled.Delete, contentDescription = null, modifier = Modifier.size(machineActionIconSize())) },
                        title = "Delete",
                    )
                }
            }
        }
    }
}

private fun machineSubtitle(profile: MachineProfile): String = MachineSearch.subtitle(profile)

private fun configurationSummary(profile: MachineProfile): String = MachineSearch.summary(profile)

@Composable
private fun machineActionIconSize() =
    if (LocalConfiguration.current.screenWidthDp < 360) 14.dp else 16.dp

@Composable
private fun machineActionPadding(): PaddingValues {
    val narrow = LocalConfiguration.current.screenWidthDp < 360
    return if (narrow) PaddingValues(horizontal = 6.dp, vertical = 4.dp) else compactButtonPadding
}

@OptIn(ExperimentalLayoutApi::class)
@Composable
private fun MachineActionButtonRow(content: @Composable () -> Unit) {
    FlowRow(
        modifier = Modifier.fillMaxWidth(),
        horizontalArrangement = Arrangement.spacedBy(8.dp),
        verticalArrangement = Arrangement.spacedBy(8.dp),
    ) {
        content()
    }
}

@Composable
private fun MachineActionContent(
    icon: @Composable () -> Unit,
    title: String,
) {
    icon()
    Spacer(Modifier.size(4.dp))
    Text(
        title,
        maxLines = 1,
        softWrap = false,
        overflow = TextOverflow.Clip,
    )
}

@Composable
private fun CompactOutlinedButton(
    onClick: () -> Unit,
    modifier: Modifier = Modifier,
    enabled: Boolean = true,
    contentColor: Color = MaterialTheme.colorScheme.onSurface,
    borderColor: Color = MaterialTheme.colorScheme.outline,
    content: @Composable RowScope.() -> Unit,
) {
    OutlinedButton(
        onClick = onClick,
        modifier = modifier.defaultMinSize(minWidth = 0.dp, minHeight = 40.dp),
        enabled = enabled,
        shape = MaterialTheme.shapes.medium,
        contentPadding = machineActionPadding(),
        border = BorderStroke(1.dp, borderColor),
        colors = ButtonDefaults.outlinedButtonColors(
            contentColor = contentColor,
        ),
        content = content,
    )
}

@Composable
private fun CompactFilledButton(
    onClick: () -> Unit,
    modifier: Modifier = Modifier,
    enabled: Boolean = true,
    colors: androidx.compose.material3.ButtonColors = ButtonDefaults.buttonColors(),
    content: @Composable RowScope.() -> Unit,
) {
    Button(
        onClick = onClick,
        modifier = modifier.defaultMinSize(minWidth = 0.dp, minHeight = 40.dp),
        enabled = enabled,
        shape = MaterialTheme.shapes.medium,
        contentPadding = machineActionPadding(),
        colors = colors,
        content = content,
    )
}

@Composable
private fun CompactTonalButton(
    onClick: () -> Unit,
    modifier: Modifier = Modifier,
    enabled: Boolean = true,
    content: @Composable RowScope.() -> Unit,
) {
    FilledTonalButton(
        onClick = onClick,
        modifier = modifier.defaultMinSize(minWidth = 0.dp, minHeight = 40.dp),
        enabled = enabled,
        shape = MaterialTheme.shapes.medium,
        contentPadding = machineActionPadding(),
        content = content,
    )
}

@Composable
private fun statusIconFor(status: MachineStatus) = when (status) {
    MachineStatus.CONNECTED -> Icons.Filled.CheckCircle
    MachineStatus.CONNECTING -> Icons.Filled.Sync
    MachineStatus.DEGRADED -> Icons.Filled.Warning
    MachineStatus.ERROR -> Icons.Filled.Error
    MachineStatus.DISCONNECTED -> Icons.Filled.PauseCircle
}

@Composable
private fun MachineCardBanner(
    profileName: String,
    subtitle: String,
    statusColor: Color,
    thumbnailBitmap: android.graphics.Bitmap?,
    searchQuery: String = "",
) {
    val shape = MaterialTheme.shapes.large
    val scheme = MaterialTheme.colorScheme
    val scrimTop = scheme.scrim.copy(alpha = 0.12f)
    val scrimBottom = scheme.scrim.copy(alpha = 0.48f)
    val onMedia = scheme.inverseOnSurface
    Box(
        modifier = Modifier
            .fillMaxWidth()
            .height(96.dp)
            .clip(shape)
    ) {
        if (thumbnailBitmap != null) {
            Image(
                bitmap = thumbnailBitmap.asImageBitmap(),
                contentDescription = null,
                contentScale = ContentScale.Crop,
                modifier = Modifier.fillMaxSize()
            )
        } else {
            Box(
                modifier = Modifier
                    .fillMaxSize()
                    .background(
                        Brush.linearGradient(
                            colors = listOf(
                                statusColor.copy(alpha = 0.42f),
                                scheme.primary.copy(alpha = 0.28f),
                                scheme.tertiary.copy(alpha = 0.22f),
                            )
                        )
                    )
            )
        }
        Box(
            modifier = Modifier
                .fillMaxSize()
                .background(
                    Brush.verticalGradient(
                        colors = listOf(scrimTop, scrimBottom)
                    )
                )
        )
        Row(
            modifier = Modifier
                .fillMaxSize()
                .padding(horizontal = 14.dp),
            verticalAlignment = Alignment.CenterVertically
        ) {
            Column(Modifier.weight(1f)) {
                val displayName = profileName.ifBlank { "Unnamed Machine" }
                val highlighted = remember(displayName, searchQuery) {
                    buildAnnotatedString {
                        highlightSearchSpans(displayName, searchQuery).forEach { (text, isMatch) ->
                            if (isMatch) {
                                withStyle(
                                    SpanStyle(
                                        background = Color.Yellow.copy(alpha = 0.65f),
                                        color = Color.Black,
                                    ),
                                ) { append(text) }
                            } else {
                                append(text)
                            }
                        }
                    }
                }
                Text(
                    highlighted,
                    style = MaterialTheme.typography.titleMedium,
                    fontWeight = FontWeight.Bold,
                    color = onMedia,
                    maxLines = 1,
                    overflow = TextOverflow.Ellipsis
                )
                Text(
                    subtitle,
                    style = MaterialTheme.typography.bodySmall,
                    color = onMedia.copy(alpha = 0.86f),
                    maxLines = 1,
                    overflow = TextOverflow.Ellipsis
                )
            }
            Surface(
                shape = MaterialTheme.shapes.medium,
                color = scheme.surface.copy(alpha = 0.55f),
                contentColor = statusColor,
            ) {
                Icon(
                    Icons.Filled.Computer,
                    contentDescription = null,
                    modifier = Modifier
                        .padding(10.dp)
                        .size(20.dp),
                )
            }
        }
    }
}

@Composable
private fun FittingBadgeText(
    text: String,
    modifier: Modifier = Modifier,
    style: TextStyle = MaterialTheme.typography.labelSmall,
    fontWeight: FontWeight? = FontWeight.Bold,
    color: Color = Color.Unspecified,
) {
    val resolved = style.copy(
        fontWeight = fontWeight ?: style.fontWeight,
        color = if (color == Color.Unspecified) style.color else color,
    )
    val maxSp = resolved.fontSize.takeIf { it.isSp } ?: 12.sp
    BasicText(
        text = text,
        modifier = modifier.widthIn(min = 0.dp),
        style = resolved,
        maxLines = 1,
        overflow = TextOverflow.Clip,
        autoSize = TextAutoSize.StepBased(
            minFontSize = 7.sp,
            maxFontSize = maxSp,
            stepSize = 0.5.sp,
        ),
    )
}

@Composable
private fun StatusChip(text: String, modifier: Modifier = Modifier) {
    FittingBadgeText(
        text = text,
        style = MaterialTheme.typography.labelSmall,
        fontWeight = FontWeight.Bold,
        color = MaterialTheme.colorScheme.onSecondaryContainer,
        modifier = modifier
            .background(
                MaterialTheme.colorScheme.secondaryContainer,
                MaterialTheme.shapes.small,
            )
            .padding(horizontal = 8.dp, vertical = 5.dp),
    )
}

@Composable
private fun statusColorFor(status: MachineStatus): Color {
    val scheme = MaterialTheme.colorScheme
    return when (status) {
        MachineStatus.CONNECTED -> scheme.tertiary
        MachineStatus.CONNECTING -> scheme.primary
        MachineStatus.DEGRADED -> scheme.secondary
        MachineStatus.ERROR -> scheme.error
        MachineStatus.DISCONNECTED -> scheme.onSurfaceVariant
    }
}

private fun machineScopeLabel(profile: MachineProfile): String =
    when (profile.type.selectablePivot()) {
        MachineType.NATIVE -> if (NativeShellSession.from(profile).second) "REMOTE" else "LOCAL"
        else -> "LOCAL"
    }

private fun typeChipLabel(profile: MachineProfile): String =
    when (profile.type.selectablePivot()) {
        MachineType.NATIVE -> {
            val (kind, useSsh) = NativeShellSession.from(profile)
            val base = "NATIVE SHELL " + kind.label.uppercase()
            if (useSsh) "$base + SSH" else base
        }
        MachineType.VM -> "VM"
        MachineType.CONTAINER -> "CONTAINER"
        else -> "NATIVE SHELL"
}

@OptIn(ExperimentalMaterial3Api::class, ExperimentalLayoutApi::class)
@Composable
private fun MachineEditorSheet(
    title: String,
    initial: MachineProfile?,
    onDismiss: () -> Unit,
    onSave: (MachineProfile) -> Unit,
    onOpenSettings: () -> Unit
) {
    val context = LocalContext.current
    val prefs = remember { context.getSharedPreferences("wawona_prefs", Context.MODE_PRIVATE) }
    var showClientPicker by remember { mutableStateOf(false) }

    var name by remember { mutableStateOf(initial?.name ?: "") }
    val initialSession = remember(initial) {
        initial?.let { NativeShellSession.from(it) } ?: (NativeShellKind.TERMINAL to false)
    }
    var uiType by remember {
        mutableStateOf(initial?.type?.selectablePivot() ?: MachineType.NATIVE)
    }
    var shellKind by remember { mutableStateOf(initialSession.first) }
    var useSsh by remember { mutableStateOf(initialSession.second) }
    var sshHost by remember { mutableStateOf(initial?.sshHost ?: "") }
    var sshPort by remember { mutableStateOf((initial?.sshPort ?: 22).toString()) }
    var sshUser by remember { mutableStateOf(initial?.sshUser ?: "") }
    var sshPassword by remember { mutableStateOf(initial?.sshPassword ?: "") }
    var sshKeyPath by remember { mutableStateOf(initial?.sshKeyPath ?: "") }
    var sshKeyPassphrase by remember { mutableStateOf(initial?.sshKeyPassphrase ?: "") }
    var sshAuthMethod by remember { mutableStateOf(initial?.sshAuthMethod ?: "password") }
    var nativeLauncher by remember { mutableStateOf(initial?.nativeLauncher ?: "weston-terminal") }
    var wasmModulePath by remember {
        mutableStateOf(initial?.runtimeOverrides?.optString("wasmModulePath", "") ?: "")
    }
    var wasmCommand by remember {
        mutableStateOf(initial?.runtimeOverrides?.optString("wasmCommand", "wasm hello-wasi-gui") ?: "wasm hello-wasi-gui")
    }
    var wasmPackage by remember {
        mutableStateOf(initial?.runtimeOverrides?.optString("wasmPackage", "") ?: "")
    }
    var wasmLaunchMode by remember {
        mutableStateOf(initial?.runtimeOverrides?.optString("wasmLaunchMode", "command") ?: "command")
    }
    var wasmCatalogResults by remember { mutableStateOf<List<WasmCatalogPackage>>(emptyList()) }
    var wasmCatalogNote by remember { mutableStateOf<String?>(null) }
    var wasmCatalogLoading by remember { mutableStateOf(false) }
    val editorScope = rememberCoroutineScope()
    var localWasmFiles by remember { mutableStateOf(WasmCatalog.listLocalModules(context)) }
    val wasmFilePicker = rememberLauncherForActivityResult(
        contract = ActivityResultContracts.OpenDocument()
    ) { uri: Uri? ->
        if (uri == null) return@rememberLauncherForActivityResult
        editorScope.launch {
            val result = withContext(Dispatchers.IO) {
                runCatching { WasmCatalog.importUri(context, uri) }
            }
            result.onSuccess {
                wasmModulePath = it.absolutePath
                wasmCommand = "wasm ${it.absolutePath}"
                wasmLaunchMode = "file"
                localWasmFiles = WasmCatalog.listLocalModules(context)
                wasmCatalogNote = "Copied ${it.name} to the Wawona folder."
            }.onFailure {
                wasmCatalogNote = it.message
            }
        }
    }
    var remoteCommand by remember { mutableStateOf(initial?.remoteCommand ?: "") }
    var vmIdentifier by remember { mutableStateOf(initial?.vmSettings?.vmIdentifier ?: "") }
    var vmVsockPort by remember { mutableStateOf(initial?.vmSettings?.vsockPort ?: "") }
    var vmNotes by remember { mutableStateOf(initial?.vmSettings?.notes ?: "") }
    var containerRef by remember { mutableStateOf(initial?.containerSettings?.containerRef ?: "") }
    var containerRuntime by remember { mutableStateOf(initial?.containerSettings?.runtime ?: "docker") }
    var containerEntry by remember { mutableStateOf(initial?.containerSettings?.entryCommand ?: "") }
    var containerNotes by remember { mutableStateOf(initial?.containerSettings?.notes ?: "") }
    var machineTypePickerExpanded by remember { mutableStateOf(false) }
    var authMethodExpanded by remember { mutableStateOf(false) }
    var touchInputExpanded by remember { mutableStateOf(false) }
    var vulkanExpanded by remember { mutableStateOf(false) }
    var openglExpanded by remember { mutableStateOf(false) }
    var compositorBackendExpanded by remember { mutableStateOf(false) }

    val existingOverrides = remember(initial) {
        if (initial != null) SettingsOverrides.merge(initial) else JSONObject()
    }
    var machineThumbnailEnabled by remember {
        mutableStateOf(readBoolOverride(existingOverrides, "machineThumbnailEnabledOverride", true))
    }
    var forceSsd by remember {
        mutableStateOf(readBoolOverride(existingOverrides, "forceServerSideDecorations", prefs.getBoolean("forceServerSideDecorations", false)))
    }
    var autoScale by remember {
        mutableStateOf(readBoolOverride(existingOverrides, "autoScale", prefs.getBoolean("autoRetinaScaling", true)))
    }
    var respectSafeArea by remember {
        mutableStateOf(
            SettingsOverrides.readBool(
                existingOverrides,
                "respectSafeArea",
                prefs.getBoolean("respectSafeArea", true)
            )
        )
    }
    var showVirtualPointer by remember {
        mutableStateOf(
            SettingsOverrides.readBool(
                existingOverrides,
                "renderMacOSPointer",
                prefs.getBoolean("renderMacOSPointer", false)
            )
        )
    }
    var nestedCompositorCursor by remember {
        mutableStateOf(
            SettingsOverrides.readString(
                existingOverrides,
                "nestedCompositorCursor",
                prefs.getString("nestedCompositorCursor", "virtual") ?: "virtual"
            ).let { if (it == "host") "host" else "virtual" }
        )
    }
    var nestedCursorExpanded by remember { mutableStateOf(false) }
    var touchInputType by remember {
        mutableStateOf(
            SettingsOverrides.readString(
                existingOverrides,
                "touchInputType",
                if (prefs.getBoolean("touchpadMode", false)) "Touchpad" else "Multi-Touch"
            )
        )
    }
    var swapCmdAlt by remember {
        mutableStateOf(readBoolOverride(existingOverrides, "swapCmdWithAlt", prefs.getBoolean("swapCmdAsCtrl", false)))
    }
    var universalClipboard by remember {
        mutableStateOf(readBoolOverride(existingOverrides, "universalClipboard", prefs.getBoolean("universalClipboard", false)))
    }
    var vulkanDriver by remember {
        mutableStateOf(
            readStringOverride(
                existingOverrides,
                "vulkanDriver",
                prefs.getString("vulkanDriver", "system") ?: "system"
            ).lowercase().takeIf { it in setOf("none", "swiftshader", "system") }
                ?: "system"
        )
    }
    var openglDriver by remember {
        mutableStateOf(readStringOverride(existingOverrides, "openglDriver", prefs.getString("openglDriver", "angle") ?: "angle"))
    }
    var compositorBackend by remember {
        mutableStateOf(
            SettingsOverrides.readString(
                existingOverrides,
                "compositorBackend",
                prefs.getString("compositorBackend", "auto") ?: "auto"
            ).lowercase().takeIf { it in setOf("auto", "wayland", "drm") }
                ?: "auto"
        )
    }
    var dmabufEnabled by remember {
        mutableStateOf(readBoolOverride(existingOverrides, "dmabufEnabled", prefs.getBoolean("nestedCompositorsSupport", true)))
    }
    var colorOperations by remember {
        mutableStateOf(readBoolOverride(existingOverrides, "colorOperations", prefs.getBoolean("colorSyncSupport", false)))
    }
    var shakeToCloseOverride by remember {
        mutableStateOf(
            SettingsOverrides.readBool(
                existingOverrides,
                "shakeToCloseEnabled",
                prefs.getBoolean("wawona.pref.shakeToCloseEnabled", true)
            )
        )
    }
    var swipeBackOverride by remember {
        mutableStateOf(
            SettingsOverrides.readBool(
                existingOverrides,
                "swipeBackToCloseEnabled",
                prefs.getBoolean("wawona.pref.swipeBackToCloseEnabled", true)
            )
        )
    }
    var resizeDisplayForVirtualKeyboardOverride by remember {
        mutableStateOf(
            SettingsOverrides.readBool(
                existingOverrides,
                "resizeDisplayForVirtualKeyboard",
                prefs.getBoolean("resizeDisplayForVirtualKeyboard", true)
            )
        )
    }
    var machineEnvironment by remember {
        mutableStateOf(
            if (initial != null) EnvironmentOverrides.loadMachine(initial) else mutableMapOf()
        )
    }
    var showMachineEnvEditor by remember { mutableStateOf(false) }
    var machineEnvEditName by remember { mutableStateOf("") }
    var machineEnvEditValue by remember { mutableStateOf("") }
    var machineEnvIsNew by remember { mutableStateOf(false) }

    fun performSave() {
        val trimmedName = name.trim().ifEmpty { "Unnamed Machine" }
        val sanitizedHostPort = MachineInputSanitizer.splitHostAndPort(
            sshHost,
            sshPort.ifBlank { null },
            initial?.sshPort ?: 22
        )
        val storageType = if (uiType == MachineType.NATIVE) {
            NativeShellSession.storageType(shellKind, useSsh)
        } else {
            uiType
        }
        val base = initial ?: MachineProfile(name = trimmedName, type = storageType)
        val settingsOverrides = JSONObject(base.settingsOverrides.toString())
        writeBoolOverride(settingsOverrides, "machineThumbnailEnabledOverride", machineThumbnailEnabled, true)
        writeBoolOverride(settingsOverrides, "forceServerSideDecorations", forceSsd, prefs.getBoolean("forceServerSideDecorations", false))
        writeBoolOverride(settingsOverrides, "autoScale", autoScale, prefs.getBoolean("autoRetinaScaling", true))
        writeBoolOverride(settingsOverrides, "respectSafeArea", respectSafeArea, prefs.getBoolean("respectSafeArea", true))
        writeBoolOverride(
            settingsOverrides,
            "renderMacOSPointer",
            showVirtualPointer,
            prefs.getBoolean("renderMacOSPointer", false)
        )
        writeStringOverride(
            settingsOverrides,
            "nestedCompositorCursor",
            nestedCompositorCursor,
            prefs.getString("nestedCompositorCursor", "virtual") ?: "virtual"
        )
        writeStringOverride(
            settingsOverrides,
            "touchInputType",
            touchInputType,
            if (prefs.getBoolean("touchpadMode", false)) "Touchpad" else "Multi-Touch"
        )
        writeBoolOverride(settingsOverrides, "swapCmdWithAlt", swapCmdAlt, prefs.getBoolean("swapCmdAsCtrl", false))
        writeBoolOverride(settingsOverrides, "universalClipboard", universalClipboard, prefs.getBoolean("universalClipboard", false))
        writeStringOverride(settingsOverrides, "vulkanDriver", vulkanDriver, prefs.getString("vulkanDriver", "system") ?: "system")
        writeStringOverride(settingsOverrides, "openglDriver", openglDriver, prefs.getString("openglDriver", "angle") ?: "angle")
        writeStringOverride(
            settingsOverrides,
            "compositorBackend",
            compositorBackend,
            prefs.getString("compositorBackend", "auto") ?: "auto"
        )
        writeBoolOverride(settingsOverrides, "dmabufEnabled", dmabufEnabled, prefs.getBoolean("nestedCompositorsSupport", true))
        writeBoolOverride(settingsOverrides, "colorOperations", colorOperations, prefs.getBoolean("colorSyncSupport", false))
        writeBoolOverride(settingsOverrides, "shakeToCloseEnabled", shakeToCloseOverride, prefs.getBoolean("wawona.pref.shakeToCloseEnabled", true))
        writeBoolOverride(settingsOverrides, "swipeBackToCloseEnabled", swipeBackOverride, prefs.getBoolean("wawona.pref.swipeBackToCloseEnabled", true))
        writeBoolOverride(
            settingsOverrides,
            "resizeDisplayForVirtualKeyboard",
            resizeDisplayForVirtualKeyboardOverride,
            prefs.getBoolean("resizeDisplayForVirtualKeyboard", true)
        )
        val withEnv = EnvironmentOverrides.withMachineEnv(base, machineEnvironment)
        val runtimeOverrides = JSONObject(withEnv.runtimeOverrides.toString())
        val trimmedWasm = wasmModulePath.trim()
        val nativeSession = uiType == MachineType.NATIVE
        if (nativeSession && shellKind == NativeShellKind.WASM) {
            runtimeOverrides.put("bundledAppID", "wawona-wasm")
            val cmd = wasmCommand.trim().ifEmpty { WasmCatalog.DEFAULT_COMMAND }
            runtimeOverrides.put("wasmCommand", cmd)
            runtimeOverrides.put("wasmLaunchMode", wasmLaunchMode.ifBlank { "command" })
            val pkg = wasmPackage.trim()
            if (pkg.isNotEmpty()) runtimeOverrides.put("wasmPackage", pkg) else runtimeOverrides.remove("wasmPackage")
            if (trimmedWasm.isNotEmpty()) runtimeOverrides.put("wasmModulePath", trimmedWasm)
            else runtimeOverrides.remove("wasmModulePath")
        } else {
            runtimeOverrides.remove("wasmModulePath")
            if (nativeSession) {
                NativeShellSession.resolvedBundledAppId(shellKind, nativeLauncher)?.let {
                    runtimeOverrides.put("bundledAppID", it)
                }
                runtimeOverrides.put("waypipeEnabled", shellKind == NativeShellKind.WAYPIPE)
            }
        }
        val resolvedLauncher = when {
            !nativeSession -> nativeLauncher
            else -> NativeShellSession.resolvedBundledAppId(shellKind, nativeLauncher) ?: nativeLauncher
        }
        onSave(
            base.copy(
                name = trimmedName,
                type = storageType,
                sshHost = sanitizedHostPort.host,
                sshPort = sanitizedHostPort.port,
                sshUser = sshUser.trim(),
                sshPassword = sshPassword,
                sshAuthMethod = sshAuthMethod.trim().ifEmpty { "password" },
                sshKeyPath = sshKeyPath.trim(),
                sshKeyPassphrase = sshKeyPassphrase,
                nativeLauncher = resolvedLauncher,
                remoteCommand = remoteCommand.trim(),
                settingsOverrides = settingsOverrides,
                runtimeOverrides = runtimeOverrides,
                vmSettings = base.vmSettings.copy(
                    vmIdentifier = vmIdentifier.trim(),
                    vsockPort = vmVsockPort.trim(),
                    notes = vmNotes.trim()
                ),
                containerSettings = base.containerSettings.copy(
                    runtime = containerRuntime.trim().ifEmpty { "docker" },
                    containerRef = containerRef.trim(),
                    entryCommand = containerEntry.trim(),
                    notes = containerNotes.trim()
                )
            )
        )
    }

    WawonaModalSheet(
        onDismiss = onDismiss,
        title = if (showClientPicker) "Wayland Client" else title,
        defaultDetent = WawonaSheetDetent.Medium,
        scrollBehavior = WawonaSheetScrollBehavior.ContentFirst,
        navigationIcon = {
            if (showClientPicker) {
                IconButton(onClick = { showClientPicker = false }) {
                    Icon(Icons.AutoMirrored.Filled.ArrowBack, contentDescription = "Back")
                }
            } else {
                TextButton(onClick = onDismiss) { Text("Cancel") }
            }
        },
        actions = {
            if (!showClientPicker) {
                TextButton(onClick = { performSave() }) {
                    Text("Save", fontWeight = FontWeight.SemiBold)
                }
            }
        },
    ) { contentScrollState ->
        LaunchedEffect(showClientPicker) { contentScrollState.scrollTo(0) }
        val motion = MaterialTheme.motionScheme
        AnimatedContent(
            targetState = showClientPicker,
            modifier = Modifier.testTag(WawonaTestTags.MACHINES_EDITOR),
            transitionSpec = {
                val slideSpec = motion.defaultSpatialSpec<androidx.compose.ui.unit.IntOffset>()
                val fadeSpec = motion.defaultEffectsSpec<Float>()
                val transform = if (targetState) {
                    (slideInHorizontally(slideSpec) { it } + fadeIn(fadeSpec)).togetherWith(
                        slideOutHorizontally(slideSpec) { -it / 4 } + fadeOut(fadeSpec),
                    )
                } else {
                    (slideInHorizontally(slideSpec) { -it } + fadeIn(fadeSpec)).togetherWith(
                        slideOutHorizontally(slideSpec) { it / 4 } + fadeOut(fadeSpec),
                    )
                }
                transform.using(SizeTransform(clip = false))
            },
            label = "machineEditorClientPicker",
        ) { pickingClient ->
            if (pickingClient) {
                BundledClientPicker(
                    selectedId = nativeLauncher,
                    scrollState = contentScrollState,
                    onSelect = { id ->
                        nativeLauncher = id
                        showClientPicker = false
                    },
                )
            } else {
                Column(
                    modifier = Modifier
                        .fillMaxWidth()
                        .verticalScroll(contentScrollState)
                        .padding(horizontal = 16.dp)
                        .padding(bottom = 24.dp),
                    verticalArrangement = Arrangement.spacedBy(16.dp),
                ) {
                    EditorSectionCard(
                        title = "Connection Profile",
                        subtitle = "Name and type for this machine profile."
                    ) {
                        OutlinedTextField(
                            value = name,
                            onValueChange = { name = it },
                            label = { Text("Display Name") },
                            placeholder = { Text("e.g. Studio Linux VM") },
                            singleLine = true,
                            modifier = Modifier.fillMaxWidth()
                        )
                        MachineTypeDropdown(
                            selected = uiType,
                            expanded = machineTypePickerExpanded,
                            onExpandedChange = { machineTypePickerExpanded = it },
                            onSelect = {
                                uiType = it
                                machineTypePickerExpanded = false
                            }
                        )
                        HorizontalDivider()
                        ToggleRow("Show Session Thumbnail On Card", machineThumbnailEnabled) {
                            machineThumbnailEnabled = it
                        }
                    }

                    if (uiType == MachineType.NATIVE) {
                        EditorSectionCard(
                            title = "Native Shell Session",
                            subtitle = "Terminal, Wayland client, Wasm, or Waypipe. SSH is an option for Terminal and Waypipe."
                        ) {
                            FlowRow(
                                horizontalArrangement = Arrangement.spacedBy(8.dp),
                                verticalArrangement = Arrangement.spacedBy(8.dp),
                            ) {
                                NativeShellKind.entries.forEach { kind ->
                                    FilterChip(
                                        selected = shellKind == kind,
                                        onClick = {
                                            shellKind = kind
                                            if (kind == NativeShellKind.WAYLAND &&
                                                (nativeLauncher == "wawona-wasm" || nativeLauncher == "wawona-shell")
                                            ) {
                                                nativeLauncher = "weston-simple-shm"
                                            }
                                            if (kind == NativeShellKind.WASM || kind == NativeShellKind.WAYLAND) {
                                                useSsh = false
                                            }
                                        },
                                        label = { Text(kind.label) },
                                    )
                                }
                            }
                            if (shellKind == NativeShellKind.TERMINAL || shellKind == NativeShellKind.WAYPIPE) {
                                ToggleRow("Use SSH", useSsh) { useSsh = it }
                            }
                        }
                    }

                    if (uiType == MachineType.NATIVE && shellKind == NativeShellKind.WASM) {
                        EditorSectionCard(
                            title = "Wasm",
                            subtitle = "Same as native shell: wasm hello-wasi-gui. Pick a local file, search repo.wawona.io /wasm/v1, or type the command. Native still runs wasm from the shell."
                        ) {
                            OutlinedTextField(
                                value = wasmCommand,
                                onValueChange = {
                                    wasmCommand = it
                                    wasmLaunchMode = "command"
                                },
                                label = { Text("Command") },
                                placeholder = { Text("wasm hello-wasi-gui") },
                                singleLine = true,
                                modifier = Modifier.fillMaxWidth()
                            )
                            OutlinedTextField(
                                value = wasmPackage,
                                onValueChange = {
                                    wasmPackage = it
                                    wasmLaunchMode = "repo"
                                },
                                label = { Text("Package") },
                                placeholder = { Text("hello-wasi-gui") },
                                singleLine = true,
                                modifier = Modifier.fillMaxWidth()
                            )
                            Row(
                                modifier = Modifier.fillMaxWidth(),
                                horizontalArrangement = Arrangement.spacedBy(8.dp)
                            ) {
                                OutlinedButton(
                                    onClick = {
                                        wasmCatalogLoading = true
                                        wasmCatalogNote = null
                                        editorScope.launch {
                                            val result = withContext(Dispatchers.IO) {
                                                runCatching { WasmCatalog.search(wasmPackage) }
                                            }
                                            wasmCatalogLoading = false
                                            result.onSuccess { wasmCatalogResults = it }
                                                .onFailure { wasmCatalogNote = it.message }
                                        }
                                    },
                                    enabled = !wasmCatalogLoading
                                ) {
                                    Text(if (wasmCatalogLoading) "Searching…" else "Search catalog")
                                }
                            }
                            if (wasmCatalogResults.isNotEmpty()) {
                                wasmCatalogResults.forEach { pkg ->
                                    Text(
                                        text = "${pkg.name}  ${pkg.version}  ${pkg.summary}",
                                        modifier = Modifier
                                            .fillMaxWidth()
                                            .clickable {
                                                wasmPackage = pkg.name
                                                wasmCommand = "wasm ${pkg.name}"
                                                wasmLaunchMode = "repo"
                                                wasmCatalogLoading = true
                                                editorScope.launch {
                                                    val result = withContext(Dispatchers.IO) {
                                                        runCatching { WasmCatalog.download(context, pkg) }
                                                    }
                                                    wasmCatalogLoading = false
                                                    result.onSuccess {
                                                        wasmModulePath = it.absolutePath
                                                        wasmCatalogNote = "Saved ${pkg.name} to the Wawona folder."
                                                    }.onFailure {
                                                        wasmCatalogNote = it.message
                                                    }
                                                }
                                            }
                                            .padding(vertical = 6.dp),
                                        style = MaterialTheme.typography.bodyMedium
                                    )
                                }
                            }
                            OutlinedTextField(
                                value = wasmModulePath,
                                onValueChange = {
                                    wasmModulePath = it
                                    wasmLaunchMode = "file"
                                },
                                label = { Text("Local .wasm") },
                                placeholder = { Text("/sdcard/…/hello-wasi-gui.wasm") },
                                singleLine = true,
                                modifier = Modifier.fillMaxWidth()
                            )
                            OutlinedButton(
                                onClick = { wasmFilePicker.launch(arrayOf("application/wasm", "*/*")) },
                                modifier = Modifier.fillMaxWidth()
                            ) {
                                Text("Choose file…")
                            }
                            if (localWasmFiles.isNotEmpty()) {
                                Text("Wawona folder", style = MaterialTheme.typography.labelMedium)
                                localWasmFiles.forEach { file ->
                                    Text(
                                        text = file.name,
                                        modifier = Modifier
                                            .fillMaxWidth()
                                            .clickable {
                                                wasmModulePath = file.absolutePath
                                                wasmCommand = "wasm ${file.absolutePath}"
                                                wasmLaunchMode = "file"
                                            }
                                            .padding(vertical = 4.dp),
                                        style = MaterialTheme.typography.bodyMedium
                                    )
                                }
                            }
                            wasmCatalogNote?.let { Text(it, style = MaterialTheme.typography.bodySmall) }
                        }
                    }

                    if (uiType == MachineType.NATIVE && shellKind == NativeShellKind.WAYLAND) {
                        EditorSectionCard(
                            title = "Wayland Client",
                            subtitle = "Choose a bundled client on the local compositor socket. Custom commands belong under the Terminal session."
                        ) {
                            Row(
                                modifier = Modifier
                                    .fillMaxWidth()
                                    .clickable { showClientPicker = true }
                                    .padding(vertical = 8.dp),
                                horizontalArrangement = Arrangement.SpaceBetween,
                                verticalAlignment = Alignment.CenterVertically
                            ) {
                                Text("Bundled Client")
                                Text(
                                    if (nativeLauncher == "wawona-wasm" && wasmModulePath.isNotBlank()) {
                                        wasmModulePath.substringAfterLast('/')
                                    } else {
                                        BundledClients.labelFor(nativeLauncher)
                                    },
                                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                                    maxLines = 1,
                                    overflow = TextOverflow.Ellipsis
                                )
                            }
                            if (nativeLauncher == "wawona-wasm") {
                                OutlinedTextField(
                                    value = wasmModulePath,
                                    onValueChange = { wasmModulePath = it },
                                    label = { Text("Wasm module path") },
                                    placeholder = { Text("/sdcard/…/wayland-shm-rust.wasm") },
                                    singleLine = true,
                                    modifier = Modifier.fillMaxWidth()
                                )
                                Text(
                                    "Empty path runs bundled hello-wasi-gui (wl_shm).",
                                    style = MaterialTheme.typography.bodySmall,
                                    color = MaterialTheme.colorScheme.onSurfaceVariant
                                )
                            }
                        }
                    }

                    if (uiType == MachineType.NATIVE && useSsh &&
                        (shellKind == NativeShellKind.TERMINAL || shellKind == NativeShellKind.WAYPIPE)
                    ) {
                        val isWaypipe = shellKind == NativeShellKind.WAYPIPE
                        EditorSectionCard(
                            title = if (isWaypipe) "SSH + Waypipe" else "SSH Connection",
                            subtitle = if (isWaypipe) {
                                "Connects to a remote host via SSH and proxies the Wayland protocol using waypipe."
                            } else {
                                "Connects to a remote host via SSH and opens a terminal session."
                            }
                        ) {
                            OutlinedTextField(value = sshHost, onValueChange = { sshHost = it }, label = { Text("Host") }, placeholder = { Text("host.example.com") }, singleLine = true, modifier = Modifier.fillMaxWidth())
                            OutlinedTextField(value = sshUser, onValueChange = { sshUser = it }, label = { Text("User") }, placeholder = { Text("username") }, singleLine = true, modifier = Modifier.fillMaxWidth())
                            OutlinedTextField(
                                value = sshPort,
                                onValueChange = { sshPort = it.filter { ch -> ch.isDigit() }.take(5) },
                                label = { Text("Port") },
                                placeholder = { Text("22") },
                                singleLine = true,
                                keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Number),
                                modifier = Modifier.fillMaxWidth()
                            )
                            OutlinedTextField(value = sshKeyPath, onValueChange = { sshKeyPath = it }, label = { Text("SSH Key Path") }, placeholder = { Text("~/.ssh/id_ed25519") }, singleLine = true, modifier = Modifier.fillMaxWidth())
                            AuthMethodDropdown(
                                selected = sshAuthMethod,
                                expanded = authMethodExpanded,
                                onExpandedChange = { authMethodExpanded = it },
                                onSelect = {
                                    sshAuthMethod = it
                                    authMethodExpanded = false
                                }
                            )
                            if (sshAuthMethod == "password") {
                                OutlinedTextField(
                                    value = sshPassword,
                                    onValueChange = { sshPassword = it },
                                    label = { Text("Password") },
                                    singleLine = true,
                                    visualTransformation = PasswordVisualTransformation(),
                                    keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Password),
                                    modifier = Modifier.fillMaxWidth()
                                )
                            } else {
                                OutlinedTextField(
                                    value = sshKeyPassphrase,
                                    onValueChange = { sshKeyPassphrase = it },
                                    label = { Text("Key Passphrase") },
                                    singleLine = true,
                                    visualTransformation = PasswordVisualTransformation(),
                                    keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Password),
                                    modifier = Modifier.fillMaxWidth()
                                )
                            }
                            OutlinedTextField(
                                value = remoteCommand,
                                onValueChange = { remoteCommand = it },
                                label = { Text(if (isWaypipe) "Remote Command" else "Remote Shell Command") },
                                placeholder = { Text(if (isWaypipe) "weston-simple-shm" else "bash -l") },
                                singleLine = true,
                                modifier = Modifier.fillMaxWidth()
                            )
                        }
                    }

                    EditorSectionCard(
                        title = "Display / Input / Graphics",
                        subtitle = "Per-machine overrides for global Display, Input, Graphics, and HDR settings."
                    ) {
                        TextButton(onClick = onOpenSettings) {
                            Text("Open Wawona Settings…")
                        }
                        ToggleRow("Force Server-Side Decorations", forceSsd) { forceSsd = it }
                        ToggleRow("Auto Scale", autoScale) { autoScale = it }
                        ToggleRow("Respect Safe Area", respectSafeArea) { respectSafeArea = it }
                        ToggleRow("Show Virtual Cursor", showVirtualPointer) { showVirtualPointer = it }
                        StringDropdownField(
                            label = "Nested Compositor Cursor",
                            selected = if (nestedCompositorCursor == "host") "Host Cursor" else "Virtual Pointer",
                            options = listOf("Virtual Pointer", "Host Cursor"),
                            expanded = nestedCursorExpanded && showVirtualPointer,
                            onExpandedChange = { if (showVirtualPointer) nestedCursorExpanded = it },
                            onSelect = {
                                nestedCompositorCursor = if (it == "Host Cursor") "host" else "virtual"
                                nestedCursorExpanded = false
                            },
                            enabled = showVirtualPointer,
                        )
                        StringDropdownField(
                            label = "Touch Input Type",
                            selected = touchInputType,
                            options = listOf("Multi-Touch", "Touchpad"),
                            expanded = touchInputExpanded,
                            onExpandedChange = { touchInputExpanded = it },
                            onSelect = {
                                touchInputType = it
                                touchInputExpanded = false
                            }
                        )
                        ToggleRow("Swap CMD with ALT", swapCmdAlt) { swapCmdAlt = it }
                        ToggleRow("Universal Clipboard", universalClipboard) { universalClipboard = it }
                        ToggleRow(
                            "Resize Display for Virtual Keyboard",
                            resizeDisplayForVirtualKeyboardOverride,
                        ) { resizeDisplayForVirtualKeyboardOverride = it }
                        StringDropdownField(
                            label = "Vulkan Driver",
                            selected = vulkanDriver,
                            options = listOf("none", "swiftshader", "system"),
                            expanded = vulkanExpanded,
                            onExpandedChange = { vulkanExpanded = it },
                            onSelect = {
                                vulkanDriver = it
                                vulkanExpanded = false
                            }
                        )
                        StringDropdownField(
                            label = "OpenGL Driver",
                            selected = openglDriver,
                            options = listOf("none", "angle", "system"),
                            expanded = openglExpanded,
                            onExpandedChange = { openglExpanded = it },
                            onSelect = {
                                openglDriver = it
                                openglExpanded = false
                            }
                        )
                        StringDropdownField(
                            label = "Display Backend",
                            selected = when (compositorBackend) {
                                "wayland" -> "Wayland (nested)"
                                "drm" -> "DRM/KMS (iLand)"
                                else -> "Auto"
                            },
                            options = listOf("Auto", "Wayland (nested)", "DRM/KMS (iLand)"),
                            expanded = compositorBackendExpanded,
                            onExpandedChange = { compositorBackendExpanded = it },
                            onSelect = {
                                compositorBackend = when (it) {
                                    "Wayland (nested)" -> "wayland"
                                    "DRM/KMS (iLand)" -> "drm"
                                    else -> "auto"
                                }
                                compositorBackendExpanded = false
                            }
                        )
                        ToggleRow("Enable DMABUF", dmabufEnabled) { dmabufEnabled = it }
                        ToggleRow("Enable HDR", colorOperations) { colorOperations = it }
                        HorizontalDivider()
                        ToggleRow("Shake to Exit Machine", shakeToCloseOverride) { shakeToCloseOverride = it }
                        ToggleRow("Swipe Back to Exit Machine", swipeBackOverride) { swipeBackOverride = it }
                        HorizontalDivider()
                        Text(
                            "Env Vars (this machine)",
                            style = MaterialTheme.typography.titleSmall,
                            fontWeight = FontWeight.SemiBold,
                        )
                        Text(
                            if (machineEnvironment.isEmpty())
                                "Inherit global (Settings → Env Vars). Add overrides for this machine only."
                            else
                                "${machineEnvironment.size} machine override(s). Machine wins over global.",
                            style = MaterialTheme.typography.bodySmall,
                            color = MaterialTheme.colorScheme.onSurfaceVariant,
                        )
                        machineEnvironment.toList().sortedBy { it.first }.forEach { (envName, entry) ->
                            Row(
                                modifier = Modifier.fillMaxWidth(),
                                verticalAlignment = Alignment.CenterVertically,
                            ) {
                                Column(modifier = Modifier.weight(1f)) {
                                    Text(envName, fontFamily = FontFamily.Monospace, fontWeight = FontWeight.SemiBold)
                                    Text(
                                        if (entry.action == "unset") "(unset)" else (entry.value ?: ""),
                                        fontFamily = FontFamily.Monospace,
                                        style = MaterialTheme.typography.bodySmall,
                                    )
                                }
                                TextButton(onClick = {
                                    machineEnvIsNew = false
                                    machineEnvEditName = envName
                                    machineEnvEditValue = entry.value ?: ""
                                    showMachineEnvEditor = true
                                }) { Text("Edit") }
                                TextButton(onClick = {
                                    machineEnvironment = machineEnvironment.toMutableMap().also { it.remove(envName) }
                                }) { Text("Reset") }
                            }
                        }
                        Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                            TextButton(onClick = {
                                machineEnvIsNew = true
                                machineEnvEditName = ""
                                machineEnvEditValue = ""
                                showMachineEnvEditor = true
                            }) { Text("New") }
                            if (machineEnvironment.isNotEmpty()) {
                                TextButton(onClick = { machineEnvironment = mutableMapOf() }) {
                                    Text("Clear all")
                                }
                            }
                        }
                        if (showMachineEnvEditor) {
                            AlertDialog(
                                onDismissRequest = { showMachineEnvEditor = false },
                                title = { Text(if (machineEnvIsNew) "New Variable" else "Edit Variable") },
                                text = {
                                    Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                                        OutlinedTextField(
                                            value = machineEnvEditName,
                                            onValueChange = { machineEnvEditName = it },
                                            label = { Text("Name") },
                                            enabled = machineEnvIsNew,
                                            singleLine = true,
                                        )
                                        OutlinedTextField(
                                            value = machineEnvEditValue,
                                            onValueChange = { machineEnvEditValue = it },
                                            label = { Text("Value") },
                                            singleLine = true,
                                        )
                                    }
                                },
                                confirmButton = {
                                    TextButton(onClick = {
                                        val n = machineEnvEditName.trim()
                                        if (n.isNotEmpty()) {
                                            machineEnvironment = machineEnvironment.toMutableMap().also {
                                                it[n] = EnvironmentOverrides.Entry.set(machineEnvEditValue)
                                            }
                                        }
                                        showMachineEnvEditor = false
                                    }) { Text("Save") }
                                },
                                dismissButton = {
                                    TextButton(onClick = { showMachineEnvEditor = false }) { Text("Cancel") }
                                },
                            )
                        }
                    }

                    if (uiType == MachineType.VM) {
                        EditorSectionCard(
                            title = "Virtual Machine",
                            subtitle = "Hypervisor is selected automatically for this platform."
                        ) {
                            // VM engine is fixed per build target by wwn-vms and is
                            // not user-configurable (Residual E).
                            OutlinedTextField(value = "QEMU/AVF", onValueChange = {}, label = { Text("Backend") }, singleLine = true, readOnly = true, modifier = Modifier.fillMaxWidth())
                            OutlinedTextField(value = vmIdentifier, onValueChange = { vmIdentifier = it }, label = { Text("VM Identifier") }, singleLine = true, modifier = Modifier.fillMaxWidth())
                            OutlinedTextField(value = vmVsockPort, onValueChange = { vmVsockPort = it }, label = { Text("VSock Port") }, singleLine = true, modifier = Modifier.fillMaxWidth())
                            OutlinedTextField(value = vmNotes, onValueChange = { vmNotes = it }, label = { Text("Notes") }, modifier = Modifier.fillMaxWidth())
                        }
                    }

                    if (uiType == MachineType.CONTAINER) {
                        EditorSectionCard(
                            title = "Container",
                            subtitle = "Container runtime is selected automatically for this platform."
                        ) {
                            // Container backend is fixed per build target by
                            // wwn-containers and is not user-configurable (Residual E).
                            OutlinedTextField(value = "container-in-VM", onValueChange = {}, label = { Text("Backend") }, singleLine = true, readOnly = true, modifier = Modifier.fillMaxWidth())
                            OutlinedTextField(value = containerRef, onValueChange = { containerRef = it }, label = { Text("Container Ref") }, singleLine = true, modifier = Modifier.fillMaxWidth())
                            OutlinedTextField(value = containerEntry, onValueChange = { containerEntry = it }, label = { Text("Entry Command") }, modifier = Modifier.fillMaxWidth())
                            OutlinedTextField(value = containerNotes, onValueChange = { containerNotes = it }, label = { Text("Notes") }, modifier = Modifier.fillMaxWidth())
                        }
                    }
                }
            }
        }
    }
}

@Composable
private fun BundledClientPicker(
    selectedId: String,
    scrollState: ScrollState,
    onSelect: (String) -> Unit
) {
    Column(
        modifier = Modifier
            .fillMaxWidth()
            .verticalScroll(scrollState)
            .padding(horizontal = 16.dp, vertical = 8.dp),
        verticalArrangement = Arrangement.spacedBy(8.dp)
    ) {
        BundledClients.waylandPickerGroups().forEach { (kind, clients) ->
            Text(
                kind.sectionTitle,
                style = MaterialTheme.typography.titleSmall,
                color = MaterialTheme.colorScheme.primary,
                modifier = Modifier.padding(top = 12.dp, bottom = 2.dp),
            )
            clients.forEach { client ->
                BundledClientPickerRow(
                    id = client.id,
                    name = client.name,
                    description = client.description,
                    icon = client.icon,
                    selectedId = selectedId,
                    onSelect = onSelect,
                )
            }
        }
    }
}

@Composable
private fun BundledClientPickerRow(
    id: String,
    name: String,
    description: String,
    icon: ImageVector,
    selectedId: String,
    onSelect: (String) -> Unit,
) {
    val isSelected = id == selectedId
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .clip(RoundedCornerShape(8.dp))
            .background(
                if (isSelected) MaterialTheme.colorScheme.primary.copy(alpha = 0.10f)
                else Color.Transparent
            )
            .clickable { onSelect(id) }
            .padding(horizontal = 8.dp, vertical = 10.dp),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(12.dp)
    ) {
        Icon(
            if (isSelected) Icons.Filled.CheckCircle else Icons.Filled.RadioButtonUnchecked,
            contentDescription = null,
            tint = if (isSelected) MaterialTheme.colorScheme.primary else MaterialTheme.colorScheme.onSurfaceVariant,
        )
        Icon(
            icon,
            contentDescription = null,
            tint = MaterialTheme.colorScheme.primary.copy(alpha = 0.85f),
            modifier = Modifier.size(22.dp),
        )
        Column(Modifier.weight(1f)) {
            Text(name, fontWeight = FontWeight.SemiBold)
            Text(
                description,
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant
            )
        }
    }
}

@Composable
private fun EditorSectionCard(
    title: String,
    subtitle: String,
    content: @Composable () -> Unit
) {
    Column(
        modifier = Modifier
            .fillMaxWidth()
            .background(
                // Subtle lighter section fill matching iOS sectionCard (secondary @ 0.08).
                MaterialTheme.colorScheme.onSurface.copy(alpha = 0.06f),
                RoundedCornerShape(14.dp),
            )
            .border(
                width = 1.dp,
                color = MaterialTheme.colorScheme.outlineVariant.copy(alpha = 0.28f),
                shape = RoundedCornerShape(14.dp),
            )
            .padding(14.dp),
        verticalArrangement = Arrangement.spacedBy(10.dp),
    ) {
        Text(title, style = MaterialTheme.typography.titleMedium, fontWeight = FontWeight.SemiBold)
        Text(subtitle, style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
        content()
    }
}

@Composable
private fun ToggleRow(label: String, checked: Boolean, onCheckedChange: (Boolean) -> Unit) {
    Row(
        modifier = Modifier.fillMaxWidth(),
        horizontalArrangement = Arrangement.SpaceBetween,
        verticalAlignment = Alignment.CenterVertically
    ) {
        Text(label, modifier = Modifier.weight(1f))
        Switch(checked = checked, onCheckedChange = onCheckedChange)
    }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun MachineTypeDropdown(
    selected: MachineType,
    expanded: Boolean,
    onExpandedChange: (Boolean) -> Unit,
    onSelect: (MachineType) -> Unit
) {
    ExposedDropdownMenuBox(expanded = expanded, onExpandedChange = onExpandedChange) {
        OutlinedTextField(
            value = selected.displayLabel,
            onValueChange = {},
            readOnly = true,
            label = { Text("Type") },
            trailingIcon = { ExposedDropdownMenuDefaults.TrailingIcon(expanded = expanded) },
            modifier = Modifier
                .fillMaxWidth()
                .menuAnchor()
        )
        DropdownMenu(expanded = expanded, onDismissRequest = { onExpandedChange(false) }) {
            MachineType.selectableForUi.forEach { candidate ->
                DropdownMenuItem(
                    text = { Text(candidate.displayLabel) },
                    onClick = { onSelect(candidate) }
                )
            }
        }
    }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun AuthMethodDropdown(
    selected: String,
    expanded: Boolean,
    onExpandedChange: (Boolean) -> Unit,
    onSelect: (String) -> Unit
) {
    val label = if (selected == "key") "Key" else "Password"
    ExposedDropdownMenuBox(expanded = expanded, onExpandedChange = onExpandedChange) {
        OutlinedTextField(
            value = label,
            onValueChange = {},
            readOnly = true,
            label = { Text("Auth Method") },
            trailingIcon = { ExposedDropdownMenuDefaults.TrailingIcon(expanded = expanded) },
            modifier = Modifier
                .fillMaxWidth()
                .menuAnchor()
        )
        DropdownMenu(expanded = expanded, onDismissRequest = { onExpandedChange(false) }) {
            DropdownMenuItem(text = { Text("Password") }, onClick = { onSelect("password") })
            DropdownMenuItem(text = { Text("Key") }, onClick = { onSelect("key") })
        }
    }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun StringDropdownField(
    label: String,
    selected: String,
    options: List<String>,
    expanded: Boolean,
    onExpandedChange: (Boolean) -> Unit,
    onSelect: (String) -> Unit,
    enabled: Boolean = true,
) {
    ExposedDropdownMenuBox(
        expanded = expanded && enabled,
        onExpandedChange = { if (enabled) onExpandedChange(it) },
    ) {
        OutlinedTextField(
            value = selected,
            onValueChange = {},
            readOnly = true,
            enabled = enabled,
            label = { Text(label) },
            trailingIcon = { ExposedDropdownMenuDefaults.TrailingIcon(expanded = expanded && enabled) },
            modifier = Modifier
                .fillMaxWidth()
                .menuAnchor()
        )
        DropdownMenu(expanded = expanded && enabled, onDismissRequest = { onExpandedChange(false) }) {
            options.forEach { option ->
                DropdownMenuItem(text = { Text(option) }, onClick = { onSelect(option) })
            }
        }
    }
}