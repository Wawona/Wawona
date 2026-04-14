plugins {
    id("com.android.application") version "8.10.0" apply false
    // ≥2.1 so stdlib includes kotlin.coroutines.jvm.internal.SpillingKt (reorderable / Skip deps).
    id("org.jetbrains.kotlin.android") version "2.1.21" apply false
    id("org.jetbrains.kotlin.plugin.compose") version "2.1.21" apply false
}

tasks.register("clean", Delete::class) {
    delete(rootProject.layout.buildDirectory)
}
