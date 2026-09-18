---
status: closed
priority: 100
kind: feature
tags:
    - game
    - refactor
---

# Refactor the game metadata out into a tagged union

We want to allow more than just steam games to work, currently the games id is saved directly from the library it gets it from.
probably, should create a UUID for each game, then save the metadata of that game in a separate field on it which then allows us to still query more specific data on it.

## The current situation

Currently most of the games data that is coming from the library, is just saved on the game itself.
For example:

```zig
const game: Game = .{
    .id = "<STEAM_ID>"
    .icon = "<STEAM_ICON>"
}
```

this is not good because in the future when we want to add more libraries (epic games, battle.net, ubisoft connect, manual, ...), we would not be able to create them since
they do not have a steam id.

## Proposed solution

The best solution in my opinion is to add a field that is a tagged union of the library added fields.
For example:

```zig
.{
    .name = "GAME TITLE"
    .library_data = .{
        .library_source = .steam,
        .id = steam_id,
    } // Tagged Union
}
```

so if for example in the future we have GOG games:
```zig
    .name = "GAME TITLE"
    .library_data = .{
        .library_source = .gog,
        .id = gog_id,
    } // Tagged Union
```
