# ListInventory

A World of Warcraft addon that lists the contents of your bags in chat.

## Usage

- `/listinv` – list every item in your bags (stacks combined, sorted by name)
- `/listinv <text>` – list only items whose name contains `<text>`

## Installation

Copy the `ListInventory` folder into `World of Warcraft/<client>/Interface/AddOns/`.

## Notes

`## Interface:` in `ListInventory.toc` must match your client's interface version
(check in-game with `/dump select(4, GetBuildInfo())`).
