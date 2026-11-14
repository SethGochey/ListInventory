# ListInventory

## v1.0.0

- **The list replaces the bags.** It opens and closes with the game's bag window however the bags are opened (bag button, LB+RB+B, the Start-button radial menu, vendors, bank, mail) and sits right over it while it's hidden.
- **Forever's Gamepad UI:** the game's own controller cursor drives the list. D-pad up/down moves between items in list order, left/right steps through an item's stacks, and A/X/Y/B are the game's own bag buttons, in combat too. Holding an item hands the grid back for normal movement until it's placed.
- **Gamepad UI off:** a controller still works through the list's own controls, matching the game's bags (A pick up / place, X use, Y More with Destroy and Link in chat, B back / close). With the mouse, items in the list click exactly like bag slots.
- Item tooltips sit beside the list and show counts on every character in the group.
- `/li grid` shows the game's bag window behind the list. `/li probe` and `/li status` help with troubleshooting, including tracing "Interface action failed" messages.

## v0.1.0

First version, for World of Warcraft: Forever (interface 16001).

- Replaces the bags with a scrollable list: one row per item, with this character's bag count and the total across the bank and every alt on the same realm, ruleset and faction.
- Items spread over several stacks open a sub-menu of those stacks.
- Every stack is a real bag slot, so use, sell, bank, trade, mail, pick up, split, link and destroy all work.
- Full controller navigation, including in combat (except using items, which waits for combat to end).
- Item tooltips show how many of the item each character has.
