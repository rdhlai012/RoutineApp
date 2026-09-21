# Routine

A personal, offline SwiftUI iPhone app. One user, one device, no backend, no
account, no network calls. Everything lives in `routine.json` in the app's
Documents directory.

- iOS 16.0 minimum, iPhone only (built for an iPhone 13 Pro)
- Local notifications only (`UNUserNotificationCenter`)
- Time zone: whatever the phone says. The code always uses `Calendar.current`
  and never hardcodes a UTC offset.

---

## What the app does

### Prayer times are exact, per date, with no fallback

Prayer times are stored against a single `yyyy-MM-dd` key. A date that has no
saved times **has no prayer times** - they are never computed, guessed or
copied from another day.

On such a date every prayer-anchored task shows **"No prayer times"**, and
nothing anchored is scheduled. Today's screen shows a banner for today and for
tomorrow whenever either is missing.

### Set Up Tomorrow

The main daily flow. After Maghrib you get tomorrow's adhan times, open the
**Tomorrow** tab, type five times and press one button.

- The header shows tomorrow's exact date.
- Pickers start from today's values for convenience, but the day is marked
  **"Draft - not saved"** until you press **SAVE TOMORROW'S TIMES**.
- All five times are required. The save button stays disabled until Fajr,
  Dhuhr, Asr, Maghrib and Isha are all entered and in ascending order within
  the same day.
- An optional **"I'm going out tomorrow"** switch sits on the same screen,
  **off by default**.
- A live preview shows the whole computed day and flags conflicts, e.g.
  *"Wudu 4:48 AM is before Bath 5:00 AM."* or *"Isha 8:55 PM falls after Gym
  8:40 PM."*

On save, in this order: validate → persist → remove **only** that date's
prayer-anchored notifications → schedule the new ones → read back
`getPendingNotificationRequests()` → report the **real** count:

> Tomorrow scheduled ✓ Fajr, Dhuhr, Asr, Maghrib, Isha (23 reminders) · saved 7:32 PM

If read-back finds any of the five missing, you get an explicit error instead
of the ✓. Saving twice produces the same identifiers, so nothing is duplicated.

The same editor opens for any date - today if you forgot, or any past date from
the calendar.

### Evening nudge

Each day a one-off notification is scheduled at **today's Maghrib + 15 minutes**
("Enter tomorrow's prayer times"). It cancels itself the moment tomorrow's
times are saved. The offset is configurable in **More**.

### The routine

Two kinds of timing, and nothing else:

- **Fixed** - minutes after midnight (wake, brush, bath, gym, shower, dinner,
  night skincare, sleep reminder).
- **Prayer-anchored** - a prayer plus a signed offset in minutes.

When a prayer time changes, **only prayer-anchored tasks move.**

Default weekday routine (all editable):

| Time | Task |
|---|---|
| 4:50 AM | Wake up (fixed, insistent alarm) |
| 4:55 AM | Brush teeth (fixed) |
| 5:00 AM | Bath (fixed) |
| Fajr − 10 | Wudu |
| Fajr + 0 | Fajr / Adhan |
| Fajr + 5 | **Fajr prayer** |
| Fajr + 15 | Read Quran |
| Fajr + 40 | Morning skincare (Round Lab Dokdo Cleanser · Dr. Althea 345 · Skin1004 SPF 50) |
| Dhuhr − 20 / − 10 / + 0 | Brush teeth · Wudu · **Dhuhr prayer** |
| Asr − 20 / − 10 / + 0 | Brush teeth · Wudu · **Asr prayer** |
| Maghrib − 20 / − 10 / + 0 | Brush teeth · Wudu · **Maghrib prayer** |
| Maghrib + 15 | Read Quran |
| Isha − 20 / − 10 / + 0 | Brush teeth · Wudu · **Isha prayer** |
| 12:00 PM | Extra sunscreen - Noon *(going out only)* |
| Asr − 30 | Extra sunscreen - Asr *(going out only)* |
| 8:40 PM | Gym |
| 9:30 PM | Return from gym |
| 9:35 PM | Shower |
| 9:45 PM | Dinner |
| 10:00 PM | Night skincare (empty checklist, add your own) |
| 10:15 PM | Sleep reminder |

