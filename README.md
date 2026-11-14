# ListInventory

A World of Warcraft: Forever addon that shows your bags as a scrollable list of items, built to be driven with a controller.

> **Test build.** The list currently opens *beside* the game's bag window rather than replacing it, while the controller integration with Forever's gamepad mode is worked out. See [Controller](#controller).

- **One row per item**, sorted by name, with two counts: how many are in this character's **Bags**, and the **Total** across this character's bank and every alt on the same realm, ruleset and faction. If you're farming Linen Cloth, the Linen row tells you at a glance how much you have everywhere.
- **Stacks sub-menu.** Selecting an item that's spread over several stacks opens a list of those stacks (bag and slot, count each), so you can pick the exact one.
- **Everything you can do in the default bags.** Each stack is a real bag slot: use, equip, open, sell to a vendor, put in the bank, trade, mail, pick up, split (Shift-click), link (Shift-click) and destroy.
- **Two views.** **Bags** shows what you're carrying, plus the bank while it's open. **Everything** also lists items that only your bank or your alts have.
- **Tooltips everywhere** gain a per-character count: "Total 367 / Main 67 (27 bags, 40 bank) / Alt 100 ...".
- Free bag slots and your gold are shown at the bottom. An **Empty slots** row lets you put a picked-up item into a particular slot.

Requires the World of Warcraft: Forever client (interface 16001).

## Controller

The list opens and closes with the game's bags, however they are opened: the bag button, the LB+RB+B chord, the Start-button radial menu, or a vendor, bank or mailbox.

The game's bag window stays open behind the list but hidden, whichever input you're using. While you hold an item (after picking it up), the bag window shows again so you can see where it goes, and hides once it's placed.

**With Forever's Gamepad UI on**, the game's own controller cursor drives the list. The list steers the cursor through the hidden bag slots in list order:

- **D-pad up/down** moves between items in the list.
- **D-pad left/right** steps through that item's stacks; the row shows which one ("< 2 of 3 >") and its count.
- **A, X, Y and B** are the game's own bag buttons (A select / pick up, X use, Y More, B close), so everything works exactly as in the default bags, in combat too.

`/li grid` shows the game's bag window again behind the list (handy if something looks wrong). This is new, so `/li probe` saves diagnostics to send back if it misbehaves.

**With the Gamepad UI off**, a controller still works: the list takes it itself, with the same buttons as the game's bags:

| Button | In the list | In a stacks sub-menu |
| --- | --- | --- |
| D-pad up/down | Move (hold to repeat) | Move |
| LT / RT | Page up / down | Page up / down |
| LB / RB | Switch Bags / Everything | – |
| A | Open the stacks sub-menu, or pick up a single stack. Holding an item: put it there | Pick up the stack, or put the held item there |
| X | Use or equip a single stack | Use or equip the stack |
| Y | More menu: Destroy (asks first), Link in chat | More menu |
| B | Close the bags | Back to the list |

The selected item's tooltip, with its per-character counts, sits next to the window.

B closes the list and the bags together.

**In combat** (gamepad mode off) the game doesn't let addons change controller bindings, so the list reads the controller directly instead. Moving, stacks, pick up, place and destroy still work. **Using** an item with A has to wait until combat ends, but clicking it with the mouse still works.

## Mouse

Click a row with several stacks to open its stacks. Click an item icon to do exactly what clicking it in the default bags does: right-click to use, sell or bank it, left-click to pick it up, Shift-click to link or split. Right-click a stacks list to go back. Drag the title bar to move the window when it's opened with `/li`; with the bags it sits beside the bag window. Esc closes it (with the bags, Esc closes the bags and the list together).

## Counting your alts

Each character's bags are saved whenever they change. Its bank is saved each time you open the bank, so **log in on each alt and visit the bank once** to get their numbers in. Characters are grouped by realm, ruleset and faction, so Horde characters on a normal realm are counted together and apart from your Alliance or hardcore characters.

## Commands

| Command | What it does |
| --- | --- |
| `/li` | Open or close the list (also `/listinv`) |
| `/li default` | Turn opening the list with your bags on or off. `/li` still opens it. |
| `/li probe` | Test build: save controller diagnostics (names and call paths only) to the saved settings file |
| `/li tooltip` | Turn the tooltip counts on or off |
| `/li chars` | List the characters counted together, and when each bag and bank was last seen |
| `/li forget <name>` | Stop counting a deleted or transferred character |
| `/li status` | Diagnostics |

Settings and counts are saved for your whole account.

## Install

Copy this folder into your Forever client's `Interface/AddOns` folder. On a default Windows install that folder is:

```
C:\Program Files (x86)\World of Warcraft\_forever_\Interface\AddOns
```

You should end up with `Interface/AddOns/ListInventory/ListInventory.toc`. Restart the game or type `/reload`, then make sure **ListInventory** is enabled in the AddOns list on the character screen.

## Troubleshooting

1. Type `/console scriptErrors 1` so Lua errors show on screen, then `/reload`.
2. Type `/li status` and include its output when you open an issue.

If the list gets in the way, `/li default` stops it opening with your bags.

## Development

The addon is plain Lua with no libraries. The repository root is the addon folder:

- `ListInventory.toc` – addon metadata. `@project-version@` is filled in at build time.
- `Data.lua` – item keys, per-character counts and the sorted rows (makes no game calls)
- `Core.lua` – saved data, bag and bank scanning, events, tooltip counts, slash commands
- `UI.lua` – the list window, its own controller navigation, and opening with the game's bags
- `Gamepad.lua` – Forever's gamepad mode: steering the game's cursor through the hidden bag slots in list order
- `tests/Data_test.lua` – tests for `Data.lua`

### Tests

The tests need Lua 5.1 or LuaJIT. On Windows, `winget install DEVCOM.LuaJIT` installs it. Run from the repository root:

```bash
luajit tests/Data_test.lua
```

It prints `N passed, 0 failed` and exits 0 on success. GitHub Actions runs it on every push.

### Local build

```powershell
.\build.ps1 -Version 0.1.0
```

This writes `dist\ListInventory-0.1.0.zip`. Add `-AddOnsPath "<your Interface\AddOns folder>"` to install the build straight into the game.

### Releasing

Releases are built by the [BigWigs packager](https://github.com/BigWigsMods/packager) in GitHub Actions (`.github/workflows/release.yml`) when you push a tag like `v0.1.0`. To publish to CurseForge, Wago or WoWInterface, add the project ID to `ListInventory.toc` (`## X-Curse-Project-ID:`, `## X-Wago-ID:`, `## X-WoWI-ID:`) and the site's token as a repository secret (`CF_API_KEY`, `WAGO_API_TOKEN`, `WOWI_API_TOKEN`).

## License

[MIT](LICENSE)
