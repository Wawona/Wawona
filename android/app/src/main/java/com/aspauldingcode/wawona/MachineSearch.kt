package com.aspauldingcode.wawona

/**
 * Fuzzy subsequence matcher aligned with iOS [WWNMachinesGridView.fzfScore].
 */
object MachineSearch {
    private val boundaryChars = setOf(' ', '_', '-', '/', '.', ':')

    fun fzfScore(pattern: String, candidate: String): Int? {
        if (pattern.isEmpty()) return 0
        val p = pattern.lowercase().toCharArray()
        val c = candidate.lowercase().toCharArray()
        if (p.size > c.size) return null

        var score = 0
        var pi = 0
        var ci = 0
        var lastMatch = -1

        while (pi < p.size && ci < c.size) {
            if (p[pi] == c[ci]) {
                score += 8
                if (lastMatch >= 0) {
                    val gap = ci - lastMatch - 1
                    score += if (gap == 0) 14 else -minOf(gap, 10)
                }
                if (ci == 0) {
                    score += 10
                } else if (boundaryChars.contains(c[ci - 1])) {
                    score += 9
                }
                lastMatch = ci
                pi++
            }
            ci++
        }
        return if (pi == p.size) score else null
    }

    fun fuzzyFilter(
        profiles: List<MachineProfile>,
        query: String,
        searchableText: (MachineProfile) -> String,
    ): List<MachineProfile> {
        val trimmed = query.trim()
        if (trimmed.isEmpty()) return profiles

        val terms = trimmed.split(Regex("\\s+")).filter { it.isNotEmpty() }
        val scored = profiles.mapNotNull { profile ->
            val haystack = searchableText(profile)
            var total = 0
            for (term in terms) {
                val termScore = fzfScore(term, haystack) ?: return@mapNotNull null
                total += termScore
            }
            profile to total
        }
        return scored
            .sortedWith(
                compareByDescending<Pair<MachineProfile, Int>> { it.second }
                    .thenBy { it.first.name.lowercase() },
            )
            .map { it.first }
    }

    fun searchableText(profile: MachineProfile): String = listOf(
        profile.name,
        profile.sshHost,
        profile.sshUser,
        scopeLabel(profile),
        typeLabel(profile),
        subtitle(profile),
        summary(profile),
        launchCommandPreview(profile),
    )
        .filter { it.isNotBlank() }
        .joinToString(" ")
        .lowercase()

    private fun scopeLabel(profile: MachineProfile): String {
        val (kind, useSsh) = NativeShellSession.from(profile)
        return when (profile.type.selectablePivot()) {
            MachineType.VM, MachineType.CONTAINER -> "LOCAL"
            else -> if (useSsh && (kind == NativeShellKind.TERMINAL || kind == NativeShellKind.WAYPIPE)) {
                "REMOTE"
            } else {
                "LOCAL"
            }
        }
    }

    private fun typeLabel(profile: MachineProfile): String = when (profile.type.selectablePivot()) {
        MachineType.VM -> "VM"
        MachineType.CONTAINER -> "CONTAINER"
        else -> "NATIVE SHELL"
    }

    internal fun subtitle(profile: MachineProfile): String {
        when (profile.type.selectablePivot()) {
            MachineType.VM -> return "VM profile (QEMU/AVF)"
            MachineType.CONTAINER -> return "Container profile (container-in-VM)"
            else -> Unit
        }
        val (kind, useSsh) = NativeShellSession.from(profile)
        return when (kind) {
            NativeShellKind.WASM -> profile.runtimeOverrides.optString("wasmCommand", "wasm hello-wasi-gui")
                .ifBlank { "wasm hello-wasi-gui" }
            NativeShellKind.TERMINAL, NativeShellKind.WAYLAND -> {
                if (useSsh) {
                    if (profile.sshHost.isBlank()) "SSH endpoint not configured"
                    else "${profile.sshUser.ifBlank { "user" }}@${profile.sshHost}"
                } else {
                    profile.remoteCommand.ifBlank { "Wawona Terminal" }
                }
            }
            NativeShellKind.WAYPIPE -> {
                if (useSsh) {
                    if (profile.sshHost.isBlank()) "SSH endpoint not configured"
                    else "${profile.sshUser.ifBlank { "user" }}@${profile.sshHost}"
                } else {
                    profile.remoteCommand.ifBlank { "waypipe (local)" }
                }
            }
        }
    }

    internal fun summary(profile: MachineProfile): String {
        when (profile.type.selectablePivot()) {
            MachineType.VM -> return "Backend: QEMU/AVF"
            MachineType.CONTAINER -> return "Backend: container-in-VM"
            else -> Unit
        }
        val (kind, useSsh) = NativeShellSession.from(profile)
        return when (kind) {
            NativeShellKind.WASM -> {
                val cmd = profile.runtimeOverrides.optString("wasmCommand", "wasm hello-wasi-gui")
                    .ifBlank { "wasm hello-wasi-gui" }
                "Runs: $cmd"
            }
            NativeShellKind.WAYPIPE -> {
                val cmd = profile.remoteCommand.ifBlank { "waypipe" }
                if (useSsh) "Waypipe command: $cmd" else "Local waypipe: $cmd"
            }
            NativeShellKind.TERMINAL, NativeShellKind.WAYLAND -> {
                val cmd = profile.remoteCommand.ifBlank { if (useSsh) "bash -l" else "interactive shell" }
                if (useSsh) "SSH terminal command: $cmd" else "Terminal: $cmd"
            }
        }
    }

    private fun launchCommandPreview(profile: MachineProfile): String = summary(profile)
}
