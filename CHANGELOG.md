# ListInventory

## Unreleased

- Test build: the list opens and closes with the game's bag window, so every way of opening the bags (bag button, LB+RB+B, the radial menu, vendors) opens it. In Forever's gamepad mode the game's cursor drives the list.
- Fixed: the list swallowed every controller press while it was shown.
- Fixed: Esc / B no longer goes through the game's special-windows list, which caused taint in Forever.
- `/li probe` saves controller diagnostics.
- Gamepad mode: the game's bag window is hidden and its controller cursor is steered through the bag slots in list order (up/down: items, left/right: stacks), so A/X/Y/B are the game's own bag actions. `/li grid` shows the bag window again.
- Fixed: the game's slot buttons in the rows were hidden, so clicking items in the list did nothing.
- Rows always show an item icon; gold shows on Forever.
- The game's bag window stays hidden while the list is open, whatever the input; it shows while you hold an item. Stray mouse clicks can't reach the hidden slots.
- Controller buttons match the game's bags: A pick up / place, X use, Y More (Destroy, Link in chat), B back / close. Destroy is no longer a top-level button.
- No "new item" glow on the list's icons. The list's close button closes the bags too.
- The list sits right over the hidden bag window, so the game's More menu opens inside it.
- Gamepad UI: holding an item hands the cursor back to the game's grid (normal 2-D movement) until it's placed.
- On its own (/li) the list starts in the bottom-right corner.
- Gamepad UI: item tooltips open beside the list straight away, without a flicker at the hidden slot.

## v0.1.0

First version, for World of Warcraft: Forever (interface 16001).

- Replaces the bags with a scrollable list: one row per item, with this character's bag count and the total across the bank and every alt on the same realm, ruleset and faction.
- Items spread over several stacks open a sub-menu of those stacks.
- Every stack is a real bag slot, so use, sell, bank, trade, mail, pick up, split, link and destroy all work.
- Full controller navigation, including in combat (except using items, which waits for combat to end).
- Item tooltips show how many of the item each character has.
