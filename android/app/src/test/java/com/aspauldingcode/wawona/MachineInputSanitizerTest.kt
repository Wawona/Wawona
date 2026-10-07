package com.aspauldingcode.wawona

import io.kotest.core.spec.style.StringSpec
import io.kotest.matchers.shouldBe
import io.kotest.property.Arb
import io.kotest.property.arbitrary.string
import io.kotest.property.checkAll
import java.io.File

class MachineInputSanitizerTest : StringSpec({
    "matches the rust ssh host vector" {
        val root = File("verification/ssh_host_vector.tsv").takeIf { it.exists() }
            ?: File("../../verification/ssh_host_vector.tsv")
        val rows = root.readLines().mapNotNull { line ->
            if (line.isEmpty() || line.startsWith("#")) return@mapNotNull null
            val parts = line.split('\t')
            if (parts.size != 2) return@mapNotNull null
            parts[0] to parts[1]
        }
        rows.forEach { (input, expected) ->
            MachineInputSanitizer.sanitizeHost(input) shouldBe expected
        }
    }

    "drops whitespace and shell metacharacters" {
        checkAll(Arb.string(0..16)) { raw ->
            val out = MachineInputSanitizer.sanitizeHost(raw)
            out.none { it.isWhitespace() || "\"'`$;&|<>\\".contains(it) }
        }
    }
})
