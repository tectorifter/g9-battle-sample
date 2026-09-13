-- Mod Manager option schema for g9-battle-sample.
--
-- Declared in manifest.json's "options_schema" field, so the manager (and
-- native launchers reading mod_option_schemas.json) can render these rows
-- even while this mod is disabled. main.lua calls mod.options:define() with
-- the IDENTICAL table at load time, which is what gives mod.options:get()
-- its defaults. Keep the two copies in sync (same convention as
-- g9-trainer-sample's own pair).
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
    description = "Every trainer's Pokemon. EASY: 0 IVs, 0 EVs, neutral natures. NORMAL: 10 IVs, 12 EVs, neutral. HARD: 20 IVs, 24 EVs, a nature favouring the highest base stat. HELL: 31 IVs, 252 EVs on the two highest base stats and 4 on the third, a nature that boosts the highest stat and lowers the weaker offence.",
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
}
