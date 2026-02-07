// eslint-disable-next-line max-len
const { onDocumentCreated, onDocumentUpdated } = require("firebase-functions/v2/firestore");
const { admin, db, fcm } = require("./adminConfig"); // Use shared config

// Initialize admin if not already initialized
// if (!admin.apps.length) {
//   admin.initializeApp();
// }

// const db = admin.firestore();
// const fcm = admin.messaging();

/**
 * Logs debug information with a formatted label.
 *
 * @param {string} label - The label for the debug output.
 * @param {*} data - The data to be stringified and logged.
 */
function logDebug(label, data) {
  console.log(`===== ${label} =====`);
  console.log(JSON.stringify(data, null, 2));
}

/**
 * Calculates the distance in kilometers between two geographic coordinates
 * using the Haversine formula.
 *
 * @param {number} lat1 - Latitude of the first point.
 * @param {number} lon1 - Longitude of the first point.
 * @param {number} lat2 - Latitude of the second point.
 * @param {number} lon2 - Longitude of the second point.
 * @return {number} The distance in kilometers.
 */
function calculateDistance(lat1, lon1, lat2, lon2) {
  const R = 6371; // Radius of earth in km
  const dLat = (lat2 - lat1) * Math.PI / 180;
  const dLon = (lon2 - lon1) * Math.PI / 180;

  const a =
    Math.sin(dLat / 2) * Math.sin(dLat / 2) +
    Math.cos(lat1 * Math.PI / 180) *
    Math.cos(lat2 * Math.PI / 180) *
    Math.sin(dLon / 2) * Math.sin(dLon / 2);

  const c = 2 * Math.atan2(Math.sqrt(a), Math.sqrt(1 - a));

  return R * c; // Distance in km
}

/**
 * Calculates driver priority score based on multiple factors.
 * Higher score = higher priority for trip assignment.
 *
 * Scoring breakdown (0-100 points total):
 * - Distance: 0-50 points (closer = more points)
 * - Tier Bonus: 0-15 points (Platinum=15, Gold=10, Silver=5, Bronze=0)
 * - Acceptance Rate: 0-20 points (100% = 20 points)
 * - User Rating: 0-15 points (5 stars = 15 points)
 *
 * @param {object} driver - Driver data including metrics and location.
 * @param {number} pickupLat - Pickup latitude.
 * @param {number} pickupLng - Pickup longitude.
 * @param {number} distance - Pre-calculated distance in km.
 * @return {object} Driver priority data with score breakdown.
 */
function calculateDriverPriority(driver, pickupLat, pickupLng, distance) {
  // 1. Distance Score (0-50 points)
  // Closer drivers get more points. 10km+ = 0 points
  const distanceScore = Math.max(0, 50 - (distance * 5));

  // 2. Tier Bonus (0-15 points)
  const tierBonuses = {
    "platinum": 15,
    "gold": 10,
    "silver": 5,
    "bronze": 0,
  };
  const tier = driver.metrics?.tier || "silver";
  const tierScore = tierBonuses[tier] || 5;

  // 3. Acceptance Rate Score (0-20 points)
  // 100% acceptance = 20 points
  const acceptanceRate = driver.metrics?.acceptanceRate || 0;
  const acceptanceScore = (acceptanceRate / 100) * 20;

  // 4. User Rating Score (0-15 points)
  // 5 stars = 15 points
  const userRating = driver.rating || 0;
  const ratingScore = (userRating / 5) * 15;

  // Total Priority Score (0-100 points)
  const totalScore = distanceScore + tierScore + acceptanceScore + ratingScore;

  return {
    driverId: driver.driverId,
    distance: distance,
    tier: tier,
    acceptanceRate: acceptanceRate,
    rating: userRating,
    reliabilityScore: driver.metrics?.reliabilityScore || 0,
    priorityScore: totalScore,
    // Score breakdown for debugging
    scoreBreakdown: {
      distance: distanceScore.toFixed(1),
      tier: tierScore,
      acceptance: acceptanceScore.toFixed(1),
      rating: ratingScore.toFixed(1),
      total: totalScore.toFixed(1),
    },
    fcmToken: driver.fcmToken,
    driverName: driver.displayName || "Driver",
  };
}

