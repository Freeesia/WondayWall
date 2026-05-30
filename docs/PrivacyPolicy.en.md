---
title: Privacy Policy
description: WondayWall Privacy Policy
---

# Privacy Policy

Last updated: May 29, 2026

This Privacy Policy explains how "WondayWall" ("the app") handles user information and data.

## Introduction

WondayWall is an app for Windows, iOS, and Android that generates wallpaper images based on the user's calendar events, RSS news, interest keywords, and additional instructions.
The app provider does not collect users' personal information, calendar details, settings, generated images, or generation history during normal use.

However, to provide its features, the app reads and writes information stored on the user's device and communicates with external services such as Google AI / Gemini, Google Calendar, RSS feed providers, article pages, and OGP image sources.
The app also uses OS features such as calendars, Photos/Gallery, notifications, and wallpaper settings based on the user's permissions or settings.

## Information Stored by OS

### Windows

The Windows app stores the following information on the user's PC:

- Settings file: `%LocalAppData%\StudioFreesia\WondayWall\config.json`
- Generation history: `%LocalAppData%\StudioFreesia\WondayWall\history.json`
- Generated images: `%LocalAppData%\StudioFreesia\WondayWall\wallpapers\`
- Google Calendar OAuth tokens: `%LocalAppData%\StudioFreesia\WondayWall\calendar-token\`
- Google AI API key: Windows Credential Manager

The Google AI API key is stored in Windows Credential Manager and is not stored directly in the settings file.

### iOS

The iOS app stores the following information on the user's device:

- App settings
- Generation history
- Generated images
- Identifiers of selected calendars
- Google AI API key

The Google AI API key is stored in Keychain.
Generated images are stored in the app container. If the user uses Photos saving, images are also saved to the WondayWall album in the Photos library.

### Android

The Android app stores the following information on the user's device:

- App settings
- Generation history
- Generated images
- Identifiers of selected calendars
- Google AI API key

App settings are stored in DataStore.
The Google AI API key is encrypted with Tink and Android Keystore, and is not stored in plain text in DataStore.
Generated images are stored in app storage and may be saved to Photos/Gallery through user action.

## Permissions and Calendar Access by OS

### Windows

If the user enables Google Calendar integration, the Windows app uses a read-only Google Calendar API scope to retrieve calendar events.
Retrieved calendar data may include event titles, start times, end times, locations, and descriptions.
Google Calendar OAuth tokens are stored on the user's PC. The app provider does not obtain, store, view, or share these tokens.

### iOS

If the user grants permission, the iOS app retrieves calendar events from the device through the iOS Calendar feature.
Retrieved calendar data may include event titles, start times, end times, locations, and descriptions.
The iOS app does not directly change the home screen or lock screen wallpaper.
Photos saving, sharing, notifications, and wallpaper setup guidance require the relevant OS permission or user action.

### Android

If the user grants the `READ_CALENDAR` permission, the Android app retrieves calendar events synced to the device through Calendar Provider / `CalendarContract`.
The initial Android version does not retrieve events through the Google Calendar API or Google OAuth.
Retrieved calendar data may include event titles, start times, end times, locations, and descriptions.

The Android app applies generated images to the home screen wallpaper through `WallpaperManager`.
If the user enables lock screen updates, the app may also apply generated images to the lock screen.
Notification, Photos/Gallery saving, and wallpaper-related features are used based on the user's permissions or actions.

## RSS, Article Pages, and OGP Images

The app accesses RSS feed URLs registered by the user and retrieves article titles, summaries, article URLs, and publication dates.
For articles used in wallpaper generation, the app may also retrieve OGP metadata and OGP images from article pages.

RSS providers, article pages, and image hosts may record access logs, IP addresses, user agents, and similar information according to their own policies.

## Information Sent to Google AI / Gemini

The app uses the Google AI / Gemini API to generate wallpapers.
API requests may include the following information:

- Interest keywords and additional instructions entered by the user
- Calendar event information retrieved from the Google Calendar API on Windows
- Calendar event information retrieved from iOS Calendar on iOS
- Calendar event information retrieved from Calendar Provider / `CalendarContract` on Android
- News information retrieved from RSS feeds and article pages
- OGP images used as reference images
- The current wallpaper or a previously generated wallpaper image, if a setting to use such an image as a base is enabled

This information is sent to Google AI / Gemini using the Google AI API key configured by the user.
The app provider does not collect request contents or generated results.
Information sent to Google AI / Gemini is handled according to Google's terms and privacy policy.

## Generated Images and Wallpaper Application

### Windows

The Windows app applies generated images as the desktop wallpaper.
If the user enables lock screen updates, the app also applies generated images to the lock screen.

### iOS

The iOS app stores generated images in the app container.
If the user chooses Photos saving, generated images are saved to the WondayWall album in the Photos library.
The app provides sharing and wallpaper setup guidance so the user can set the wallpaper manually.
The app does not directly change the iOS home screen or lock screen wallpaper.

### Android

The Android app stores generated images in app storage and applies them as the home screen wallpaper through `WallpaperManager`.
If the user enables lock screen updates, the app may also apply generated images to the lock screen.
The user can save generated images to Photos/Gallery or share them through user action.

## Data Sharing

The app provider does not sell, share, or transfer users' personal information, calendar information, RSS settings, API keys, OAuth tokens, on-device data, generated images, or generation history to third parties.

However, based on the user's actions and settings, the app communicates with external services such as Google, RSS providers, article pages, and image hosts.
Data handled by those external services is governed by their respective terms and privacy policies.

## How to Delete Data

### Windows

To delete settings, history, generated images, and Google Calendar OAuth tokens stored by the app, delete the following folder:

`%LocalAppData%\StudioFreesia\WondayWall\`

To delete the Google AI API key, remove the credentials related to `StudioFreesia.WondayWall.AppConfig` from Windows Credential Manager.

### iOS

Settings, history, and generated images stored in the app container can be deleted by changing app settings or deleting the app.
Images saved to the Photos library should be deleted from the Photos app.
Calendar, Photos, and notification permissions can be changed in the iOS Settings app.

### Android

Settings, history, and generated images stored in app storage can be deleted by clearing app data from Android app settings or uninstalling the app.
Images saved to Photos/Gallery should be deleted from the Photos or Gallery app on the device.
Calendar, notification, and wallpaper-related permissions can be changed in the Android Settings app.

## Contact

For questions about this Privacy Policy, contact the following GitHub account:

GitHub account: [Freeesia](https://github.com/Freeesia)

## Changes to This Privacy Policy

This Privacy Policy may be updated due to changes in app features, external services used by the app, or applicable laws and regulations.
When changes are made, they will be announced through the GitHub repository or related app pages.
