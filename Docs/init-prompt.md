You are an expert macOS systems engineer. Build a native macOS app called `DisplayPilot` in Swift/SwiftUI.

Goal:
Create a lightweight BetterDisplay-like macOS utility for personal use.

The app focuses on:

- enabling/selecting HiDPI resolutions
- changing resolution
- changing refresh rate
- enabling/disabling displays
- changing display rotation
- clearing generated display configuration
- uninstalling/removing all app-created system changes safely

This app does not need to be Mac App Store compliant. You may use public APIs, CoreGraphics, IOKit, DDC/CI, shell helpers, launch agents, helper tools, undocumented/private APIs, or reverse-engineered techniques when necessary. However, all risky/private/experimental logic must be isolated behind clear abstractions and documented.

Target:

- macOS 14+
- macOS 15+
- Apple Silicon first
- Native Swift app
- SwiftUI preferred
- Menu bar utility preferred
- No Electron
- No web app
- No cloud dependency

Important engineering rules:

- Do not stop at a stub project.
- Implement real working functionality as much as possible.
- Keep the project buildable after each step.
- Make reasonable engineering decisions without asking follow-up questions.
- Prefer working partial features over theoretical comments.
- Clearly separate stable public API features from experimental/private API features.
- Never silently fake success.
- Every risky system change must have a backup, rollback, clear config, and uninstall path.
- Never delete unrelated user/system files.
- Only remove files/settings that this app created.
- Add logs and diagnostics for every display operation.

Core Feature 1: Display discovery

Implement display detection using CoreGraphics and IOKit where useful.

The app must show:

- display name
- CGDirectDisplayID
- display UUID if available
- vendor ID / product ID if available
- serial number if available
- built-in vs external
- active / online / asleep / mirrored status if available
- main display status
- current logical resolution
- current pixel resolution
- refresh rate
- scale factor
- HiDPI status
- rotation
- available modes

Use APIs such as:

- CGGetOnlineDisplayList
- CGGetActiveDisplayList
- CGDisplayCopyDisplayMode
- CGDisplayCopyAllDisplayModes
- CGDisplayCreateUUIDFromDisplayID
- CGDisplayIsBuiltin
- CGDisplayIsActive
- CGDisplayIsOnline
- CGDisplayIsAsleep
- CGDisplayIsInMirrorSet
- IOKit display service matching if needed

Core Feature 2: Resolution and HiDPI mode selection

Implement a UI that allows the user to select resolution modes.

Requirements:

- List all available modes per display.
- Show normal modes and HiDPI modes separately.
- Show logical size, pixel size, refresh rate, IO flags, and whether the mode is HiDPI.
- Detect HiDPI by comparing logical width/height vs pixel width/height.
- Include hidden/duplicate/low-resolution modes when possible.
- Use CoreGraphics display mode options where available.
- Allow switching display mode from the UI.
- Add a safe rollback path:
  - save previous display mode before applying
  - attempt new mode
  - detect failure
  - revert to previous mode on failure

- Do not break the only usable display.

Also investigate how to enable additional HiDPI scaled modes.

Try these approaches:

- CoreGraphics mode options
- display override files
- EDID override techniques
- virtual display tricks
- private/undocumented APIs
- shell helper commands if needed

If custom HiDPI enabling requires system-level override files, implement it as an experimental feature with:

- explicit user confirmation
- backup before writing
- generated files clearly marked as created by DisplayPilot
- clear config button
- uninstall cleanup path
- README warning

Core Feature 3: Refresh rate selection

Implement refresh rate selection per display.

Requirements:

- Group display modes by resolution.
- Show available refresh rates for each resolution.
- Allow user to switch refresh rate.
- Keep HiDPI and non-HiDPI distinction visible.
- Preserve current resolution when only changing refresh rate if possible.
- Add rollback on failure.

Core Feature 4: Display rotation

Implement display rotation control.

Requirements:

- Show current rotation for each display.
- Allow choosing:
  - 0 degrees
  - 90 degrees
  - 180 degrees
  - 270 degrees

- Use CoreGraphics display configuration APIs where possible:
  - CGBeginDisplayConfiguration
  - CGConfigureDisplayRotation
  - CGCompleteDisplayConfiguration

- Add rollback safety.
- Make the UI clearly show that rotation may rearrange displays.
- Do not apply rotation to a display if the system reports it is unsupported.

Core Feature 5: Enable / disable display

Implement display enable/disable or best-effort display disconnect.

Goal:
Allow disabling an external display from the app and enabling it again later.

Try multiple approaches:

- CoreGraphics display configuration
- display mirroring / active display configuration
- private/undocumented APIs
- IOKit display services
- DDC/CI power control for external monitors
- shell helper fallback if necessary

Requirements:

- Never disable the only active usable display.
- Warn before disabling a display.
- Store enough info to attempt re-enable.
- Provide an emergency recovery note in README.
- Implement best-effort alternatives when true disable is not possible:
  - DDC/CI power off / standby if supported
  - set brightness to zero if supported
  - blank/fade display as fallback
  - move windows away if feasible

- Clearly mark each approach as:
  - supported
  - experimental
  - unavailable
  - failed with reason

Core Feature 6: DDC/CI support

