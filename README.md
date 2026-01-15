# TalkTime Project

This project implements a real-time communication application utilizing a modern, decoupled architecture with a dedicated backend service and a cross-platform mobile/web frontend.

## Motivation

1) There's no modern looking chat app, which doesn't require you to register for selfhosting.
2) An attempt to change the industry of making electron apps or web apps, which are not as performant and clean as native apps
3) To learn and practice modern web development technologies.

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
- The PC build is taking about 52MB and the web build is taking about 35MB.

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

### All Platforms:
- Add p2p encryption.
- Add message sharing between devices.
- Add message read status.
- Add reaction support.
- Add support for profile view / edit.
- Add support for settings / preferences.
- Add support for multiple languages.
- Add support for theme switching.
- Optimize performance for large conversations.
- Add backups to third party services.
- Add support for voice / video messages.
- Add support for attachments.
- Add profile settings / preferences.

### Android & iOS
- Test with real devices.

### Desktop
- Add keyboard shortcuts.
- Add overlay for incoming or ongoing calls (discord like).


## How to setup everything

Check both frontend and backend directories for setup instructions.

## FAQ

### Why using firebase?

It's the only option for push notifications on ios.
