// native-api-bindgen React Native runtime (TypeScript side).
// Apache License, Version 2.0.
import NativeApiBindgen from '../specs/NativeApiBindgen';

/** Opaque JSI handle to a Java object (a HostObject owned by JS). */
export type Handle = object;

/** Native root installed by the C++ Turbo Module. */
interface Root {
  readonly version: string;
  release(h: Handle): void;
  isReleased(h: Handle): boolean;
  isInstanceOf(h: Handle, internalName: string): boolean;
  isSameObject(a: Handle, b: Handle): boolean;
  javaToString(h: Handle): string;
  javaClassName(h: Handle): string;
  javaHashCode(h: Handle): number;
  javaEquals(a: Handle, b: Handle | null): boolean;
  implement(internalName: string, dispatcher: object, asyncDescriptors: string[]): Handle;
  applicationContext(): Handle | null;
  currentActivity(): Handle | null;
  androidSdkInt(): number;
  androidSdkIntFull(): number;
  [className: string]: unknown;
}

let root: Root | undefined;

/** Installs the native runtime (idempotent). Called lazily on first use. */
export function installNativeApiBindings(): void {
  const g = globalThis as unknown as {__nab?: Root};
  if (g.__nab === undefined) {
    NativeApiBindgen.install();
  }
  root = g.__nab;
  if (root === undefined) {
    throw new Error('native-api-bindgen: runtime installation failed');
  }
}

/** The native root. */
export function nab(): Root {
  if (root === undefined) installNativeApiBindings();
  return root as Root;
}

/** Lazily resolves the member table of one generated class. */
export function classTable(key: string): () => Record<string, (...args: unknown[]) => unknown> {
  let table: Record<string, (...args: unknown[]) => unknown> | undefined;
  return () => {
    if (table === undefined) {
      const t = nab()[key];
      if (t === undefined) {
        throw new Error(`E010 RUNTIME_BINDING_FAILURE: ${key} is not part of the generated bindings`);
      }
      table = t as Record<string, (...args: unknown[]) => unknown>;
    }
    return table;
  };
}

/** Constructor shape of generated classes. */
export interface JavaClass<T extends JavaObject> {
  new (handle: Handle): T;
  readonly javaInternalName: string;
}

/** Base of every generated class: a typed view over a Java object handle. */
export class JavaObject {
  static readonly javaInternalName: string = 'java/lang/Object';

  /** @internal */
  readonly $h: Handle;

  constructor(handle: Handle) {
    this.$h = handle;
    ensureInherited(new.target as unknown as InheritingClass);
  }

  /** Releases the Java reference now (otherwise released on JS GC). */
  release(): void {
    nab().release(this.$h);
  }

  /** Idempotent {@link release}. */
  dispose(): void {
    if (!this.isReleased) nab().release(this.$h);
  }

  /** Whether this handle was released. */
  get isReleased(): boolean {
    return nab().isReleased(this.$h);
  }

  /** Runtime class name of the Java object (`getClass().getName()`). */
  javaClassName(): string {
    return nab().javaClassName(this.$h);
  }

  /** Java `equals`. */
  javaEquals(other: JavaObject | null): boolean {
    return nab().javaEquals(this.$h, other === null ? null : other.$h);
  }

  /** Java `hashCode`. */
  javaHashCode(): number {
    return nab().javaHashCode(this.$h);
  }

  /** Java `toString()` (or `[released]`). */
  toString(): string {
    return this.isReleased ? '[released]' : nab().javaToString(this.$h);
  }

  /** Java `instanceof` check against a generated class. */
  isInstanceOf(cls: {readonly javaInternalName: string}): boolean {
    return nab().isInstanceOf(this.$h, cls.javaInternalName);
  }

  /** Checked cast; the result shares this object's handle. */
  as<T extends JavaObject>(cls: JavaClass<T>): T {
    if (!this.isInstanceOf(cls)) {
      throw new TypeError(`Cannot cast ${this.javaClassName()} to ${cls.javaInternalName.replace(/\//g, '.')}`);
    }
    return new cls(this.$h);
  }
}

/** Error thrown for Java exceptions (created natively). */
export interface NativeJavaError extends Error {
  readonly nativeClassName: string;
  readonly javaStackTrace: string;
}

/** Type guard for {@link NativeJavaError}. */
export function isNativeJavaError(e: unknown): e is NativeJavaError {
  return e instanceof Error && e.name === 'NativeJavaError';
}

/** Thrown when a method declared non-null by the SDK returned null. */
export class NativeNullError extends Error {
  constructor(symbol: string) {
    super(`${symbol} returned null although the SDK declares it non-null`);
    this.name = 'NativeNullError';
  }
}

/** Thrown by availability guards (E012). */
export class NativeApiUnavailableError extends Error {
  constructor(readonly symbol: string, readonly required: string, readonly actual: string) {
    super(`E012 AVAILABILITY_MISMATCH: ${symbol} requires Android API ${required} (device: ${actual})`);
    this.name = 'NativeApiUnavailableError';
  }
}

