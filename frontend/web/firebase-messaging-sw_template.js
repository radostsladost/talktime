importScripts(
  "https://www.gstatic.com/firebasejs/12.7.0/firebase-app-compat.js",
);
importScripts(
  "https://www.gstatic.com/firebasejs/12.7.0/firebase-messaging-compat.js",
);

firebase.initializeApp({
  apiKey: "<FIREBASE_WEB_APIKEY>",
  authDomain: "<FIREBASE_WEB_AUTHDOMAIN>",
  databaseURL: "<FIREBASE_WEB_DATABASEURL>",
  projectId: "<FIREBASE_WEB_PROJECTID>",
  storageBucket: "<FIREBASE_WEB_STORAGEBUCKET>",
  messagingSenderId: "<FIREBASE_WEB_MESSAGINGSENDERID>",
  appId: "<FIREBASE_WEB_APPID>",
});

const messaging = firebase.messaging();

// Optional:
messaging.onBackgroundMessage((message) => {
  console.log("onBackgroundMessage", message);
});
