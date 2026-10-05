/**
 * Micro-benchmarks (TRD §35) of generated React Native bindings, run after
 * the self-tests in release builds. Returns metric -> value.
 */
import { Platform } from 'react-native';

import { Bundle, Uri } from '../native-api-bindings';
import {
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
    const fm = NSFileManager.defaultManager;
    r.promise_variant_us = await usPerAsyncCall(2000, () =>
      fm.fileExistsAtPathAsync('/'),
    );
  }
  return r;
}
