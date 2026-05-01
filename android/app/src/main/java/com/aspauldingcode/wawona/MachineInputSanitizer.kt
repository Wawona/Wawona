package com.aspauldingcode.wawona

object MachineInputSanitizer {
    data class HostPort(val host: String, val port: Int)

    private fun cleanupHost(raw: String): String {
        var value = raw.trim()
        if (value.isEmpty()) return ""

        val schemeIndex = value.indexOf("://")
        if (schemeIndex >= 0 && schemeIndex + 3 <= value.length) {
            value = value.substring(schemeIndex + 3)
        }

        value = value.substringBefore("/")
            .substringBefore("?")
            .substringBefore("#")

        val disallowed = setOf('"', '\'', '`', '$', ';', '&', '|', '<', '>', '\\')
        value = value.filter { ch ->
            !ch.isWhitespace() && !disallowed.contains(ch)
        }
        return value
    }

    fun sanitizeHost(raw: String): String {
        var value = cleanupHost(raw)
        if (value.startsWith("[")) {
            val endBracket = value.indexOf(']')
            if (endBracket > 0 && endBracket + 1 < value.length && value[endBracket + 1] == ':') {
                val maybePort = value.substring(endBracket + 2)
                if (maybePort.isNotEmpty() && maybePort.all { it.isDigit() }) {
                    value = value.substring(0, endBracket + 1)
                }
            }
        } else {
            val colon = value.lastIndexOf(':')
            if (colon > 0 && colon + 1 < value.length) {
                val host = value.substring(0, colon)
                val maybePort = value.substring(colon + 1)
                if (!host.contains(':') && maybePort.all { it.isDigit() }) {
                    value = host
                }
            }
        }
        return value
    }

    fun normalizePort(raw: String, fallback: Int = 22): Int {
        val parsed = raw.trim().toIntOrNull() ?: return fallback
        return if (parsed in 1..65535) parsed else fallback
    }

    fun normalizePortText(raw: String, fallback: Int = 22): String =
        normalizePort(raw, fallback).toString()

    fun splitHostAndPort(rawHost: String, rawPort: String?, fallbackPort: Int = 22): HostPort {
        val cleaned = cleanupHost(rawHost)
        val explicitPort = rawPort?.let { normalizePort(it, fallbackPort) } ?: fallbackPort
        if (cleaned.startsWith("[")) {
            val endBracket = cleaned.indexOf(']')
            if (endBracket > 0 && endBracket + 1 < cleaned.length && cleaned[endBracket + 1] == ':') {
                val maybePort = cleaned.substring(endBracket + 2)
                if (maybePort.isNotEmpty() && maybePort.all { it.isDigit() }) {
                    return HostPort(cleaned.substring(0, endBracket + 1), normalizePort(maybePort, explicitPort))
                }
            }
            return HostPort(cleaned, explicitPort)
        }
        val colon = cleaned.lastIndexOf(':')
        if (colon > 0 && colon + 1 < cleaned.length) {
            val host = cleaned.substring(0, colon)
            val maybePort = cleaned.substring(colon + 1)
            if (!host.contains(':') && maybePort.all { it.isDigit() }) {
                return HostPort(host, normalizePort(maybePort, explicitPort))
            }
        }
        return HostPort(cleaned, explicitPort)
    }
}
