const {initializeApp} = require('firebase-admin/app');
const {getAuth} = require('firebase-admin/auth');
const {FieldValue, getFirestore} = require('firebase-admin/firestore');
const {getMessaging} = require('firebase-admin/messaging');
const {onCall, HttpsError} = require('firebase-functions/v2/https');
const {onDocumentCreated} = require('firebase-functions/v2/firestore');

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

exports.sendMessageNotification = onDocumentCreated(
  {
    region: 'us-central1',
    document: 'chat_rooms/{roomId}/messages/{messageId}',
  },
  async (event) => {
    const data = event.data?.data();
    if (!data) return;

    const {senderID, senderEmail, receiverID, message: text} = data;
    if (!senderID || !receiverID || !text) return;

    const db = getFirestore();

    // Check if receiver blocked the sender
    const isBlocked = (
      await db
        .collection('Users')
        .doc(receiverID)
        .collection('blocked_users')
        .doc(senderID)
        .get()
    ).exists;

    if (isBlocked) return;

    // Fetch receiver's FCM token
    const receiverDoc = await db.collection('Users').doc(receiverID).get();
    const fcmToken = receiverDoc.data()?.fcmToken;
    if (!fcmToken) return;

    // Dispatch push notification
    try {
      await getMessaging().send({
        token: fcmToken,
        notification: {
          title: senderEmail || 'New message',
          body: text.length > 100 ? `${text.substring(0, 100)}...` : text,
        },
        data: {
          senderID: senderID,
          senderEmail: senderEmail || '',
          roomId: event.params.roomId,
        },
      });
    } catch (error) {
      console.error('Failed to send FCM notification:', error);
    }
  }
);
