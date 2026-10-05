// native-api-bindgen React Native runtime for iOS (TypeScript side).
// Apache License, Version 2.0.
import NativeApiBindgen from '../specs/NativeApiBindgen';

/** Opaque JSI handle to an Objective-C object (a HostObject owned by JS). */
export type Handle = object;

/** Native root installed by the C++ Turbo Module on iOS. */
interface ObjCRoot {
  readonly version: string;
  readonly platform: string;
  release(h: Handle): void;
  isReleased(h: Handle): boolean;
  isKindOfClass(h: Handle, className: string): boolean;
  conformsToProtocol(h: Handle, protocolName: string): boolean;
  isSameObject(a: Handle, b: Handle): boolean;
  isEqual(a: Handle, b: Handle | null): boolean;
  describe(h: Handle): string;
  className(h: Handle): string;
  hashOf(h: Handle): number;
  classExists(name: string): boolean;
  iosVersion(): string;
  string(h: Handle): string | null;
  log(message: string): void;
  dataFromBytes(buffer: ArrayBuffer): Handle;
  bytesOfData(h: Handle): ArrayBuffer;
  arrayItems(h: Handle): Handle[];
  /** Object implementing [protocols]; [table] maps selectors to [codes, function]. */
  implementProtocols(
    protocols: string[],
    table: Record<string, [string, (...args: never[]) => unknown]>,
  ): Handle;
  [key: string]: unknown;
}

let root: ObjCRoot | undefined;

/** The native root (installs the runtime on first use). */
export function objc(): ObjCRoot {
  if (root === undefined) {
    const g = globalThis as unknown as {__nab?: ObjCRoot};
    if (g.__nab === undefined) NativeApiBindgen.install();
    root = g.__nab;
    if (root === undefined || root.platform !== 'ios') {
      throw new Error('native-api-bindgen: the iOS runtime is not installed (Objective-C bindings used on another platform?)');
    }
  }
  return root;
}

type Table = Record<string, (...args: unknown[]) => unknown>;

/** Lazily resolves the member table of one generated class. */
export function classTable(key: string): () => Table {
  let table: Table | undefined;
  return () => {
    if (table === undefined) {
      const t = objc()[key];
      if (t === undefined) {
        throw new Error(`E010 RUNTIME_BINDING_FAILURE: ${key} is not part of the generated bindings`);
      }
      table = t as Table;
    }
    return table;
  };
}

/** Constructor shape of generated classes and protocols. */
export interface ObjCClass<T extends ObjCObject> {
  new (handle: Handle): T;
  readonly objcName: string;
  readonly objcProtocol?: boolean;
}

/** Base of every generated class: a typed view over an Objective-C object. */
export class ObjCObject {
  static readonly objcName: string = 'NSObject';

  /** @internal */
  readonly $h: Handle;

  constructor(handle: Handle) {
    this.$h = handle;
    ensureInherited(new.target as unknown as InheritingClass);
  }

  /** Releases the strong reference now (otherwise released on JS GC). */
  release(): void {
    objc().release(this.$h);
  }

  /** Idempotent {@link release}. */
  dispose(): void {
    if (!this.isReleased) objc().release(this.$h);
  }

  /** Whether this handle was released. */
  get isReleased(): boolean {
    return objc().isReleased(this.$h);
  }

  /** Runtime class name (`NSStringFromClass([obj class])`). */
  objcClassName(): string {
    return objc().className(this.$h);
  }

  /** Pointer identity. */
  isSameObject(other: ObjCObject | null): boolean {
    return other !== null && objc().isSameObject(this.$h, other.$h);
  }

  /** `-description` (or `[released]`). */
  toString(): string {
    return this.isReleased ? '[released]' : objc().describe(this.$h);
  }

  /** `-isKindOfClass:` / `-conformsToProtocol:` against a generated type. */
  isKindOf(cls: {readonly objcName: string; readonly objcProtocol?: boolean}): boolean {
    return cls.objcProtocol === true
      ? objc().conformsToProtocol(this.$h, cls.objcName)
      : objc().isKindOfClass(this.$h, cls.objcName);
  }

  /** Checked cast; the result shares this object's handle. */
  as<T extends ObjCObject>(cls: ObjCClass<T>): T {
    if (!this.isKindOf(cls)) {
      throw new TypeError(`Cannot cast ${this.objcClassName()} to ${cls.objcName}`);
    }
    return new cls(this.$h);
  }
}

