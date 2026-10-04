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
  maxWrongBuffer: 8, // wrong characters a run may stack up before the rest are ignored
  minVariation: 0.05, // stdev / mean: bots type with metronomic regularity
  wpmTolerance: 0.4, // wpm vs keystroke-interval estimate
  timeTolerance: 0.25, // wpm vs chars/typing-span estimate (the wall clock may be much longer)
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
  // typingMs is the active typing span; timeMs is the whole race from GO (includes reading time).
  // Only the typing span may be matched against the claimed WPM, otherwise honest players who
  // study the text before typing are rejected. Old clients send no typingMs: fall back to timeMs.
  const typingMs = Number.isFinite(p.typingMs) && p.typingMs > 0 ? p.typingMs : timeMs;
  if (typingMs < 1500 || typingMs > 30 * 60 * 1000) return { ok: false, reason: 'typing-duration' };
  if (timeMs < typingMs - 1000) return { ok: false, reason: 'time-inconsistent' };
  if (!Array.isArray(intervals) || intervals.length < L.minIntervals || intervals.length > L.maxIntervals) return { ok: false, reason: 'intervals-missing' };
  if (!intervals.every((n) => Number.isInteger(n) && n >= 0 && n <= 10000)) return { ok: false, reason: 'intervals-invalid' };
  // total typing time implied by the raw chars must roughly match the claimed WPM
  const estByTime = (chars / 5) / (typingMs / 60000);
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
  // When the client sends its raw keystroke log, the numbers above are not trusted any more: they
  // are re-derived from the keys and must agree.
  const replay = resimulate(p);
  if (!replay.ok) return replay;
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

/**
 * Replays a raw keystroke log and re-derives the result instead of believing it.
 *
 * `keys` is the flat log the client sends: triples of [dtMs, codeUnit, okFlag]. This is the same
 * rule set as `lib/core/anticheat/replay.dart`, so the device and the server judge one log the same
 * way. Without the text (the function does not carry the content catalog) the arithmetic is still
 * re-derived: counts, accuracy from the flags, the typing span, and the one impossible direction —
 * a claimed WPM faster than the keys allow.
 *
 * Returns { ok: true } or { ok: false, reason }.
 */
function resimulate(p, keysOverride) {
  const keys = keysOverride || (p && p.keys);
  if (!Array.isArray(keys) || keys.length === 0) return { ok: true, skipped: 'no-log' };
  if (keys.length % 3 !== 0) return { ok: false, reason: 'log-shape' };
  const n = keys.length / 3;
  // Backspace off: the client logs every wrong key on its own, so a long run proves nothing.
  const cap = p && p.bs === false ? 0 : DEFAULT_LIMITS.maxWrongBuffer;
  let correct = 0, wrong = 0, span = 0, buffer = 0;
  for (let i = 0; i < n; i++) {
    const dt = keys[i * 3], code = keys[i * 3 + 1], flag = keys[i * 3 + 2];
    if (!Number.isInteger(dt) || dt < 0 || dt > 1800000) return { ok: false, reason: 'log-timing' };
    if (!Number.isInteger(code) || code < 0 || code > 0xffff) return { ok: false, reason: 'log-code' };
    if (flag !== 0 && flag !== 1) return { ok: false, reason: 'log-flag' };
    span += dt;
    if (flag === 1) {
      // Backspace is not logged (it types nothing), so an accepted key after an error *is* the erase.
      buffer = 0;
      correct++;
    } else {
      if (cap > 0 && buffer >= cap) return { ok: false, reason: 'error-buffer-overflow' };
      buffer++;
      wrong++;
    }
  }
  if (p.full === false) return { ok: true, partial: true };
  if (correct !== p.chars) return { ok: false, reason: 'chars-mismatch' };
  const total = correct + wrong;
  if (total > 0) {
    const acc = (100 * correct) / total;
    if (Math.abs(acc - p.acc) > 0.6) return { ok: false, reason: 'accuracy-mismatch' };
  }
  const typingMs = n > 1 ? span : 0;
  // The claimed span is the race clock (it contains the reading time before the first key), so the
  // keys can only ever span less than it.
  if (typingMs > 0 && Number.isFinite(p.typingMs) && p.typingMs > 0 && typingMs > p.typingMs * 1.05 + 1500) {
    return { ok: false, reason: 'typing-span-mismatch' };
  }
  if (typingMs > 0 && p.wpm > 0) {
    const typingWpm = (correct / 5) / (typingMs / 60000);
    if (p.wpm > typingWpm * 1.05 + 2) return { ok: false, reason: 'wpm-above-log' };
  }
  return { ok: true, resimulated: { correct, wrong, typingMs } };
}

module.exports = { validateScore, resimulate, boardIds, weekKey, DEFAULT_LIMITS, median, mean, stdev };