**All five prayers are mandatory.** Isha is enabled by default like the rest.

### Protected prayers

The five prayer tasks cannot be deleted, cannot be disabled, and their alarm
cannot be switched off. Only their **offset** and **note** are editable.
"Reset to defaults" always recreates all five, and a hand-edited or corrupted
`routine.json` is repaired on load.

The preparation tasks (brush teeth, wudu) are fully editable, but the app warns
before you disable or delete one.

### Going out

Stored per date and **off by default for every date**, so tomorrow is off
unless you switch it on. Turning it on adds that date's going-out tasks and
schedules them; turning it off removes them. Only that date's notifications are
touched.

### Sleep

Bedtime and wake time per date, with cross-midnight maths
(10:10 PM → 4:50 AM = 6h 40m). Settings: minimum (default 6h), goal
(default 7h), and a fixed wake time (default 4:50 AM) that is the single source
of truth shared with the Wake up task. The app shows target bedtime
(wake − goal = 9:50 PM), latest bedtime (wake − minimum = 10:50 PM), a status of
below minimum / meets minimum / meets goal, and a 7-night average with counts.

### Calendar, day detail, stats, notes

The calendar colours each date complete / partial / missed / no data, and marks
dates with no prayer times. Tapping a date opens the full day grouped by
category (Tasks, Prayers, Quran, Skincare with each product, Gym, Sleep, notes,
completion %). **Past days stay editable.** Stats show the routine start date,
current day number, current streak, longest streak and good days (default
threshold 80%, configurable).

Every task has an optional note that appears in the notification body and on
Today, plus one free-text daily note per date.

---

## Notifications: what they can and cannot do

**Read this before relying on the wake-up alarm.**

These are **local notifications, not Clock alarms.** They **cannot** bypass:

- the **Silent / Ring** switch,
- **Focus** or **Do Not Disturb**,
- a muted volume.

The wake-up uses the bundled 28-second `alarm.wav` and fires **5 bursts one
minute apart**, which is the loudest and most persistent thing a notification
is allowed to be. It is still not a Clock alarm.

**Keep a Clock alarm as a backup for 4:50 AM.** The app says this in
**More → Notifications** and in the task editor, and it is not claimed
otherwise anywhere.

### How scheduling works

One central scheduler (`Routine/NotificationScheduler.swift`). It is a thin
wrapper: every decision is made by `Planner` in the Foundation-only core.

Deterministic identifiers:

```
routine.<taskUUID>.<yyyy-MM-dd>.<burstIndex>   one-off, for a specific date
routine.<taskUUID>.daily.<burstIndex>          repeating daily fixed-time task
routine.nudge.<yyyy-MM-dd>                     the evening nudge
routine.test.alarm                             the "Send test alarm" button
```

`removeAllPendingNotificationRequests()` is **never** called. The scheduler
fetches the pending requests, filters by the `routine.` prefix, and removes
only the affected ones (per date, per task, or the stale ones), then adds the
new ones. Anything belonging to another app or to iOS is untouched.

- **Fixed-time tasks** are scheduled as repeating daily reminders, so they ring
  even if you never open the app.
- **Prayer-anchored tasks** are scheduled only for dates whose exact times
  exist.
- **Going-out tasks** are per date, never daily.
- Rescheduling is triggered by: a task edit, prayer times saved, going-out
  toggled, app foregrounded, and app launch.
- iOS allows 64 pending requests. The app keeps the soonest **60** and reports
  how many later reminders were skipped (**More → Notifications**).

---

## Data and migration

`routine.json` carries a `schemaVersion` (currently **1**). Decoding is
deliberately tolerant:

- every field is `decodeIfPresent` with a default, so new fields never break an
  old file and missing fields never throw;
