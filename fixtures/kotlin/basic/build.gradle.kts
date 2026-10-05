// Builds build/libs/kfixtures.jar. Run (offline when the plugin is cached):
//   <gradle> -p fixtures/kotlin/basic jar --offline
plugins {
    kotlin("jvm") version "2.4.20"
}

kotlin {
    jvmToolchain(17)
}

dependencies {
    // compileOnly: the app (or test classpath) provides the runtime libraries.
    compileOnly("org.jetbrains.kotlinx:kotlinx-coroutines-core:1.10.2")
}
