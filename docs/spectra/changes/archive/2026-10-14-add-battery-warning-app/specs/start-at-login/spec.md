## Purpose

Define how the app registers itself to start automatically after login, how the user turns that behaviour on and off, and how the app recovers when the macOS login item mechanism rejects the registration.

## ADDED Requirements

### Requirement: App runs without a Dock presence or main window

The app SHALL run as a menu bar application with no Dock icon and no main window. It SHALL NOT display any window, dialog, or notification at launch, so that starting the app produces no interruption to the user's session.

#### Scenario: App starts after login

- **WHEN** the app is started by the system at login
- **THEN** no window SHALL be shown, no Dock icon SHALL appear, and the menu bar item SHALL appear

#### Scenario: App is launched by the user

- **WHEN** the user launches the app from Finder
- **THEN** the app SHALL show only its menu bar item

### Requirement: App starts automatically after login when enabled

When launch at login is enabled, the app SHALL start automatically on every user login. The app SHALL complete startup without presenting a window to the user.

#### Scenario: Login after enabling launch at login

- **WHEN** the user enables launch at login, then logs out and logs back in
- **THEN** the app SHALL be running and its menu bar item SHALL be present without any window being shown

#### Scenario: Login after disabling launch at login

- **WHEN** the user disables launch at login, then logs out and logs back in
- **THEN** the app SHALL NOT be running

### Requirement: User controls launch at login from the menu bar menu

The menu bar menu SHALL contain a launch at login toggle whose checked state reflects whether the app will actually start after login. Selecting the toggle SHALL register or unregister the app and SHALL leave the toggle's checked state consistent with the actual registration outcome.

#### Scenario: Enabling the toggle

- **WHEN** the user selects the launch at login toggle while it is off
- **THEN** the app SHALL be registered to start at login and the toggle SHALL appear checked

#### Scenario: Disabling the toggle

- **WHEN** the user selects the launch at login toggle while it is on
- **THEN** the app SHALL be unregistered and the toggle SHALL appear unchecked

#### Scenario: Registration fails

- **WHEN** the user enables the toggle and the primary registration mechanism rejects the registration
- **THEN** the app SHALL fall back to the alternative mechanism before deciding the toggle's state

### Requirement: Login item registration falls back when the primary mechanism is rejected

The app SHALL first attempt registration through the macOS login item mechanism. If that registration returns an error, the app SHALL register itself through a per-user launch agent instead, so that launch at login still works. The fallback SHALL be applied automatically without asking the user.

#### Scenario: Primary registration succeeds

- **WHEN** the primary login item registration succeeds
- **THEN** the app SHALL NOT write a launch agent file and the user SHALL see the app in the system login items list

#### Scenario: Primary registration is rejected

- **WHEN** the primary login item registration returns an error
- **THEN** the app SHALL write a launch agent definition for the current user, load it, and launch at login SHALL still function

#### Scenario: Launch agent is removed on uninstall

- **WHEN** the app is removed from the applications folder
- **THEN** the launch agent definition SHALL be removable by the documented rollback procedure and SHALL NOT leave the app running after login

### Requirement: Actual registration state is the source of truth at startup

On every launch, the app SHALL read the actual registration state and SHALL reconcile it with the stored preference. If the user disabled the app from the system login items list outside the app, the app SHALL reflect that disabled state and SHALL NOT re-enable itself.

#### Scenario: User disables the app in System Settings before launch

- **WHEN** the user removed the app from the system login items list and then launches the app
- **THEN** the launch at login toggle SHALL appear unchecked and the app SHALL NOT re-register itself

#### Scenario: Registration removed outside the app

- **WHEN** the app's stored preference says launch at login is enabled but no registration exists
- **THEN** the launch at login toggle SHALL appear unchecked and the app SHALL NOT re-create the registration on its own, because the user may have removed it deliberately
- **AND** the app SHALL start automatically after login again only after the user turns the toggle back on

### Requirement: Registration failures are reported only through the toggle and the system log

When neither the primary mechanism nor the fallback can complete registration, the app SHALL leave the launch at login toggle unchecked, SHALL record the failure in the system log, and SHALL NOT display an error dialog.

#### Scenario: Both registration mechanisms fail

- **WHEN** the primary registration fails and the fallback also fails to load
- **THEN** the launch at login toggle SHALL appear unchecked, the failure SHALL be written to the system log, and no error dialog SHALL be shown
