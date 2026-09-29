const {onValueWritten} = require("firebase-functions/v2/database");
const {setGlobalOptions} = require("firebase-functions");
const admin = require("firebase-admin");

admin.initializeApp();

setGlobalOptions({
  maxInstances: 10,
});

// ============================================================
// BOREWELL GUARD — EMERGENCY NOTIFICATION
// ============================================================
//
// Firebase Realtime Database:
//
// borewell_guard/sensor
//
// When:
//   humanDetected == true
//   AND
//   distance <= dangerDistance
//
// Send FCM notification to registered users.
// ============================================================

exports.borewellDangerAlert = onValueWritten(
    {
      ref: "/borewell_guard/sensor",
      region: "us-central1",
    },
    async (event) => {
      const after = event.data.after.val();

      if (!after) {
        return null;
      }

      const humanDetected = after.humanDetected === true;
      const distance = Number(after.distance);

      if (!humanDetected || !Number.isFinite(distance)) {
        return null;
      }

      // Read configured danger distance
      const settingsSnapshot = await admin
          .database()
          .ref("/borewell_guard/settings/dangerDistance")
          .once("value");

      const dangerDistance = Number(
  settingsSnapshot.val() === null ? 2 : settingsSnapshot.val(),
      );
      // Outside danger zone
      if (distance > dangerDistance) {
        return null;
      }

      // ========================================================
      // GET FCM TOKENS FROM:
      //
      // owners/<userId>/fcmToken
      // ========================================================

      const ownersSnapshot = await admin
          .database()
          .ref("/owners")
          .once("value");

      const ownersData = ownersSnapshot.val();

      if (!ownersData) {
        console.log("No owners found.");
        return null;
      }

      const tokens = [];

      Object.values(ownersData).forEach((owner) => {
        if (
          owner &&
        typeof owner.fcmToken === "string" &&
        owner.fcmToken.length > 0
        ) {
          tokens.push(owner.fcmToken);
        }
      });

      if (tokens.length === 0) {
        console.log("No valid FCM tokens found.");
        return null;
      }

      console.log(`Found ${tokens.length} FCM device token(s).`);

      // ========================================================
      // FCM MESSAGE
      // ========================================================

      const message = {
        notification: {
          title: "🚨 BOREWELL DANGER ALERT",
          body:
          `Human detected ${distance.toFixed(1)} m from the borewell. ` +
          "Please check immediately!",
        },

        data: {
          type: "BOREWELL_DANGER",
          distance: distance.toFixed(1),
          dangerDistance: dangerDistance.toFixed(1),
          humanDetected: "true",
        },

        android: {
          priority: "high",

          notification: {
            channelId: "borewell_emergency",
            priority: "max",
            visibility: "public",
          },
        },

        tokens: tokens,
      };

      try {
        const response =
        await admin.messaging().sendEachForMulticast(message);

        console.log(
            `Notification sent: ${response.successCount} successful, ` +
        `${response.failureCount} failed.`,
        );

        return null;
      } catch (error) {
        console.error("Error sending notification:", error);
        return null;
      }
    },
);
