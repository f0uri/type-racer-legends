'use strict';
const admin = require('firebase-admin');
const { onCall, HttpsError } = require('firebase-functions/v2/https');
const { onDocumentWritten } = require('firebase-functions/v2/firestore');
const { setGlobalOptions, logger } = require('firebase-functions/v2');
const v1 = require('firebase-functions/v1');
const { validateScore, boardIds, DEFAULT_LIMITS } = require('./antiCheat');

admin.initializeApp();
const db = admin.firestore();
setGlobalOptions({ region: 'europe-west1', maxInstances: 10 });

const need = (req) => {
  if (!req.auth) throw new HttpsError('unauthenticated', 'Sign in first');
  return req.auth.uid;
};

async function limits() {
  try {
    const d = await db.doc('config/limits').get();
    return d.exists ? { ...DEFAULT_LIMITS, ...d.data() } : DEFAULT_LIMITS;
  } catch (e) {
    return DEFAULT_LIMITS;
  }
}

/** Small per-user rate limiter (N calls per hour). */
async function rateLimit(uid, key, max) {
  const ref = db.doc(`users/${uid}/meta/rate_${key}`);
  const hour = Math.floor(Date.now() / 3600000);
  await db.runTransaction(async (tx) => {
    const s = await tx.get(ref);
    const d = s.exists && s.data().hour === hour ? s.data() : { hour, n: 0 };
    if (d.n >= max) throw new HttpsError('resource-exhausted', 'Too many requests');
    tx.set(ref, { hour, n: d.n + 1 });
  });
}

/**
 * Validates a leaderboard score (WPM ceiling, keystroke timing, consistency) and writes it to the boards.
 * Suspicious submissions are stored in /flagged and never reach a board.
 */
exports.submitScore = onCall(async (req) => {
  const uid = need(req);
  await rateLimit(uid, 'score', 40);
  const p = req.data || {};
  const verdict = validateScore(p, await limits());
  if (!verdict.ok) {
    await db.collection('flagged').add({ uid, reason: verdict.reason, wpm: p.wpm ?? null, at: admin.firestore.FieldValue.serverTimestamp(), payload: JSON.stringify(p).slice(0, 4000) });
    const f = db.doc(`users/${uid}/meta/flags`);
    await f.set({ count: admin.firestore.FieldValue.increment(1), last: admin.firestore.FieldValue.serverTimestamp() }, { merge: true });
    return { ok: false, reason: verdict.reason };
  }
  // trust nothing from the client profile except what the server stored
  const user = (await db.doc(`users/${uid}`).get()).data() || {};
  let blob = {};
  try { blob = JSON.parse(user.blob || '{}'); } catch (e) { /* ignore */ }
  const flags = (await db.doc(`users/${uid}/meta/flags`).get()).data() || {};
  if ((flags.count || 0) >= 5) return { ok: false, reason: 'account-under-review' };
  const entry = {
    uid, name: String(user.name || 'Player').slice(0, 24), cc: String(user.country || '').slice(0, 2).toUpperCase(),
    title: String(blob.title || '').slice(0, 40), avatar: Number(blob.avatar) || 0, tier: Math.min(6, Math.max(0, Math.floor((Number(user.rankPoints) || 0) / 400))),
    wpm: Math.round(p.wpm * 10) / 10, acc: Math.round(p.acc * 10) / 10, textId: String(p.textId || '').slice(0, 40), mode: String(p.mode || ''), at: admin.firestore.FieldValue.serverTimestamp(),
  };
  const ids = boardIds(entry.cc);
  await Promise.all(ids.map((id) => db.runTransaction(async (tx) => {
    const ref = db.doc(`leaderboards/${id}/entries/${uid}`);
    const cur = await tx.get(ref);
    if (!cur.exists || cur.data().wpm < entry.wpm) tx.set(ref, entry);
  })));
  return { ok: true, boards: ids };
});

/**
 * Verifies a Google Play purchase with the Play Developer API.
 * Needs the service account (see TODO_MANUAL.md). Until configured it answers {valid: null} so the app can deliver provisionally.
 */
