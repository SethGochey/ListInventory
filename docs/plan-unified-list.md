# Plan: one list instead of the Bags / Everything tabs

Status: built on `feature/unified-list` (after 1.0). Both open questions were settled as proposed: Elsewhere starts expanded, and this character's bank counts as Elsewhere while the bank window is closed.

## Problem

With Forever's Gamepad UI on, there is no controller way to switch between the **Bags** and
**Everything** tabs. With a mouse the tabs are fine, and most players use a mouse and keyboard, so
1.0 keeps them. This plan is for controller players.

## Why not LB / RB to switch tabs

- With the Gamepad UI on, LB and RB belong to the game: its own override bindings
  (`InputFunctionBindingButton_*`) win over an addon's, and LB and RB are part of the game's bag
  chord (LB+RB+B).
- Catching them would mean reading the buttons behind the game's back (`IsKeyDown` polling),
  which may also fire whatever the game does with them, or fighting the game's bindings again.

## Proposal: one list, two sections

1. **In your bags**: the current Bags rows, then the **Empty slots** row.
2. **Elsewhere**: items only in this character's bank or on alts, under a divider, drawn greyed
   (as the Everything tab draws them now).

The tabs go away.

### Why this suits what comes later

Post-1.0 features this has to leave room for: sorting by more than name (type, category,
rarity), filtering, and search.

- **Sorting** applies within each section, so what you can act on always stays on top.
- **Grouping** by category later is the same mechanism as these sections: more headers.
- **Filtering and search** apply to the whole list at once instead of two tabs' worth of results.
- A sort or filter choice then only needs a way to cycle it, without competing with tab
  switching for the same buttons.

## Reaching "Elsewhere" with the controller (Gamepad UI on)

The game's cursor only stands on real bag slots, and Elsewhere rows have none. So:

- **In:** pressing **down on the Empty slots row** (the last bag row) moves the list's
  selection into Elsewhere. Detected by polling `IsKeyDown("PADDDOWN")` while the cursor is on an
  empty slot; the slot's DOWN jump already points at itself, so the cursor stays put.
- **Browsing:** the game's cursor stays parked on that **empty slot**, so A, X and Y act on an
  empty slot and do nothing harmful. While browsing, the parked slot's UP jump also points at
  itself, so D-pad up/down only move the list's selection. Each row shows its tooltip with the
  per-character counts (a hyperlink tooltip beside the list, as now).
- **Out:** pressing **up past the first Elsewhere row** returns to the bag rows: restore the
  parked slot's normal jumps, select the Empty slots row.
- **Bags full** (no empty slot to park on): no browsing; show a hint instead, "Free a bag slot to
  browse items elsewhere". This is the main weakness of the approach.
- **Holding an item** while browsing: leave browse mode first (the grid hand-over takes over).

With the mouse, or with the Gamepad UI off, Elsewhere is just more rows: the mouse wheel and
the list's own D-pad navigation already reach them.

## Work

- `Data.BuildRows`: one call returning bag rows, then elsewhere rows, with a section marker;
  tests for the order (bag items first, then elsewhere), including under a filter.
- `UI.lua`: drop the tabs; draw a section divider row; `ns.db.view` no longer used (migrate
  it away).
- `Gamepad.lua`: browse mode as above (poll D-pad edges, park on an empty slot, swap that
  slot's UP jump while browsing, restore on leaving or on picking something up).
- README and CHANGELOG.

## Open questions

- Should Elsewhere start collapsed, with its row count in the divider, to keep the list short?
- Should the bank (this character's) count as "elsewhere" when the bank is closed? Proposed:
  yes; when the bank window is open its stacks are real slots and appear in the bags section.