/** A new `NSData` holding a copy of [bytes]. */
export function nsDataFromBytes(bytes: Uint8Array): ObjCObject {
  const buffer =
    bytes.byteOffset === 0 && bytes.byteLength === bytes.buffer.byteLength
      ? (bytes.buffer as ArrayBuffer)
      : (bytes.slice().buffer as ArrayBuffer);
  return new ObjCObject(objc().dataFromBytes(buffer));
}

/** A copy of the bytes of [data] (an `NSData`). */
export function bytesFromNSData(data: ObjCObject): Uint8Array {
  return new Uint8Array(objc().bytesOfData(data.$h));
}

/** The elements of [array] (an `NSArray`) as a JavaScript array. */
export function nsArrayItems(array: ObjCObject): ObjCObject[] {
  return objc().arrayItems(array.$h).map(h => new ObjCObject(h));
}

/** Writes [message] to the unified log via NSLog (works in release builds). */
export function nativeLog(message: string): void {
  objc().log(message);
}

/** Error for `NSError **` failures (created natively). */
export interface NativeObjCError extends Error {
  readonly domain: string;
  readonly code: number;
}

/** Type guard for {@link NativeObjCError}. */
export function isNativeObjCError(e: unknown): e is NativeObjCError {
  return e instanceof Error && e.name === 'NativeObjCError';
}

/** Error for an Objective-C exception raised by a call (created natively). */
export interface NativeObjCException extends Error {
  readonly exceptionName: string;
  readonly reason: string;
}

/** Type guard for {@link NativeObjCException}. */
export function isNativeObjCException(e: unknown): e is NativeObjCException {
  return e instanceof Error && e.name === 'NativeObjCException';
}

/** Thrown when a method declared non-null by the SDK returned nil. */
export class NativeNullError extends Error {
  constructor(symbol: string) {
    super(`${symbol} returned nil although the SDK declares it non-null`);
    this.name = 'NativeNullError';
  }
}

/** Thrown by availability guards (E012). */
export class NativeApiUnavailableError extends Error {
  constructor(readonly symbol: string, readonly required: string, readonly actual: string) {
    super(`E012 AVAILABILITY_MISMATCH: ${symbol} requires iOS ${required} (device: ${actual})`);
    this.name = 'NativeApiUnavailableError';
  }
}

function parseVersion(v: string): [number, number, number] {
  const p = v.split('.').map(x => parseInt(x, 10) || 0);
  return [p[0] ?? 0, p[1] ?? 0, p[2] ?? 0];
}

/** iOS version checks. */
export const IosApi = {
  /** Test hook: `"major.minor.patch"`, or undefined. */
  debugOverrideVersion: undefined as string | undefined,

  /** Running iOS version, `major.minor.patch`. */
  get version(): string {
    return IosApi.debugOverrideVersion ?? objc().iosVersion();
  },

  isAtLeast(major: number, minor = 0, patch = 0): boolean {
    const [a, b, c] = parseVersion(IosApi.version);
    if (a !== major) return a > major;
    if (b !== minor) return b > minor;
    return c >= patch;
  },

  require(major: number, minor: number, patch: number, symbol: string): void {
    if (IosApi.isAtLeast(major, minor, patch)) return;
    const required = patch === 0 ? `${major}.${minor}` : `${major}.${minor}.${patch}`;
    throw new NativeApiUnavailableError(symbol, required, IosApi.version);
  },
};

/** Shape of generated classes with ancestors. */
interface InheritingClass {
  prototype: object;
  $anc?: () => Array<{prototype: object}>;
}

const inherited = new WeakSet<object>();

/**
 * @internal Copies inherited members onto a generated class's prototype the
 * first time the class is instantiated (generated classes declare only their
 * own members and list ancestors, nearest first, in a `$anc` thunk).
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

/** @internal */
export function h(o: ObjCObject | null | undefined): Handle | null {
  return o === null || o === undefined ? null : o.$h;
}

/** @internal Wraps a raw handle (null stays null). */
export function wrap<T extends ObjCObject>(cls: new (h: Handle) => T, raw: unknown): T | null {
  return raw === null || raw === undefined ? null : new cls(raw as Handle);
}

/** @internal Wraps a raw handle that the SDK declares non-null. */
export function wrapNonNull<T extends ObjCObject>(cls: new (h: Handle) => T, raw: unknown, symbol: string): T {
  if (raw === null || raw === undefined) throw new NativeNullError(symbol);
  return new cls(raw as Handle);
}

/** @internal Checks a non-null-declared string result. */
export function nonNullString(raw: unknown, symbol: string): string {
  if (raw === null || raw === undefined) throw new NativeNullError(symbol);
  return raw as string;
}
