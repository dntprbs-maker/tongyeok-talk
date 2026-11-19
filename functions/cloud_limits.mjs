// Operator-owned configuration. Clients cannot write _workerControl.
export function translationPolicy(control = {}) {
  const limits = control.translationLimits;
  if (!limits) return {mode: 'legacy'};
  if (limits.mode === 'unlimited') return {mode: 'unlimited'};
  if (limits.mode !== 'daily') throw Error('invalid_translation_limits');
  const calls = limits.maxCallsPerDay, cost = limits.maxCostUsdPerDay;
  if (!(calls == null || Number.isSafeInteger(calls) && calls > 0) ||
      !(cost == null || Number.isFinite(cost) && cost > 0) ||
      calls == null && cost == null) throw Error('invalid_translation_limits');
  return {mode: 'daily', calls, cost};
}

export function koreaDay(now = new Date()) {
  return new Date(now.getTime() + 9 * 3600000).toISOString().slice(0, 10);
}
