# Break presentation integration

The main app owns one `@MainActor BreakWindowController`. Constructing it creates no
windows. Agent code must not instantiate or own presentation. Keep the owner alive
for the application lifetime and call `dismiss()` before shutdown, including forced
and system termination. Deinitialization also dismisses on the main actor.

Drive presentation from the coordinator's published **new** `runtime` value:

```swift
let covers = BreakWindowController()
let background = ImageBackgroundProvider(libraryURL: imageLibraryURL)
covers.onFailure = { [weak coordinator] error in
    coordinator?.presentationFailed(error)
}
// In the runtime observer, on main actor:
if runtime.phase == .breaking && runtime.isAvailable {
    do {
        try covers.show(runtime: runtime, background: background) { [weak coordinator] event in
            coordinator?.send(event)
        }
    } catch {
        // onFailure already ran after cleanup. Do not invoke it a second time.
    }
} else {
    covers.dismiss()
}
```

`show(runtime:background:onEvent:) throws` updates an existing same-cycle break;
`update(runtime:)` updates countdown/strict snapshot or dismisses when unavailable,
outside breaking, or when the cycle differs. The observer must use `show` to enter a
new cycle and to re-enter coverage after unlocking. Internal topology changes are
observed by the controller. Failure clears every cover and restores previous AppKit
presentation options **before** `onFailure`. `AppController.presentationFailed(_:)`
bypasses ordinary strict pause restrictions through emergency release, persists the
paused state, and publishes/logs an error. Cleanup never depends on successful disk
persistence. Always wire `onFailure` in the executable lifecycle owner.

Call `background.prepare(for: DisplayTopology.current(), singleImage: false)` once
per upcoming work cycle, after library mutations, or after work-time topology
changes. Do not call on every timer tick. Preparation selects a common theme/layout
for all screens and renders off the main actor. A break never waits for preparation.
The default dark background appears immediately if nothing is ready. A hot-plugged
screen uses the already selected theme with its own pixel dimensions. Both provider
revision tokens and controller lifetime/window-identity tokens reject stale results.
Provider `invalidate()` clears prepared content. The shared thread-safe cache is
bounded by the image library's 8-image/128-MiB ceilings; displayed images remain
owned by their visible windows.

Use the provider's async `librarySnapshot()`, `importImages(_:)`, `removeImage(id:)`,
and `saveThemes(_:)` APIs for settings. `ImageLibrarySnapshot` contains `assets` and
`themes`. The worker actor owns a single non-Sendable `AssetLibrary`; do not share it
with UI/background threads or mutate the same metadata through another instance.
All imports, metadata I/O, selection, decode, and render execute serially off main.
After a mutation, explicitly prepare again while working. Library/render failure
uses the dark default and does not delay break entry.

Native windows are borderless, nonmovable, floating, join all Spaces, and opt into
full-screen auxiliary behavior. They omit ordinary close/minimize controls. Dock
and menu-bar auto-hide are temporary, restored on every dismissal/failure. There
are no event taps, key blockers, process-switch, Force Quit, session termination,
or Accessibility restrictions. Foreground activation and full-screen coverage are
best effort. System and higher modal surfaces remain available. UI supplies a large
countdown, opaque dark contrast panel, scrollable safe layout, reduced-transparency
fallback, no animations, VoiceOver labels, non-strict end action, and a separate
inline emergency confirmation before release/pause. Real Spaces, full screen,
Mission Control, Retina, hot plug, VoiceOver, keyboard-only use, system shortcuts,
sleep/lock and emergency confirmation remain explicit manual acceptance work.
