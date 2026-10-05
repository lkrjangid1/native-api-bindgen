// Synthetic Kotlin fixtures for native-api-bindgen (Apache-2.0).
package com.example.kfixtures

import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.flow
import kotlinx.coroutines.flow.flowOf

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

    /** Suspends, then returns a value or null (nullable result). */
    suspend fun maybe(present: Boolean): String? {
        delay(1)
        return if (present) "yes, $name" else null
    }

    /** Default arguments (not applied through JNI: every argument is passed). */
    fun repeat(text: String, times: Int = 2, separator: String = ","): String =
        List(times) { text }.joinToString(separator)

    /** A mutable nullable property. */
    var nickname: String? = null

    /** A read-only computed property. */
    val nameLength: Int
        get() = name.length

    /** A boolean property (`isLoud` / `setLoud`). */
    var isLoud: Boolean = false

    /** A cold flow of 1..[count], suspending between values. */
    fun countTo(count: Int): Flow<Int> = flow {
        for (i in 1..count) {
            delay(1)
            emit(i)
        }
    }

    /** A flow of strings that may contain null. */
    fun words(): Flow<String?> = flowOf("a", null, "c")

    /** A flow that fails after one value. */
    fun failing(message: String): Flow<String> = flow {
        emit("first")
        throw IllegalStateException(message)
    }

    /** An endless flow (cancelled by the collector). */
    fun ticks(): Flow<Long> = flow {
        var i = 0L
        while (true) {
            delay(1)
            emit(i++)
        }
    }

    companion object {
        /** A static factory. */
        @JvmStatic
        fun create(name: String): Greeter = Greeter(name)
    }
}
