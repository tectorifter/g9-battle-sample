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
    description = "ON (default): an ordinary wild encounter's species is re-rolled to a random species that shares a type with it and whose base-stat total is within -5% to +(5*level)% of the original's. The random LAYOUT bands (hordes/triples/doubles/singles, and the 0.5% bossFight) stay on either way.",
  },
  {
    key = "rand_trainers",
    label = "RAND TRAINER MONS",
    type = "toggle",
    default = true,
    description = "ON (default): every trainer, gym leader, Elite Four, Champion and rival has each party Pokemon swapped for a random species sharing at least one type and of equivalent BST (within -5% to +(5*level)%). OFF: trainer teams keep their real species.",
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
    label = "REBATTLES",
    type = "toggle",
    default = false,
    description = "ON: a trainer you have already beaten can be fought again -- press A on them (the ordinary way you would talk to anyone) to start a rematch. It only ever starts on your own press, so a beaten trainer can never re-challenge you by itself as you walk past. Their dialogue, payout and any badge/TM reward stay exactly as they were (a reward is never paid twice), and a trainer whose talk is a hand-ported story scene -- a rival, the Rocket hideout, a gym leader's own line -- is deliberately left alone, so no story flag can be set out of order. Works on both Red/Blue/Yellow and Gold/Silver/Crystal.",
  },
  {
    key = "rebattle_levels",
    label = "+LEVEL PER REBATTLE",
    type = "choice",
    default = "off",
    choices = { { "OFF", "off" }, { "+1", "1" }, { "+2", "2" },
                { "+4", "4" }, { "+8", "8" }, { "+16", "16" } },
    description = "Every rematch (see REBATTLES) puts this many levels on each Pokemon in the trainer's team, cumulatively: the first fight is vanilla, the second is +this, the third +2x this, and so on. Only ever raises a level -- never a level cap or a species change of its own -- and it stacks with the DIFFICULTY team-size floor and with RAND TRAINER MONS. OFF leaves every team at its real level.",
  },
  {
    key = "trainer_item_drop",
    label = "TRAINER ITEM DROP",
    type = "toggle",
    default = false,
    description = "ON: beating a trainer -- a first fight or a rematch (see REBATTLES) -- can drop one random NON-KEY item (drawn from the game's whole item list, same pool as ITEM RANDOMIZER) into your bag, shown as an ordinary \"{PLAYER} found X!\" box the moment you are back on the map. Key items are never dropped. If the bag pocket is full the item is quietly lost rather than shown, exactly as a real pickup would be. Works on both generations.",
  },
  {
    key = "trainer_item_chance",
    label = "TRAINER ITEM CHANCE",
    type = "choice",
    default = "100",
    choices = { { "5%", "5" }, { "10%", "10" }, { "20%", "20" },
                { "40%", "40" }, { "80%", "80" }, { "100%", "100" } },
    description = "The chance that beating a trainer -- a first fight or a rematch (see REBATTLES) -- actually pays out the TRAINER ITEM DROP: 5%, 10%, 20%, 40%, 80% or 100% (default) of wins. Rolled once per win, so it only ever changes how often the drop happens, never which item. Only read while TRAINER ITEM DROP is on, and a key item is never dropped whatever the roll.",
  },
}
