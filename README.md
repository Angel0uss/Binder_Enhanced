# Binder Enhanced

A keybinding and loadout manager for World of Warcraft (WotLK 3.3.5a). Perfect especially for players who use more than two specializations or play the same class across multiple accounts, allowing them to switch talents/toon without having to reconfigure their UI every time. save once and let the auto apply trigger for you 

Save a full setup — keybinds, action bars, gear, and macros — as a named **Set**, organize Sets under **Profiles**, and re-apply or share them whenever you need to.

## Features

### Profiles & Sets
- Organize saved setups into **Profiles**, each holding any number of **Sets**
- Standalone description/notes field per Set, editable independently of saving
- Tree-list view of all Profiles and Sets with quick apply/save/delete actions

### Keybinds
- Capture and restore keybindings, either **Character**-specific or **General/account-wide**
- Confirm/diff popup before applying, so you can see what a Set will change before committing
- Unbound keybinds in saved sets stay unbound after applying and don't revert to blizzard default values like they used to.

### Action Bars
- Save and restore full action bar layouts, including:
  - Spells
  - Items
  - Macros (see below)
  - Mounts & companion pets
- A confirm popup previews the apply before anything changes

### Macros
- Macros are restored to their original macro bank (General/Character) and placed back on the same bar spot
- Automatically **re-creates missing macros** on the target character if they no longer exist
- Matches existing macros by name and body content so it never overwrites the wrong macro
- **Full Macro Bank resolve dialog**: if a macro's bank (General or Character) is full, choose an existing macro to replace, or skip it — includes a body-content preview for unnamed/blank-named macros so they can be told apart
- Configurable behavior for a full bank: prompt to pick a replacement, auto-pick one, or just skip

### Gear
- Equip a saved Equipment Manager gear set as part of applying a Set

### Talent-Spec Auto-Apply (Talent Link)
- Link a Set to a specific talent spec
- Automatically re-applies keybinds, bars, gear, and macros the moment you switch to that spec — no manual click needed

### Export / Import
- Export any Set as a single paste-able string, portable between characters and accounts
- Import that string back into any character's Profile list
- Legacy import support for Sets from the original "Binder" addon (by Tensai)

### Share
- Send a single Set directly to another player in-game via an addon message (keybinds only)

### UI
- Minimap button for quick access
- Full settings window (Interface Options panel links straight to it)
- Dedicated panels for Profiles/Sets, Talent Link & Settings, and Export/Import

### Slash Commands
- `/binder` — open the main window
- `/bde` — shortcut alias

## Requirements
- World of Warcraft client 3.3.5a (WotLK), Interface 30300
- Works on private servers targeting this patch (developed/tested on Warmane)
- If you're using bars addons like Bartender4, make sure to apply the same profile so your action bars match exactly.

## Installation
1. Download or clone this repository
2. Copy the `Binder_Enhanced` folder into your `Interface/AddOns/` directory
3. Restart the client (or `/reload`) and enable the addon at the character-select screen


## comming next
- saving bars disposition and layout (now it only save spells,macros etc)

## Author
Angelouss
