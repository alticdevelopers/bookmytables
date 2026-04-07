import { onDocumentCreated } from "firebase-functions/v2/firestore";
import { logger } from "firebase-functions";
import * as admin from "firebase-admin";

admin.initializeApp();

// Trigger when a new booking request is created
export const notifyNewBooking = onDocumentCreated(
  "businesses/{slug}/requests/{requestId}",
  async (event) => {
    const snap = event.data;
    if (!snap) return null;

    const data = snap.data();
    const slug = event.params.slug;
    const requestId = event.params.requestId;
    const customer = data["customerName"] || "Someone";
    const guests = data["guests"] || 2;
    const datetime = data["datetime"]?.toDate
      ? data["datetime"].toDate().toLocaleString()
      : "soon";

    const title = "New Table Booking!";
    const body = `${customer} requested a table for ${guests} — Tap to view`;

    // Get restaurant owner info
    const bizRef = admin.firestore().collection("businesses").doc(slug);
    const bizSnap = await bizRef.get();
    if (!bizSnap.exists) return null;

    const ownerEmail = bizSnap.data()?.["ownerEmail"];
    if (!ownerEmail) {
      logger.warn("⚠️ No ownerEmail for", slug);
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
      logger.warn("⚠️ No user found for email", ownerEmail);
      return null;
    }

    const userDoc = userSnap.docs[0];
    const tokens: string[] = userDoc.data()["fcmTokens"] || [];

    if (!tokens.length) {
      logger.warn("⚠️ No FCM tokens found for", ownerEmail);
      return null;
    }

    // Build the notification payload
    const payload: admin.messaging.MulticastMessage = {
      notification: {
        title,
        body,
      },
      android: {
        notification: {
          channelId: "book_my_tables_default_channel",
          priority: "high",
        },
      },
      apns: {
        payload: {
          aps: {
            sound: "default",
            badge: 1,
          },
        },
      },
      data: {
        bookingId: String(requestId),
        customerName: String(customer),
        guests: String(guests),
        datetime: String(datetime),
        deep_link: "/dashboard",
        title,
        body,
      },
      tokens,
    };

    try {
      const res = await admin.messaging().sendEachForMulticast(payload);
      logger.info(`✅ Sent ${res.successCount} notification(s) for ${slug}`);

      // Clean up stale/invalid tokens
      const staleTokens: string[] = [];
      res.responses.forEach((resp, idx) => {
        if (!resp.success) {
          const errCode = resp.error?.code;
          if (
            errCode === "messaging/invalid-registration-token" ||
            errCode === "messaging/registration-token-not-registered"
          ) {
            staleTokens.push(tokens[idx]);
          }
          logger.warn(`Token ${tokens[idx]} failed: ${errCode}`);
        }
      });

      // Remove stale tokens from the user's fcmTokens array
      if (staleTokens.length > 0) {
        await userDoc.ref.update({
          fcmTokens: admin.firestore.FieldValue.arrayRemove(...staleTokens),
        });
        logger.info(`🧹 Cleaned up ${staleTokens.length} stale token(s)`);
      }

      return res;
    } catch (err) {
      logger.error("❌ Error sending FCM:", err);
      return null;
    }
  }
);