Implement DDC/CI support for external monitors if possible.

Features:

- detect DDC support
- read brightness
- set brightness
- read contrast if supported
- set contrast if supported
- power off / standby if supported
- wake / power on if supported
- input source switch if feasible

Use IOKit or existing known DDC techniques as needed.

Requirements:

- DDC support varies by monitor, cable, hub, and macOS version.
- The app must gracefully show unsupported instead of crashing.
- All DDC code must be isolated in `DDCService`.

Core Feature 7: Clear config / uninstall

Implement a dedicated “Clear Config / Uninstall” section.

This is very important.

The app must be able to remove everything it created.

Clear Config should:

- remove app-created display override files
- remove app-created generated HiDPI config files
- remove app-created backup files only when user confirms
- reset app preferences
- remove app-created launch agents if any
- remove app-created helper tool registration if any
- reset experimental feature flags
- show exactly what will be removed before removing
- never remove unrelated files
- require confirmation before destructive cleanup

Uninstall mode should:

- perform Clear Config
- remove helper tools or launch agents created by the app
- remove privileged helper if installed
- remove app support folder
- remove caches/logs created by the app
- explain manual steps if macOS requires user action
- create a final uninstall report

Use app-specific paths such as:

- `~/Library/Application Support/DisplayPilot`
- `~/Library/Preferences/<bundle-id>.plist`
- `~/Library/Logs/DisplayPilot`
- app-created LaunchAgent plist only
- app-created display override files only

If the app writes to `/Library/Displays/Contents/Resources/Overrides` or any system-level location, it must:

- ask for admin permission only when needed
- create a backup
- write only clearly marked DisplayPilot-generated files
- keep a manifest of every file written
- use that manifest for cleanup
- never blindly delete a whole system folder

Core Feature 8: Menu bar UX

Create a menu bar app.

Menu bar should show:

- connected displays
- current resolution
- current refresh rate
- current rotation
- HiDPI status
- quick resolution choices
- quick refresh rate choices
- enable/disable display action
- open settings
- diagnostics
- quit

Settings window should include:

- display list
- mode picker
- refresh rate picker
- rotation picker
- HiDPI section
- enable/disable section
- DDC controls
- clear config / uninstall section
- diagnostics panel

Core Feature 9: Architecture

Use this structure or a similarly clean structure:

- `DisplayPilotApp`
- `MenuBarController`
- `DisplayManager`
- `DisplayModeService`
- `HiDPIService`
- `RefreshRateService`
- `RotationService`
- `DisplayPowerService`
- `DDCService`
- `DisplayReconfigurationObserver`
- `ExperimentalDisplayService`
- `ConfigManifestStore`
- `ClearConfigService`
- `UninstallService`
- `DiagnosticsService`

Models:

- `DisplayInfo`
- `DisplayModeInfo`
- `DisplayIdentifier`
- `DisplayConfigManifest`
- `DisplayOperationResult`

Rules:

- Keep CoreGraphics and IOKit logic out of SwiftUI views.
- Keep private/experimental APIs out of normal services.
- UI should call high-level services only.
- Use main-thread-safe state updates.
- Handle display unplug events safely.
- Do not hardcode display IDs.
- Add detailed comments for private/undocumented APIs.

Core Feature 10: Diagnostics

Add a diagnostics screen and export button.

Diagnostics should include:

- all displays
- all modes
- current mode
- current rotation
- HiDPI detection result
- DDC support status
- display IDs
- vendor/product IDs
- generated config files
- helper/launch agent status
- recent operation logs
- last error per display operation

Allow exporting diagnostics as JSON or text.

Core Feature 11: README

Create a detailed README.

README must include:

- what the app does
- supported macOS versions
- supported features
- known limitations
- public APIs used
- private/experimental APIs or techniques used
- how to build
- how to run
- how to safely test resolution switching
- how to safely test rotation
- how to safely test display disable
- how to recover from bad display settings
- how Clear Config works
- how Uninstall works
- what files the app may create
- risks of custom HiDPI and display override files
- risks of private APIs breaking after macOS updates

Implementation plan:

1. Create working menu bar SwiftUI macOS app.
2. Implement display discovery.
3. Implement display mode listing.
4. Implement resolution switching.
5. Implement HiDPI detection and HiDPI mode selection.
6. Implement refresh rate selection.
7. Implement rotation.
8. Implement display connect/disconnect observer.
9. Implement enable/disable display best-effort.
10. Implement DDC/CI support.
11. Implement experimental custom HiDPI enabling.
12. Implement config manifest tracking.
13. Implement Clear Config.
14. Implement Uninstall cleanup.
15. Add diagnostics export.
16. Add tests.
17. Write README.

Testing:
Add unit tests for:

- HiDPI detection
- display mode classification
- refresh rate grouping
- config manifest cleanup logic

Manual test checklist:

- list displays
- switch resolution
- switch HiDPI mode
- switch refresh rate
- rotate display
- unplug/replug display
- disable external display
- re-enable external display
- run clear config
- run uninstall cleanup
- verify no unrelated files are removed

Final response from the coding agent should include:

- what was implemented
- what works
- what is experimental
- what could not be implemented
- exact build/run instructions
- files changed
- risks and recovery steps
