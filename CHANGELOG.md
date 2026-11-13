# Changelog

## 2.2.0

### Fixed
- **Duplicate macros:** the addon could create a second copy of a macro it had just made. This happened when the server hadn't synced the new macro yet and the addon re-applied shortly after, for example on the delayed second pass after a talent switch. The addon now remembers each macro's text as well as its slot, so it recognises its own macro.
- **Unnamed macros in the Replace dialog:** they were saved under an empty name, which could mix up different unnamed macros. They are now tracked by their text.
- **Duplicate prompts:** if the same macro was on several action bar slots and the macro bank was full, you were asked once per slot. Now you are asked once, and one Replace fills every slot that needed it.
- **Stale prompts:** if the exact macro (same name and text) already exists in the bank by the time the dialog opens, the prompt is skipped and the macro is placed on its slots.

### Changed
- **Default for a full macro bank:** new installs now start on "Auto-pick one, but ask me to confirm" instead of "do nothing". Existing saves keep their current setting.
- **Replace list (Auto and manual):** macros the set being applied needs are no longer offered for replacement. If none are left, the dialog tells you to free a slot manually.
- **Auto pick:** it now chooses a macro that is on no action bar, preferring one that is not stored in any saved set either, with ties going to the lowest slot. If every remaining macro is on a bar, it pre-selects nothing. You still have to click Replace.
