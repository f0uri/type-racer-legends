'use strict';
const test = require('node:test');
const assert = require('node:assert');
const { validateScore, boardIds, weekKey } = require('../antiCheat');

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
