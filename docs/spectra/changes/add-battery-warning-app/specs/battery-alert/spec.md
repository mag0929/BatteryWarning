## Purpose

Define how the app observes battery state, decides whether a low-battery alert is active, and presents that alert so the user notices it without losing the keyboard focus of the application they are working in.

## ADDED Requirements

### Requirement: Continuous battery state monitoring

The system SHALL observe battery level, external power connection, and charging state, and SHALL re-evaluate the alert condition on every observed status update. The system SHALL also re-read battery status on a timer at least once every 30 seconds so that level changes which emit no power-source event are still detected.

#### Scenario: Battery level drops to the alert threshold while unplugged

- **WHEN** the observed battery level becomes less than or equal to the alert threshold and no external power is connected
- **THEN** the system SHALL mark the alert condition as active

#### Scenario: Battery level is already low but the machine is plugged in

- **WHEN** the observed battery level is less than or equal to the alert threshold and external power is connected
- **THEN** the system SHALL NOT mark the alert condition as active

#### Scenario: No power event arrives within the polling window

- **WHEN** no power-source change event has arrived for 30 seconds
- **THEN** the system SHALL re-read the battery status and re-evaluate the alert condition

#### Scenario: System resumes from sleep

- **WHEN** the system resumes from sleep
- **THEN** the system SHALL re-read the battery status immediately rather than acting on the last known value

### Requirement: Alert activation uses a clear threshold above the trigger threshold

The system SHALL use two thresholds: an alert threshold the user can adjust, and a clear threshold fixed at 5 percentage points above the alert threshold. The alert condition SHALL become active when battery level is less than or equal to the alert threshold and no external power is connected, and SHALL become inactive when battery level is greater than or equal to the clear threshold or external power becomes connected. The default alert threshold SHALL be 20.

#### Scenario: Default threshold activation and clearing

- **WHEN** the alert threshold is the default 20
- **THEN** the system SHALL activate the alert at battery level 20 and SHALL clear the alert at battery level 25

#### Scenario: Battery level fluctuates inside the hysteresis band

- **WHEN** the alert condition is active at the default threshold and the battery level rises to 21 but stays below 25
- **THEN** the system SHALL keep the alert condition active

##### Example: default threshold state transitions

| Previous level | New level | External power | Alert after change |
| --- | --- | --- | --- |
| 21 | 20 | no | active |
| 20 | 21 | no | active |
| 20 | 24 | no | active |
| 20 | 25 | no | inactive |
| 20 | 30 | no | inactive |
| 20 | 15 | yes | inactive |

### Requirement: External power connection clears the alert regardless of charging state

The system SHALL treat external power connection as sufficient to clear the alert condition and SHALL NOT require the battery to be actively charging. This covers machines that are connected to power while fully charged or while charge optimization is active.

#### Scenario: Machine is plugged in but not charging

- **WHEN** external power is connected, the battery is not charging, and the battery level is below the clear threshold
- **THEN** the system SHALL clear the alert condition

#### Scenario: External power is disconnected again while the battery is still low

- **WHEN** external power is disconnected and the battery level is still less than or equal to the alert threshold
- **THEN** the system SHALL mark the alert condition as active

### Requirement: Alert panel is presented above all applications

The alert SHALL be presented as a panel whose window level is higher than the window level of every application, including full-screen applications and the macOS menu bar. The panel SHALL appear without changing which application holds keyboard focus, so that the user can continue typing in the application they were already using.

#### Scenario: Alert appears while a regular application is active

- **WHEN** the alert condition becomes active and a regular application is frontmost
- **THEN** the alert panel SHALL be visible above that application's windows and the frontmost application SHALL remain the keyboard focus owner

#### Scenario: Alert appears while a full-screen application is active

- **WHEN** the alert condition becomes active while a full-screen application occupies the display
- **THEN** the alert panel SHALL be visible above the full-screen application's window

#### Scenario: User keeps typing during the alert

- **WHEN** the alert panel is visible
- **THEN** keystrokes SHALL still be delivered to the application that held keyboard focus before the panel appeared

### Requirement: Alert panel follows the display under the pointer

The alert panel SHALL be placed on the display that contains the mouse pointer. When the pointer moves to a different display while the alert is active, the panel SHALL relocate to that display. The panel SHALL NOT cover the macOS menu bar contents on the display it is shown on.

#### Scenario: Alert triggered on a secondary display

- **WHEN** the alert condition becomes active while the mouse pointer is on the second display
- **THEN** the alert panel SHALL be placed on the second display

#### Scenario: Pointer moves to another display during an active alert

- **WHEN** the alert condition is active and the mouse pointer moves to a different display
- **THEN** the alert panel SHALL relocate to the display now containing the pointer

#### Scenario: Menu bar is hidden on the display showing the panel

- **WHEN** the menu bar is not visible on the display containing the pointer
- **THEN** the alert panel SHALL NOT reserve vertical space for the menu bar

### Requirement: Alert panel is dismissed automatically without user interaction

The alert panel SHALL be hidden automatically when the alert condition becomes inactive, and SHALL re-evaluate at once whenever the user changes the alert threshold. Changing the threshold SHALL be evaluated as a fresh decision rather than continuing from the previous alert state, because the user has just redefined which levels count as low. The panel SHALL provide no control that the user must press to dismiss it, and dismissing the alert SHALL NOT require any user interaction.

