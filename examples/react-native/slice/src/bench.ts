/**
 * Micro-benchmarks (TRD §35) of generated React Native bindings, run after
 * the self-tests in release builds. Returns metric -> value.
 */
import { Platform } from 'react-native';

import { Arrays, Bundle, Uri } from '../native-api-bindings';
import {
  bytesFromNSData,
  nsDataFromBytes,
  NSFileManager,
  NSProcessInfo,
  UIView,
} from '../native-api-bindings/ios';

/** High-resolution clock provided by React Native (Web Performance API). */
declare const performance: { now(): number };

function nsPerCall(n: number, f: () => unknown): number {
  for (let i = 0; i < n / 10; i++) f();
  const t0 = performance.now();
  for (let i = 0; i < n; i++) f();
  return Math.round(((performance.now() - t0) * 1e6) / n);
}

function usPerCall(n: number, f: () => unknown): number {
  f();
  const t0 = performance.now();
  for (let i = 0; i < n; i++) f();
  return Math.round(((performance.now() - t0) * 1e3) / n);
}

async function usPerAsyncCall(
  n: number,
  f: () => Promise<unknown>,
): Promise<number> {
  for (let i = 0; i < n / 10; i++) await f();
  const t0 = performance.now();
  for (let i = 0; i < n; i++) await f();
  return Math.round(((performance.now() - t0) * 1e3) / n);
}

export async function benchmarks(): Promise<Record<string, number>> {
  const r: Record<string, number> = {};
  if (Platform.OS === 'android') {
    const bundle = Bundle.new();
    r.jsi_jni_instance_call_int_ns = nsPerCall(100000, () => bundle.size());
    r.jsi_jni_static_call_object_ns = nsPerCall(20000, () =>
      Uri.parse('https://example.com/path?q=1')?.release(),
    );
    const uri = Uri.parse('https://example.com/path?q=1');
    r.jsi_jni_string_return_ns = nsPerCall(20000, () => uri?.toString());
    r.promise_variant_us = await usPerAsyncCall(2000, () => bundle.sizeAsync());
    for (const [label, size] of [['1mb', 1 << 20], ['16mb', 16 << 20]] as const) {
      const data = new Uint8Array(size).fill(7);
      r[`jsi_jni_bytes_roundtrip_${label}_us`] = usPerCall(10, () => {
        if (Arrays.copyOf(data, size).length !== size) throw new Error('size');
      });
    }
    const plain = Array.from(new Uint8Array(1 << 20).fill(7));
    r.jsi_jni_number_array_roundtrip_1mb_us = usPerCall(3, () => {
      if (Arrays.copyOf(plain, plain.length).length !== plain.length) throw new Error('size');
    });
  } else {
    const info = NSProcessInfo.processInfo;
    r.jsi_objc_getter_int_ns = nsPerCall(
      100000,
      () => info.activeProcessorCount,
    );
    r.jsi_objc_class_getter_object_ns = nsPerCall(20000, () =>
      NSProcessInfo.processInfo.release(),
    );
    r.jsi_objc_string_return_ns = nsPerCall(20000, () => info.processName);
    const view = UIView.new$();
    r.jsi_objc_uikit_getter_main_thread_ns = nsPerCall(20000, () => view.tag);
    r.jsi_objc_uikit_struct_roundtrip_ns = nsPerCall(10000, () => {
      view.frame = view.frame;
    });
    for (const [label, size] of [['1mb', 1 << 20], ['16mb', 16 << 20]] as const) {
      const data = new Uint8Array(size).fill(7);
      r[`jsi_objc_nsdata_roundtrip_${label}_us`] = usPerCall(10, () => {
        const d = nsDataFromBytes(data);
        if (bytesFromNSData(d).length !== size) throw new Error('size');
        d.release();
      });
    }
    const fm = NSFileManager.defaultManager;
    r.promise_variant_us = await usPerAsyncCall(2000, () =>
      fm.fileExistsAtPathAsync('/'),
    );
  }
  return r;
}
