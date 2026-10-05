/**
 * Unit tests for the TypeScript side of the native-api-bindgen runtime.
 * Native behaviour is covered on-device (src/selfTests.ts); here a fake
 * native root stands in for the C++ HostObject.
 */
jest.mock('../native-api-bindings/specs/NativeApiBindgen', () => ({
  __esModule: true,
  default: {install: () => true},
}));

import {
  AndroidApi,
  JavaObject,
  NativeApiUnavailableError,
  NativeCallbacks,
  hArray,
  isNativeJavaError,
  nab,
  voidCallback,
  wrap,
  wrapArray,
  wrapNonNull,
} from '../native-api-bindings/src/runtime';

const released = new Set<object>();
(globalThis as {__nab?: unknown}).__nab = {
  release: (h: object) => {
    if (released.has(h)) throw new Error('DoubleReleaseError');
    released.add(h);
  },
  isReleased: (h: object) => released.has(h),
  androidSdkInt: () => 34,
  androidSdkIntFull: () => 3400000,
};

class Thing extends JavaObject {
  static readonly javaInternalName = 'x/Thing';
}

test('installs lazily from the global root', () => {
  expect(nab().androidSdkInt()).toBe(34);
});

test('wrap / wrapNonNull / arrays', () => {
  const h = {};
  expect(wrap(Thing, null)).toBeNull();
  expect(wrap(Thing, h)?.$h).toBe(h);
  expect(() => wrapNonNull(Thing, null, 'x.Thing#get()')).toThrow('declares it non-null');
  const arr = wrapArray(Thing, [h, null], 1) as (Thing | null)[];
  expect(arr[0]).toBeInstanceOf(Thing);
  expect(arr[1]).toBeNull();
  expect(hArray([new Thing(h), null, 'text'])).toEqual([h, null, 'text']);
});

test('release is explicit, dispose is idempotent', () => {
  const t = new Thing({});
  t.dispose();
  t.dispose();
  expect(t.isReleased).toBe(true);
  expect(() => t.release()).toThrow('DoubleReleaseError');
});

test('availability guard', () => {
  expect(AndroidApi.isAtLeast(34)).toBe(true);
  expect(AndroidApi.isAtLeast(34, 1)).toBe(false);
  expect(() => AndroidApi.require(36, 1, 'a.B#c()')).toThrow(NativeApiUnavailableError);
  AndroidApi.debugOverrideFullVersion = 3600001;
  expect(() => AndroidApi.require(36, 1, 'a.B#c()')).not.toThrow();
  AndroidApi.debugOverrideFullVersion = undefined;
});

test('void callbacks report errors instead of throwing (default policy)', () => {
  const seen: string[] = [];
  NativeCallbacks.onError = (_e, symbol) => seen.push(symbol);
  const g = globalThis as {ErrorUtils?: unknown};
  const saved = g.ErrorUtils;
  const reportedErrors: unknown[] = [];
  g.ErrorUtils = {reportError: (e: unknown) => reportedErrors.push(e)};
  expect(() => voidCallback('a.B#run()', () => { throw new Error('boom'); })).not.toThrow();
  NativeCallbacks.policy = 'propagate';
  expect(() => voidCallback('a.B#run()', () => { throw new Error('boom'); })).toThrow('boom');
  NativeCallbacks.policy = 'report';
  NativeCallbacks.onError = undefined;
  g.ErrorUtils = saved;
  expect(seen).toEqual(['a.B#run()', 'a.B#run()']);
  expect(reportedErrors).toHaveLength(1);
});

test('isNativeJavaError', () => {
  const e = new Error('java.lang.IllegalStateException: x');
  e.name = 'NativeJavaError';
  expect(isNativeJavaError(e)).toBe(true);
  expect(isNativeJavaError(new Error('x'))).toBe(false);
});
