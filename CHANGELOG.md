# ListInventory

## Unreleased

- Test build: the list opens and closes with the game's bag window, so every way of opening the bags (bag button, LB+RB+B, the radial menu, vendors) opens it. In Forever's gamepad mode the game's cursor drives the list.
- Fixed: the list swallowed every controller press while it was shown.
- Fixed: Esc / B no longer goes through the game's special-windows list, which caused taint in Forever.
- `/li probe` saves controller diagnostics.

First version, for World of Warcraft: Forever (interface 16001).

- Replaces the bags with a scrollable list: one row per item, with this character's bag count and the total across the bank and every alt on the same realm, ruleset and faction.
- Items spread over several stacks open a sub-menu of those stacks.
- Every stack is a real bag slot, so use, sell, bank, trade, mail, pick up, split, link and destroy all work.
- Full controller navigation, including in combat (except using items, which waits for combat to end).
- Item tooltips show how many of the item each character has.