- `TimeOfDay` accepts both an `Int` (minutes after midnight) and `"HH:mm"`;
- legacy task shapes (`time`, `anchor`, `offsetMinutes`) are understood;
- a legacy top-level `prayerTimes` map and `goingOut` map are folded into the
  per-date records;
- a legacy `sleepHours` number becomes a real bedtime/wake pair anchored to
  your wake time;
- unknown categories are mapped where sensible (`fitness` → gym) and otherwise
  become `other`;
- an old file that never had prayer tasks gains all five protected prayers.

A file with no `schemaVersion` is treated as version 0 and migrated on load.
The previous file is copied once to `routine.json.v0.backup` before the first
v1 write, so a bad migration is recoverable by hand.

> ⚠️ **Caveat:** the exact shape of the original v0 file was not available when
> this migration was written, so it is built to be maximally tolerant rather
> than matched field-for-field to a known file. If your device's real
> `routine.json` differs, copy it off the phone and the decoder can be tightened
> to it. Nothing is deleted: unknown keys are simply ignored, and the backup is
> kept.

---

## Project layout

```
Package.swift                 swift test entry point for the core
project.yml                   XcodeGen definition for the iOS app
Sources/RoutineKit/           Foundation-only core (no SwiftUI, no UserNotifications)
  Time.swift                  TimeOfDay, DateKey, calendar helpers
  Prayer.swift                the five prayers, PrayerTimes, validation
  RoutineTask.swift           tasks, timing, checklist steps, protection rules
  DayRecord.swift             one date: times, going out, completions, sleep, note
  RoutineSettings.swift       wake time, sleep goals, thresholds
  RoutineData.swift           the document + schemaVersion + migration
  DefaultRoutine.swift        the shipped routine and its stable UUIDs
  Planner.swift               anchor resolution, notification plan, IDs, 60 cap
  ConflictChecker.swift       sequence and Isha-vs-gym conflicts
  SleepMath.swift             cross-midnight maths, targets, summaries
  Stats.swift                 completion, day number, streaks, good days
  TomorrowSetup.swift         the Set Up Tomorrow rules and read-back check
  Persistence.swift           routine.json load/save/backup
Routine/                      the SwiftUI app
  RoutineApp.swift            @main, tabs, scene phase
  AppData.swift               the store: mutate, persist, reschedule
  NotificationScheduler.swift the only file that touches UserNotifications
  DayView.swift               Today
  PrayerView.swift            the prayer-times editor + Set Up Tomorrow tab
  CalendarTab.swift           month grid
  DayDetailView.swift         one day, grouped by category
  ManageView.swift            the routine and the task editor
  SleepView.swift             sleep targets and history
  MoreView.swift              stats, settings, notification status, test alarm
  Components.swift            shared small views
  Info.plist
Resources/alarm.wav           28 s, 44.1 kHz mono
Tests/RoutineKitTests/        XCTest suite + Fixtures/old-routine.json
```

All the logic lives in `Sources/RoutineKit`, which imports neither SwiftUI nor
UserNotifications, so `swift test` runs it on any machine with a Swift
toolchain. The app target compiles those same files directly - there is exactly
one copy of the code.

---

## Building

### Locally (macOS with Xcode 15+)

```bash
brew install xcodegen
xcodegen generate          # writes Routine.xcodeproj (git-ignored)
swift test                 # the core test suite
open Routine.xcodeproj
```

### CI

`.github/workflows/build.yml` is **manual trigger only** (`workflow_dispatch`),
so it never burns macOS minutes on a push or a pull request. Run it from
**Actions → Build Routine (unsigned IPA) → Run workflow**.

It does exactly one thing:

```
Swift source
  -> swift test                     (the core suite; the build stops if it fails)
  -> xcodegen generate              (Routine.xcodeproj, git-ignored)
  -> xcodebuild ... CODE_SIGNING_ALLOWED=NO
  -> Routine.app                    (verified to exist, with alarm.wav inside)
  -> Payload/Routine.app
  -> RoutineApp-Unsigned.ipa
  -> GitHub Actions artifact "RoutineApp-Unsigned"
```

