package com.aspauldingcode.wawona

import androidx.compose.animation.AnimatedVisibility
import androidx.compose.animation.core.Spring
import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.animation.core.spring
import androidx.compose.animation.expandVertically
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.animation.shrinkVertically
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Add
import androidx.compose.material.icons.filled.PlayArrow
import androidx.compose.material.icons.filled.Settings
import androidx.compose.material.icons.filled.Stop
import androidx.compose.material3.FloatingActionButton
import androidx.compose.material3.FloatingActionButtonDefaults
import androidx.compose.material3.Icon
import androidx.compose.material3.LargeFloatingActionButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.rotate
import androidx.compose.ui.draw.scale
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.unit.dp

@Composable
fun ExpressiveFabMenu(
    modifier: Modifier = Modifier,
    isWaypipeRunning: Boolean,
    onSettingsClick: () -> Unit,
    onRunWaypipeClick: () -> Unit,
    onStopWaypipeClick: () -> Unit,
    onMenuClosed: () -> Unit = {}
) {
    var expanded by remember { mutableStateOf(false) }

    val rotation by animateFloatAsState(
        targetValue = if (expanded) 135f else 0f,
        animationSpec = spring(
            dampingRatio = Spring.DampingRatioMediumBouncy,
            stiffness = Spring.StiffnessMedium
        ),
        label = "fab_rotation"
    )

    val fabScale by animateFloatAsState(
        targetValue = if (expanded) 1.05f else 1f,
        animationSpec = spring(
            dampingRatio = Spring.DampingRatioMediumBouncy,
            stiffness = Spring.StiffnessMedium
        ),
        label = "fab_scale"
    )

    Column(
        modifier = modifier,
        horizontalAlignment = Alignment.End,
        verticalArrangement = Arrangement.Bottom
    ) {
        AnimatedVisibility(
            visible = expanded,
            enter = fadeIn(
                animationSpec = spring(stiffness = Spring.StiffnessMediumLow)
            ) + expandVertically(
                expandFrom = Alignment.Bottom,
                animationSpec = spring(
                    dampingRatio = Spring.DampingRatioMediumBouncy,
                    stiffness = Spring.StiffnessMediumLow
                )
            ),
            exit = fadeOut(
                animationSpec = spring(stiffness = Spring.StiffnessMedium)
            ) + shrinkVertically(
                shrinkTowards = Alignment.Bottom,
                animationSpec = spring(stiffness = Spring.StiffnessMedium)
            )
        ) {
            Column(
                horizontalAlignment = Alignment.End,
                verticalArrangement = Arrangement.spacedBy(16.dp),
                modifier = Modifier.padding(bottom = 24.dp)
            ) {
                FabMenuItem(
                    text = "Settings",
                    icon = Icons.Filled.Settings,
                    onClick = {
                        onSettingsClick()
                        expanded = false
                        onMenuClosed()
                    }
                )
                if (isWaypipeRunning) {
                    FabMenuItem(
                        text = "Stop Waypipe",
                        icon = Icons.Filled.Stop,
                        onClick = {
                            onStopWaypipeClick()
                            expanded = false
                            onMenuClosed()
                        }
                    )
                } else {
                    FabMenuItem(
                        text = "Run Waypipe",
                        icon = Icons.Filled.PlayArrow,
                        onClick = {
                            onRunWaypipeClick()
                            expanded = false
                            onMenuClosed()
                        }
                    )
                }
            }
        }

        LargeFloatingActionButton(
            onClick = {
                if (expanded) onMenuClosed()
                expanded = !expanded
            },
            containerColor = if (expanded)
                MaterialTheme.colorScheme.primaryContainer
            else
                MaterialTheme.colorScheme.primary,
            contentColor = if (expanded)
                MaterialTheme.colorScheme.onPrimaryContainer
            else
                MaterialTheme.colorScheme.onPrimary,
            shape = FloatingActionButtonDefaults.largeShape,
            modifier = Modifier.scale(fabScale)
        ) {
            Icon(
                imageVector = Icons.Filled.Add,
                contentDescription = if (expanded) "Close menu" else "Open menu",
                modifier = Modifier
                    .size(36.dp)
                    .rotate(rotation)
            )
        }
    }
}

@Composable
fun FabMenuItem(
    text: String,
    icon: ImageVector,
    onClick: () -> Unit
) {
    Row(
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.End
    ) {
        Surface(
            shape = RoundedCornerShape(16.dp),
            color = MaterialTheme.colorScheme.surfaceVariant,
            shadowElevation = 3.dp,
            tonalElevation = 2.dp,
            onClick = onClick
        ) {
            Text(
                text = text,
                style = MaterialTheme.typography.labelLarge,
                modifier = Modifier.padding(horizontal = 16.dp, vertical = 10.dp)
            )
        }
        Spacer(modifier = Modifier.width(16.dp))
        FloatingActionButton(
            onClick = onClick,
            containerColor = MaterialTheme.colorScheme.secondaryContainer,
            contentColor = MaterialTheme.colorScheme.onSecondaryContainer,
            elevation = FloatingActionButtonDefaults.elevation(
                defaultElevation = 3.dp,
                pressedElevation = 6.dp
            ),
            modifier = Modifier.size(56.dp)
        ) {
            Icon(imageVector = icon, contentDescription = text)
        }
    }
}
