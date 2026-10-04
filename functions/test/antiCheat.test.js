'use strict';
const test = require('node:test');
const assert = require('node:assert');
const { validateScore, resimulate, boardIds, weekKey } = require('../antiCheat');

function humanIntervals(n, meanMs, jitter = 0.35, seed = 1) {
  let s = seed;
  const rnd = () => { s = (s * 16807) % 2147483647; return s / 2147483647; };
  return Array.from({ length: n }, () => Math.max(40, Math.round(meanMs * (1 + (rnd() - 0.5) * 2 * jitter))));
}
function payload(over = {}) {
  const wpm = 60, chars = 300, meanMs = 60000 / (wpm * 5);
  return { wpm, acc: 96, chars, timeMs: Math.round((chars / 5) / wpm * 60000), intervals: humanIntervals(300, meanMs), ...over };
}

test('a normal human run is accepted', () => { assert.deepStrictEqual(validateScore(payload()), { ok: true }); });
test('fast but plausible typists are accepted', () => {
  const wpm = 140, meanMs = 60000 / (wpm * 5);
  assert.ok(validateScore(payload({ wpm, timeMs: Math.round((300 / 5) / wpm * 60000), intervals: humanIntervals(300, meanMs, 0.3, 4) })).ok);
});
test('above the human limit is rejected', () => { assert.strictEqual(validateScore(payload({ wpm: 400 })).reason, 'wpm-above-human-limit'); });
test('too slow to rank / bad accuracy / bad length', () => {
  assert.strictEqual(validateScore(payload({ wpm: 2 })).reason, 'too-slow-to-rank');
  assert.strictEqual(validateScore(payload({ acc: 60 })).reason, 'accuracy');
  assert.strictEqual(validateScore(payload({ chars: 5 })).reason, 'length');
});
test('missing or invalid keystroke data is rejected', () => {
  assert.strictEqual(validateScore(payload({ intervals: [] })).reason, 'intervals-missing');
  assert.strictEqual(validateScore(payload({ intervals: Array(100).fill(-5) })).reason, 'intervals-invalid');
  assert.strictEqual(validateScore(null).reason, 'bad-payload');
  assert.strictEqual(validateScore(payload({ wpm: 'x' })).reason, 'bad-number');
});
test('pasted / macro input (near-zero intervals) is rejected', () => {
  assert.strictEqual(validateScore(payload({ intervals: Array(300).fill(3) })).reason, 'keystrokes-too-fast');
  const burst = humanIntervals(300, 200).map((n, i) => (i % 5 === 0 ? 2 : n));
  assert.strictEqual(validateScore(payload({ intervals: burst })).reason, 'burst-input');
});
test('metronomic bots are rejected', () => { assert.strictEqual(validateScore(payload({ intervals: Array(300).fill(200) })).reason, 'robotic-timing'); });
test('wpm must match the duration', () => { assert.strictEqual(validateScore(payload({ timeMs: 200000 })).reason, 'wpm-time-mismatch'); });
test('wpm must match the keystroke rhythm', () => {
  const slowKeys = humanIntervals(300, 600);
  assert.strictEqual(validateScore(payload({ intervals: slowKeys })).reason, 'wpm-interval-mismatch');
});
test('reading the text before typing is not punished (typing span vs wall clock)', () => {
  // 300 chars at 60 wpm = 60 s of typing; the player studied the text for 9 s first.
  assert.deepStrictEqual(validateScore(payload({ typingMs: 60000, timeMs: 69000 })), { ok: true });
  // typing faster than the race is impossible (clock skew would show up here)
  assert.strictEqual(validateScore(payload({ typingMs: 60000, timeMs: 5000 })).reason, 'time-inconsistent');
  // a nonsense typing span is rejected
  assert.strictEqual(validateScore(payload({ typingMs: 500 })).reason, 'typing-duration');
});

test('limits can be tightened remotely', () => { assert.strictEqual(validateScore(payload({ wpm: 60 }), { maxWpm: 50 }).reason, 'wpm-above-human-limit'); });
test('boards: global + weekly + monthly (+ country)', () => {
  const ids = boardIds('ma', new Date(Date.UTC(2026, 9, 7)));
  assert.deepStrictEqual(ids, ['global', 'weekly_2026-10-05', 'monthly_202610', 'country_MA']);
  assert.deepStrictEqual(boardIds('', new Date(Date.UTC(2026, 0, 1))).length, 3);
  assert.strictEqual(weekKey(new Date(Date.UTC(2026, 9, 5))), '2026-10-05');
  assert.strictEqual(weekKey(new Date(Date.UTC(2026, 9, 11))), '2026-10-05');
});

