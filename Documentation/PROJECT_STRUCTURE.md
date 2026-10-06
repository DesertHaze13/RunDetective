# Project structure

The Xcode navigator mirrors the folders on disk. Keep app code in `Sources`, target resources in `Resources`, and project notes in `Documentation`.

```text
RunDetective/
├── RunDetective.xcodeproj/          Xcode targets and shared schemes
├── Sources/
│   ├── iOS/
│   │   ├── App/                     App entry point and root navigation
│   │   ├── Features/                One folder per screen or user feature
│   │   │   ├── Today/
│   │   │   ├── History/
│   │   │   ├── Trends/
│   │   │   └── Settings/
│   │   ├── DesignSystem/            Reusable iOS views, styles, and motion
│   │   ├── Services/                HealthKit access and synchronization
│   │   └── Domain/                  Workout models and deterministic analysis
│   └── Watch/App/                    Watch entry point and views
├── Resources/
│   ├── iOS/                          iOS assets, Info.plist, entitlements
│   ├── Watch/                        Watch assets, Info.plist, entitlements
│   └── IconSource/                   Editable Icon Composer artwork
├── Documentation/
│   ├── CALCULATIONS.md               Verifiable analysis formulas
│   ├── PROJECT_STRUCTURE.md          This guide
│   └── Screenshots/                  Review captures, not app resources
└── README.md                         Setup, scope, and current limitations
```

## Conventions for the next project

1. Start with the same `Sources`, `Resources`, and `Documentation` folders. Add a feature folder when a new screen or capability has its own behavior; keep small related views together.
2. Put each platform's app entry point and platform-only code under that platform. Add `Sources/Shared` only when code is genuinely used by more than one target. Xcode target membership should match.
3. Keep assets, property lists, and entitlements under the matching platform in `Resources`. Update the Xcode build settings when moving an `Info.plist` or entitlements file.
4. Keep calculations and data-source rules in documentation so changes can be reviewed against the UI. Do not copy HealthKit data into project resources.
5. For a new app, copy this layout, rename the project and app targets, choose new bundle identifiers, update display names and signing teams, replace the assets, then build each target. Do not reuse Run Detective's identifiers or personal team settings.

The structure is a starting pattern, not a requirement to create empty folders or split every small view into its own file.