There is **no** App Store submission, **no** App Store Connect, **no**
TestFlight, and **no** cloud signing. The workflow contains **no certificate,
no private key, no password and no provisioning profile**, and no signing
secret is ever uploaded to GitHub.

---

## Sideloading onto your iPhone

```
GitHub Actions
   ↓  RoutineApp-Unsigned.ipa
Download to iPhone
   ↓
eSign  (signs with the certificate/profile already configured on the phone)
   ↓
Install on the iPhone 13 Pro
```

### `RoutineApp-Unsigned.ipa` is not directly installable

It has **no code signature and no embedded provisioning profile**. iOS will not
install it as-is. It is a build artifact whose only purpose is to be signed on
your side. eSign is what makes it installable, by signing it at import time
with the certificate and profile you already have on the phone.

### Steps

1. **Actions → Build Routine (unsigned IPA) → Run workflow.**
2. When it finishes, download the **RoutineApp-Unsigned** artifact. GitHub
   hands it over as a `.zip`; unzip it to get `RoutineApp-Unsigned.ipa`.
3. Get the `.ipa` onto the iPhone - Files, iCloud Drive, AirDrop from a Mac, a
   cable, or download it straight from GitHub in Safari on the phone.
4. Open **eSign → Import the .ipa → sign it with your configured certificate
   and provisioning profile → Install.**
5. First launch: allow notifications when asked.

### Re-signing

How long the app keeps working is a property of **your** certificate, not of
this project: a free Apple ID certificate expires after about 7 days, a paid
Apple Developer Program one after about a year. When it lapses, re-sign the
same IPA in eSign again. Nothing in the build changes.

### Keeping your signing material out of the repo

`.gitignore` already blocks `*.p12`, `*.cer`, `*.mobileprovision`,
`*.provisionprofile` and `ExportOptions.plist`. Keep it that way: the
certificate and profile belong on the phone and in eSign, never in git and
never in GitHub Actions secrets.

### If the app installs but nothing rings

- iOS **Settings → Notifications → Routine** must show the app with
  notifications allowed. **More → Notifications** in the app shows the current
  permission status and warns if it is blocked.
- Remember the Silent switch and Focus caveat above.

---

## Manual device checklist

Run through this once on the phone after installing:

- [ ] **Permissions:** open the app, allow notifications. Check
      **iOS Settings → Notifications → Routine** lists the app.
- [ ] **Test alarm:** More → *Send test alarm*, lock the phone, wait ~10 s.
      Confirm `alarm.wav` plays. Then try it again with the Silent switch on and
      with a Focus enabled, so you know exactly what it does in each case.
- [ ] **Set up tomorrow:** after Maghrib, open **Tomorrow**, enter all five
      times, confirm the save button stays disabled until the fifth is entered,
      then save. Confirm the message reads
      *"Tomorrow scheduled ✓ Fajr, Dhuhr, Asr, Maghrib, Isha (N reminders)"*
      and that **N is not zero**.
- [ ] **No duplicates:** save tomorrow a second time. The count should not grow.
- [ ] **Going out:** toggle *"I'm going out tomorrow"* on and off. The two
      sunscreen reminders should appear and disappear from the preview, and the
      reminder count should change by 2.
- [ ] **Only anchored tasks move:** change tomorrow's Fajr by 10 minutes and
      re-save. Wudu, Adhan, Fajr prayer, Quran and morning skincare shift;
      Bath, Gym and Dinner do not.
- [ ] **No fallback:** pick a date with no times in the Calendar. Every
      prayer-anchored task must say *"No prayer times"*.
- [ ] **Protected prayers:** try to delete or disable a prayer in **Routine**.
      It must refuse. Then *Reset to defaults* and confirm all five are back.
- [ ] **Wake-up:** the night before, confirm the 4:50 AM wake-up fires 5 bursts
      a minute apart - and keep a Clock alarm as a backup anyway.