#### Scenario: Plugging in power dismisses the panel

- **WHEN** the alert panel is visible and external power becomes connected
- **THEN** the panel SHALL be hidden without any user interaction

#### Scenario: Lowering the threshold below the current level dismisses the panel

- **WHEN** the alert panel is visible and the user lowers the alert threshold to a value below the current battery level
- **THEN** the panel SHALL be hidden immediately without waiting for the next polling interval, because the battery is no longer below the threshold

#### Scenario: Raising the threshold above the current level shows the panel

- **WHEN** the alert panel is hidden and the user raises the alert threshold to a value at or above the current battery level while no external power is connected
- **THEN** the panel SHALL appear immediately without waiting for the next polling interval

#### Scenario: Raising the threshold while already below it keeps the panel

- **WHEN** the alert panel is visible at a battery level below the current threshold and the user raises the threshold further
- **THEN** the panel SHALL stay visible, because the battery remains below the new threshold

### Requirement: User can adjust the alert threshold from the menu bar menu

The menu bar menu SHALL display the current alert threshold and SHALL provide menu items to raise and lower it. Adjustments SHALL move the threshold in steps of 5 percentage points within the range 5 to 50. The menu SHALL rebuild its items each time it opens and SHALL disable an adjustment item when the threshold is already at the corresponding bound. Pressing an adjustment item SHALL NOT dismiss the open menu in a way that requires a second interaction to see the new value.

#### Scenario: Raising the threshold from the menu

- **WHEN** the user selects the raise item while the threshold is 20
- **THEN** the threshold SHALL become 25 and the displayed threshold SHALL read 25

#### Scenario: Lowering the threshold from the menu

- **WHEN** the user selects the lower item while the threshold is 20
- **THEN** the threshold SHALL become 15 and the displayed threshold SHALL read 15

#### Scenario: Raise item is disabled at the upper bound

- **WHEN** the threshold is 50 and the user opens the menu
- **THEN** the raise item SHALL be disabled and the stored threshold SHALL remain 50

#### Scenario: Lower item is disabled at the lower bound

- **WHEN** the threshold is 5 and the user opens the menu
- **THEN** the lower item SHALL be disabled and the stored threshold SHALL remain 5

#### Scenario: Clear threshold always stays above the alert threshold

- **WHEN** the user raises the alert threshold to 50
- **THEN** the clear threshold SHALL be 55 and SHALL NOT be settable to a value less than or equal to the alert threshold

### Requirement: Alert threshold is persisted across app restarts

The system SHALL store the adjusted alert threshold in user defaults and SHALL reload it on launch. A stored value outside the range 5 to 50, or a stored value whose type cannot be read as an integer, SHALL be discarded in favour of the default 20 so that an externally written invalid value cannot disable the alert permanently.

#### Scenario: Threshold survives quit and relaunch

- **WHEN** the user sets the threshold to 30, quits the app, and launches it again
- **THEN** the displayed threshold SHALL be 30 and the clear threshold SHALL be 35

#### Scenario: Stored threshold is out of range

- **WHEN** the stored threshold is 200
- **THEN** the system SHALL use the default 20 and SHALL record the substitution in the system log

#### Scenario: Stored threshold is negative

- **WHEN** the stored threshold is -5
- **THEN** the system SHALL use the default 20 and the alert SHALL remain active at a battery level of 20

#### Scenario: Stored value is not an integer

- **WHEN** the stored threshold cannot be read as an integer
- **THEN** the system SHALL use the default 20 without crashing

### Requirement: Menu bar always reports current battery status

The menu bar SHALL show an item reporting the current battery level for the whole time the app runs. While the alert condition is active the item SHALL be rendered in a warning colour and SHALL carry a charging prompt. The alert panel and the menu bar item SHALL reflect the same alert condition, so that they cannot disagree.

#### Scenario: Normal battery level

- **WHEN** the alert condition is inactive
- **THEN** the menu bar item SHALL show the current battery level without a warning colour

#### Scenario: Alert active

- **WHEN** the alert condition is active
- **THEN** the menu bar item SHALL show a warning colour and the charging prompt alongside the battery level

#### Scenario: Alert clears

- **WHEN** the alert condition becomes inactive
- **THEN** the menu bar item SHALL return to its normal appearance in the same update that hides the panel

### Requirement: Machines without a battery are handled silently

When the system reports no battery, the system SHALL treat battery state as unavailable, SHALL NOT activate the alert condition under any battery level, and SHALL report the absence in the menu bar. The system SHALL NOT surface an error to the user.

#### Scenario: Desktop Mac with no battery

- **WHEN** the app runs on a Mac with no internal battery
- **THEN** no alert panel SHALL ever appear and the menu bar item SHALL report that no battery information is available

#### Scenario: Battery status cannot be read

- **WHEN** the system fails to read battery status
- **THEN** the system SHALL treat the battery as unavailable, SHALL NOT show a panel, and SHALL NOT crash

### Requirement: Diagnostic failures are silent to the user

Every failure encountered while reading battery status, registering the app, or storing the threshold SHALL be written to the system log and SHALL NOT be presented as a dialog or alert to the user.

#### Scenario: Status read fails repeatedly

- **WHEN** battery status reads fail on consecutive polling intervals
- **THEN** the system SHALL log each failure and SHALL NOT display any dialog
