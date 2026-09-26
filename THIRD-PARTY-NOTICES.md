# Third-Party Notices

## Pokemon intellectual property

Pokemon and all related names, characters, creatures, moves, items, types,
sprites, music, sound effects and other assets are the intellectual property
and/or registered trademarks of **Nintendo**, **Creatures Inc.**, **GAME FREAK
inc.** and **The Pokemon Company**.

This mod is an **unofficial, free, fan-made project** for the
[gen1recomp](https://github.com/bryanthaboi/gen1recomp) engine. It is **not**
produced, affiliated with, sponsored by, endorsed by or approved by Nintendo,
Creatures Inc., GAME FREAK inc., The Pokemon Company or any of their
subsidiaries or affiliates, and it claims no ownership of, or licence to, any
Pokemon intellectual property. The Pokemon names and other marks it reads or
displays remain the property of their owners and are used only to describe the
game data the mod operates on.

## This mod's own work

The only material this project owns is its **original source code** -- the Lua
that hooks the gen1recomp engine, written by its author. That code is licensed
under the **GNU General Public License, version 3 or later (GPL-3.0-or-later)**,
copyright (C) 2026 **tectorifter** (<https://github.com/tectorifter/>); the full
licence text ships beside this file as `LICENSE`. That grant covers this
project's own code only -- it does **not** purport to license any Pokemon data,
artwork, audio, text or other game asset, which remain their owners' property.

## Third-party material

- This mod is Lua code only. It depends on the optional **g9-battle-engine**
  and **g9-Battle-Scene** mods (battle resolution and screen) and, when
  present, on **national_dex** (species / move data). None of those is bundled.
- The sample teams it registers contain **Pokemon names, species, moves and
  items**, which remain Pokemon IP; they are data passed to the engine, not
  artwork or text redistributed by this mod.

## Sources and credits

- **g9-battle-engine** / **g9-Battle-Scene** -- the optional mods this sample
  exercises.
- **national_dex** -- the optional data source the sample's teams are resolved
  against.
- **gen1recomp** (<https://github.com/bryanthaboi/gen1recomp>) -- the engine this
  project builds on; its public mod API and engine behaviour are what this code
  hooks. See that repository for its own licence.
