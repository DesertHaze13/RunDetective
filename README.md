# Run Detective

Native SwiftUI project for iPhone, iPad, and Apple Watch. Open `RunDetective.xcodeproj` in Xcode 27 beta, select the `RunDetective` scheme, and set your development team and unique bundle identifiers before running on a device. Apple Health workout data is usually unavailable in Simulator.

The source tree is organized by platform and feature. See [Project structure](Documentation/PROJECT_STRUCTURE.md) for the folder map and steps to reuse it for a new app.

## Implemented

- On-device HealthKit read authorization for workouts, heart rate, and existing workout routes.
- Automatic historical import on launch, refresh, activity filters, import-period setting, and last successful sync time. HealthKit observer queries for workout and heart-rate changes trigger an in-app refresh; returning the app to the foreground refreshes it too. A second refresh requested during an import is queued. A full query refreshes an in-memory snapshot keyed by HealthKit workout UUID, so it does not create duplicate local workout records.
- Daily logical aggregation while retaining individual workouts; running and walking weekly pace remain separate.
- Dashboard, history, day/workout detail, rolling seven-day totals, selectable calendar-week running comparisons, deterministic pace/speed/HR/energy analysis, three trend charts, route map, and a basic watch recent-workout view.
- Formula documentation in [CALCULATIONS.md](Documentation/CALCULATIONS.md).

## Current limitations

This is an early MVP, not the complete four-phase specification. The iOS app was signed, installed, launched, and visually checked with live workouts on Dony’s iPhone on 2026-09-25 and iPad Air on 2026-09-28. The watchOS scheme also builds, but Watch installation has not been verified. Heart-rate averages now weight samples by bounded time intervals; long gaps remain unmeasured and weekly HR analysis requires coverage. Weekly analysis never claims high confidence because route and conditions are not yet matched. HealthKit background delivery while the app is suspended, SwiftData app state, contextual metrics, cadence/power samples, splits, route-colored pace, personal records, and advanced comparable-run analysis remain to be implemented. The Apple Watch target shows recent Health workouts but has no companion synchronization with iPhone. The app does not store HealthKit workouts or routes outside HealthKit and memory.

## Privacy

There are no network calls, accounts, analytics SDKs, advertising SDKs, or external route services in this project. Routes are read from Apple Health and drawn with MapKit on device.

## Overview refresh

Overview shows the last successful Health sync, the latest run and its closest comparable workout, then the rolling seven-day and in-progress current-week cards. The weekly selector defaults to this week versus last week and can compare any two distinct weeks in the previous year. All weekly analysis cards use the selected pair and show their date ranges. When the current week is selected, the baseline is trimmed to the same elapsed portion of its week; both periods update when Health sync completes. Further cards show running distance and consistency, aggregate pace and speed, measured HR with sample coverage, active-energy completeness, walking distance, the last active day, and up to three deterministic findings. Weeks without runs show insufficient data instead of borrowing older weeks. The rolling window and current-week boundary update while the app remains open. On wide iPad windows, Today uses two staggered columns and Trends places pace and HR charts side by side below a featured distance chart; narrower windows retain a single column. The recent-run pace chart and all three Trends charts support horizontal scrubbing with the exact observed value at the nearest plotted run or week. Chart dragging uses the native selection gesture; card tap animations remain tied to taps. Each analysis states its caveats; missing values stay unavailable.

An original 1024 px Run Detective icon is included in the iOS and watchOS asset catalogs. The current icon is the first approved right-facing short-haired male runner illustration, restored at the user’s request. Its milky-white glass figure has subtle cyan stacked contours on a dark blue field. The editable Icon Composer document contains the final illustration as a raster layer. Both app targets reference `AppIcon`, and the built iPhone/iPad app contains compiled icon files. The Icon Composer file is at `Resources/IconSource/RunDetective.icon`; its glass contours are baked into the single artwork layer.

## Interactive details

Cards spring into view while scrolling, pulse and flash at their corners when tapped, and sit over a slowly moving ambient background. The latest-run card has a continuously moving layered runner and a tappable runner clue. Overview, History, workout details, route maps, Trends, and Watch use these motion details. Reduce Motion suppresses decorative movement. The iOS target includes a launch-screen declaration so modern iPhones use their full display.