/** Platform version checks. */
export const AndroidApi = {
  /** Test hook: `major * 100000 + minor`, or undefined. */
  debugOverrideFullVersion: undefined as number | undefined,

  /** `Build.VERSION.SDK_INT`. */
  get sdkInt(): number {
    const o = AndroidApi.debugOverrideFullVersion;
    return o !== undefined ? Math.floor(o / 100000) : nab().androidSdkInt();
  },

  /** `major * 100000 + minor` (`SDK_INT_FULL` on API 36+). */
  get fullVersion(): number {
    const o = AndroidApi.debugOverrideFullVersion;
    return o !== undefined ? o : nab().androidSdkIntFull();
  },

  isAtLeast(major: number, minor = 0): boolean {
    return AndroidApi.fullVersion >= major * 100000 + minor;
  },

  require(major: number, minor: number, symbol: string): void {
    if (AndroidApi.isAtLeast(major, minor)) return;
    const v = AndroidApi.fullVersion;
    const actual = v % 100000 === 0 ? `${Math.floor(v / 100000)}` : `${Math.floor(v / 100000)}.${v % 100000}`;
    throw new NativeApiUnavailableError(symbol, minor === 0 ? `${major}` : `${major}.${minor}`, actual);
  },
};

/** Callback error policy (mirrors the Dart runtime). */
export const NativeCallbacks = {
  /** `report`: void callbacks report errors and return normally to Java. */
  policy: 'report' as 'report' | 'propagate',
  onError: undefined as ((error: unknown, symbol: string) => void) | undefined,
};

/** @internal Runs a void callback body under the error policy. */
export function voidCallback(symbol: string, body: () => void): void {
  try {
    body();
  } catch (e) {
    NativeCallbacks.onError?.(e, symbol);
    if (NativeCallbacks.policy === 'propagate') throw e;
    const reporter = (globalThis as {ErrorUtils?: {reportError(e: unknown): void}}).ErrorUtils;
    if (reporter !== undefined) {
      reporter.reportError(e);
    } else {
      console.error(`Error in JS implementation of ${symbol}`, e);
    }
  }
}

/** @internal Runs a value-returning callback body (errors propagate to Java). */
export function valueCallback<T>(symbol: string, body: () => T): T {
  try {
    return body();
  } catch (e) {
    NativeCallbacks.onError?.(e, symbol);
    throw e;
  }
}

/** Shape of generated classes with ancestors. */
interface InheritingClass {
  prototype: object;
  $anc?: () => Array<{prototype: object}>;
}

const inherited = new WeakSet<object>();

/**
 * @internal Copies inherited members onto a generated class's prototype the
 * first time the class is instantiated. Generated classes declare only their
 * own members and list ancestors (nearest first) in a `$anc` thunk, which
 * keeps output linear in the API size and makes import cycles between the
 * per-package modules harmless.
 */
export function ensureInherited(cls: InheritingClass): void {
  if (inherited.has(cls)) return;
  inherited.add(cls);
  const ancestors = cls.$anc?.() ?? [];
  const own = cls.prototype;
  for (const a of ancestors) {
    for (const key of Object.getOwnPropertyNames(a.prototype)) {
      if (key === 'constructor' || Object.prototype.hasOwnProperty.call(own, key)) continue;
      const d = Object.getOwnPropertyDescriptor(a.prototype, key);
      if (d !== undefined) Object.defineProperty(own, key, d);
    }
  }
}

/**
 * @internal A `byte[]` argument: a `Uint8Array` crosses as an `ArrayBuffer`
 * (one copy into the Java array); `number[]` is still accepted.
 */
export function bytesArg(v: Uint8Array | number[] | null | undefined): ArrayBuffer | number[] | null {
  if (v === null || v === undefined) return null;
  if (Array.isArray(v)) return v;
  if (v.byteOffset === 0 && v.byteLength === v.buffer.byteLength && v.buffer instanceof ArrayBuffer) {
    return v.buffer;
  }
  return v.slice().buffer as ArrayBuffer;
}

/** @internal A `byte[]` result (an `ArrayBuffer` from native) as `Uint8Array`. */
export function bytesResult(raw: unknown): Uint8Array | null {
  if (raw === null || raw === undefined) return null;
  return new Uint8Array(raw as ArrayBuffer);
}

/** @internal */
export function h(o: JavaObject | null | undefined): Handle | null {
  return o === null || o === undefined ? null : o.$h;
}

/** @internal Wraps a raw handle (null stays null). */
export function wrap<T extends JavaObject>(cls: new (h: Handle) => T, raw: unknown): T | null {
  return raw === null || raw === undefined ? null : new cls(raw as Handle);
}

/** @internal Wraps a raw handle that the SDK declares non-null. */
export function wrapNonNull<T extends JavaObject>(cls: new (h: Handle) => T, raw: unknown, symbol: string): T {
  if (raw === null || raw === undefined) throw new NativeNullError(symbol);
  return new cls(raw as Handle);
}

/** @internal Wraps (nested) arrays of handles. */
export function wrapArray(cls: new (h: Handle) => JavaObject, raw: unknown, depth: number): unknown {
  if (raw === null || raw === undefined) return null;
  const arr = raw as unknown[];
  return depth <= 1 ? arr.map(x => wrap(cls, x)) : arr.map(x => wrapArray(cls, x, depth - 1));
}

/** @internal Unwraps (nested) arrays of objects to handles. */
export function hArray(arr: unknown): unknown {
  if (arr === null || arr === undefined) return null;
  return (arr as unknown[]).map(x => (x instanceof JavaObject ? x.$h : Array.isArray(x) ? hArray(x) : x));
}

/** The application `Context` handle (requires `NabContext.init(app)`). */
export function applicationContextHandle(): Handle | null {
  return nab().applicationContext();
}

/** The current `Activity` handle, or null. */
export function currentActivityHandle(): Handle | null {
  return nab().currentActivity();
}
