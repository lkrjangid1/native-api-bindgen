// Synthetic Kotlin fixtures for native-api-bindgen (Apache-2.0).
package com.example.kfixtures

import kotlinx.coroutines.delay

/** Exercises Kotlin `suspend` functions as seen through JNI. */
class Greeter(private val name: String) {
    /** A regular (blocking) function. */
    fun greet(): String = "Hello, $name"

    /** Suspends, then returns a value. */
    suspend fun greetLater(delayMs: Long): String {
        delay(delayMs)
        return "Later, $name"
    }

    /** Returns without suspending (the value is returned directly). */
    suspend fun immediate(): Int = name.length

    /** Suspends, then completes without a value (`Unit`). */
    suspend fun pause(delayMs: Long) {
        delay(delayMs)
    }

    /** Suspends, then throws. */
    suspend fun failLater(message: String): String {
        delay(1)
        throw IllegalStateException(message)
    }

    /** Returns another Kotlin object. */
    suspend fun child(suffix: String): Greeter {
        delay(1)
        return Greeter(name + suffix)
    }

    companion object {
        /** A static factory. */
        @JvmStatic
        fun create(name: String): Greeter = Greeter(name)
    }
}
