/**
 * Lets self-tests render an element into the running app (used to show a
 * native view created through the bindings).
 */
import type React from 'react';

let host: ((el: React.ReactElement | null) => void) | undefined;

export function registerTestHost(
  fn: (el: React.ReactElement | null) => void,
): void {
  host = fn;
}

export function showInTestHost(el: React.ReactElement | null): void {
  if (host === undefined) throw new Error('test host not mounted');
  host(el);
}