// --- re-simulation: the raw keystroke log is replayed instead of trusted -------------------
function honestLog(chars, wpm, errors = 0, seed = 7) {
  let s = seed;
  const rnd = () => { s = (s * 16807) % 2147483647; return s / 2147483647; };
  const meanMs = 60000 / (wpm * 5);
  const out = [];
  let i = 0, e = 0;
  while (i < chars) {
    const dt = Math.max(35, Math.round(meanMs * (1 + (rnd() - 0.5) * 0.7)));
    if (e < errors && i > 0 && i % Math.floor(chars / (errors + 1)) === 0) { out.push(dt, 0, 0); e++; continue; }
    out.push(dt, 97 + (i % 26), 1);
    i++;
  }
  return out;
}
function logPayload(over = {}) {
  const chars = 300, wpm = 60, errors = 6;
  const keys = honestLog(chars, wpm, errors);
  const total = chars + errors;
  const typingMs = keys.filter((_, i) => i % 3 === 0).reduce((a, b) => a + b, 0);
  return {
    wpm, acc: Math.round((100 * chars) / total * 10) / 10, chars, timeMs: Math.round((chars / 5) / wpm * 60000) + 3000,
    // the client's span is the race clock: it starts before the first key (reading time)
    typingMs: typingMs + 2000, intervals: humanIntervals(total, typingMs / total), keys, ...over,
  };
}

test('an honest log replays to the same numbers', () => {
  const r = resimulate(logPayload());
  assert.strictEqual(r.ok, true);
  assert.strictEqual(r.resimulated.correct, 300);
});

test('a log that does not add up is rejected', () => {
  const p = logPayload();
  const short = p.keys.slice(0, p.keys.length - 30); // the claimed character count has no keys behind it
  assert.strictEqual(resimulate({ ...p, keys: short }).reason, 'chars-mismatch');
});

test('a run of errors longer than the engine can hold is rejected', () => {
  const p = logPayload();
  const keys = [40, 122, 0];
  for (let i = 0; i < 12; i++) keys.push(80, 122, 0); // twelve wrong keys with nothing accepted between
  assert.strictEqual(resimulate({ ...p, keys }).reason, 'error-buffer-overflow');
});

test('an inflated accuracy is rejected', () => {
  const p = logPayload();
  assert.strictEqual(resimulate({ ...p, acc: 99.9 }).reason, 'accuracy-mismatch');
});

test('an inflated WPM is rejected: the keys themselves set the ceiling', () => {
  const p = logPayload();
  assert.strictEqual(resimulate({ ...p, wpm: 400 }).reason, 'wpm-above-log');
});

test('a truncated log is accepted as partial, never as proof', () => {
  const p = logPayload();
  const r = resimulate({ ...p, keys: p.keys.slice(0, 60), full: false });
  assert.deepStrictEqual(r, { ok: true, partial: true });
});

test('with backspace off, long error runs are legitimate', () => {
  const keys = [];
  for (let i = 0; i < 12; i++) keys.push(200, 120, 0);
  const p = { wpm: 0, acc: 0, chars: 0, timeMs: 4000, typingMs: 4000, bs: false, keys };
  assert.strictEqual(resimulate(p).ok, true);
  assert.strictEqual(resimulate({ ...p, bs: true }).reason, 'error-buffer-overflow');
});

test('malformed logs are rejected', () => {
  const p = logPayload();
  assert.strictEqual(resimulate({ ...p, keys: [1, 2] }).reason, 'log-shape');
  assert.strictEqual(resimulate({ ...p, keys: [1, 97, 2, 1, 97, 1] }).reason, 'log-flag');
  assert.strictEqual(resimulate({ ...p, keys: [-5, 97, 1, 5, 97, 1] }).reason, 'log-timing');
});

test('a client with no log is still judged by the interval checks', () => {
  assert.deepStrictEqual(resimulate({ wpm: 60, acc: 96, chars: 300, typingMs: 60000 }), { ok: true, skipped: 'no-log' });
});
