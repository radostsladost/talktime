# talktime

A new Flutter project.

## Getting Started

This project is a starting point for a Flutter application.

A few resources to get you started if this is your first Flutter project:

- [Lab: Write your first Flutter app](https://docs.flutter.dev/get-started/codelab)
- [Cookbook: Useful Flutter samples](https://docs.flutter.dev/cookbook)

For help getting started with Flutter development, view the
[online documentation](https://docs.flutter.dev/), which offers tutorials,
samples, guidance on mobile development, and a full API reference.

## Preparation

1) Create the .env file in the root directory of the frontend project with the following content:
```
API_BASE_URL=https://<your_api_base_host>
# ex: API_BASE_URL=https://example.com
# firebase web variables used for scripts\build-firebase-sw.js
FIREBASE_WEB_APIKEY=<FROM_FIREBASE_CONFIG>
FIREBASE_WEB_APPID=<FROM_FIREBASE_CONFIG>
FIREBASE_WEB_MESSAGINGSENDERID=<FROM_FIREBASE_CONFIG>
FIREBASE_WEB_AUTHDOMAIN=<FROM_FIREBASE_CONFIG>
IREBASE_WEB_DATABASEURL=<FROM_FIREBASE_CONFIG>
FIREBASE_WEB_STORAGEBUCKET=<FROM_FIREBASE_CONFIG>
FIREBASE_WEB_PROJECTID=<FROM_FIREBASE_CONFIG>
#or just manually create web/firebase-messaging-sw.js and paste all variables as in https://firebase.google.com/docs/admin/setup
```
2) Follow the instructions in the Notifications section to turn on or off notifications.

## Build Instructions

```sh
flutter pub get
dart run sqflite_common_ffi_web:setup
# build for web
node scripts\build-firebase-sw.js && flutter build web --release --dart-define=ENV_PROF=production
# build for android
flutter build apk --release --dart-define=ENV_PROF=production
# build for ios
flutter build ios --release --dart-define=ENV_PROF=production
# build for macos
flutter build macos --release --dart-define=ENV_PROF=production
# build for windows
flutter build windows --release --dart-define=ENV_PROF=production
# build for linux
flutter build linux --release --dart-define=ENV_PROF=production
```

## Notifications

### Deactivate

If in runtime it gives you a firebase error and/or you don't need notifications, just remove the code below from `main.dart`:

```dart
await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
```

This will deactivate the firebase initialization, so no notifications will be sent. But if you want to enable notifications, read the section below.

### Activate

To activate notifications, follow these steps:

1. Prepare your workspace
The easiest way to get you started is to use the FlutterFire CLI.

Before you continue, make sure to:

Install the Firebase CLI and log in (run firebase login)
Install the Flutter SDK
Create a Flutter project (run flutter create)

2. Install and run the FlutterFire CLI
From any directory, run this command:

```sh
dart pub global activate flutterfire_cli
```
Then, at the root of your Flutter project directory, run this command:

```sh
cd frontend
flutterfire configure --project=project_name
```
This automatically registers your per-platform apps with Firebase and adds a lib/firebase_options.dart configuration file to your Flutter project.

3. Initialize Firebase and add plugins
To initialize Firebase, call Firebase.initializeApp from the firebase_core package with the configuration from your new firebase_options.dart file:

```dart
import 'package:firebase_core/firebase_core.dart';
import 'firebase_options.dart';

// ...

await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
);
Then, add and begin using the Flutter plugins for the Firebase products you'd like to use.
```
