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
        scopeLabel(profile.type),
        typeLabel(profile),
        subtitle(profile),
        summary(profile),
        launchCommandPreview(profile),
    )
        .filter { it.isNotBlank() }
        .joinToString(" ")
        .lowercase()

    private fun scopeLabel(type: MachineType): String = when (type) {
        MachineType.NATIVE, MachineType.VM, MachineType.CONTAINER -> "LOCAL"
        MachineType.SSH_WAYPIPE, MachineType.SSH_TERMINAL -> "REMOTE"
    }

    private fun typeLabel(profile: MachineProfile): String = when (profile.type) {
        MachineType.NATIVE -> "NATIVE"
        MachineType.SSH_WAYPIPE -> "SSH+WAYPIPE"
        MachineType.SSH_TERMINAL -> "SSH TERMINAL"
        MachineType.VM -> "VM"
        MachineType.CONTAINER -> "CONTAINER"
    }

    internal fun subtitle(profile: MachineProfile): String = when (profile.type) {
        MachineType.NATIVE -> BundledClients.labelFor(profile.nativeLauncher)
        MachineType.SSH_WAYPIPE, MachineType.SSH_TERMINAL -> {
            if (profile.sshHost.isBlank()) "SSH endpoint not configured"
            else "${profile.sshUser.ifBlank { "user" }}@${profile.sshHost}"
        }
        MachineType.VM -> "VM profile (QEMU/AVF)"
        MachineType.CONTAINER -> "Container profile (container-in-VM)"
    }

    internal fun summary(profile: MachineProfile): String = when (profile.type) {
        MachineType.NATIVE -> {
            val client = BundledClients.labelFor(profile.nativeLauncher)
            if (client.isBlank()) "No client configured. Edit to select one"
            else "Runs: $client"
        }
        MachineType.SSH_WAYPIPE -> {
            val cmd = profile.remoteCommand.ifBlank { "weston-simple-shm" }
            "Waypipe command: $cmd"
        }
        MachineType.SSH_TERMINAL -> {
            val cmd = profile.remoteCommand.ifBlank { "bash -l" }
            "SSH terminal command: $cmd"
        }
        MachineType.VM -> "Backend: QEMU/AVF"
        MachineType.CONTAINER -> "Backend: container-in-VM"
    }

    private fun launchCommandPreview(profile: MachineProfile): String = summary(profile)
}
