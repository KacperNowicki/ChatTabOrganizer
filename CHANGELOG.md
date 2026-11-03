# Changelog

## 0.2.0 - 2026-11-03

Fixes:

- The Communities tab now receives community messages. It previously used a message group that doesn't exist, so it stayed empty.
- A tab you turned off and back on now reappears. Closed chat windows keep their name, and the addon used to reuse the hidden window.
- Applying no longer closes chat windows you created yourself that happen to share a disabled tab's name. The main chat window and Combat Log are never touched.
- `/ctabs disable` now persists across reloads.
- The chosen font face is no longer lost after a reload or overwritten when opening the settings.
- The settings page is rebuilt on the current Settings API, replacing option templates removed from the game.
- Updated for patch 12.1.5 (Interface 120105).

New:

- Tab editor: add custom tabs, rename tabs, choose message types and channels per tab, and reorder tabs.
- Option to remove routed messages from the main chat tab (restored when turned off).
- Tabs are applied automatically at login (can be turned off); newly joined channels are picked up automatically; updates during combat wait until combat ends.
- Managed tabs stay docked in the configured order.
- Appearance settings also apply to whisper windows and new chat windows.
- `/ctabs apply` now applies immediately. Added `/ctabs tabs`, `/ctabs list` and `/ctabs join`; `/ctabs tab <name> on|off` accepts tab names.

## 0.1.12 - 2026-07-02

- Added a Join selected channels button that immediately requests named channels from enabled managed tabs.

## 0.1.11 - 2026-06-06

- Fixed the background color swatch layer so the selected color is visible instead of being covered by the border.

## 0.1.10 - 2026-06-05

- Removed the unused Current font dropdown option.
- Wrapped the current chat tab list into short lines so names stay inside the settings panel.
- Fixed color swatch refresh so picked colors are not overwritten by reading the selected chat tab again.

## 0.1.9 - 2026-06-05

- Tightened the settings panel layout so appearance controls fit inside the AddOns options panel.

## 0.1.8 - 2026-06-05

- Added live font-face selection for chat windows.
- Added live visual controls for all current chat tabs.
- Added managed tabs for common chat flows.
- Party tab includes raid, raid warning, and instance chat routing.
- Added manual Apply Now workflow for chat-tab routing.