// Helper function to find nearby drivers
// eslint-disable-next-line require-jsdoc
async function findDriversForTrip(tripId, tripData) {
  try {
    logDebug("Processing trip", { tripId, tripStatus: tripData.status });

    // Only process trips with 'searching' status
    if (tripData.status !== "searching") {
      logDebug("Trip not in searching status", { status: tripData.status });
      return null;
    }

    console.log(`Finding drivers for trip ${tripId}`);

    // Get pickup coordinates
    const pickupLat = tripData.pickup.latitude;
    const pickupLng = tripData.pickup.longitude;

    // Define search radius (in km)
    const searchRadius = 5;

    // Query for available drivers
    const driversSnapshot = await db.collection("drivers")
      .where("isOnline", "==", true)
      .where("isAvailable", "==", true)
      .get();

    if (driversSnapshot.empty) {
      console.log("No available drivers found");
      // You might want to update the trip status here
      await db.collection("trips").doc(tripId).update({
        lastUpdated: admin.firestore.FieldValue.serverTimestamp(),
        noDriversAvailable: true,
      });
      return null;
    }

    // Calculate distance and priority for each driver
    const driversWithPriority = [];

    driversSnapshot.forEach((doc) => {
      const driverData = doc.data();
      const driverId = doc.id;

      // Check if driver has valid location
      if (driverData.location &&
        driverData.location.latitude &&
        driverData.location.longitude) {
        const distance = calculateDistance(
          pickupLat,
          pickupLng,
          driverData.location.latitude,
          driverData.location.longitude,
        );

        // Only include drivers within the search radius
        if (distance <= searchRadius) {
          // Calculate priority score for this driver
          const driverWithPriority = calculateDriverPriority(
            {
              driverId: driverId,
              ...driverData,
            },
            pickupLat,
            pickupLng,
            distance,
          );

          driversWithPriority.push(driverWithPriority);
        }
      }
    });

    // Sort drivers by PRIORITY SCORE (highest first) instead of distance
    driversWithPriority.sort((a, b) => b.priorityScore - a.priorityScore);

    console.log(`Found ${driversWithPriority.length} nearby drivers`);

    if (driversWithPriority.length === 0) {
      console.log("No drivers within search radius");
      await db.collection("trips").doc(tripId).update({
        lastUpdated: admin.firestore.FieldValue.serverTimestamp(),
        noDriversAvailable: true,
      });
      return null;
    }

    // Log top 3 drivers for debugging
    console.log("Top 3 drivers by priority:");
    driversWithPriority.slice(0, 3).forEach((driver, index) => {
      console.log(`${index + 1}. ${driver.driverName} (${driver.tier})`);
      console.log(`   Priority: ${driver.priorityScore.toFixed(1)} points`);
      console.log(`   Distance: ${driver.distance.toFixed(2)}km`);
      console.log(`   Breakdown: ${JSON.stringify(driver.scoreBreakdown)}`);
    });

    // Select the TOP PRIORITY driver (highest score)
    const topDriver = driversWithPriority[0];

    // Store a record of which driver was notified with priority info
    await db.collection("trips").doc(tripId).update({
      nearbyDrivers: driversWithPriority.map((d) => ({
        driverId: d.driverId,
        distance: d.distance,
        tier: d.tier,
        priorityScore: d.priorityScore,
        acceptanceRate: d.acceptanceRate,
      })),
      notifiedDriverId: topDriver.driverId,
      notifiedDriverTier: topDriver.tier,
      notifiedDriverPriority: topDriver.priorityScore,
      notificationTime: admin.firestore.FieldValue.serverTimestamp(),
      status: "driver_notified",
    });

    // Send push notification to top priority driver
    if (topDriver.fcmToken) {
      // Prepare message data
      const messageData = {
        tripId: tripId,
        pickupAddress: tripData.pickup.address || "Unknown location",
        pickupLatitude: pickupLat.toString(),
        pickupLongitude: pickupLng.toString(),
        dropoffAddress: tripData.dropoff.address || "Unknown destination",
        fare: tripData.fare ? tripData.fare.toString() : "0",
        distance: tripData.distance ? tripData.distance.toString() : "0",
        // eslint-disable-next-line max-len
        estimatedDuration: tripData.duration ? tripData.duration.toString() : "0",
        expiresIn: "20", // Driver has 20 seconds to respond
        notificationType: "tripRequest",
        // Add notification time from tripData
        notificationTime: tripData.notificationTime ?
          tripData.notificationTime.toMillis().toString() :
          Date.now().toString(),
      };
      // Add stops information if present
      // eslint-disable-next-line max-len
      if (tripData.stops && Array.isArray(tripData.stops) && tripData.stops.length > 0) {
        // Create a formatted string of stops for the notification
        const stopsCount = tripData.stops.length;
        messageData.hasStops = "true";
        messageData.stopsCount = stopsCount.toString();
        // Calculate total waiting time
        let totalWaitingTime = 0;
        // eslint-disable-next-line max-len
        // Add details for each stop (up to 5 stops - FCM has message size limitations)
        const maxStops = Math.min(stopsCount, 5);
        for (let i = 0; i < maxStops; i++) {
          const stop = tripData.stops[i];
          if (stop) {
            // Add address information
            // eslint-disable-next-line max-len
            messageData[`stop${i + 1}Address`] = stop.address || "Unknown stop location";
            // Add coordinates if available
            if (stop.latitude && stop.longitude) {
              messageData[`stop${i + 1}Latitude`] = stop.latitude.toString();
              messageData[`stop${i + 1}Longitude`] = stop.longitude.toString();
            }
            // Add waiting time for each stop - important new addition
            if (stop.waitingTime !== undefined) {
              // eslint-disable-next-line max-len
              messageData[`stop${i + 1}WaitingTime`] = stop.waitingTime.toString();
              totalWaitingTime += parseInt(stop.waitingTime) || 0;
            } else {
              messageData[`stop${i + 1}WaitingTime`] = "0";
            }
          }
        }
        // Add total waiting time across all stops
        messageData.totalWaitingTime = totalWaitingTime.toString();
        // If more stops exist than we can include in the message
        if (stopsCount > maxStops) {
          messageData.additionalStops = (stopsCount - maxStops).toString();
        }
      } else {
        messageData.hasStops = "false";
        messageData.totalWaitingTime = "0";
      }

      // Create notification message with additional waiting time info
      // eslint-disable-next-line max-len
      let notificationBody = `New pickup request (${topDriver.distance.toFixed(1)}km away)`;
      // Add stops info
      if (tripData.stops && tripData.stops.length > 0) {
        // eslint-disable-next-line max-len
        notificationBody += ` with ${tripData.stops.length} stop${tripData.stops.length > 1 ? "s" : ""}`;
        // Add waiting time information if available
        const totalWaitingMinutes = parseInt(messageData.totalWaitingTime) || 0;
        if (totalWaitingMinutes > 0) {
          notificationBody += ` (${totalWaitingMinutes} min waiting)`;
        }
      }
      const message = {
        token: topDriver.fcmToken,
        notification: {
          title: "New Trip Request",
          body: notificationBody,
        },
        data: messageData,
      };

      try {
        await fcm.send(message);
        console.log(`Notification sent to driver ${topDriver.driverId}`);
        console.log(`Driver tier: ${topDriver.tier}, Priority: ${topDriver.priorityScore.toFixed(1)}`);
      } catch (error) {
        console.error("Error sending notification:", error);
      }
    }

    return null;
  } catch (error) {
    console.error("Error in findDriversForTrip function:", error);
    return null;
  }
}

