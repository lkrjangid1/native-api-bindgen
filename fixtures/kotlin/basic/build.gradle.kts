import org.jetbrains.kotlin.gradle.dsl.KotlinVersion

// Builds build/libs/kfixtures.jar. Run (offline when the plugin is cached):
//   <gradle> -p fixtures/kotlin/basic jar --offline
plugins {
    kotlin("jvm") version "2.4.20"
}

kotlin {
    jvmToolchain(17)
    compilerOptions {
        // Readable by apps built with older Kotlin compilers (metadata 2.0).
        languageVersion.set(KotlinVersion.KOTLIN_2_0)
        apiVersion.set(KotlinVersion.KOTLIN_2_0)
    }
}

dependencies {
    // compileOnly: the app (or test classpath) provides the runtime libraries.
    compileOnly("org.jetbrains.kotlinx:kotlinx-coroutines-core:1.10.2")
}