exports.verifyPurchase = onCall(async (req) => {
  const uid = need(req);
  await rateLimit(uid, 'purchase', 30);
  const { productId, purchaseToken } = req.data || {};
  if (typeof productId !== 'string' || typeof purchaseToken !== 'string') throw new HttpsError('invalid-argument', 'bad request');
  const packageName = process.env.ANDROID_PACKAGE || 'com.typeracerlegends.game';
  try {
    const { google } = require('googleapis');
    const auth = new google.auth.GoogleAuth({ scopes: ['https://www.googleapis.com/auth/androidpublisher'] });
    const pub = google.androidpublisher({ version: 'v3', auth });
    const r = await pub.purchases.products.get({ packageName, productId, token: purchaseToken });
    const ok = r.data && r.data.purchaseState === 0;
    await db.collection('purchases').doc(purchaseToken.slice(0, 120).replace(/\//g, '_')).set({ uid, productId, valid: !!ok, at: admin.firestore.FieldValue.serverTimestamp() }, { merge: true });
    return { valid: !!ok };
  } catch (e) {
    logger.warn('verifyPurchase not configured or failed', e.message);
    return { valid: null, reason: 'verification-unavailable' };
  }
});

// ---------------------------------------------------------------------------------------------------- referrals
const REFERRAL = { level: 5, inviterReward: { coins: 3000, gems: 30 }, inviteeReward: { coins: 2000, gems: 20 } };

/** The new player enters a friend's code (once). */
exports.redeemReferral = onCall(async (req) => {
  const uid = need(req);
  await rateLimit(uid, 'referral', 10);
  const code = String((req.data || {}).code || '').trim().toUpperCase();
  if (!/^[A-Z0-9]{4,10}$/.test(code)) throw new HttpsError('invalid-argument', 'bad code');
  const mine = await db.doc(`users/${uid}`).get();
  if (!mine.exists) throw new HttpsError('failed-precondition', 'sync first');
  if (mine.data().refCode === code) throw new HttpsError('failed-precondition', 'own code');
  const q = await db.collection('users').where('refCode', '==', code).limit(1).get();
  if (q.empty) throw new HttpsError('not-found', 'unknown code');
  const inviter = q.docs[0].id;
  const ref = db.doc(`referrals/${uid}`);
  await db.runTransaction(async (tx) => {
    const s = await tx.get(ref);
    if (s.exists) throw new HttpsError('already-exists', 'already redeemed');
    tx.set(ref, { invitee: uid, inviter, at: admin.firestore.FieldValue.serverTimestamp(), inviteeClaimed: false, inviterClaimed: false });
  });
  return { ok: true };
});

/** Returns the rewards this user may collect now (as invitee and as inviter). The app applies them; flags make them one-time. */
exports.claimReferralRewards = onCall(async (req) => {
  const uid = need(req);
  await rateLimit(uid, 'referral_claim', 30);
  let coins = 0, gems = 0, invitees = 0;
  const me = (await db.doc(`users/${uid}`).get()).data() || {};
  // as invitee
  const own = db.doc(`referrals/${uid}`);
  await db.runTransaction(async (tx) => {
    const s = await tx.get(own);
    if (s.exists && !s.data().inviteeClaimed && (me.level || 1) >= REFERRAL.level) {
      tx.update(own, { inviteeClaimed: true });
      coins += REFERRAL.inviteeReward.coins; gems += REFERRAL.inviteeReward.gems;
    }
  });
  // as inviter: every invitee that reached the level
  const mine = await db.collection('referrals').where('inviter', '==', uid).where('inviterClaimed', '==', false).limit(20).get();
  for (const d of mine.docs) {
    const invitee = (await db.doc(`users/${d.id}`).get()).data() || {};
    if ((invitee.level || 1) < REFERRAL.level) continue;
    const ok = await db.runTransaction(async (tx) => {
      const s = await tx.get(d.ref);
      if (!s.exists || s.data().inviterClaimed) return false;
      tx.update(d.ref, { inviterClaimed: true });
      return true;
    });
    if (ok) { coins += REFERRAL.inviterReward.coins; gems += REFERRAL.inviterReward.gems; invitees += 1; }
  }
  return { coins, gems, invitees };
});

// ---------------------------------------------------------------------------------------------------- announcements (FCM)
/**
 * Writing config/announcement = { id, title, body, topic? } in the Firebase console sends a push to the topic
 * (default "events"; use "all" for everyone). The app subscribes to both topics (events only if the player allows it).
 */
exports.onAnnouncement = onDocumentWritten('config/announcement', async (event) => {
  const after = event.data && event.data.after && event.data.after.exists ? event.data.after.data() : null;
  const before = event.data && event.data.before && event.data.before.exists ? event.data.before.data() : null;
  if (!after || !after.title || !after.body) return;
  if (before && before.id === after.id && after.id) return; // same announcement: do not resend
  const topic = ['all', 'events'].includes(after.topic) ? after.topic : 'events';
  await admin.messaging().send({ topic, notification: { title: String(after.title).slice(0, 80), body: String(after.body).slice(0, 240) }, android: { priority: 'normal', notification: { channelId: 'trl_main' } } });
  logger.info('announcement sent', { topic, id: after.id });
});

// ---------------------------------------------------------------------------------------------------- backups + deletion
/** Keeps three rotating cloud backups of every user profile (restore from the app). */
exports.onUserWrite = onDocumentWritten('users/{uid}', async (event) => {
  const after = event.data && event.data.after && event.data.after.exists ? event.data.after.data() : null;
  if (!after || !after.blob) return;
  const uid = event.params.uid;
  const slotRef = db.doc(`users/${uid}/backups/_state`);
  const state = (await slotRef.get()).data() || { slot: 0, lastAt: 0 };
  // at most one backup every 30 minutes
  if (Date.now() - (state.lastAt || 0) < 30 * 60 * 1000) return;
  const slot = (state.slot + 1) % 3;
  await db.doc(`users/${uid}/backups/${slot}`).set({ blob: after.blob, rev: after.rev || 0, at: admin.firestore.FieldValue.serverTimestamp() });
  await slotRef.set({ slot, lastAt: Date.now() });
});

async function wipeUser(uid) {
  const subs = ['backups', 'meta'];
  for (const s of subs) {
    const docs = await db.collection(`users/${uid}/${s}`).listDocuments();
    await Promise.all(docs.map((d) => d.delete()));
  }
  await Promise.all([db.doc(`users/${uid}`).delete(), db.doc(`fcmTokens/${uid}`).delete(), db.doc(`referrals/${uid}`).delete()]);
  // remove from leaderboards
  const boards = await db.collection('leaderboards').listDocuments();
  await Promise.all(boards.map((b) => b.collection('entries').doc(uid).delete()));
}

/** Account deletion requested from the app. */
exports.deleteAccountData = onCall(async (req) => {
  const uid = need(req);
  await wipeUser(uid);
  return { ok: true };
});

/** Safety net: also wipe data if the auth user is deleted elsewhere. */
exports.onAuthDelete = v1.region('europe-west1').auth.user().onDelete(async (user) => { await wipeUser(user.uid); });
