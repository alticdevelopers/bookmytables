import * as functions from "firebase-functions";
import * as admin from "firebase-admin";

admin.initializeApp();

// Trigger when a new booking request is created
export const notifyNewBooking = functions.firestore
  .document("businesses/{slug}/requests/{requestId}")
  .onCreate(async (snap, context) => {
    const data = snap.data();
    const slug = context.params.slug;
    const customer = data.customerName || "Someone";
    const guests = data.guests || 2;
    const datetime = data.datetime?.toDate
      ? data.datetime.toDate().toLocaleString()
      : "soon";

    // Get restaurant owner info
    const bizRef = admin.firestore().collection("businesses").doc(slug);
    const bizSnap = await bizRef.get();
    if (!bizSnap.exists) return null;

    const ownerEmail = bizSnap.data()?.ownerEmail;
    if (!ownerEmail) {
      console.log("⚠️ No ownerEmail for", slug);
      return null;
    }

    // Find user's FCM tokens by email
    const userSnap = await admin
      .firestore()
      .collection("users")
      .where("email", "==", ownerEmail)
      .limit(1)
      .get();

    if (userSnap.empty) {
      console.log("⚠️ No user found for email", ownerEmail);
      return null;
    }

    const userDoc = userSnap.docs[0];
    const tokens: string[] = userDoc.data().fcmTokens || [];

    if (!tokens.length) {
      console.log("⚠️ No FCM tokens found for", ownerEmail);
      return null;
    }

    // Build the notification payload
    const payload: admin.messaging.MulticastMessage = {
      notification: {
        title: "🍽️ New Table Booking!",
        body: `${customer} requested a table for ${guests} on ${datetime}`,
      },
      data: {
        deep_link: "/dashboard",
      },
      tokens,
    };

    try {
      const res = await admin.messaging().sendMulticast(payload);
      console.log(`✅ Sent ${res.successCount} notification(s) for ${slug}`);
      return res;
    } catch (err) {
      console.error("❌ Error sending FCM:", err);
      return null;
    }
  });