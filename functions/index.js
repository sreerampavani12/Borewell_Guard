const { onValueWritten } = require("firebase-functions/v2/database");
const { setGlobalOptions } = require("firebase-functions");
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
// borewell_guard/sensor
//
// When:
//   humanDetected == true
//   AND
//   distance <= dangerDistance
//
// Firebase Cloud Function sends an FCM notification.
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

    const dangerDistance = Number(settingsSnapshot.val() ?? 2);

    // Human is detected but outside danger zone
    if (distance > dangerDistance) {
      return null;
    }

    // Get all registered device tokens
    const tokensSnapshot = await admin
      .database()
      .ref("/deviceTokens")
      .once("value");

    const tokensData = tokensSnapshot.val();

    if (!tokensData) {
      console.log("No FCM device tokens found.");
      return null;
    }

    const tokens = [];

    Object.values(tokensData).forEach((value) => {
      if (typeof value === "string" && value.length > 0) {
        tokens.push(value);
      }
    });

    if (tokens.length === 0) {
      console.log("No valid FCM tokens found.");
      return null;
    }

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
          sound: "emergency_alert",
          defaultSound: false,
          priority: "max",
          visibility: "public",
        },
      },

      tokens: tokens,
    };

    try {
      const response = await admin.messaging().sendEachForMulticast(message);

      console.log(
        `Notification sent: ${response.successCount} successful, ` +
        `${response.failureCount} failed.`
      );

      return null;
    } catch (error) {
      console.error("Error sending notification:", error);
      return null;
    }
  }
);