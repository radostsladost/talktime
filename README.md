# TalkTime Project

This project implements a real-time communication application utilizing a modern, decoupled architecture with a dedicated backend service and a cross-platform mobile/web frontend.

## Architecture Summary

This codebase is composed of two main parts:

### Backend Service (ASP.NET Core)

The backend is built using **ASP.NET Core**. Based on the solution structure found under `talktime/backend/talktime.sln`, the architecture separates concerns:
- `talktime/backend/TalkTime.Api`: Primary service layer for hosting APIs.
- `talktime/backend/TalkTime.Core`: Business logic and domain models.
- `talktime/backend/TalkTime.Infrastructure`: Data access and external service integration details.

This service likely handles API requests, real-time communication setup (e.g., SignalR), and data persistence.

### Frontend Application (Flutter)

The user-facing application is developed using **Flutter**, enabling deployment across multiple platforms from a single codebase (tested on Android, PC, and web, though iOS should also work).

- The core logic and UI reside within the `talktime/frontend/lib` directory.
- Platform-specific configurations and dependencies are managed in directories like `talktime/frontend/android`, `talktime/frontend/ios`, and configuration files like `talktime/frontend/pubspec.yaml`.

### Screenshots

- Main Menu
![Main Menu](https://github.com/radostsladost/talktime/blob/main/docs/main_menu.jpg "Main Menu")

- Chat with messages

![chats](https://github.com/radostsladost/talktime/blob/main/docs/chats.jpg "chats")

- Conference tap to join

![conference_tap_to_join](https://github.com/radostsladost/talktime/blob/main/docs/conference_tap_to_join.jpg "conference_tap_to_join")

- Incoming call screen

![incoming_call](https://github.com/radostsladost/talktime/blob/main/docs/incoming_call.jpg "incoming_call")

- Ongoing call screen

![ongoing_call](https://github.com/radostsladost/talktime/blob/main/docs/ongoing_call.jpg "ongoing_call")

## Documentation

Work in progress.


## TODO:

### Android & iOS
- Implement push notifications for incoming calls and messages.
- Optimize performance for large conversations.
- Add support for multiple languages.

### iOS
- Test with real devices.

### Web
- Implement push notifications for incoming calls and messages.
- Add support for multiple languages.

### Desktop
- Implement push notifications for incoming calls and messages.
- Optimize performance for large conversations.
- Add support for multiple languages.
- Add keyboard shortcuts.
- Add overlay for incoming or ongoing calls (discord like).
