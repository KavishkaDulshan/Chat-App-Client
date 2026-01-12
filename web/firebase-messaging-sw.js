importScripts("https://www.gstatic.com/firebasejs/8.10.0/firebase-app.js");
importScripts("https://www.gstatic.com/firebasejs/8.10.0/firebase-messaging.js");

// You can leave this config object empty for now, or copy values from firebase_options.dart
// But this listener is required to prevent errors.
firebase.initializeApp({
    apiKey: "ignored-by-sw",
    projectId: "ignored-by-sw",
    messagingSenderId: "ignored-by-sw",
    appId: "ignored-by-sw",
});

const messaging = firebase.messaging();

messaging.onBackgroundMessage(function (payload) {
    console.log('[firebase-messaging-sw.js] Background message: ', payload);
});