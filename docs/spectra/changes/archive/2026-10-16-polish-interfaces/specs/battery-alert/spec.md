## ADDED Requirements

### Requirement: Menu bar always shows the app status icon

The menu bar SHALL show a single status icon for the whole time the app runs, so the user can always find the app and open its menu. The menu bar item SHALL NOT display any text alongside the icon. The current battery level and the alert state SHALL be reported by the alert panel and by the menu opened from the item, not by the menu bar itself.

#### Scenario: Normal battery level

- **WHEN** the alert condition is inactive
- **THEN** the menu bar item SHALL display the status icon and no text

#### Scenario: Alert active

- **WHEN** the alert condition is active
- **THEN** the menu bar item SHALL display the status icon and no text

#### Scenario: Alert clears

- **WHEN** the alert condition becomes inactive
- **THEN** the menu bar item SHALL display the status icon and no text

#### Scenario: Battery level is reported when the menu opens

- **WHEN** the user opens the menu from the menu bar item
- **THEN** the menu SHALL report the current battery level and power state

### Requirement: Alert panel reports the current battery level

The alert panel SHALL display the observed battery level as a percentage and SHALL display a charging prompt next to it, preceded by a warning marker so the prompt reads as a caution rather than a suggestion, so the user can tell how much charge remains without leaving the application they are working in. The displayed level SHALL be re-read whenever the observed battery level changes while the panel is visible. The panel SHALL render the battery icon that matches the same observed level.

#### Scenario: Panel shows the observed battery level

- **WHEN** the alert condition is active and the observed battery level is 15 percent
- **THEN** the alert panel SHALL display 15 percent

#### Scenario: Panel follows a change in the observed level

- **WHEN** the alert panel is visible and the observed battery level changes from 15 percent to 12 percent
- **THEN** the alert panel SHALL display 12 percent

#### Scenario: Panel icon matches the displayed level rather than the lowest level

- **WHEN** the alert condition is active and the observed battery level is 45 percent
- **THEN** the alert panel SHALL render the battery icon selected for 45 percent rather than the icon selected for the lowest level

#### Scenario: Panel level stays correct across a threshold change

- **WHEN** the user raises the alert threshold so that the alert condition becomes active at 45 percent
- **THEN** the alert panel SHALL display 45 percent and SHALL render the icon selected for 45 percent

#### Scenario: Charging prompt is preceded by a warning marker

- **WHEN** the alert panel is visible
- **THEN** the charging prompt SHALL be preceded by a warning marker

### Requirement: Alert panel renders a battery icon for the observed level

The alert panel SHALL render a battery icon that matches the observed battery level and the observed charging state. The icon SHALL remain distinguishable from the panel background under both the light system appearance and the dark system appearance. The menu bar item SHALL render a single fixed status icon instead of a battery icon, and SHALL NOT change as the battery level changes.

#### Scenario: Panel icon shows the observed level

- **WHEN** the alert condition is active and the observed battery level is 15 percent and the battery is not charging
- **THEN** the alert panel SHALL render the icon selected for the 15 percent level

##### Example: observed level resolves to an icon bucket

| Observed level          | Selected icon          |
| ----------------------- | ---------------------- |
| 0 percent               | lowest-level icon      |
| 25 percent              | lowest-level icon      |
| 26 percent              | second icon            |
| 50 percent              | second icon            |
| 51 percent              | third icon             |
| 75 percent              | third icon             |
| 76 percent              | fourth icon            |
| 100 percent             | fourth icon            |
| any level, charging     | charging icon          |

#### Scenario: Panel icon shows the charging state

- **WHEN** the battery is charging
- **THEN** the alert panel SHALL render the charging icon instead of a level icon

##### Example: charging takes priority over the level

- **GIVEN** a battery at 80 percent that is charging
- **WHEN** the alert panel renders
- **THEN** it SHALL render the charging icon rather than the icon for 80 percent

#### Scenario: Menu bar icon does not change with the battery level

- **WHEN** the observed battery level changes from 15 percent to 80 percent
- **THEN** the menu bar item SHALL display the same fixed status icon and no text

#### Scenario: No battery means no panel icon

- **WHEN** the system reports that no battery is present
- **THEN** the alert panel SHALL NOT display a battery icon

##### Example: desktop Mac with no internal battery

- **GIVEN** a status reporting no battery present
- **WHEN** the alert panel renders
- **THEN** it SHALL NOT display a battery icon

#### Scenario: Icon stays distinguishable under the dark system appearance

- **WHEN** the system appearance is dark
- **THEN** the battery icon SHALL remain distinguishable from the panel background

#### Scenario: Level outside the covered ranges still yields an icon

- **WHEN** the observed battery level falls outside the ranges the icon set covers
- **THEN** the icon selected for the nearest covered level SHALL be rendered instead of no icon

##### Example: levels outside the covered range

| Observed level | Selected icon     |
| --------------- | ----------------- |
| -1 percent      | lowest-level icon |
| 101 percent     | fourth icon       |
| 150 percent     | fourth icon       |

## MODIFIED Requirements

### Requirement: Machines without a battery are handled silently

When the system reports no battery, the system SHALL treat battery state as unavailable, SHALL NOT activate the alert condition under any battery level, and SHALL report the absence in the menu opened from the menu bar item. The system SHALL NOT surface an error to the user.

#### Scenario: Desktop Mac with no battery

- **WHEN** the app runs on a Mac with no internal battery
- **THEN** no alert panel SHALL ever appear and the menu opened from the menu bar item SHALL report that no battery information is available

#### Scenario: Battery status cannot be read

- **WHEN** the system fails to read battery status
- **THEN** the system SHALL treat the battery as unavailable, SHALL NOT show a panel, and SHALL NOT crash

## REMOVED Requirements

### Requirement: Menu bar always reports current battery status

**Reason**: The menu bar no longer reports anything about the battery. It shows one fixed status icon and no text; the battery level and the alert state are reported by the alert panel and by the menu opened from the item. A requirement whose title promises a report the interface no longer performs would send anyone reading this spec looking for behaviour that does not exist.

**Migration**: Read "Menu bar always shows the app status icon" for what the menu bar itself does. Read "Alert panel reports the current battery level" and the scenario "Battery level is reported when the menu opens" for where the battery level is actually reported.