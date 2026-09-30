'use strict';
// Server-side plausibility checks for leaderboard submissions. Pure functions (unit tested in test/antiCheat.test.js).

const DEFAULT_LIMITS = {
  maxWpm: 240, // hard ceiling for a human on a keyboard (world record is ~216 WPM sustained)
  minWpm: 5,
  minAccuracy: 80,
  minChars: 30,
  maxChars: 1200,
  minIntervals: 20,
  maxIntervals: 600,
  minMedianIntervalMs: 30,
  maxFastShare: 0.15, // share of keystroke intervals below 25 ms
  minVariation: 0.05, // stdev / mean: bots type with metronomic regularity
  wpmTolerance: 0.4, // wpm vs keystroke-interval estimate
  timeTolerance: 0.45, // wpm vs chars/time estimate
};

function median(a) {
  const s = [...a].sort((x, y) => x - y);
  const m = Math.floor(s.length / 2);
  return s.length % 2 ? s[m] : (s[m - 1] + s[m]) / 2;
}
function mean(a) { return a.reduce((x, y) => x + y, 0) / a.length; }
function stdev(a) { const m = mean(a); return Math.sqrt(mean(a.map((x) => (x - m) ** 2))); }

/** Returns { ok: true } or { ok: false, reason }. */
function validateScore(p, limitsOverride = {}) {
  const L = { ...DEFAULT_LIMITS, ...limitsOverride };
  if (!p || typeof p !== 'object') return { ok: false, reason: 'bad-payload' };
  const { wpm, acc, chars, timeMs, intervals } = p;
  if (![wpm, acc, chars, timeMs].every((n) => typeof n === 'number' && Number.isFinite(n))) return { ok: false, reason: 'bad-number' };
  if (wpm < L.minWpm) return { ok: false, reason: 'too-slow-to-rank' };
  if (wpm > L.maxWpm) return { ok: false, reason: 'wpm-above-human-limit' };
  if (acc < L.minAccuracy || acc > 100) return { ok: false, reason: 'accuracy' };
  if (chars < L.minChars || chars > L.maxChars) return { ok: false, reason: 'length' };
  if (timeMs < 2000 || timeMs > 30 * 60 * 1000) return { ok: false, reason: 'duration' };
  if (!Array.isArray(intervals) || intervals.length < L.minIntervals || intervals.length > L.maxIntervals) return { ok: false, reason: 'intervals-missing' };
  if (!intervals.every((n) => Number.isInteger(n) && n >= 0 && n <= 10000)) return { ok: false, reason: 'intervals-invalid' };
  // total typing time implied by the raw chars must roughly match the claimed WPM
  const estByTime = (chars / 5) / (timeMs / 60000);
  if (Math.abs(estByTime - wpm) / wpm > L.timeTolerance) return { ok: false, reason: 'wpm-time-mismatch' };
  const med = median(intervals);
  if (med < L.minMedianIntervalMs) return { ok: false, reason: 'keystrokes-too-fast' };
  const fast = intervals.filter((n) => n < 25).length / intervals.length;
  if (fast > L.maxFastShare) return { ok: false, reason: 'burst-input' };
  const m = mean(intervals);
  if (m <= 0) return { ok: false, reason: 'intervals-zero' };
  if (stdev(intervals) / m < L.minVariation) return { ok: false, reason: 'robotic-timing' };
  // keystroke intervals imply a typing speed; the claimed WPM must be in the same ballpark
  const estByKeys = 60000 / m / 5;
  if (estByKeys < wpm * (1 - L.wpmTolerance) * 0.6 || estByKeys > wpm * (1 + L.wpmTolerance) * 2.2) return { ok: false, reason: 'wpm-interval-mismatch' };
  return { ok: true };
}

function weekKey(d) {
  const date = new Date(Date.UTC(d.getUTCFullYear(), d.getUTCMonth(), d.getUTCDate()));
  const dow = (date.getUTCDay() + 6) % 7; // Monday = 0
  date.setUTCDate(date.getUTCDate() - dow);
  return date.toISOString().slice(0, 10);
}

function boardIds(country, now = new Date()) {
  const ids = ['global', `weekly_${weekKey(now)}`, `monthly_${now.getUTCFullYear()}${String(now.getUTCMonth() + 1).padStart(2, '0')}`];
  if (country && /^[A-Za-z]{2}$/.test(country)) ids.push(`country_${country.toUpperCase()}`);
  return ids;
}

module.exports = { validateScore, boardIds, weekKey, DEFAULT_LIMITS, median, mean, stdev };
