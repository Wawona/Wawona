package com.aspauldingcode.wawona

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ColumnScope
import androidx.compose.foundation.layout.RowScope
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.SheetValue
import androidx.compose.material3.Text
import androidx.compose.material3.TopAppBar
import androidx.compose.material3.rememberModalBottomSheetState
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.remember
import androidx.compose.ui.Modifier
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.input.nestedscroll.NestedScrollConnection
import androidx.compose.ui.input.nestedscroll.NestedScrollSource
import androidx.compose.ui.input.nestedscroll.nestedScroll
import androidx.compose.ui.unit.Velocity
import androidx.compose.ui.unit.dp

enum class WawonaSheetDetent {
    Medium,
    Large,
}

/** How inner scroll interacts with sheet expansion (iOS presentationContentInteraction). */
enum class WawonaSheetScrollBehavior {
    /** Scroll content at medium detent without dragging the sheet taller (machine editor). */
    ContentFirst,
    /** Allow sheet to grow as the user scrolls (settings). */
    ExpandWithContent,
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun WawonaModalSheet(
    onDismiss: () -> Unit,
    title: String,
    defaultDetent: WawonaSheetDetent = WawonaSheetDetent.Medium,
    scrollBehavior: WawonaSheetScrollBehavior = WawonaSheetScrollBehavior.ExpandWithContent,
    navigationIcon: @Composable () -> Unit = {},
    actions: @Composable RowScope.() -> Unit = {},
    content: @Composable ColumnScope.() -> Unit,
) {
    val skipPartiallyExpanded = defaultDetent == WawonaSheetDetent.Large
    val sheetState = rememberModalBottomSheetState(
        skipPartiallyExpanded = skipPartiallyExpanded,
        confirmValueChange = { true },
    )

    LaunchedEffect(defaultDetent) {
        when (defaultDetent) {
            WawonaSheetDetent.Medium ->
                if (sheetState.currentValue == SheetValue.Hidden) {
                    sheetState.partialExpand()
                }
            WawonaSheetDetent.Large ->
                if (sheetState.currentValue != SheetValue.Expanded) {
                    sheetState.expand()
                }
        }
    }

    val scrollConnection = remember(sheetState, scrollBehavior) {
        if (scrollBehavior == WawonaSheetScrollBehavior.ContentFirst) {
            object : NestedScrollConnection {
                override fun onPreScroll(available: Offset, source: NestedScrollSource): Offset {
                    if (sheetState.currentValue == SheetValue.PartiallyExpanded && available.y < 0f) {
                        return Offset(0f, available.y)
                    }
                    return Offset.Zero
                }

                override suspend fun onPreFling(available: Velocity): Velocity {
                    if (sheetState.currentValue == SheetValue.PartiallyExpanded) {
                        return available
                    }
                    return Velocity.Zero
                }
            }
        } else {
            null
        }
    }

    ModalBottomSheet(
        onDismissRequest = onDismiss,
        sheetState = sheetState,
        shape = RoundedCornerShape(topStart = 28.dp, topEnd = 28.dp),
        containerColor = MaterialTheme.colorScheme.surface,
        dragHandle = { WawonaSheetDragHandle() },
    ) {
        Column(
            Modifier
                .fillMaxWidth()
                .navigationBarsPadding()
                .then(
                    if (scrollConnection != null) {
                        Modifier.nestedScroll(scrollConnection)
                    } else {
                        Modifier
                    },
                ),
        ) {
            TopAppBar(
                title = {
                    Text(
                        title,
                        maxLines = 1,
                        style = MaterialTheme.typography.titleLarge,
                    )
                },
                navigationIcon = navigationIcon,
                actions = actions,
            )
            Column(
                modifier = Modifier.fillMaxWidth(),
                content = content,
            )
        }
    }
}

@Composable
fun WawonaSheetDragHandle(modifier: Modifier = Modifier) {
    Box(
        modifier
            .padding(vertical = 12.dp)
            .width(40.dp)
            .height(4.dp)
            .background(
                MaterialTheme.colorScheme.onSurfaceVariant.copy(alpha = 0.4f),
                RoundedCornerShape(2.dp),
            ),
    )
}