// Handle trip creation
// eslint-disable-next-line max-len
exports.findNearbyDrivers = onDocumentCreated("trips/{tripId}", async (event) => {
  try {
    const tripId = event.params.tripId;
    const tripData = event.data.data();

    logDebug("New trip created", { tripId, tripData });

    return findDriversForTrip(tripId, tripData);
  } catch (error) {
    console.error("Error in findNearbyDrivers onCreate function:", error);
    return null;
  }
});

// Handle trip updates (for periodic searches)
// eslint-disable-next-line max-len
exports.refreshNearbyDriversSearch = onDocumentUpdated("trips/{tripId}", async (event) => {
  try {
    const tripId = event.params.tripId;
    const beforeData = event.data.before.data();
    const afterData = event.data.after.data();
    // Only trigger on searchRefreshedAt updates for searching trips
    if (afterData.status !== "searching") {
      return null;
    }
    // Check if searchRefreshedAt was updated
    if (!afterData.searchRefreshedAt) {
      return null;
    }
    // If searchRefreshedAt existed before, make sure it changed
    // eslint-disable-next-line max-len
    if (beforeData.searchRefreshedAt && afterData.searchRefreshedAt.seconds === beforeData.searchRefreshedAt.seconds) {
      return null;
    }
    // eslint-disable-next-line max-len
    logDebug("Refreshing driver search", { tripId, searchAttempts: afterData.searchAttempts || 0 });
    return findDriversForTrip(tripId, afterData);
  } catch (error) {
    console.error("Error in refreshNearbyDriversSearch function:", error);
    return null;
  }
});
