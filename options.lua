-- Mod Manager option schema for g9-battle-sample.
--
-- Declared in manifest.json's "options_schema" field, so the manager (and
-- native launchers reading mod_option_schemas.json) can render these rows
-- even while this mod is disabled. main.lua calls mod.options:define() with
-- the IDENTICAL table at load time, which is what gives mod.options:get()
-- its defaults. Keep the two copies in sync (the engine's documented
-- convention for a mod that ships an options schema).
--
-- Row shapes (documented in the engine's own mod-options reference):
--   toggle : { key, label, type = "toggle", default = bool }
--   choice : { key, label, type = "choice", default = value,
--              choices = { { "LABEL", value }, ... } }
-- Labels are kept short -- the manager's row layout truncates long ones.
return {
  {
    key = "battle_scene",
    label = "2v2/3v3/4v1",
    type = "toggle",
    default = true,
    description = "ON (default): the custom layouts g9-Battle-Scene adds are chosen from the fight -- a wild encounter takes singles, doubles (2v2), triples (3v3), a 1v5 horde or the 0.5% bossFight, and a trainer fight picks doubles, triples or the 4v1 bossFight from the enemy battle that already exists (the Elite Four roll doubles-or-triples, Champion/Red and wild_forms's Eternatus are bossFight, everyone else doubles). OFF: every fight still renders through g9-Battle-Scene, but ALWAYS on its singles layout -- no doubles, triples, hordes or bossFights -- instead of falling back to the game's native screen. To switch the custom scene off entirely (native battles), turn OFF the BACKGROUND row in g9-Battle-Scene's own options.",
  },
  {
    key = "difficulty",
    label = "DIFFICULTY",
    type = "choice",
    default = "normal",
    choices = { { "EASY", "easy" }, { "NORMAL", "normal" },
                { "HARD", "hard" }, { "HELL", "hell" } },
    description = "Every trainer's Pokemon, and their team size. EASY: vanilla team size, 0 IVs, 0 EVs, neutral natures. NORMAL: at least 2 Pokemon, 10 IVs, 12 EVs, neutral. HARD: at least 4 Pokemon, 20 IVs, 24 EVs, a nature favouring the highest base stat. HELL: at least 6 Pokemon, 31 IVs, 252 EVs on the two highest base stats and 4 on the third, a nature that boosts the highest stat and lowers the weaker offence. A team is only ever grown when the vanilla one is smaller than the setting's floor.",
  },
  {
    key = "rand_wilds",
    label = "RAND WILDS",
    type = "toggle",
    default = true,
    description = "ON (default): an ordinary wild encounter's species is re-rolled to a random species that shares a type with it and whose base-stat total is within -5% to +(5*level)% of the original's. A WATER encounter (surfing or fishing) only re-rolls into a WATER- or FLYING-type species -- water areas are water-and-flying exclusive -- while a LAND or CAVE encounter bans WATER types (a FLYING type is welcome anywhere). Every randomised species is pushed to the latest evolution its level allows -- a level-up evolution needs its own level, a trade one needs level 40, a STONE evolution appears in the wild only from level 35, and a HELD-ITEM or HAPPINESS evolution appears from level 35 too (or level 25 when the mon evolving is a BABY, e.g. Happiny's Chansey) -- and a legendary is only ever picked at level 45 or higher. A blacklisted species (the BLACKLIST row on the OPTIONS menu) is never picked at all -- MEGA and GIGANTAMAX forms are delisted out of the box, and the window's own [MEGA] [GIGA] row flips either whole group at once. The random LAYOUT bands (hordes/triples/doubles/singles, and the 0.5% bossFight) stay on either way. In a DOUBLES or TRIPLES wild fight each extra enemy is rolled independently (a horde stays one species), and the two WILD LEVELS settings below apply.",
  },
  {
    key = "wild_levels",
    label = "WILD LEVELS",
    type = "choice",
    default = "off",
    choices = { { "OFF", "off" }, { "0", "0" }, { "+2", "2" }, { "+4", "4" },
                { "+6", "6" }, { "+8", "8" }, { "+16", "16" }, { "-2", "-2" },
                { "-4", "-4" }, { "-6", "-6" }, { "-8", "-8" },
                { "-16", "-16" } },
    description = "OFF (default) leaves every wild Pokemon at the level the game rolled it -- vanilla values, with no level difference applied. 0 sets the level to WILD LV ANCHOR exactly, and +2/+4/+6/+8/+16 or -2/-4/-6/-8/-16 add or subtract that much from the anchor. The area's own spawn-level spread is kept on top, so a delta of 0 on a party whose highest is 30 turns a route that rolls 2-4 into 30-32 (not a flat 30), and +16 makes it 46-48. Only read while RAND WILDS is on.",
  },
  {
    key = "wild_anchor",
    label = "WILD LV ANCHOR",
    type = "choice",
    default = "highest",
    choices = { { "LOWEST", "lowest" }, { "HIGHEST", "highest" },
                { "AVERAGE", "average" }, { "LEADER", "leader" } },
    description = "Which party Pokemon's level WILD LEVELS is measured from: LOWEST = the lowest level in your party, HIGHEST (default) = the highest, AVERAGE = the arithmetic mean, LEADER = the first Pokemon in your party. Only read while RAND WILDS is on and WILD LEVELS is not OFF.",
  },
  {
    key = "rand_trainers",
    label = "RAND TRAINER MONS",
    type = "toggle",
    default = true,
    description = "ON (default): every trainer, gym leader, Elite Four, Champion and rival has each party Pokemon swapped for a random species sharing at least one type and of equivalent BST (within -5% to +(5*level)%). Each swap is pushed to the latest evolution its level allows (trade/item/held-item/friendship evolutions from level 40 -- a trainer's roster keeps the level-40 gate, not the wild's 35/25), a legendary is only ever chosen at level 45 or higher, and a blacklisted species (Mega and Gigantamax forms are delisted by default) is never chosen at all. A gym leader's, Elite Four member's or gym trainer's swaps also stay on that gym's own type theme (GYM THEMES): Falkner only ever uses FLYING types, Brock only ROCK, and so on. OFF: trainer teams keep their real species.",
  },
  {
    key = "league_aces",
    label = "LEAGUE ACES",
    type = "toggle",
    default = true,
    -- Only offered while RAND TRAINER MONS is on: the aces ARE the slots the
    -- randomizer would otherwise overwrite, so the row is meaningless without
    -- it.  The engine's own `visible_if` schema field is what makes the manager
    -- show and hide this row LIVE as RAND TRAINER MONS is flipped (flipping a
    -- row rebuilds the menu), so it APPEARS when the randomizer is switched on
    -- and disappears again when it is switched off.
    visible_if = { key = "rand_trainers", equals = true },
    description = "ON (default): every league trainer -- a gym leader, an Elite Four member, the Champion or Red -- keeps its listed SIGNATURE Pokemon in the FINAL slots of its team, so RAND TRAINER MONS cannot randomize them away. The rest of the team is still randomized and grown by DIFFICULTY as usual, an ace takes the level of the slot it fills, and its nature/IVs/EVs come from DIFFICULTY like any other trainer mon; its moveset and held item are the entry's own (which is how a Mega Stone or a Light Ball reaches battle_forms). OFF: the whole team is randomized like any other trainer's. Only offered while RAND TRAINER MONS is on, and the in-game OPTIONS menu carries the same ON/OFF row (see LEAGUE_ACES.md for the full team table).",
  },
  {
    key = "item_randomizer",
    label = "ITEM RANDOMIZER",
    type = "toggle",
    default = false,
    description = "ON: an ordinary item ball or hidden item no longer holds its real item -- it holds a random NON-KEY item drawn from the game's whole item list instead (TMs and HMs are in that pool; a true key item -- the Silph Scope, the LIFT KEY, the Card Key, the badges, the fishing rods, ... -- is never). A spot that really held a key item is left exactly as it is, so nothing the story needs can be randomised away, and a respawned item (see ITEM RESPAWN) is randomised the same way when it is next picked up. Works on both Red/Blue/Yellow and Gold/Silver/Crystal.",
  },
  {
    key = "item_respawn",
    label = "ITEM RESPAWN",
    type = "toggle",
    default = false,
    description = "ON: every item spot you have already taken on the map you are STANDING ON can come back. Once per ITEM RESPAWN TIMER, one random already-taken non-key item on the current map reappears -- an item ball is placed back exactly where it was, a hidden item becomes diggable again -- until the map runs out of taken spots. Nothing is duplicated: it is the same one spot at a time, and the timer restarts on every warp (and on a page reload, since it is a live-play timer, not a saved one).",
  },
  {
    key = "respawn_timer",
    label = "RESPAWN TIMER",
    type = "choice",
    default = "1m",
    choices = { { "30S", "30s" }, { "1 MIN", "1m" }, { "2 MIN", "2m" },
                { "3 MIN", "3m" }, { "4 MIN", "4m" }, { "5 MIN", "5m" } },
    description = "How long ITEM RESPAWN waits between respawns: 30 seconds, or 1 to 5 minutes. Only read while ITEM RESPAWN is on.",
  },
  {
    key = "rebattles",
    label = "REMATCHES",
    type = "toggle",
    default = false,
    description = "ON: a trainer you have already beaten can be fought again. Press A on them (the ordinary way you would talk to anyone) and they will ask whether you want to battle again: YES starts a rematch, NO carries on with their usual after-battle line, exactly as if you had never asked. It only ever starts on your own press, so a beaten trainer can never re-challenge you by itself as you walk past. Their dialogue, payout and any badge/TM reward stay exactly as they were (a reward is never paid twice), and a trainer whose talk is a hand-ported story scene -- a rival, the Rocket hideout, a gym leader's own line -- is deliberately left alone, so no story flag can be set out of order; gym leaders and the Elite Four are re-enabled by the GYM REMATCHES row. Works on both Red/Blue/Yellow and Gold/Silver/Crystal.",
  },
  {
    key = "rebattle_levels",
    label = "+LEVEL PER REMATCH",
    type = "choice",
    default = "off",
    choices = { { "OFF", "off" }, { "+1", "1" }, { "+2", "2" },
                { "+4", "4" }, { "+8", "8" }, { "+16", "16" } },
    description = "Every rematch (see REMATCHES) puts this many levels on each Pokemon in the trainer's team, cumulatively: the first fight is vanilla, the second is +this, the third +2x this, and so on. Only ever raises a level -- never a level cap or a species change of its own -- and it stacks with the DIFFICULTY team-size floor and with RAND TRAINER MONS. OFF leaves every team at its real level.",
  },
  {
    key = "gym_rematches",
    label = "GYM REMATCHES",
    type = "toggle",
    default = true,
    description = "ON (default): REMATCHES also covers gym leaders and the Elite Four. Their A press is a hand-ported story script (the badge/TM line, advice text), which plain REMATCHES deliberately leaves alone -- with this ON, a beaten gym leader or Elite Four member asks whether you want to battle again and, on YES, starts the rematch without re-running that script (a badge or TM is never paid twice). A rematch of one keeps its gym's type theme through RAND TRAINER MONS and the DIFFICULTY team floor (see GYM THEMES). OFF: gyms and the Elite Four keep their story talk, exactly as if this were an ordinary NPC. Requires REMATCHES to be on. Only the league is affected; rivals, Rocket and every other story trainer are still left alone.",
  },
  {
    key = "trainer_item_drop",
    label = "TRAINER ITEM DROP",
    type = "toggle",
    default = false,
    description = "ON: beating a trainer -- a first fight or a rematch (see REMATCHES) -- can drop one random NON-KEY item (drawn from the game's whole item list, same pool as ITEM RANDOMIZER) into your bag, shown as an ordinary \"{PLAYER} found X!\" box the moment you are back on the map. Key items are never dropped. If the bag pocket is full the item is quietly lost rather than shown, exactly as a real pickup would be. Works on both generations.",
  },
  {
    key = "trainer_item_chance",
    label = "TRAINER ITEM CHANCE",
    type = "choice",
    default = "100",
    choices = { { "5%", "5" }, { "10%", "10" }, { "20%", "20" },
                { "40%", "40" }, { "80%", "80" }, { "100%", "100" } },
    description = "The chance that beating a trainer -- a first fight or a rematch (see REMATCHES) -- actually pays out the TRAINER ITEM DROP: 5%, 10%, 20%, 40%, 80% or 100% (default) of wins. Rolled once per win, so it only ever changes how often the drop happens, never which item. Only read while TRAINER ITEM DROP is on, and a key item is never dropped whatever the roll.",
  },
}
