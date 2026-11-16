const {initializeApp} = require('firebase-admin/app');
const {getAuth} = require('firebase-admin/auth');
const {FieldValue, getFirestore} = require('firebase-admin/firestore');
const {onCall, HttpsError} = require('firebase-functions/v2/https');

initializeApp();

async function deleteMatching(query, db) {
  while (true) {
    const page = await query.limit(250).get();
    if (page.empty) return;
    const batch = db.batch();
    for (const document of page.docs) batch.delete(document.ref);
    await batch.commit();
  }
}

exports.deleteAccount = onCall({region: 'us-central1', timeoutSeconds: 540, maxInstances: 3}, async (request) => {
  if (!request.auth) throw new HttpsError('unauthenticated', 'Sign in first.');
  const authTime = Number(request.auth.token.auth_time);
  if (!authTime || Date.now() / 1000 - authTime > 300) {
    throw new HttpsError('failed-precondition', 'Confirm your password again.');
  }

  // The caller's identity comes from Firebase, never from request data.
  const uid = request.auth.uid;
  const db = getFirestore();
  const deletion = db.collection('account_deletions').doc(uid);
  await deletion.set({requestedAt: FieldValue.serverTimestamp()});

  // The deletion marker prevents new messages and profile writes during cleanup.
  // Every step is safe to repeat if a previous attempt was interrupted.
  const rooms = await db.collection('chat_rooms').where('participantIds', 'array-contains', uid).get();
  for (const room of rooms.docs) {
    await deleteMatching(room.ref.collection('messages').where('senderID', '==', uid), db);
  }
  await deleteMatching(db.collectionGroup('blocked_users').where('userId', '==', uid), db);
  await deleteMatching(db.collection('reports').where('reporterId', '==', uid), db);
  await deleteMatching(db.collection('reports').where('reportedUserId', '==', uid), db);
  await db.recursiveDelete(db.collection('Users').doc(uid));
  try {
    await getAuth().deleteUser(uid);
  } catch (error) {
    if (error.code !== 'auth/user-not-found') throw error;
  }
  return {deleted: true};
});
