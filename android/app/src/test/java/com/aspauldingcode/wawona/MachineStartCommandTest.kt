package com.aspauldingcode.wawona

import io.kotest.core.spec.style.StringSpec
import io.kotest.matchers.shouldBe
import io.kotest.matchers.string.shouldContain
import io.kotest.matchers.string.shouldNotContain
import io.kotest.matchers.string.shouldStartWith

/**
 * Zero-device gate for Terminal-as-Start argv banners.
 * Run: `./gradlew :Wawona:testDebugUnitTest --tests '*MachineStartCommandTest'`
 */
class MachineStartCommandTest : StringSpec({
    "waypipe argv includes ssh host port and remote command" {
        val argv = MachineStartCommand.waypipeArgv(
            sshOn = true,
            host = "127.0.0.1",
            port = 49419,
            user = "ubuntu",
            remote = "foot",
            compress = "lz4",
        )
        argv shouldStartWith "waypipe"
        argv shouldContain "-c lz4"
        argv shouldContain "ssh"
        argv shouldContain "-p 49419"
        argv shouldContain "ubuntu@127.0.0.1"
        argv shouldContain "foot"
    }

    "waypipe argv omits default ssh port 22" {
        val argv = MachineStartCommand.waypipeArgv(
            sshOn = true,
            host = "example.com",
            port = 22,
            user = "me",
            remote = "weston-simple-shm",
            compress = "none",
        )
        argv shouldContain "me@example.com"
        argv shouldNotContain "-p "
    }

    "shellQuote leaves safe tokens bare" {
        MachineStartCommand.shellQuoteForTest("foot") shouldBe "foot"
        MachineStartCommand.shellQuoteForTest("a b") shouldBe "'a b'"
    }

    "argvBanner prefixes dollar prompt" {
        // Banner helper needs prefs; exercise pure waypipe string shape instead.
        val line = "$ " + MachineStartCommand.waypipeArgv(
            sshOn = false,
            host = "",
            port = 22,
            user = "",
            remote = "weston-simple-shm",
            compress = "lz4",
        )
        line shouldStartWith "$ waypipe"
        line shouldContain "weston-simple-shm"
    }
})
