-- g9-battle-sample -- fork of Sample-Battle-Scene, retargeted at
-- g9-Battle-Scene instead of g2-Battle-Scene. Exists for one reason:
-- g9-Battle-Scene has no consumer of its own -- nothing anywhere else in
-- this workspace calls its mod.exports.pushLayoutBattle -- so the whole
-- g9-battle-engine connection (turn resolution via
-- resolveTurnActions, native EXP/catch, the battle-exit music sequence)
-- has never had a real, live encounter to run through. This is that
-- encounter. Same TEST/EXAMPLE status as the mod it forks from -- either
-- delete it once the connection's been exercised, or keep it installed as
-- a working reference.
--
-- Do NOT enable alongside Sample-Battle-Scene: both mods independently
-- wrap World.tryWildEncounter, and two mods intercepting the same
-- encounter conflicts. Pick one.
--
-- Deliberately simplified vs g2-Battle-Scene's own world_intercept.lua
-- (deleted from that mod entirely, per this session's earlier decision --
-- see g2-Battle-Scene's own manifest.json): extra enemy slots (beyond the
-- one real wild roll the native trigger already committed to) clone that
-- roll's own species/level rather than rolling distinct wild mons per
-- slot, and a missing ally slot is just left out rather than a fresh mon
-- being created and appended to the real save party.
--
-- Trap technique (temporarily swap World.startBattle, call the
-- unmodified original tryWildEncounter, restore, act on what got
-- captured) is unchanged from Sample-Battle-Scene's own -- confirmed the
-- only clean way to intercept a wild encounter in this engine.
--
-- NOT carried over from Sample-Battle-Scene: the g2-Battle-Scene custom
-- E-menu button listener (mod.events:on("mod.g2-Battle-Scene.customButton",
-- ...)) -- that's g2-Battle-Scene's own comms channel specifically, not
-- something g9-Battle-Scene emits.
--
-- Added since: wild_forms's Eternatus-as-Eternamax static (INDIGO_PLATEAU,
-- level 75) now routes through g9-Battle-Scene's own "bossFight" layout
-- instead of the ordinary battle screen -- explicit user request. A
-- SEPARATE, PERMANENT World:startBattle wrap, not the scoped
-- tryWildEncounter trap below -- that fight is object_event-triggered, a
-- different call path the scoped trap never sees. See that wrap's own
-- header for the full grounding.
--
-- Also added: an ordinary wild encounter rolls one of g9-Battle-Scene's
-- own layouts -- 1% "hordes", 2% "triples", 10% "doubles", 87% "singles"
-- -- and EVERY trainer battle routes to "doubles" whenever that trainer
-- actually has 2+ Pokemon (tryDoublesTrainer, in the same permanent wrap
-- as Eternatus, for the same reason -- a trainer battle is script-VM
-- triggered, not tryWildEncounter). Both explicit user requests.
--
-- 2026-09-11, explicit user request: the native/vanilla battle scene is
-- NEVER called for an ordinary wild encounter any more. The 87% default
-- band -- which the earlier pass deliberately sent to the real native
-- scene -- now routes to the g9-Battle-Scene "singles" preset instead,
-- and a party too small for the multi-mon layouts also falls to
-- "singles" rather than to native.
--
-- NOW BOTH GENERATIONS, 2026-09-12, explicit user request ("make this lua
-- also compatible with gen 1 and crystal, so it fires in any of the games
-- the encounter types"): the mod used to be Gen 2 only (manifest games
-- ["gen2"]) and it did NOTHING on a Red/Blue/Yellow boot -- its
-- World.startBattle / World.tryWildEncounter wraps resolve to modules
-- nothing instantiates there, so it was a silent no-op.  The Gen 2 path
-- above is unchanged; a second, Gen 1 arm (installGen1, below) now wraps
-- Gen 1's own single battle funnel, OverworldState:pushBattle, so the same
-- layouts fire on Red/Blue/Yellow too.  "Crystal" needs no separate work:
-- the engine treats every Gen 2 game -- Gold, Silver AND Crystal -- through
-- src.world.gen2.World, so the Gen 2 arm already covers it; the manifest's
-- `games` list is what widened.  See installGen1's own header for the full
-- account of the Gen 1 seam, the battle.onFinish contract it honours, and
-- what deliberately stays native.
--
-- 2026-09-12, explicit user request -- five more systems, all of them
-- generation-agnostic where the engine gave a shared seam (see
-- installRandomizer below):
--   1. A 0.5% WILD bossFight: one in two hundred ordinary wild encounters
--      now renders through the scene's "bossFight" preset, with a random
--      boss-protection flag set (the engine's own BOSS_FIGHT_FLAG_NAMES) and
--      a random x1..x5 max-HP roll on the wild mon.  Chosen by its own
--      1-in-1000 roll so it can never overlap the hordes/triples/doubles/
--      singles bands below.
--   2. A SPECIES RANDOMIZER: every trainer party mon (ordinary trainer, gym
--      leader, Elite Four, Champion, rival) can be swapped for a random
--      species that shares at least one type with the original and whose
--      BST sits in the user's band -- -5% up to +(5*level)% of the
--      original's.  Applied through the engine's own generation-agnostic
--      "trainer.party" hook, so it runs on BOTH games.
--   3. WILD SPECIES RANDOMIZATION, through the shared "encounter.species"
--      hook (same BST/type matcher).  Toggled by its own option; the random
--      LAYOUT bands stay on regardless.
--   4. TRAINER COMBAT-TYPE ROUTING: every 2+-mon trainer is still a
--      doubles; the Elite Four now rolls doubles-or-triples per battle;
--      and the Champion (CHAMPION / Gen 1's OPP_RIVAL3) and Red (RED) route
--      to the "bossFight" layout, with the randomised boss protections on.
--   5. A DIFFICULTY PRESET for every trainer's mons (easy / normal / hard /
--      hell), fed through the engine's own registerTrainerStatsProvider API
--      -- one registration covers both generations.
--   6. A TRAINER-TEAM FLOOR tied to that same DIFFICULTY setting: EASY keeps
--      the vanilla team size, NORMAL is 2, HARD is 4 and HELL is 6, and
--      Pokemon are only ever ADDED when the vanilla team is under the floor
--      (a 5-mon team stays 5 on hard and becomes 6 on hell).  Each added mon
--      is modelled on one of the team's own members, at that member's level,
--      through the same species matcher the randomizer uses.
-- All of this is gated by this mod's options.lua (DIFFICULTY, RAND WILDS,
-- RAND TRAINER MONS), read lazily at battle/encounter time so the Mod
-- Manager changes take effect without a reload.
-- Two rows steer the custom-scene layer instead (see the define() table
-- below).  The sample's own "2v2/3v3/4v1" row picks the LAYOUT: ON keeps the
-- full wild/trainer routing, OFF forces every fight onto g9-Battle-Scene's
-- singles screen.  g9-Battle-Scene's own BACKGROUND row is the master switch:
-- with it OFF no fight is routed to the scene at all -- every wild encounter
-- and trainer battle goes to the game's own native battle screen, for Gen 1
-- and Gen 2 respectively, and g9-Battle-Scene is never consulted (which is why
-- it is an optional dependency rather than a hard one).
local function installRandomizer(mod, gen)
  local shared = {}
  local unpack = table.unpack or unpack

  -- The running game's generation (1 or 2).  The arm chooser at the bottom
  -- already worked it out and passes it in; recomputed here only when this
  -- is called without one (the test harness does), so an added mon is built
  -- through the right constructor for the game actually running.
  local gameGen = 1
  if gen == 1 or gen == 2 then
    gameGen = gen
  else
    local okGV, GameVersion = pcall(require, "src.core.GameVersion")
    if okGV and GameVersion and GameVersion.generation then
      local okGen, value = pcall(GameVersion.generation)
      if okGen and (value == 1 or value == 2) then gameGen = value end
    end
  end

  -- ---------------------------------------------------------------- options
  -- The SAME schema options.lua returns (the two copies are kept in sync by
  -- hand, per the engine's documented convention: the manager reads
  -- options.lua while a disabled mod is shown, and mod.options:get needs the
  -- defaults from this define() call at load time).
  mod.options:define({
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
      -- it.  The engine's own `visible_if` schema field is what makes the
      -- manager show and hide this row LIVE as RAND TRAINER MONS is flipped
      -- (flipping a row rebuilds the menu), so it APPEARS when the randomizer
      -- is switched on and disappears again when it is switched off.
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
      description = "ON: beating a trainer -- a first fight or a rematch (see REMATCHES) -- can drop one random NON-KEY item (drawn from the game's whole item list, same pool as ITEM RANDOMIZER) into your bag, shown as an ordinary \"{PLAYER} found X!\" box the moment you are back on the map. Whether a given win pays out is TRAINER ITEM CHANCE (100% by default). Key items are never dropped. If the bag pocket is full the item is quietly lost rather than shown, exactly as a real pickup would be. Works on both generations.",
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
  })

  local function option(key) return mod.options:get(key) end
  local function randWildsOn() return option("rand_wilds") == true end
  local function randTrainersOn() return option("rand_trainers") == true end
  -- The generation arms (installGen1/installGen2) close over `shared`, not
  -- this scope, so the wild-multi-roll gate there needs the alias.
  shared.randWildsOn = randWildsOn
  shared.randTrainersOn = randTrainersOn
  local function difficulty() 
    local value = option("difficulty")
    if value == "easy" or value == "normal" or value == "hard" or value == "hell" then
      return value
    end
    return "normal"
  end

  -- MULTI-MON LAYOUTS -- the Manager's "2v2/3v3/4v1" row (option key
  -- `battle_scene`, kept for stored-setting compatibility).  ON (the
  -- default) keeps the full layout routing: a wild encounter rolls
  -- singles/doubles/triples/hordes plus the 0.5% bossFight, and a trainer
  -- fight picks doubles/triples/bossFight from the enemy battle that already
  -- exists.  OFF narrows EVERY fight to g9-Battle-Scene's own "singles"
  -- layout -- it no longer hands the battle back to the native screen.  Read
  -- at battle time, so a Mod Manager change takes effect without a reload.
  local function multiLayoutOn() return option("battle_scene") ~= false end

  -- IS THE CUSTOM SCENE WANTED AT ALL?  g9-Battle-Scene owns the master
  -- switch now: its own BACKGROUND row set to OFF means "use the game's
  -- native battle screen, please", and then NO fight is routed to the scene
  -- (art and layouts alike).  AUTO (the default) or a pinned tag keeps it.
  -- Read live per fight, and tolerant of an older scene that only exposes the
  -- raw option (or none at all) -- a missing export means "wanted".
  local function sceneWanted()
    local scene = shared.sceneHandle()
    if not scene then return false end
    local exports = scene.exports
    local bg = exports and exports.battleSceneBackground
    if bg then
      if type(bg.sceneWanted) == "function" then
        local ok, wanted = pcall(bg.sceneWanted)
        if ok then return wanted and true or false end
      end
      if type(bg.option) == "function" then
        local ok, value = pcall(bg.option)
        if ok and value == "off" then return false end
      end
    end
    return true
  end

  -- Exposed on `shared` (the table the arm chooser at the bottom hands to
  -- installGen1/installGen2) so those separate functions -- which do not close
  -- over this one's locals -- read the same switches.
  shared.multiLayoutOn = multiLayoutOn
  shared.sceneWanted = sceneWanted

  -- --------------------------------------------------------- gym themes
  -- 2026-09-10, explicit user request: a gym leader's (and an Elite Four's)
  -- randomized AND difficulty-added team must stay on that gym's own type
  -- theme -- "Falkner is flying type, he can only use flying types, same for
  -- elite fours".  This table IS that config: one trainer-class id -> the
  -- type(s) allowed for it.  A value may be a single type or a list (a gym's
  -- main type plus any acceptable sub-types); a species is allowed when AT
  -- LEAST ONE of its own types is named here, so a Normal/Flying Pidgey is
  -- legal for Falkner (its FLYING half) exactly as a mono-Flying mon is.
  -- Class ids are per generation and disjoint (Gen 1 spells Kanto's OPP_*),
  -- so one table answers for both.  A mixed-type trainer (BLUE) has no theme
  -- and is deliberately absent.
  local GYM_THEMES = {
    -- Kanto gyms
    OPP_BROCK = "ROCK", OPP_MISTY = "WATER", OPP_LT_SURGE = "ELECTRIC",
    OPP_ERIKA = "GRASS", OPP_KOGA = "POISON", OPP_SABRINA = "PSYCHIC",
    OPP_BLAINE = "FIRE", OPP_GIOVANNI = "GROUND",
    -- Kanto Elite Four (Gen 1)
    OPP_LORELEI = "ICE", OPP_BRUNO = "FIGHTING", OPP_AGATHA = "GHOST",
    OPP_LANCE = "DRAGON",
    -- Johto gyms (Gen 2)
    FALKNER = "FLYING", BUGSY = "BUG", WHITNEY = "NORMAL", MORTY = "GHOST",
    CHUCK = "FIGHTING", JASMINE = "STEEL", PRYCE = "ICE", CLAIR = "DRAGON",
    -- Johto Elite Four (Gen 2)
    WILL = "PSYCHIC", KOGA = "POISON", BRUNO = "FIGHTING", KAREN = "DARK",
    -- Kanto gyms (Gen 2 post-game); Blue is mixed, so no theme row for him.
    BROCK = "ROCK", MISTY = "WATER", LT_SURGE = "ELECTRIC", ERIKA = "GRASS",
    JANINE = "POISON", SABRINA = "PSYCHIC", BLAINE = "FIRE",
  }

  -- Every league trainer the GYM REMATCHES switch knows about -- a gym leader
  -- or Elite Four member (Blue included, even though he has no theme).  Their
  -- A press is a hand-ported story script (badge/TM retry, advice line), so
  -- plain REMATCHES deliberately leaves them alone; this set is what the
  -- dedicated switch looks up.
  local GYM_CLASSES = {
    OPP_BROCK = true, OPP_MISTY = true, OPP_LT_SURGE = true, OPP_ERIKA = true,
    OPP_KOGA = true, OPP_SABRINA = true, OPP_BLAINE = true, OPP_GIOVANNI = true,
    OPP_LORELEI = true, OPP_BRUNO = true, OPP_AGATHA = true, OPP_LANCE = true,
    FALKNER = true, BUGSY = true, WHITNEY = true, MORTY = true, CHUCK = true,
    JASMINE = true, PRYCE = true, CLAIR = true,
    WILL = true, KOGA = true, BRUNO = true, KAREN = true,
    BROCK = true, MISTY = true, LT_SURGE = true, ERIKA = true, JANINE = true,
    SABRINA = true, BLAINE = true, BLUE = true,
  }

  -- A class id -> a { [TYPE] = true } set, or nil when the trainer has no
  -- theme (a non-league trainer, or mixed-type Blue).
  local function themeSetOf(classId)
    local theme = type(classId) == "string" and GYM_THEMES[classId] or nil
    if theme == nil then return nil end
    local set = {}
    if type(theme) == "table" then
      for _, t in ipairs(theme) do
        if type(t) == "string" then set[t:upper()] = true end
      end
    else
      set[tostring(theme):upper()] = true
    end
    return set
  end
  function shared.themeTypesFor(classId) return themeSetOf(classId) end
  function shared.isGymClass(classId)
    return type(classId) == "string" and GYM_CLASSES[classId] == true
  end

  -- The class id off whichever generation's object this is.  Gen 1 keeps the
  -- class NAME on def.trainerClass.  Gen 2 keeps the class's NUMERIC constant
  -- on the extracted def.trainer struct (`class`), while every table above --
  -- GYM_CLASSES, GYM_THEMES, E4_CLASSES -- keys on the name, so the number is
  -- resolved through the cache's own class index.  (Before that resolve this
  -- returned the raw byte, so on Gold/Silver/Crystal `isGymClass` was false
  -- for every leader and the type themes never matched.)  `record.classId` is
  -- honored first for a caller that has already resolved it.
  function shared.trainerClassOf(npcOrDef)
    local d = npcOrDef and (npcOrDef.def or npcOrDef)
    if type(d) ~= "table" then return nil end
    if d.trainerClass ~= nil then return d.trainerClass end
    local record = type(d.trainer) == "table" and d.trainer or nil
    if record == nil then return nil end
    if record.classId ~= nil then return record.classId end
    if shared.gen2ClassName then return shared.gen2ClassName(record.class) end
    return record.class
  end

  -- ----------------------------------------------------- reaching the scene
  -- The scene's manifest id is `g9-Battle-Scene`, but a fork or re-release
  -- has shipped it lower-cased (`g9-battle-scene`) -- the loader keys every mod
  -- and its exports by `manifest.id` alone, so an id that differs only in case
  -- would make `mod.find("g9-Battle-Scene")` return nil and turn EVERY fight
  -- silently native.  One resolver, tried in the canonical-then-slug order,
  -- so no other site has to know the ids.
  local SCENE_IDS = { "g9-Battle-Scene", "g9-battle-scene", "g9-battle-scenes",
                      "g9-Battle-Scenes" }
  function shared.sceneHandle()
    for _, id in ipairs(SCENE_IDS) do
      local handle = mod.find and mod.find(id)
      if handle and handle.exports and handle.exports.pushLayoutBattle then
        return handle
      end
    end
    return nil
  end

  -- ------------------------------------------------- silent-failure reporting
  -- The battle scene is on but the scene cannot be reached (not installed,
  -- disabled, or failed to load) -- the ONE failure mode that otherwise looks
  -- exactly like "the custom screens simply don't work", with no reason
  -- visible on a build where the player cannot read the log.  Reported ONCE
  -- per boot: to the log and the engine's own error list immediately, and as
  -- a one-off in-game box the moment the overworld is next idle (the update
  -- seams below flush it).  `gameText` is the short line the player reads;
  -- `logDetail` is the actionable one for the mod manager / console.
  local sceneProblemLogged, sceneProblemQueued = false, nil
  function shared.reportSceneProblem(world, logDetail, gameText)
    if not sceneProblemLogged then
      sceneProblemLogged = true
      mod.log:error("%s", logDetail)
      local okRuntime, Runtime = pcall(require, "src.mods.Runtime")
      if okRuntime and Runtime and type(Runtime.reportError) == "function" then
        pcall(Runtime.reportError, mod.id or "g9-battle-sample", logDetail)
      end
    end
    if gameText and not sceneProblemQueued then sceneProblemQueued = gameText end
  end

  -- Shown from whichever per-frame overworld seam the installed arm has, and
  -- only while the world is idle, so the notice can never land on top of a
  -- script or an open text box (and a fallback mid-battle shows after it).
  function shared.flushSceneProblem(world)
    if not sceneProblemQueued then return end
    local text = sceneProblemQueued
    sceneProblemQueued = nil
    if world and type(world.showText) == "function" then
      pcall(function() world:showText(text) end)
    end
  end

  -- Run `fn` with g9-Battle-Scene's own layout-push exports hidden, then put
  -- them back (the same swap-and-restore this file already uses for a
  -- randomized item id).  THE CUSTOM SCENE OFF (g9-Battle-Scene's BACKGROUND
  -- row) has to beat EVERY route to the
  -- scene -- including another mod's registered trainer: g9-battle-engine's
  -- own registerTrainer wrap (the Gen 2 arm's captured native startBattle)
  -- pushes a doubles/triples layout on its own whenever it finds
  -- g9-Battle-Scene available, so hiding the scene for the length of the
  -- native call is what makes "OFF" mean a vanilla battle for those fights too.
  function shared.withoutScene(fn)
    local scene = shared.sceneHandle()
    local exports = scene and scene.exports
    local savedPush, savedData
    if exports then
      savedPush, savedData = exports.pushLayoutBattle, exports.getLayoutData
      exports.pushLayoutBattle, exports.getLayoutData = nil, nil
    end
    local ok, result = pcall(fn)
    if exports then
      exports.pushLayoutBattle, exports.getLayoutData = savedPush, savedData
    end
    if not ok then error(result, 0) end
    return result
  end

  -- ------------------------------------------------------------- live data
  -- require("src.core.Game") is the Gen2Compat-provided facade, so .data
  -- resolves against whichever game is actually running (the same facade the
  -- engine's own overworld/pokecenter_heal.lua uses).
  local function liveData()
    local ok, Game = pcall(require, "src.core.Game")
    if ok and type(Game) == "table" then return Game.data end
    return nil
  end

  -- The live save, same facade.  Declared here (with liveData) rather than
  -- next to the beaten-trainer helpers, because the wild-level settings below
  -- read the party anchor off it and their helpers must be lexically visible
  -- to the encounter hooks further up the file.
  local function liveSave()
    local ok, Game = pcall(require, "src.core.Game")
    if ok and type(Game) == "table" then return Game.save end
    return nil
  end

  -- ------------------------------------------------- Gen 2 trainer classes
  -- A Gen 2 trainer struct -- and `loadtrainer --class, member` -- carries the
  -- class's NUMERIC constant (Trainers.lookup's `class`), while GYM_THEMES /
  -- GYM_CLASSES / E4_CLASSES key on the class NAME (Trainers.lookup's
  -- `classId`).  The cache's trainer table carries the pair, so index it once
  -- and hand the name back.  Nil when the cache's trainers table is not loaded
  -- yet, which is exactly right: the caller then falls back to the raw value
  -- rather than inventing a class.
  local gen2ClassIndex
  function shared.gen2ClassName(class)
    if type(class) ~= "number" then return class end
    local data = liveData()
    local classes = data and data.trainers and data.trainers.classes
    if type(classes) ~= "table" then return nil end
    if gen2ClassIndex == nil then
      gen2ClassIndex = {}
      for id, entry in pairs(classes) do
        if type(entry) == "table" and type(entry.index) == "number" then
          gen2ClassIndex[entry.index] = entry.id or id
        end
      end
    end
    return gen2ClassIndex[class]
  end
  -- Both are handed to the two generation arms (which are defined OUTSIDE this
  -- closure and receive nothing but `shared`), the same way every other
  -- predicate an arm calls is.
  shared.liveSave = liveSave
  shared.liveData = liveData

  -- ---------------------------------------------------------- species pool
  -- data.pokemon is the merged content registry (the cart's own species
  -- plus everything national_dex registered), so this is the "national dex
  -- expanded entries" pool the user asked for -- forms included -- without
  -- paying for a deepCopy per species the way national_dex's read API does.
  -- Built once, on first use, then cached: the roster does not change at
  -- runtime and a wild encounter should never walk ~1500 records.
  local pool, byType

  -- ------------------------------------------------------------- legendaries
  -- 2026-09-14, explicit user request: "legendaries are available for
  -- randomization after level 45".  NO record in either generation's merged
  -- registry carries a legendary flag (checked the engine's own species
  -- records AND national_dex's generated tables), so the set is spelled out
  -- here once.  A form is caught through its base: every alternate form
  -- (MEGA, MEGA_X/Y, gigantamax/TERA-shaped, a regional variant) carries
  -- `baseSpecies`, so `baseSpecies`-or-id membership covers all ~50 legendary
  -- forms without listing them by hand.  The two level gates the user named
  -- live here as named constants so the walker and the picker cannot drift.
  local LEGENDARY_LEVEL = 45
  local TRADE_LEVEL = 40
  -- 2026-09-18, explicit user rule: "pokemon evolved by stones are only to
  -- appear at minimum level of 35 in the wild".  A stone (use-item) evolution
  -- is its own gate, and only in the wild -- a trainer's own roster keeps the
  -- level-40 gate the rest of the non-level methods use.  See latestEvolution.
  local STONE_LEVEL = 35
  -- 2026-09-19, explicit user rule: "evolution by held items or happiness
  -- condition.  IF baby pokemon (ex: happiny) allows chansey starting to appear
  -- at lvl 25 spawn table entries.  IF non baby pokemon, evolution starts
  -- appearing at lvl 35 spawn table entries."
  --
  -- So a held-item evolution (a level-up that needs the mon to HOLD a given
  -- item -- Happiny's Oval Stone, Sneasel's Razor Claw) and a happiness
  -- evolution (a level-up that needs friendship) are their own wild gates:
  -- EVO_LEVEL for an ordinary pre-evolution, BABY_EVO_LEVEL when the mon
  -- evolving is a BABY.  A trainer's own roster keeps TRADE_LEVEL, exactly as
  -- the stone gate above does.  The BABY set is spelled out for the same
  -- reason LEGENDARY is: no registry record carries a baby flag (checked the
  -- engine's own records and national_dex's generated tables), and a baby is
  -- the one thing that moves this gate.  See latestEvolution and buildEvoGates.
  local EVO_LEVEL = 35
  local BABY_EVO_LEVEL = 25
  local BABY = {
    PICHU = true, CLEFFA = true, IGGLYBUFF = true, TOGEPI = true,
    TYROGUE = true, SMOOCHUM = true, ELEKID = true, MAGBY = true,
    AZURILL = true, WYNAUT = true, BUDEW = true, CHINGLING = true,
    BONSLY = true, MIME_JR = true, HAPPINY = true, MUNCHLAX = true,
    RIOLU = true, MANTYKE = true, TOXEL = true,
  }
  local LEGENDARY = {
    -- Gen 1-2
    ARTICUNO = true, ZAPDOS = true, MOLTRES = true, MEWTWO = true, MEW = true,
    RAIKOU = true, ENTEI = true, SUICUNE = true, LUGIA = true, HO_OH = true,
    CELEBI = true,
    -- Gen 3
    REGIROCK = true, REGICE = true, REGISTEEL = true, LATIAS = true,
    LATIOS = true, KYOGRE = true, GROUDON = true, RAYQUAZA = true,
    JIRACHI = true, DEOXYS = true,
    -- Gen 4
    UXIE = true, MESPRIT = true, AZELF = true, DIALGA = true, PALKIA = true,
    HEATRAN = true, REGIGIGAS = true, GIRATINA = true, CRESSELIA = true,
    PHIONE = true, MANAPHY = true, DARKRAI = true, SHAYMIN = true,
    ARCEUS = true,
    -- Gen 5
    VICTINI = true, COBALION = true, TERRAKION = true, VIRIZION = true,
    TORNADUS = true, THUNDURUS = true, RESHIRAM = true, ZEKROM = true,
    LANDORUS = true, KYUREM = true, KELDEO = true, MELOETTA = true,
    GENESECT = true,
    -- Gen 6
    XERNEAS = true, YVELTAL = true, ZYGARDE = true, DIANCIE = true,
    HOOPA = true, VOLCANION = true,
    -- Gen 7 (the Ultra Beasts are included -- they are encounter-restricted
    -- the same way in every game that ships them)
    TAPU_KOKO = true, TAPU_LELE = true, TAPU_BULU = true, TAPU_FINI = true,
    COSMOG = true, COSMOEM = true, SOLGALEO = true, LUNALA = true,
    NIHILEGO = true, BUZZWOLE = true, PHEROMOSA = true, XURKITREE = true,
    CELESTEELA = true, KARTANA = true, GUZZLORD = true, NECROZMA = true,
    MAGEARNA = true, MARSHADOW = true, POIPOLE = true, NAGANADEL = true,
    STAKATAKA = true, BLACEPHALON = true, ZERAORA = true, MELTAN = true,
    MELMETAL = true,
    -- Gen 8
    ZACIAN = true, ZAMAZENTA = true, ETERNATUS = true, KUBFU = true,
    URSHIFU = true, ZARUDE = true, REGIELEKI = true, REGIDRAGO = true,
    GLASTRIER = true, SPECTRIER = true, CALYREX = true, ENAMORUS = true,
    -- Gen 9
    KORAIDON = true, MIRAIDON = true, WO_CHIEN = true, CHIEN_PAO = true,
    TING_LU = true, CHI_YU = true, OKIDOGI = true, MUNKIDORI = true,
    FEZANDIPITI = true, OGERPON = true, TERAPAGOS = true,
  }
  local function isLegendaryId(id, rec)
    if type(id) == "string" and LEGENDARY[id] then return true end
    local base = rec and rec.baseSpecies
    if type(base) == "string" and LEGENDARY[base] then return true end
    return false
  end
  -- A baby is a baby by its OWN id (a form's base could be one, but only the
  -- base itself evolves out of babyhood, so this is deliberately id-only).
  local function isBabyId(id)
    return type(id) == "string" and BABY[id] == true
  end

  local function buildPool(data)
    if pool then return true end
    data = data or liveData()
    local src = data and data.pokemon
    if type(src) ~= "table" then return false end
    local p, bt = {}, {}
    for id, rec in pairs(src) do
      if type(rec) == "table" and type(rec.baseStats) == "table"
          and type(rec.types) == "table" and #rec.types >= 1 then
        local b = rec.baseStats
        -- national_dex supplies the real Sp.Atk/Sp.Def split; the cart's own
        -- records carry one collapsed `special`.  Counting `special` as BOTH
        -- special stats (when there is no split) reproduces the real modern
        -- base-stat total for those species, so the two kinds of record
        -- compare on the same scale.
        local spa = b.spAttack or b.specialAttack or b.special
        local spd = b.spDefense or b.specialDefense or b.special
        if type(b.hp) == "number" and type(b.attack) == "number"
            and type(b.defense) == "number" and type(b.speed) == "number"
            and type(spa) == "number" and type(spd) == "number" then
          local entry = {
            id = id,
            bst = b.hp + b.attack + b.defense + b.speed + spa + spd,
            types = rec.types,
            baseStats = b,
            -- A legendary (or a form OF one) may only ever be picked once the
            -- encounter/party mon is LEGENDARY_LEVEL or higher -- see the
            -- picker below.  Nothing else about the pool changes.
            legendary = isLegendaryId(id, rec),
          }
          p[id] = entry
          for _, t in ipairs(rec.types) do
            if type(t) == "string" then
              local list = bt[t]
              if not list then list = {}; bt[t] = list end
              list[#list + 1] = entry
            end
          end
        end
      end
    end
    if next(p) == nil then return false end
    pool, byType = p, bt
    return true
  end

  -- ---------------------------------------------------------------- blacklist
  -- 2026-09-18, explicit user request: an in-game BLACKLIST window reached from
  -- a "BLACKLIST" row on the OPTIONS menu.  It indexes every Pokemon AND every
  -- alternate form by name, filters by generation (START) and by starting
  -- letter (SELECT), and lets the player delist an individual species or form,
  -- a whole generation's roster, or a whole FORM GROUP, from randomization.
  --
  -- Stored as a plain array of ids on mod.save["blacklist"].  Delisting a base
  -- species also covers its forms (delisting CHARIZARD keeps CHARIZARD_MEGA_X
  -- out too); delisting a form covers only that form.  A whole-generation cell
  -- simply writes every id of that generation into the same set.
  --
  -- 2026-09-19, explicit user request: "we will have mega forms and gigantamax
  -- forms blacklisted by default", and the window grows a [MEGA] [GIGA] row
  -- (the 3x3 generation grid's cells still say G1..G9) so the player can flip
  -- either group at once.  See formGroupOf, blacklistDefaults and
  -- shared.blacklistFormGroupToggle.
  --
  -- THE BLACKLIST IS A RANDOMIZER FILTER ONLY.  It is consulted exclusively by
  -- the species picker below (pickSpecies / latestEvolution / randomizeParty)
  -- -- never by a battle.  A battle-triggered form change (the mega evolution
  -- a boss fight runs as the player enters the scene, the Dynamax/Gigantamax/
  -- Terastal a battle_forms mechanic applies) is the ENGINE's, and reads none
  -- of this: delisting every Mega and Gigantamax form by default therefore
  -- cannot stop a boss from mega-evolving mid-fight.  Explicit user rule.
  local BLACKLIST_KEY = "blacklist"

  -- National-dex ranges -> generation.  A form is placed by its BASE species'
  -- dex (a form record's own dex is synthetic), which is what makes the
  -- generation filter and the 3x3 cell grid agree with the real games.
  local GEN_RANGES = {
    { 1, 1, 151 }, { 2, 152, 251 }, { 3, 252, 386 }, { 4, 387, 493 },
    { 5, 494, 649 }, { 6, 650, 721 }, { 7, 722, 809 }, { 8, 810, 905 },
    { 9, 906, 1025 },
  }
  local GEN_COUNT = #GEN_RANGES
  local function generationOfDex(dex)
    dex = tonumber(dex)
    if not dex then return nil end
    for _, range in ipairs(GEN_RANGES) do
      if dex >= range[2] and dex <= range[3] then return range[1] end
    end
    return nil
  end

  -- Mega / Gigantamax are the two form GROUPS the window toggles at once, and
  -- the two delisted by default.  Detected from the record's own `form` label,
  -- which the merged registry spells "MEGA" / "MEGA_X" / "MEGA_Y" / "MEGA_Z"
  -- (plus this project's own variants, e.g. "MALE_MEGA") and "GMAX" /
  -- "..._GMAX"; the id suffix is the fallback for a record with no label.
  -- Eternamax, Primal, Crowned and the regional variants are deliberately NOT
  -- here: the request named Megas and Gigantamax only, and Eternamax in
  -- particular is a boss form (see the RANDOMIZER-ONLY note above).
  local function formGroupOf(id, rec)
    local form = type(rec) == "table" and rec.form
    if type(form) == "string" and form ~= "" then
      local f = form:upper()
      if f == "GMAX" or f:sub(-5) == "_GMAX" then return "gmax" end
      if f:find("MEGA", 1, true) then return "mega" end
    end
    if type(id) == "string" then
      local u = id:upper()
      if u:sub(-5) == "_GMAX" then return "gmax" end
      if u:sub(-5) == "_MEGA" or u:find("_MEGA_", 1, true) then return "mega" end
    end
    return nil
  end

  -- Every displayable species/form, built once from the merged registry.
  -- Sorted by display name so the letter filter walks a stable A-Z order.
  local blacklistIndex
  local function buildBlacklistIndex(data)
    if blacklistIndex then return blacklistIndex end
    data = data or liveData()
    local src = data and data.pokemon
    if type(src) ~= "table" then return nil end
    local function baseDex(rec)
      if type(rec) ~= "table" then return nil end
      if type(rec.baseDex) == "number" then return rec.baseDex end
      local base = rec.baseSpecies
      if type(base) == "string" then
        local parent = src[base]
        if type(parent) == "table" and type(parent.dex) == "number" then
          return parent.dex
        end
      end
      return rec.dex
    end
    local out = {}
    for id, rec in pairs(src) do
      if type(id) == "string" and type(rec) == "table" then
        local name = rec.name
        if type(name) ~= "string" or name == "" then name = id end
        local base = type(rec.baseSpecies) == "string" and rec.baseSpecies
          or nil
        if base == "" then base = nil end
        local entry = {
          id = id, name = name, base = base,
          form = base ~= nil, dex = baseDex(rec),
          group = formGroupOf(id, rec),
        }
        entry.gen = generationOfDex(entry.dex)
        out[#out + 1] = entry
      end
    end
    if #out == 0 then return nil end
    table.sort(out, function(a, b)
      local an, bn = a.name:upper(), b.name:upper()
      if an ~= bn then return an < bn end
      return tostring(a.id) < tostring(b.id)
    end)
    blacklistIndex = out
    return out
  end

  -- The shipped default: every Mega and Gigantamax form the registry carries.
  -- Built straight from the live registry (the sorted index may not exist yet
  -- when the randomizer asks first) and nil when the registry is not loaded
  -- yet, so the caller can retry rather than persist an empty "default".
  local function blacklistDefaults()
    local data = liveData()
    local src = data and data.pokemon
    if type(src) ~= "table" then return nil end
    local ids = {}
    for id, rec in pairs(src) do
      if type(id) == "string" and formGroupOf(id, rec) then
        ids[#ids + 1] = id
      end
    end
    return ids
  end

  -- The set is read once and then kept.  A save with NO list at all is a fresh
  -- install, so the shipped default (every Mega + Gigantamax form) is seeded
  -- and written; and because a later RESET ALL writes an EMPTY list rather
  -- than a nil one, that reset is deliberate and is never re-seeded.
  local blacklistSet
  local blacklistResolved = false
  local blacklist, blacklistSave

  blacklist = function()
    if blacklistResolved then return blacklistSet end
    local stored = mod.save and mod.save:get(BLACKLIST_KEY)
    if type(stored) == "table" then
      blacklistSet = {}
      for _, id in ipairs(stored) do
        if type(id) == "string" then blacklistSet[id] = true end
      end
      blacklistResolved = true
      return blacklistSet
    end
    local ids = blacklistDefaults()
    if not ids then
      -- The registry is not up yet: answer an empty set for this call and try
      -- again next time (never persist a default we could not compute).
      return {}
    end
    blacklistSet = {}
    for _, id in ipairs(ids) do blacklistSet[id] = true end
    blacklistResolved = true
    blacklistSave()
    return blacklistSet
  end

  blacklistSave = function()
    local list = {}
    for id in pairs(blacklist()) do list[#list + 1] = id end
    table.sort(list)
    if mod.save and mod.save.set then
      pcall(mod.save.set, mod.save, BLACKLIST_KEY, list)
    end
  end

  -- A form's own base species, cached off the live registry (the blacklist
  -- index may not have been built when the randomizer asks first).
  local baseOfCache = {}
  local function baseOf(id)
    if baseOfCache[id] ~= nil then return baseOfCache[id] or nil end
    local data = liveData()
    local rec = data and data.pokemon and data.pokemon[id]
    local base = type(rec) == "table" and rec.baseSpecies
    if type(base) ~= "string" or base == "" then base = nil end
    baseOfCache[id] = base or false
    return base
  end

  -- The one predicate the randomizer consults: an id is delisted when it is in
  -- the set itself OR when its base species is (a delisted species hides its
  -- own forms too).
  local function isBlacklisted(id)
    if type(id) ~= "string" then return false end
    local set = blacklist()
    if set[id] then return true end
    local base = baseOf(id)
    return base ~= nil and set[base] == true
  end
  shared.isBlacklisted = isBlacklisted
  shared.buildBlacklistIndex = buildBlacklistIndex
  shared.blacklistRaw = function(id)
    if type(id) ~= "string" then return false end
    return blacklist()[id] == true
  end

  -- The whole generation's roster, base species and forms alike.  A cell is
  -- "complete" only when every indexed id of that generation is delisted (its
  -- own id, or through a delisted base), so the drawing and the toggle agree.
  function shared.blacklistGenComplete(gen)
    local index = buildBlacklistIndex()
    if not index then return false end
    local set = blacklist()
    local any = false
    for _, entry in ipairs(index) do
      if entry.gen == gen then
        any = true
        if not (set[entry.id] or (entry.base and set[entry.base])) then
          return false
        end
      end
    end
    return any
  end

  -- The window's write actions.  Every one writes straight through, so the
  -- list is kept until it is changed or reset -- there is no save step.
  function shared.blacklistToggle(id)
    if type(id) ~= "string" then return end
    local set = blacklist()
    -- A base species carries its forms along (so the window's own rows and
    -- the randomizer agree); a form stands alone.  The flip is decided from
    -- the id itself, once, so the whole group moves together.
    local turnOn = not set[id]
    set[id] = turnOn and true or nil
    local index = buildBlacklistIndex()
    for _, entry in ipairs(index or {}) do
      if entry.base == id then set[entry.id] = turnOn and true or nil end
    end
    blacklistSave()
  end

  function shared.blacklistGenToggle(gen)
    local index = buildBlacklistIndex()
    if not index then return end
    local set = blacklist()
    local complete = shared.blacklistGenComplete(gen)
    for _, entry in ipairs(index) do
      if entry.gen == gen then
        if complete then set[entry.id] = nil else set[entry.id] = true end
      end
    end
    blacklistSave()
  end

  function shared.blacklistReset()
    local set = blacklist()
    for id in pairs(set) do set[id] = nil end
    blacklistSave()
  end

  -- The [MEGA] / [GIGA] row's two cells.  A group is "complete" when every
  -- indexed id of that group is delisted (its own id, or through a delisted
  -- base), which is exactly what the cell's check mark draws; the toggle flips
  -- the whole group at once.  `group` is formGroupOf's "mega" / "gmax".
  function shared.blacklistFormGroupComplete(group)
    if type(group) ~= "string" then return false end
    local index = buildBlacklistIndex()
    if not index then return false end
    local set = blacklist()
    local any = false
    for _, entry in ipairs(index) do
      if entry.group == group then
        any = true
        if not (set[entry.id] or (entry.base and set[entry.base])) then
          return false
        end
      end
    end
    return any
  end

  function shared.blacklistFormGroupToggle(group)
    if type(group) ~= "string" then return end
    local index = buildBlacklistIndex()
    if not index then return end
    local set = blacklist()
    local complete = shared.blacklistFormGroupComplete(group)
    for _, entry in ipairs(index) do
      if entry.group == group then
        if complete then set[entry.id] = nil else set[entry.id] = true end
      end
    end
    blacklistSave()
  end
  shared.formGroupOf = formGroupOf

  -- ------------------------------------------------------------ terrain class
  -- 2026-09-18, explicit user rule (superseding the earlier aquatic allow-list):
  -- water areas are WATER and FLYING exclusive, a water type is banned from
  -- every non-water area, and a flying type is allowed everywhere.  The picker
  -- still needs to know WHICH of three kinds of ground it is standing on, so
  -- the three spellings below converge.
  --
  -- Gen 1 spells a cave "indoor" (OverworldState:rollEncounter passes
  -- "grass" / "water" / "indoor"); Gen 2 passes only "grass" / "water" and
  -- keeps the cave/indoor case in the map header's environment
  -- (FieldMoves.canEncounterWildMon rolls any walkable cave tile, so a cave
  -- step is a "grass" roll with environment CAVE/DUNGEON).  Both spellings,
  -- and the map-header fallback for a caller that passes neither, land here.
  --   * water -- a surf/fish roll: candidates must be WATER or FLYING typed.
  --   * cave  -- indoor/cave/dungeon/gate: land rules apply.
  --   * land  -- grass/route: same land rules.
  local CAVE_ENV = { CAVE = true, DUNGEON = true, INDOOR = true, GATE = true }
  local function terrainClass(ctx)
    if type(ctx) ~= "table" then return "land" end
    local t = type(ctx.terrain) == "string" and ctx.terrain:lower() or nil
    if t == "water" or t == "ocean" then return "water" end
    if t == "indoor" or t == "cave" then return "cave" end
    local env = ctx.environment
    if type(env) == "string" and CAVE_ENV[env:upper()] then return "cave" end
    return "land"
  end

  -- True when a pool entry carries the given type, in either generation's
  -- spelling ("WATER", "WATER_TYPE", "Water").  WATER is the ban on land and
  -- cave; WATER-or-FLYING is the allow-list on water.
  local function hasType(entry, want)
    local types = type(entry) == "table" and entry.types
    if type(types) ~= "table" then return false end
    for _, t in ipairs(types) do
      if type(t) == "string" then
        local u = t:upper():gsub("_TYPE$", "")
        if u == want then return true end
      end
    end
    return false
  end
  local function isWaterTyped(entry) return hasType(entry, "WATER") end
  local function isFlyingTyped(entry) return hasType(entry, "FLYING") end

  -- True when a pool entry carries ANY of the types in a gym theme set --
  -- the gym-leader rule (see GYM_THEMES).  A nil set means "no theme", i.e.
  -- every species is allowed, which is what a non-league trainer gets.
  local function carriesTheme(entry, themeSet)
    if not themeSet then return true end
    local types = type(entry) == "table" and entry.types
    if type(types) ~= "table" then return false end
    for _, t in ipairs(types) do
      if type(t) == "string" then
        local u = t:upper():gsub("_TYPE$", "")
        if themeSet[u] then return true end
      end
    end
    return false
  end

  -- ----------------------------------------------------- evolutions by level
  -- 2026-09-14, explicit user request: "if Level allows it, we always evolve
  -- pokemon to latest available evolution, trade evolutions are available for
  -- randomization after lvl 40".  So a randomised species is always pushed to
  -- the deepest evolution its LEVEL reaches: a level method needs its own
  -- level, every non-level method (trade, item, friendship, stat) needs
  -- TRADE_LEVEL, and the walk stops the moment nothing is unlocked.
  --
  -- Two sources answer "what does this evolve into":
  --   * the registered `evolutions` field on game.data.pokemon[id] -- the
  --     ROM's own rows for the species that game ships (Red spells a target
  --     `species` and a method LEVEL/ITEM/TRADE; Gold spells it `into` and
  --     EVOLVE_LEVEL/ITEM/TRADE/HAPPINESS/STAT).
  --   * national_dex's exported evolutionsOf(id) DISPLAY record, when that
  --     mod is installed -- the only source of a chain for the 874+
  --     beyond-ROM species, because every record national_dex registers ships
  --     `evolutions = {}` on purpose (its own docs: that field is an
  --     f.id into a fixed per-generation vocabulary and the modern
  --     conditions have no honest id there).  Its rows are { id, methods =
  --     { { trigger, level, ... } } }, current PokeAPI method first.
  -- Both are normalised to { to, kind, level } so ONE walker serves them.
  local displayEvolutions, displayResolved = nil, false
  local function resolveDisplayEvolutions()
    if displayResolved then return displayEvolutions end
    displayResolved = true
    local dex = mod.find and mod.find("national_dex")
    local exports = dex and dex.exports
    if exports and type(exports.evolutionsOf) == "function" then
      displayEvolutions = exports.evolutionsOf
    end
    return displayEvolutions
  end
  local function normaliseDisplay(record)
    local out = {}
    local into = type(record) == "table" and record.evolvesInto
    if type(into) ~= "table" then return out end
    for _, target in ipairs(into) do
      local to = type(target) == "table" and target.id
      local methods = type(target) == "table" and target.methods
      local method = type(methods) == "table" and methods[1] or nil
      local trigger = method and method.trigger
      if type(to) == "string" then
        if trigger == "level-up" then
          -- A level-up row carries its condition in flat fields: an outright
          -- `level`, or a `heldItem` (hold the Oval Stone / Razor Claw and
          -- level up) or a `minHappiness` (level up with friendship).  The
          -- held-item and happiness shapes have NO `level`, so they must not
          -- be read as a level-0 evolution.
          if tonumber(method.level) then
            out[#out + 1] = { to = to, kind = "level",
                              level = tonumber(method.level) }
          elseif type(method.heldItem) == "string" and method.heldItem ~= "" then
            out[#out + 1] = { to = to, kind = "helditem" }
          elseif tonumber(method.minHappiness) then
            out[#out + 1] = { to = to, kind = "happiness" }
          else
            out[#out + 1] = { to = to, kind = "other" }
          end
        elseif trigger == "trade" then
          out[#out + 1] = { to = to, kind = "trade" }
        elseif trigger == "use-item" then
          out[#out + 1] = { to = to, kind = "item" }
        else
          out[#out + 1] = { to = to, kind = "other" }
        end
      end
    end
    return out
  end
  local function normaliseRegistered(rows)
    local out = {}
    if type(rows) ~= "table" then return out end
    for _, evo in ipairs(rows) do
      if type(evo) == "table" then
        local to = evo.species or evo.into
        if type(to) == "string" then
          local method = tostring(evo.method or ""):upper()
          if method:find("HAPPINESS", 1, true) or method:find("FRIEND", 1, true) then
            out[#out + 1] = { to = to, kind = "happiness" }
          elseif method:find("TRADE", 1, true) then
            out[#out + 1] = { to = to, kind = "trade" }
          elseif method:find("LEVEL", 1, true) then
            out[#out + 1] = { to = to, kind = "level",
                              level = tonumber(evo.level) or 0 }
          elseif method:find("ITEM", 1, true) then
            out[#out + 1] = { to = to, kind = "item" }
          else
            out[#out + 1] = { to = to, kind = "other" }
          end
        end
      end
    end
    return out
  end
  local evoCache = {}
  local function evolutionRowsOf(data, id)
    if evoCache[id] then return evoCache[id] end
    local rows
    local resolve = resolveDisplayEvolutions()
    if resolve then
      local ok, record = pcall(resolve, id)
      if ok and type(record) == "table" then rows = normaliseDisplay(record) end
    end
    if not rows then
      local rec = data and data.pokemon and data.pokemon[id]
      rows = normaliseRegistered(rec and rec.evolutions)
    end
    evoCache[id] = rows
    return rows
  end
  -- The wild spawn gate of every evolved species, the reverse of
  -- evolutionRowsOf.  Built once over the whole pool: a species reached ONLY
  -- by a stone / held-item / happiness evolution appears in the wild from its
  -- own gate -- STONE_LEVEL for a stone, EVO_LEVEL (or BABY_EVO_LEVEL when the
  -- pre-evolution is a baby) for a held-item or happiness one -- and never
  -- below it (explicit user rules).  A species that is ALSO reachable by an
  -- ordinary level-up is dropped from the table, because that path's own level
  -- is what actually gates it.
  local evoGates
  local function buildEvoGates(data)
    if evoGates then return evoGates end
    local set, leveled = {}, {}
    if pool then
      for id in pairs(pool) do
        for _, row in ipairs(evolutionRowsOf(data, id)) do
          local to = row.to
          if type(to) == "string" then
            if row.kind == "level" then
              leveled[to] = true
            elseif row.kind == "item" or row.kind == "helditem"
                or row.kind == "happiness" then
              local gate
              if row.kind == "item" then
                gate = STONE_LEVEL
              elseif isBabyId(id) then
                gate = BABY_EVO_LEVEL
              else
                gate = EVO_LEVEL
              end
              local currentGate = set[to]
              if currentGate == nil or gate < currentGate then
                set[to] = gate
              end
            end
          end
        end
      end
    end
    for to in pairs(leveled) do set[to] = nil end
    evoGates = set
    return set
  end

  -- Walk `id` down its chain as far as `level` unlocks, one random branch at
  -- a time when a species has several available, and answer the final id.
  -- `wild` selects the non-level gates: a stone needs STONE_LEVEL in the wild
  -- and TRADE_LEVEL elsewhere, a held-item or happiness evolution needs
  -- EVO_LEVEL (BABY_EVO_LEVEL when the mon evolving is a baby) in the wild and
  -- TRADE_LEVEL elsewhere, and a trade keeps TRADE_LEVEL on both.  A
  -- blacklisted target is never taken.
  local function latestEvolution(data, id, level, wild)
    if type(id) ~= "string" or not pool then return id end
    level = tonumber(level) or 1
    local visited = { [id] = true }
    local current = id
    for _ = 1, 20 do
      local options = {}
      for _, row in ipairs(evolutionRowsOf(data, current)) do
        local target = row.to
        local targetEntry = pool[target]
        if targetEntry and target ~= current and not visited[target]
            and not isBlacklisted(target) then
          local unlocked
          if row.kind == "level" then
            unlocked = level >= (row.level or 0)
          elseif row.kind == "item" then
            unlocked = level >= (wild and STONE_LEVEL or TRADE_LEVEL)
          elseif row.kind == "helditem" or row.kind == "happiness" then
            local gate = wild
              and (isBabyId(current) and BABY_EVO_LEVEL or EVO_LEVEL)
              or TRADE_LEVEL
            unlocked = level >= gate
          else
            unlocked = level >= TRADE_LEVEL
          end
          -- A legendary target obeys the user's level-45 gate too (the only
          -- chains that reach one are the Cosmog line).
          if unlocked and not (targetEntry.legendary
              and level < LEGENDARY_LEVEL) then
            options[#options + 1] = target
          end
        end
      end
      if #options == 0 then break end
      local nextId = options[love.math.random(1, #options)]
      visited[nextId] = true
      current = nextId
    end
    return current
  end

  -- A random species sharing at least one type with origId and whose base
  -- total lands in the user's band: 95% of the original's BST up to
  -- 100% + 5*level percentage points of it.  Returns nil (leave the mon
  -- alone) when the species is unknown or nothing qualifies -- never a
  -- forced substitute.
  --
  -- `opts.terrain` is the terrain class (see terrainClass above): on "water"
  -- a candidate must be WATER or FLYING typed; on "land"/"cave" a WATER type
  -- is banned (a flying type is welcome anywhere).  `opts.data` lets a caller
  -- hand the live data in rather than going through the Game facade, and
  -- `opts.wild` marks a wild encounter so the non-level gates (stone, held
  -- item, happiness) use their WILD levels rather than TRADE_LEVEL.  Once a
  -- candidate is chosen it is pushed to its latest level-legal evolution.  A
  -- legendary is never a candidate below LEGENDARY_LEVEL, and a blacklisted
  -- species (or form) is never one at all.
  local function pickSpecies(origId, level, opts)
    if not pool then return nil end
    local orig = pool[origId]
    if not orig then return nil end
    local lvl = tonumber(level) or 1
    opts = opts or {}
    local data = opts.data or liveData()
    local terrain = opts.terrain or (opts.aquatic and "water") or "any"
    local wild = opts.wild == true
    -- A gym theme (see GYM_THEMES): when set, a candidate -- and the form its
    -- evolution walk lands on -- must carry at least one of the theme's types.
    local theme = type(opts.types) == "table" and opts.types or nil
    local gates = buildEvoGates(data)
    local low = orig.bst * 0.95
    local high = orig.bst * (1 + 5 * lvl / 100)
    local function gateOf(id) return wild and gates[id] or nil end
    local function allowed(e)
      if isBlacklisted(e.id) then return false end
      if theme and not carriesTheme(e, theme) then return false end
      -- A stone / held-item / happiness evolution only shows up in the wild
      -- from its own gate (35, or 25 for a baby line).
      local gate = gateOf(e.id)
      if gate and lvl < gate then return false end
      if terrain == "water" then
        -- Surf/fish rule: WATER and FLYING are the only types that live here.
        return isWaterTyped(e) or isFlyingTyped(e)
      end
      if terrain == "any" then return true end
      -- Land and cave rule: never a WATER type (a flying type is fine).
      return not isWaterTyped(e)
    end
    local seen, candidates = {}, {}
    for _, t in ipairs(orig.types) do
      for _, e in ipairs(byType[t] or {}) do
        if not seen[e.id] and e.id ~= origId
            and e.bst >= low and e.bst <= high
            and (not e.legendary or lvl >= LEGENDARY_LEVEL)
            and allowed(e) then
          seen[e.id] = true
          candidates[#candidates + 1] = e.id
        end
      end
    end
    if #candidates == 0 then return nil end
    local base = candidates[love.math.random(1, #candidates)]
    local evolved = latestEvolution(data, base, lvl, wild)
    -- The evolution walk can land on a species the terrain (or the blacklist,
    -- an evolution gate, or the gym theme) forbids; leave the original alone
    -- rather than produce an illegal mon.
    if isBlacklisted(evolved) then return nil end
    if theme and not carriesTheme(pool[evolved], theme) then return nil end
    local gate = gateOf(evolved)
    if gate and lvl < gate then return nil end
    if terrain == "water" then
      if not (isWaterTyped(pool[evolved]) or isFlyingTyped(pool[evolved])) then
        return nil
      end
    elseif terrain ~= "any" and isWaterTyped(pool[evolved]) then
      return nil
    end
    return evolved
  end

  -- ------------------------------------------------------- difficulty specs
  -- The 20 natures that actually move a stat, as { boosted, lowered }.  HP
  -- is never affected by a nature, so it never appears here.
  local NATURE_EFFECT = {
    Lonely = { "atk", "def" }, Adamant = { "atk", "spa" },
    Naughty = { "atk", "spd" }, Brave = { "atk", "spe" },
    Bold = { "def", "atk" }, Impish = { "def", "spa" },
    Lax = { "def", "spd" }, Relaxed = { "def", "spe" },
    Modest = { "spa", "atk" }, Mild = { "spa", "def" },
    Rash = { "spa", "spd" }, Quiet = { "spa", "spe" },
    Calm = { "spd", "atk" }, Gentle = { "spd", "def" },
    Careful = { "spd", "spa" }, Sassy = { "spd", "spe" },
    Timid = { "spe", "atk" }, Hasty = { "spe", "def" },
    Jolly = { "spe", "spa" }, Naive = { "spe", "spd" },
  }
  local STAT_KEYS = { "hp", "atk", "def", "spa", "spd", "spe" }
  local NEUTRAL_NATURE = "Hardy"

  local function baseStatMap(baseStats)
    if type(baseStats) ~= "table" then return nil end
    local spa = baseStats.spAttack or baseStats.specialAttack or baseStats.special
    local spd = baseStats.spDefense or baseStats.specialDefense or baseStats.special
    if type(baseStats.hp) ~= "number" or type(baseStats.attack) ~= "number"
        or type(baseStats.defense) ~= "number" or type(baseStats.speed) ~= "number"
        or type(spa) ~= "number" or type(spd) ~= "number" then
      return nil
    end
    return { hp = baseStats.hp, atk = baseStats.attack, def = baseStats.defense,
             spa = spa, spd = spd, spe = baseStats.speed }
  end

  -- A favourable nature: boost the highest non-HP base stat.  `mode` picks
  -- the stat to lower.  "hard" lowers the overall lowest non-HP stat (the
  -- plain reading of "favorable natures based on highest base stat");
  -- "hell" lowers the weaker of the two OFFENCES and never a defensive stat
  -- ("only attack or special"), which is strictly the better mon -- exactly
  -- what the hardest setting should field.
  local function natureFor(baseStats, mode)
    local b = baseStatMap(baseStats)
    if not b then return NEUTRAL_NATURE end
    local order = {}
    for _, k in ipairs({ "atk", "def", "spa", "spd", "spe" }) do
      order[#order + 1] = { key = k, value = b[k] }
    end
    table.sort(order, function(x, y) return x.value > y.value end)
    local up = order[1].key
    local down
    if mode == "hell" then
      down = (b.atk <= b.spa) and "atk" or "spa"
      if down == up then down = (down == "atk") and "spa" or "atk" end
    else
      down = order[#order].key
      if down == up then down = order[#order - 1].key end
    end
    for name, effect in pairs(NATURE_EFFECT) do
      if effect[1] == up and effect[2] == down then return name end
    end
    return NEUTRAL_NATURE
  end

  -- The engine's spec table (stats/trainer_modern_stats.lua): iv/ev per
  -- ModernStats.ORDER key plus a nature.
  local function specFor(baseStats, level)
    local diff = difficulty()
    local iv, ev = 10, 12
    local nature = NEUTRAL_NATURE
    if diff == "easy" then iv, ev = 0, 0
    elseif diff == "hard" then
      iv, ev = 20, 24
      nature = natureFor(baseStats, "hard")
    elseif diff == "hell" then
      iv = 31
      nature = natureFor(baseStats, "hell")
    end

    local evs = {}
    for _, k in ipairs(STAT_KEYS) do evs[k] = ev end
    if diff == "hell" then
      -- 252 / 252 on the two highest base stats, 4 on the third highest.
      local b = baseStatMap(baseStats)
      local order = {}
      for _, k in ipairs(STAT_KEYS) do
        order[#order + 1] = { key = k, value = (b and b[k]) or 0 }
      end
      table.sort(order, function(x, y) return x.value > y.value end)
      for _, k in ipairs(STAT_KEYS) do evs[k] = 0 end
      evs[order[1].key] = 252
      evs[order[2].key] = 252
      evs[order[3].key] = 4
    end

    local function part(k) return { iv = iv, ev = evs[k] or 0 } end
    return {
      nature = nature,
      hp = part("hp"), atk = part("atk"), def = part("def"),
      spa = part("spa"), spd = part("spd"), spe = part("spe"),
    }
  end

  -- One provider serves both generations (the engine's own design): Gen 1
  -- calls it from a BattleState.newTrainer wrap, Gen 2 from its
  -- battle.started listener.  Priority 100 deliberately outranks every
  -- default-priority provider, so the DIFFICULTY setting governs every
  -- trainer the engine's stats chain is asked about.
  local function trainerStatsProvider(ctx)
    if type(ctx) ~= "table" then return nil end
    local data = ctx.data or (ctx.game and ctx.game.data) or liveData()
    local rec = data and data.pokemon and ctx.species and data.pokemon[ctx.species]
    return specFor(rec and rec.baseStats, ctx.level)
  end

  local providerInstalled = false
  local function installProvider()
    if providerInstalled then return end
    local engine = mod.find and mod.find("g9-battle-engine")
    local exports = engine and engine.exports
    if exports and exports.registerTrainerStatsProvider then
      exports.registerTrainerStatsProvider(trainerStatsProvider, 100)
      providerInstalled = true
    end
  end
  installProvider()
  if not providerInstalled then
    -- The engine is a declared dependency, so it is normally loaded by now;
    -- this is the same safe deferred-install fallback the engine's modding
    -- guide recommends for when it isn't.
    mod.events:on("mods.loaded", installProvider)
  end

  -- ------------------------------------------------- randomizer party swap
  -- Gen 2's "trainer.party" hands back real Mon objects, so a swapped
  -- species has to be REBUILT as one (same Mon.new call Trainers.lua's own
  -- Trainers.party uses), keeping the mon's own DVs and held item so its
  -- identity/gender/shiny stay put; Gen 1's hook hands back plain
  -- {species, level, moves?} rows instead, so there the species is edited in
  -- place and any explicit move list is dropped (it described the OLD
  -- species; the new one gets its own level-up set).
  local function rebuildGen2Mon(data, newId, orig)
    local ok, Mon = pcall(require, "src.battle.gen2.Mon")
    if not (ok and type(Mon) == "table" and type(Mon.new) == "function") then
      return nil
    end
    local opts = {}
    if type(orig.dvs) == "table" then opts.dvs = orig.dvs end
    if orig.item ~= nil then opts.item = orig.item end
    local okNew, mon = pcall(Mon.new, data, newId, orig.level, opts)
    if okNew and type(mon) == "table" then return mon end
    return nil
  end

  -- The one party-swap implementation, used by BOTH the "trainer.party" hook
  -- (Gen 1's rows and every native trainer battle) and the Gen 2 arm's own
  -- scene path (see tryTrainerLayout: a g9-Battle-Scene fight renders the
  -- roster IT was handed in payload.enemies, not battle.enemyParty, so the
  -- scene's roster has to be swapped BEFORE the push -- and those swapped
  -- mons are tagged __g9sampleRand so the hook leaves them alone on the way
  -- through Battle.new.  Without the tag the model and the screen would end
  -- up holding different rosters, and the difficulty provider -- which runs
  -- on battle.enemyParty -- would land on the ones the player never sees).
  -- Returns the SAME array when nothing changed, so a battle with the
  -- randomizer off (or nothing eligible) keeps exact object identity for the
  -- engine's own Mon.refreshStats/stat passes.
  function shared.randomizeParty(party, data, theme)
    if type(party) ~= "table" then return party end
    if not randTrainersOn() then return party end
    data = data or liveData()
    if not buildPool(data) then return party end
    local opts = theme and { types = theme } or nil
    local out, changed = {}, false
    for i = 1, #party do
      local entry = party[i]
      if type(entry) == "table" and type(entry.species) == "string"
          and not entry.__g9sampleRand then
        local newId = pickSpecies(entry.species, entry.level, opts)
        if newId then
          if type(entry.stats) == "table" or type(entry.dvs) == "table" then
            local rebuilt = rebuildGen2Mon(data, newId, entry)
            if rebuilt then
              rebuilt.__g9sampleRand = true
              out[i] = rebuilt
              changed = true
            else
              out[i] = entry
            end
          else
            local copy = {}
            for k, v in pairs(entry) do copy[k] = v end
            copy.species = newId
            copy.moves = nil
            out[i] = copy
            changed = true
          end
        else
          out[i] = entry
        end
      else
        out[i] = entry
      end
    end
    if not changed then return party end
    return out
  end

  -- ------------------------------------------------- trainer team minimums
  -- The DIFFICULTY setting ALSO sets a floor on a trainer's team size
  -- (explicit user request, 2026-09-13): EASY keeps the vanilla quantity,
  -- NORMAL is 2, HARD is 4, HELL is 6.  Pokemon are only ever ADDED when the
  -- vanilla team is under that floor -- a trainer with 5 mons keeps all 5 on
  -- hard and gets exactly one more on hell.  Every added mon is modelled on
  -- one of the team's own members, at THAT member's level, with the same
  -- species rules the randomizer already uses (the type/BST matcher when
  -- RAND TRAINER MONS is on, the template's own species when it is off), so
  -- a padded team is level-matched and obeys the mod's rules.  This is a
  -- DIFFICULTY feature, not a randomization one, so it applies with RAND
  -- TRAINER MONS off too.
  local MIN_TEAM = { easy = 0, normal = 2, hard = 4, hell = 6 }
  local function minTeamSize() return MIN_TEAM[difficulty()] or 0 end

  -- A numeric level off a template member, falling back to the first level
  -- in the party and then to 5, so a row without one still gets a sane mon.
  local function teamLevel(template, party)
    if type(template) == "table" and type(template.level) == "number" then
      return template.level
    end
    for i = 1, #party do
      local l = party[i] and party[i].level
      if type(l) == "number" then return l end
    end
    return 5
  end

  -- One ADDITIONAL member modelled on `template`.  A real Mon object (the
  -- Gen 2 arm's parties, and a built Gen 1 enemyParty) gets a real mon back
  -- through the running game's own constructor; the plain
  -- {species, level, moves?} ROWS Gen 1's party builder feeds the hook get a
  -- row back.  Returns nil when nothing can be built.
  local function buildExtraMember(data, template, party, theme)
    if type(template) ~= "table" then return nil end
    local level = teamLevel(template, party)
    local newId = template.species
    if randTrainersOn() and buildPool(data) then
      newId = pickSpecies(template.species, level,
        theme and { types = theme } or nil) or template.species
    end
    if type(newId) ~= "string" then return nil end
    if type(template.stats) == "table" or type(template.dvs) == "table" then
      local mon
      if gameGen == 2 then
        mon = rebuildGen2Mon(data, newId, template)
      else
        local ok, Pokemon = pcall(require, "src.pokemon.Pokemon")
        if ok and type(Pokemon) == "table"
            and type(Pokemon.new) == "function" then
          local okNew, built = pcall(Pokemon.new, data or liveData(), newId,
            level)
          if okNew and type(built) == "table" then mon = built end
        end
      end
      -- A mon the running game cannot rebuild is left out rather than
      -- downgraded to a row (a row where a mon was expected would break the
      -- party builder).
      if type(mon) ~= "table" then return nil end
      mon.__g9sampleRand = true
      return mon
    end
    local copy = {}
    for k, v in pairs(template) do copy[k] = v end
    copy.species = newId
    copy.level = level
    copy.moves = nil
    copy.__g9sampleRand = true
    return copy
  end

  -- Pad a trainer party up to the difficulty floor.  Returns the SAME array
  -- when it already qualifies -- identity preserved for the engine's own
  -- stat passes -- and a fresh one otherwise.
  function shared.padTrainerParty(party, data, theme)
    if type(party) ~= "table" or #party == 0 then return party end
    local want = minTeamSize()
    if want <= #party then return party end
    data = data or liveData()
    local out = {}
    for i = 1, #party do out[i] = party[i] end
    while #out < want do
      local template = party[love.math.random(1, #party)]
      local mon = buildExtraMember(data, template, party, theme)
      if not mon then break end
      out[#out + 1] = mon
    end
    if #out == #party then return party end
    return out
  end
  shared.minTeamSize = minTeamSize
  -- The two live-facade readers the LEAGUE ACES installer (a separate
  -- top-level function, so this one's own local budget stays untouched)
  -- needs: it builds its mon/rows off the running game's data and reads the
  -- player's starter off the save.
  shared.liveData = liveData
  shared.liveSave = liveSave

  -- ------------------------------------------------- wild level settings
  -- 2026-09-10, explicit user request (both a no-op unless RAND WILDS is on):
  --   [WILD LEVELS]    OFF/0/+2/+4/+6/+8/+16/-2/-4/-6/-8/-16 -- OFF keeps the
  --                    vanilla level; a number rebases the level onto the
  --                    anchor (0 = exactly the anchor, +/-N = anchor+N).
  --   [WILD LV ANCHOR] LOWEST/HIGHEST/AVERAGE/LEADER -- which party mon's
  --                    level the value is measured from.
  -- A wild mon's level becomes (anchor + delta) + the area's own natural
  -- spread, so a delta of 16 on a party whose highest is 30 makes the area
  -- 46-48 and a delta of 0 on the same party makes a 2-4 route read 30-32,
  -- rather than flattening every roll to one number.
  --
  -- 2026-09-10 (1.2.1), explicit user request: before this there was no OFF
  -- and a 0 delta was the no-op, so "0" silently did nothing.  Now OFF is the
  -- only no-op and 0 really rebases onto the anchor.
  local WILD_LEVEL_DELTAS = {
    ["0"] = 0, ["2"] = 2, ["4"] = 4, ["6"] = 6, ["8"] = 8, ["16"] = 16,
    ["-2"] = -2, ["-4"] = -4, ["-6"] = -6, ["-8"] = -8, ["-16"] = -16,
  }

  -- nil means OFF (leave the vanilla roll alone); a number is the delta.
  local function wildLevelsDelta()
    local v = option("wild_levels")
    if v == nil then return nil end
    if type(v) == "string" then
      local key = v:lower()
      if key == "off" then return nil end
      local n = WILD_LEVEL_DELTAS[key]
      if n then return n end
    end
    local n = tonumber(v)
    if n then return n end
    return nil
  end

  local function clampWildLevel(level)
    level = math.floor((tonumber(level) or 1) + 0.5)
    if level < 1 then level = 1 end
    if level > 100 then level = 100 end
    return level
  end

  -- The party's anchor level, by the chosen mode; nil when no party mon has a
  -- numeric level (or the party is empty).
  local function partyAnchorLevel(mode)
    local save = liveSave()
    local party = save and save.party
    if type(party) ~= "table" or #party == 0 then return nil end
    mode = type(mode) == "string" and mode or "highest"
    if mode == "leader" then
      local lead = party[1]
      return lead and tonumber(lead.level) or nil
    end
    local min, max, sum, n
    for i = 1, #party do
      local l = party[i] and tonumber(party[i].level)
      if l then
        if not min or l < min then min = l end
        if not max or l > max then max = l end
        sum = (sum or 0) + l
        n = (n or 0) + 1
      end
    end
    if not n then return nil end
    if mode == "lowest" then return min end
    if mode == "average" then return math.floor(sum / n + 0.5) end
    return max
  end

  -- The last real roll's own spawn-level window (min/max across the area's
  -- slots) and terrain, stashed here by the encounter.roll wrap.  Module
  -- state, not fields on the roll -- Gen 2 builds a real Mon from the roll
  -- before the wild path ever sees it, so anything hung on the roll table is
  -- lost by then.  The wild path runs synchronously right after the roll, so
  -- the stash is always the roll that produced the fight.
  local lastAreaMin, lastAreaMax = nil, nil
  local lastWildTerrain = "land"
  local lastWildBanned = false
  -- The last real roll's own VANILLA spawn level, before WILD LEVELS rebases
  -- it.  The SPECIES pick (the BST band, the evolution walk and the
  -- stone/held-item gates) reads this, never the rebased fight level --
  -- explicit user rule (2026-09-10): "if level allows it evolve the pokemon
  -- (must) -- that level refers to the base (vanilla) spawn table not the set
  -- by dynamic growth of [wild levels]".  WILD LEVELS changes what level the
  -- fight happens at; it must not push the species further up its evolution
  -- line (or widen its band) than its own spawn-table level allows.
  local lastWildVanillaLevel = 1

  -- Ruins of Alph underground (the Unown spawn area) is NEVER randomised.
  -- Explicit user request (2026-09-12), and an unconditional ban: there is
  -- deliberately no option to turn it off.  The four item chambers and the
  -- Inner Chamber are the underground, and their own wild table is UNOWN and
  -- nothing else -- a randomised step there would overwrite the one species
  -- the area exists to spawn.  RUINS_OF_ALPH_OUTSIDE (Natu / Smeargle /
  -- Wooper) is an ordinary outdoor area and stays randomised, which is why
  -- the match is the RUINS_OF_ALPH_*CHAMBER shape and not the bare
  -- RUINS_OF_ALPH prefix.  Matching is case-insensitive on the map id.
  local function ruinsUnderground(mapId)
    if type(mapId) ~= "string" then return false end
    return mapId:upper():match("^RUINS_OF_ALPH_.*CHAMBER$") ~= nil
  end

  -- finalLevel, base, spread.  nil when the settings are off or inapplicable.
  -- `rolledLevel` lets the caller keep the rolled mon's own position inside
  -- the area's spread; a nil `rolledLevel` asks only for the base.
  local function wildLevelPlan(rolledLevel)
    if not randWildsOn() then return nil end
    local delta = wildLevelsDelta()
    if delta == nil then return nil end
    local anchor = partyAnchorLevel(option("wild_anchor"))
    if not anchor then return nil end
    local base = anchor + delta
    local spread = 0
    if type(lastAreaMin) == "number" and type(lastAreaMax) == "number"
        and lastAreaMax > lastAreaMin then
      spread = lastAreaMax - lastAreaMin
    end
    local variance = 0
    if type(rolledLevel) == "number" and type(lastAreaMin) == "number"
        and rolledLevel > lastAreaMin then
      variance = math.min(rolledLevel - lastAreaMin, spread)
    end
    return clampWildLevel(base + variance), base, spread
  end

  -- An INDEPENDENT roll for one extra enemy slot of a doubles/triples wild
  -- fight: its own species pick (same terrain rule as the base roll) and its
  -- own level inside the area's spread.  Returns nil when there is nothing to
  -- roll, and the caller then clones the base roll exactly as before.
  function shared.wildSlotSpecies(enc, level)
    if not randWildsOn() or lastWildBanned then return nil end
    local base = type(enc) == "table" and enc.species or nil
    if type(base) ~= "string" then return nil end
    local data = liveData()
    if not buildPool(data) then return nil end
    -- The extra slot's species pick reads the base roll's VANILLA level (same
    -- rule as the base pick -- see lastWildVanillaLevel); the `level` handed
    -- in is only the slot's FIGHT level (the rebased one).
    return pickSpecies(base, lastWildVanillaLevel,
      { terrain = lastWildTerrain, data = data, wild = true })
  end

  function shared.wildSlotLevel()
    if not randWildsOn() or lastWildBanned then return nil end
    local _, base, spread = wildLevelPlan(nil)
    if not base then return nil end
    local variance = 0
    if spread and spread > 0 then variance = love.math.random(0, spread) end
    return clampWildLevel(base + variance)
  end

  -- One real roll -> stash the area's spawn-level window.  Handles both
  -- generations' table shapes: Gen 2 is encDef.grass[mapId].slots[DAY/NITE],
  -- Gen 1 is encDef.grass.slots.
  local function levelWindow(list, mn, mx)
    for _, slot in ipairs(type(list) == "table" and list or {}) do
      local l = type(slot) == "table" and tonumber(slot.level)
      if l then
        if not mn or l < mn then mn = l end
        if not mx or l > mx then mx = l end
      end
    end
    return mn, mx
  end

  local function areaLevelWindow(encDef, ctx)
    if type(encDef) ~= "table" or type(ctx) ~= "table" then return nil, nil end
    local terrain = type(ctx.terrain) == "string" and ctx.terrain:lower() or "grass"
    local wantWater = (terrain == "water" or terrain == "ocean")
    local mapId = ctx.mapId
    local mn, mx
    if mapId then
      local grass = encDef.grass and encDef.grass[mapId]
      if grass and grass.slots and not wantWater then
        local key = (ctx.daytime == "DARK") and "NITE" or (ctx.daytime or "DAY")
        mn, mx = levelWindow(grass.slots[key] or grass.slots.DAY, mn, mx)
      end
      local water = encDef.water and encDef.water[mapId]
      if water and water.slots and (wantWater or not mn) then
        mn, mx = levelWindow(water.slots, mn, mx)
      end
    end
    if not mn and encDef.grass and encDef.grass.slots and not wantWater then
      mn, mx = levelWindow(encDef.grass.slots, mn, mx)
    end
    if encDef.water and encDef.water.slots and (wantWater or not mn) then
      mn, mx = levelWindow(encDef.water.slots, mn, mx)
    end
    return mn, mx
  end

  mod.hooks:wrap("encounter.roll", function(nextFn, encDef, ctx)
    local enc = nextFn(encDef, ctx)
    if type(ctx) == "table" then
      -- The Ruins of Alph underground ban, read from the map the roll came
      -- from.  Kept as module state so the doubles/triples slot rolls below
      -- (which run after this, off the same encounter) can see it too.
      lastWildBanned = ruinsUnderground(ctx.mapId)
      local mn, mx = areaLevelWindow(encDef, ctx)
      if mn then lastAreaMin, lastAreaMax = mn, mx end
    else
      lastWildBanned = false
    end
    return enc
  end, 0)

  -- The wild species swap.  `terrainClass(ctx)` is the whole terrain rule on
  -- BOTH games -- Gen 1's rollEncounter passes "grass"/"water"/"indoor", Gen 2
  -- passes "water" for anything rolled off a water tile and keeps its caves in
  -- the map header's `environment` -- so one call settles water vs cave vs
  -- land here.
  mod.hooks:wrap("encounter.species", function(nextFn, enc, ctx)
    local rolled = nextFn(enc, ctx)
    -- Ruins of Alph underground: an unconditional ban, checked before
    -- anything else, so the roll is handed on exactly as vanilla -- species
    -- and level untouched.  (The roll hook above already set the flag for
    -- this encounter; this also covers a caller that reached the species
    -- hook without it.)
    lastWildBanned = ruinsUnderground(ctx and ctx.mapId)
    if lastWildBanned or not randWildsOn() then return rolled end
    if type(rolled) ~= "table" or type(rolled.species) ~= "string" then
      return rolled
    end
    local data = (ctx and ctx.data) or liveData()
    local terrain = terrainClass(ctx)
    lastWildTerrain = terrain
    -- The SPECIES pick reads the VANILLA rolled level -- its BST band, its
    -- evolution walk and its stone/held-item gates all key off the spawn
    -- table's own level.  Explicit user rule (2026-09-10): "[a wild mon]
    -- evolves if its level allows it -- that level is the base (vanilla)
    -- spawn table, not the [WILD LEVELS] one".  WILD LEVELS is applied AFTER,
    -- and only changes the level the fight happens at.
    lastWildVanillaLevel = tonumber(rolled.level) or 1
    local planLevel = wildLevelPlan(rolled.level)
    if planLevel then rolled.level = planLevel end
    if buildPool(data) then
      local newId = pickSpecies(rolled.species, lastWildVanillaLevel,
        { terrain = terrain, data = data, wild = true })
      if newId then rolled.species = newId end
    end
    return rolled
  end, 0)

  -- Fishing rides its OWN hook, never the one above: both games roll the rod
  -- through `encounter.fishing` and hand the result straight to the battle, so
  -- a fished Pokemon was not being randomised at all before 0.9.1.  The
  -- user's water rule names fished Pokemon explicitly, so the chain is wrapped
  -- here with the same aquatic-restricted pick as a surf encounter.  The chain
  -- returns { species, level } (or nil for "not even a nibble"), so it is
  -- edited in place exactly like the species hook's result.
  mod.hooks:wrap("encounter.fishing", function(nextFn, rod, mapId, candidates,
                                                 ctx)
    local enc = nextFn(rod, mapId, candidates, ctx)
    -- Ruins of Alph underground ban (see the wild hooks above): no fished
    -- roll is randomised there either.  The area has no water, so this is
    -- belt-and-braces rather than a live path, but it keeps the ban whole.
    if ruinsUnderground(mapId) or (ctx and ruinsUnderground(ctx.mapId)) then
      lastWildBanned = true
      return enc
    end
    lastWildBanned = false
    if not randWildsOn() then return enc end
    if type(enc) ~= "table" or type(enc.species) ~= "string" then return enc end
    local data = (ctx and ctx.data) or liveData()
    lastWildTerrain = "water"
    -- Same rule as the grass roll above: the species pick reads the VANILLA
    -- level; WILD LEVELS only changes the fight's level afterwards.
    lastWildVanillaLevel = tonumber(enc.level) or 1
    local planLevel = wildLevelPlan(enc.level)
    if planLevel then enc.level = planLevel end
    if buildPool(data) then
      local newId = pickSpecies(enc.species, lastWildVanillaLevel,
        { terrain = "water", data = data, wild = true })
      if newId then enc.species = newId end
    end
    return enc
  end, 0)

  mod.hooks:wrap("trainer.party", function(nextFn, classId, memberId, party)
    local result = nextFn(classId, memberId, party)
    -- A gym leader / Elite Four keeps their own type theme through BOTH the
    -- difficulty team floor and the species swap (GYM_THEMES); every other
    -- trainer gets no theme.
    local theme = shared.themeTypesFor(classId)
    -- Difficulty team floor first, then the cumulative rematch levels (Gen 1
    -- only -- on Gen 2 the bonus is applied once, in the arm's own
    -- World:startBattle wrap, because this hook runs a second time inside the
    -- scene's own model build there), then the species swap (added mons are
    -- tagged, so the swap leaves them exactly as built).
    result = shared.padTrainerParty(result, nil, theme)
    if gameGen == 1 then
      result = shared.scaleGen1RematchLevels(classId, memberId, result)
    end
    result = shared.randomizeParty(result, nil, theme)
    -- LEAGUE ACES last: the listed ace Pokemon take over the FINAL slots and
    -- are exempt from the randomizer that just ran over the rest (see
    -- installLeagueAces).  Returns the same array when the row is OFF, the
    -- class is not a league trainer, or the party already carries an ace.
    return shared.applyLeagueAces(result, classId, memberId)
  end, 0)

  -- ------------------------------------------------- combat-type routing
  -- Class ids are per generation and disjoint (Gen 1 spells them OPP_*), so
  -- ONE pair of tables answers for both.  Elite Four rolls doubles-or-
  -- triples per battle; Champion and Red are the bossFight.
  local E4_CLASSES = {
    OPP_LORELEI = true, OPP_BRUNO = true, OPP_AGATHA = true, OPP_LANCE = true,
    WILL = true, BRUNO = true, KAREN = true, KOGA = true,
  }
  local BOSS_CLASSES = { OPP_RIVAL3 = true, CHAMPION = true, RED = true }

  -- Kept for a caller that knows only the class, not the team size: it is
  -- exactly the 2+-mon answer of the real router below (bossFight for a boss
  -- class, a doubles-or-triples roll for the Elite Four, otherwise doubles).
  function shared.layoutForClass(classId)
    return shared.layoutForTrainer(classId, 2)
  end

  function shared.isBossClass(classId)
    return type(classId) == "string" and BOSS_CLASSES[classId] == true
  end

  -- The TRAINER layout, decided by the shape of the fight that already exists
  -- (explicit user request, 2026-09-14: trainer battles and rematches enable
  -- "doubles, triples and bossfight based on the already existing enemy
  -- battle").  A boss class (Champion, Red, Gen 1's OPP_RIVAL3) always takes
  -- "bossFight"; a team with a single Pokemon cannot fill a doubles/triples
  -- row, so it takes the scene's own "singles" screen -- never the game's
  -- native one; the Elite Four roll doubles-or-triples per battle; every other
  -- 2+-mon team is a "doubles".  BOTH generation arms call this one function,
  -- so the trainer routing can no longer drift between them.
  function shared.layoutForTrainer(classId, partySize)
    if shared.isBossClass(classId) then return "bossFight" end
    local size = tonumber(partySize) or 1
    if size < 2 then return "singles" end
    if type(classId) == "string" and E4_CLASSES[classId] then
      return (love.math.random(1, 2) == 1) and "doubles" or "triples"
    end
    return "doubles"
  end

  -- The wild bands, plus the 0.5% bossFight.  Its own 1-in-1000 roll first,
  -- so the special bands below keep exactly the odds they had and can never
  -- overlap it.
  function shared.rollWildLayout(multiAlly)
    if love.math.random(1, 1000) <= 5 then return "bossFight", true end
    local roll = love.math.random(1, 100)
    if multiAlly and roll <= 1 then return "hordes", false end
    if multiAlly and roll <= 3 then return "triples", false end
    if multiAlly and roll <= 13 then return "doubles", false end
    return "singles", false
  end

  -- x1..x5 max HP on a wild boss.  Both the live hp and the max the scene
  -- reads are written, across both generations' field conventions (Gen 2
  -- stamps mon.maxHp; Gen 1 keeps the cap on mon.stats.hp).
  function shared.scaleWildHp(mon)
    if type(mon) ~= "table" then return 1 end
    local mult = love.math.random(1, 5)
    local base = tonumber(mon.maxHp) or (mon.stats and tonumber(mon.stats.hp)) or 0
    if base > 0 then
      local hp = base * mult
      mon.hp = hp
      mon.maxHp = hp
      if mon.stats then mon.stats.hp = hp end
    end
    return mult
  end

  -- A RANDOM boss-protection set on the battle the scene just built.  Each
  -- recognised flag is switched on with independent 35% odds, and at least
  -- one always is, so a bossFight is never flagless.  `screen.battle` is the
  -- live model (Gen 1 and Gen 2 both put it there -- it is what
  -- pushDoubleBattleScreen hands back and what battle_screen.lua's own
  -- bossFightFlags check reads).
  function shared.applyBossFlags(screen)
    local engine = mod.find and mod.find("g9-battle-engine")
    local exports = engine and engine.exports
    local battle = screen and screen.battle
    if not (exports and exports.setBossFightProtections and battle) then return end
    local names = exports.BOSS_FIGHT_FLAG_NAMES or {}
    if #names == 0 then return end
    local picked = {}
    for _, name in ipairs(names) do
      if love.math.random() < 0.35 then picked[#picked + 1] = name end
    end
    if #picked == 0 then picked[1] = names[love.math.random(1, #names)] end
    exports.setBossFightProtections(battle, unpack(picked))
  end

  -- ======================================================================
  -- 2026-09-14, explicit user request -- five more systems, each its own
  -- option, each OFF by default so an untouched save keeps the behaviour it
  -- had: an item randomizer, an item respawn timer, rematches, a cumulative
  -- +level per rematch, and a random item drop from a beaten trainer.
  --
  -- Everything here is generation-agnostic -- the states and pools below are
  -- plain data -- and the two arms (installGen2 / installGen1) hang the same
  -- helpers off whichever seam their generation actually has.
  -- ======================================================================

  -- The option predicates.  They are locals for this file's own use AND are
  -- hung on `shared`, because the two arms receive nothing but that table: a
  -- predicate an arm calls has to live on it, and a bare-local call from an
  -- arm is a nil call (exactly the crash the 0.5.0 build shipped with).
  local function itemRandomizerOn() return option("item_randomizer") == true end
  local function itemRespawnOn() return option("item_respawn") == true end
  local function rematchesOn() return option("rebattles") == true end
  local function gymRematchesOn() return option("gym_rematches") == true end
  local function trainerDropOn() return option("trainer_item_drop") == true end
  shared.itemRandomizerOn = itemRandomizerOn
  shared.itemRespawnOn = itemRespawnOn
  shared.rematchesOn = rematchesOn
  shared.gymRematchesOn = gymRematchesOn
  shared.trainerDropOn = trainerDropOn

  -- How often a beaten trainer actually pays out the drop, as a 0..1
  -- probability, read live off the Manager (like every other sub-setting
  -- here) so changing it takes effect on the next win.  100% maps to exactly
  -- 1.0, which queueTrainerDrop short-circuits -- the pre-0.5.5 behaviour,
  -- where an ON drop always landed, is what the default reproduces.
  local TRAINER_DROP_CHANCES = { ["5"] = 0.05, ["10"] = 0.10,
                                 ["20"] = 0.20, ["40"] = 0.40,
                                 ["80"] = 0.80, ["100"] = 1.0 }
  local function trainerDropChance()
    return TRAINER_DROP_CHANCES[tostring(option("trainer_item_chance"))] or 1.0
  end
  shared.trainerDropChance = trainerDropChance

  -- The cumulative per-rematch level step, 0 when OFF.  Every step is read
  -- live off the Manager, so changing it takes effect on the next fight.
  local REMATCH_STEPS = { ["1"] = 1, ["2"] = 2, ["4"] = 4, ["8"] = 8,
                           ["16"] = 16 }
  local function rematchStep()
    if option("rebattle_levels") == "off" then return 0 end
    return REMATCH_STEPS[tostring(option("rebattle_levels"))] or 0
  end
  -- Wins are only tallied while at least one of the two rematch settings
  -- wants them, so a player who never turns this on pays nothing for it.
  local function rematchTracking()
    return rematchesOn() or rematchStep() > 0
  end

  local RESPAWN_SECONDS = { ["30s"] = 30, ["1m"] = 60, ["2m"] = 120,
                            ["3m"] = 180, ["4m"] = 240, ["5m"] = 300 }
  local function respawnInterval()
    return RESPAWN_SECONDS[tostring(option("respawn_timer"))] or 60
  end
  shared.rematchStep = rematchStep
  shared.rematchTracking = rematchTracking
  shared.respawnInterval = respawnInterval

  -- The player roster handed to the scene: the first `count` LIVING party mons
  -- in party order.  2026-09-12, explicit user report: a fainted mon at slot
  -- 2/3/4 of the party was still being sent out for doubles/triples/boss
  -- layouts, because every caller sliced party[1..count] with no HP test.  The
  -- scene draws whatever it is handed, so a 0-HP mon landed on the field with
  -- no switch prompt instead of the next healthy mon taking its place.  This
  -- lives on `shared` (not per-arm) because all three Gen 2 sites -- the
  -- doubles/triples trainer push, the fixed bossFight (Eternatus), and the
  -- ordinary wild push -- build their rosters from the same live save, and
  -- installGen1's own local playerRoster now delegates here too.  Walking the
  -- whole party rather than slicing 1..count keeps the lead correct when
  -- party[1] is the fainted one.
  local function playerRoster(count)
    local save = liveSave()
    local party = save and save.party
    local players = {}
    for i = 1, #(party or {}) do
      if #players >= count then break end
      local mon = party[i]
      if mon and (mon.hp or 0) > 0 then players[#players + 1] = mon end
    end
    return players
  end
  shared.playerRoster = playerRoster

  -- --------------------------------------------------- beaten trainers
  -- "Is this object a trainer?" and "has it already been beaten?" -- the two
  -- questions every REMATCHES gate asks.  They live here, on `shared`, because
  -- the two generations answer both in DIFFERENT places and a gate that only
  -- looked at one of them is precisely how 0.9.3 shipped a REMATCHES switch
  -- that was dead for whole classes of trainer (a Gen 2 field test that never
  -- matched, see isTrainerNpc below).  Both are deliberately UNIONS, in the
  -- spirit of the trainer_rematch reference's own isTrainerDefeated: one odd
  -- defeat store must never be able to silently switch the feature off.
  --
  -- A trainer, by whichever field its generation fills in.  Gen 1 gives an
  -- object `trainerClass` (+ `trainerParty`, the party index); Gen 2 gives it
  -- the extracted `trainer` header struct (class / member / event / scriptKey).
  --
  -- NOTE the deliberate absence of any `scriptKey` test here.  On Gen 1 a
  -- `scriptKey` means "this object's A press is a hand-ported story scene"
  -- (the reason the Gen 1 gate still consults canRematch), but on Gen 2
  -- RomExtractorGen2 sets `obj.scriptKey` from the trainer struct's own
  -- after-battle script pointer, so it is set on essentially EVERY G/S/C
  -- trainer.  The 0.9.3 Gen 2 gate required `not def.scriptKey`, which meant
  -- `world:trainerBeaten(header)` was only ever reached for the handful of
  -- trainers whose struct names no after-script -- i.e. for almost nobody.
  function shared.isTrainerNpc(npc)
    local d = npc and npc.def
    if type(d) ~= "table" then return false end
    return d.trainerClass ~= nil or d.trainerParty ~= nil
        or type(d.trainer) == "table"
  end

  -- Already beaten, in whichever bookkeeping recorded it.
  --
  -- Gen 2 keeps it in the trainer struct's own EVENT_BEAT_* flag, which is
  -- what World:trainerBeaten reads and what makes the engine's own A-press
  -- branch skip a beaten trainer.  Both generations also expose the engine's
  -- own `trainerDefeated` method (Gen 1 reads save.defeatedTrainers[npc.id]
  -- and the header's event flag; Gen 2's facade backs the same name) --
  -- that is the method the engine's built-in beaten-trainer branch uses, so
  -- it is the one answer that is definitely right on both.  The explicit
  -- save/flags reads underneath are the second and third look, for the same
  -- reason the reference mod keeps them: a save that records the win in only
  -- one of the stores still gets asked.
  function shared.isBeatenTrainer(world, npc)
    local d = npc and npc.def
    if type(d) ~= "table" then return false end
    local record = type(d.trainer) == "table" and d.trainer or nil

    if record and type(world) == "table"
        and type(world.trainerBeaten) == "function" then
      local ok, beaten = pcall(world.trainerBeaten, world, record)
      if ok and beaten then return true end
    end

    if type(world) == "table" and type(world.trainerDefeated) == "function" then
      local ok, defeated = pcall(world.trainerDefeated, world, npc)
      if ok and defeated then return true end
    end

    local save = liveSave()
    if save and type(save.defeatedTrainers) == "table"
        and npc.id ~= nil and save.defeatedTrainers[npc.id] then
      return true
    end

    -- The header's event flag.  Gen 2 carries it on the struct; Gen 1's comes
    -- off the extracted trainer header for (map label, object index).
    local event = record and record.event or nil
    if event == nil then
      local data = liveData()
      local label = world and world.map and world.map.def and world.map.def.label
      if data and label and type(data.trainerHeader) == "function" then
        local ok, header = pcall(data.trainerHeader, data, label, d.index)
        event = ok and header and header.event or nil
      end
    end
    if event == nil then return false end
    if world and world.events and type(world.events.get) == "function" then
      local ok, set = pcall(world.events.get, world.events, event)
      if ok and set then return true end
    end
    if save and type(save.flags) == "table" and save.flags[event] then
      return true
    end
    return false
  end

  -- ------------------------------------------------------------ key items
  -- A KEY item is never randomised, respawned, or dropped -- the whole point
  -- of the setting.  Gen 1 marks them with the ROM's own key-item bit, which
  -- the extractor carries as `keyItem` (there are no badges in data.items on
  -- Gen 1, so the BADGE_* ids are screened by name too).  Gen 2 has no such
  -- flag at all: it keeps key items in their own pocket, so `pocket` is the
  -- test there.  Both tests run against both generations -- a record simply
  -- fails the one that does not apply to it.
  function shared.isKeyItemId(id, rec)
    if type(id) ~= "string" then return true end
    if id:find("BADGE", 1, true) then return true end
    if type(rec) ~= "table" then return true end
    if rec.keyItem == true then return true end
    if rec.pocket == "KEY_ITEM" then return true end
    return false
  end

  -- ----------------------------------------------------------- banned items
  -- Items the RANDOMIZER must never hand out -- an explicit user ban
  -- (2026-09-10), independent of the key-item test above: none of these is a
  -- key item in the engine's own table on either generation (the battle_forms
  -- stone / crystal / key-item registrations carry no `keyItem` flag), which
  -- is exactly why the pool used to be able to draw one.  Four rules cover
  -- the whole list the user named:
  --   * every HM -- the record's own `machine.kind == "HM"`, with the id
  --     spellings as a fallback ("HM_CUT" on Gen 1, "HM01"/"HM_01" elsewhere);
  --   * every Mega Stone -- every one the engine carries has "ITE" in its id
  --     (ABOMASITE, CHARIZARDITE_X, MEOWSTICITE_MALE, TATSUGIRIITE_CURLY,
  --     GARCHOMPITE_Z, ...), so a substring test covers every suffix variant;
  --     national_dex's own 530-item table has exactly two non-Mega items that
  --     also contain "ITE" -- EVIOLITE and WHITE_HERB -- and both are excluded;
  --   * every Z-Crystal -- an id ending in "_Z" (GRASSIUM_Z and the other
  --     seventeen type crystals; a Mega Stone's own "_Z" is caught above);
  --   * the four trainer key items by name -- KEY_STONE, DYNAMAX_BAND,
  --     Z_RING and TERA_ORB.
  -- A plain evolution stone (FIRE_STONE, OVAL_STONE, ...) is NOT a Mega Stone
  -- and stays in the pool.
  local BANNED_ITEM_IDS = {
    KEY_STONE = true, DYNAMAX_BAND = true, Z_RING = true, TERA_ORB = true,
  }
  function shared.isBannedItemId(id, rec)
    if type(id) ~= "string" then return false end
    local up = id:upper()
    if BANNED_ITEM_IDS[up] then return true end
    if type(rec) == "table" and type(rec.machine) == "table"
        and rec.machine.kind == "HM" then
      return true
    end
    if up:match("^HM_") or up:match("^HM%d") then return true end
    if up:match("ITE") and up ~= "EVIOLITE" and not up:match("^WHITE") then
      return true
    end
    if up:match("_Z$") then return true end
    return false
  end

  -- ------------------------------------------------- item id vs item index
  -- Gen 2 hands the two item-holding seams a NUMERIC operand, not a name.  An
  -- item ball's operand is the raw ROM byte (the extractor keeps the pair as
  -- { item = byte, quantity = byte }) and a hidden item's operand is the same
  -- single byte; the engine's own VM resolves both through the record's
  -- `index` field (World.lua's itemByIndex, wired in as getItemNameFn /
  -- giveItemFn).  Gen 1 hands the string id over directly and keys data.items
  -- by it.  Everything in this mod that reasons about WHICH item a spot holds
  -- -- the pool, the key-item test -- is name-based, so a numeric operand is
  -- resolved to its record's string id here, and the chosen replacement is
  -- resolved BACK to the same numeric index: the script list the engine runs
  -- must carry the numeric operand the vanilla call carried, or giveitem /
  -- getitemname resolve nothing and the pickup silently hands over garbage.
  --
  -- This was the whole reason the randomizer (and Gen 2 respawn) read as dead
  -- on Gold/Silver/Crystal: isKeyItemId screens a non-string id as a key item,
  -- so every numeric spot was left exactly as it was.
  local function itemIdForIndex(index)
    local data = liveData()
    local src = data and data.items
    if type(src) ~= "table" then return nil end
    for id, rec in pairs(src) do
      if type(rec) == "table" and rec.index == index then return id, rec end
    end
    return nil
  end

  local function itemIndexForId(id)
    local data = liveData()
    local rec = data and data.items and data.items[id]
    local index = type(rec) == "table" and rec.index
    if type(index) == "number" then return index end
    return nil
  end

  -- The key-item test for a caller that may hold either a name (Gen 1) or a
  -- raw ROM index (Gen 2).  An operand that resolves to no record at all is
  -- reported as key -- the same conservative default the randomizer already
  -- relied on for an unknown name.
  function shared.isKeyItem(id)
    if type(id) ~= "number" then
      local data = liveData()
      return shared.isKeyItemId(id, data and data.items and data.items[id])
    end
    local name, rec = itemIdForIndex(id)
    if not name then return true end
    return shared.isKeyItemId(name, rec)
  end

  -- ------------------------------------------------------- the item pool
  -- Every real, non-key, non-banned item the game knows about, as one cached
  -- list.  TMs stay IN the pool (the user asked for non-key items, and a TM is
  -- a legitimate pickup), but HMs, Mega Stones, Z-Crystals and the four
  -- battle key items are excluded -- explicit user ban, see isBannedItemId
  -- above.  Built once, then cached -- the item table does not change at
  -- runtime and a pickup should never walk ~250 records.
  local itemPool
  local function buildItemPool(data)
    if itemPool then return true end
    data = data or liveData()
    local src = data and data.items
    if type(src) ~= "table" then return false end
    local out = {}
    for id, rec in pairs(src) do
      if type(rec) == "table" and type(rec.name) == "string"
          and rec.name ~= "" and not shared.isKeyItemId(id, rec)
          and not shared.isBannedItemId(id, rec) then
        out[#out + 1] = id
      end
    end
    if #out == 0 then return false end
    table.sort(out)
    itemPool = out
    return true
  end

  -- One random pool id, trying not to hand back `exclude` (the item the spot
  -- really held) so a "randomised" pickup does not read as untouched.
  function shared.randomItemId(exclude)
    if not buildItemPool() then return nil end
    local n = #(itemPool or {})
    if n == 0 then return nil end
    if n == 1 then return itemPool[1] end
    local id
    for _ = 1, 8 do
      id = itemPool[love.math.random(1, n)]
      if id ~= exclude then return id end
    end
    return id
  end

  -- What a given spot should hand out: its real item when the setting is off,
  -- when the spot is a key item, or when there is no pool at all; a random
  -- non-key item otherwise.  Accepts EITHER a string id (Gen 1) or a numeric
  -- ROM index (Gen 2) and returns the same kind it was handed -- see the
  -- itemIdForIndex / itemIndexForId note above.
  function shared.randomizedItem(origId)
    if not itemRandomizerOn() then return origId end
    local numeric = type(origId) == "number"
    local id, rec
    if numeric then
      id, rec = itemIdForIndex(origId)
      if not id then return origId end
    else
      local data = liveData()
      id = origId
      rec = data and data.items and data.items[id]
    end
    if shared.isKeyItemId(id, rec) then return origId end
    for _ = 1, 8 do
      local pick = shared.randomItemId(id)
      if not pick then return origId end
      if not numeric then return pick end
      local index = itemIndexForId(pick)
      if index then return index end
    end
    return origId
  end

  -- ------------------------------------------------------- rematch store
  -- How many times each trainer has been beaten, in the mod's OWN namespace --
  -- mod.save, which is save.modData[g9-battle-sample] -- because that is the
  -- save model's one rule for mod state (namespaced, never mixed into engine
  -- tables) and it is the same bucket on both generations.  get hands back the
  -- live table and set stores that same table, so the tallies accumulate with
  -- one write per win and survive a save/reload.  The key is the same string
  -- on both generations (class/member for a Gen 2 map object's own header,
  -- class/party-index on Gen 1), which is what makes the +level ramp and the
  -- win tally line up whichever seam saw the fight.
  local function rematchStore(create)
    local store = mod.save:get("rebattles")
    if type(store) ~= "table" then
      if not create then return nil end
      store = {}
      mod.save:set("rebattles", store)
    end
    return store
  end

  function shared.rematchCount(key)
    if type(key) ~= "string" then return 0 end
    local store = rematchStore(false)
    local n = store and store[key]
    return type(n) == "number" and n or 0
  end

  function shared.noteTrainerWin(key)
    if type(key) ~= "string" then return end
    local store = rematchStore(true)
    if not store then return end
    store[key] = (type(store[key]) == "number" and store[key] or 0) + 1
  end

  -- The level bonus the UPCOMING fight against `key` should get: 0 for the
  -- first fight, one step for the second, two for the third, and so on.
  function shared.rematchBonus(key)
    local step = rematchStep()
    if step <= 0 then return 0 end
    return step * shared.rematchCount(key)
  end

  -- One key for a trainer record, whichever shape it arrives in: a Gen 2
  -- Trainers.lookup record (classId + id), the battle's own opts.trainer (the
  -- same two values as classId + memberId), or a bare map-object header
  -- (class + member).
  function shared.trainerKeyOf(trainer)
    if type(trainer) ~= "table" then return nil end
    local class = trainer.classId or trainer.class
    if class == nil then return nil end
    local member = trainer.memberId or trainer.id or trainer.member
      or trainer.index
    if member == nil then member = 1 end
    return tostring(class) .. "/" .. tostring(member)
  end

  -- Cumulative +level on a Gen 1 trainer's ROWS.  Gen 1's `trainer.party` hook
  -- is handed the party table straight out of game.data.trainers -- the SAME
  -- rows every later fight against that trainer is built from -- so the bonus
  -- goes onto freshly copied rows and never onto the originals.  Returns the
  -- SAME array when there is nothing to add, so a fight with the setting off
  -- keeps exact object identity for the engine's own builder.
  function shared.scaleGen1RematchLevels(classId, memberId, party)
    if type(party) ~= "table" or #party == 0 or rematchStep() <= 0 then
      return party
    end
    local key = tostring(classId) .. "/" .. tostring(memberId or 1)
    local bonus = shared.rematchBonus(key)
    if bonus <= 0 then return party end
    local out, changed = {}, false
    for i = 1, #party do
      local row = party[i]
      if type(row) == "table" and type(row.level) == "number" then
        local copy = {}
        for k, v in pairs(row) do copy[k] = v end
        copy.level = row.level + bonus
        out[i] = copy
        changed = true
      else
        out[i] = row
      end
    end
    if not changed then return party end
    return out
  end

  -- --------------------------------------------------------- respawn clock
  -- One interval's worth of accumulated overworld time.  `dt` is the world
  -- clock's own slice, and a fast-forward multiplier can make a single slice
  -- large, so an oversized slice is dropped instead of counted: the timer
  -- measures minutes of play, not one long frame.  Returns true on the frame an
  -- item should come back.
  local respawnElapsed = 0
  function shared.tickRespawn(dt)
    if not itemRespawnOn() then
      respawnElapsed = 0
      return false
    end
    if type(dt) ~= "number" or dt <= 0 or dt > 5 then dt = 0 end
    respawnElapsed = respawnElapsed + dt
    if respawnElapsed >= respawnInterval() then
      respawnElapsed = 0
      return true
    end
    return false
  end

  -- ------------------------------------------------------- trainer drops
  -- One pending item, handed to the bag on the next idle overworld frame so
  -- the box never lands on top of the battle-exit text.  A second win before
  -- the first has been shown simply replaces it (one drop per win is the
  -- promise, not a queue of them).
  local pendingDrop = nil
  function shared.queueTrainerDrop()
    if not trainerDropOn() then return end
    -- TRAINER ITEM CHANCE gates the payout: one roll per win, before any item
    -- is chosen, so a failed roll costs nothing and a passed one behaves
    -- exactly as it always did.  At 100% the comparison is skipped outright.
    local chance = trainerDropChance()
    if chance < 1 and love.math.random() >= chance then return end
    pendingDrop = shared.randomItemId(pendingDrop) or pendingDrop
  end
  function shared.takePendingDrop()
    local id = pendingDrop
    pendingDrop = nil
    return id
  end

  -- Add the pending drop to the bag.  Returns false (and leaves it pending)
  -- when there is nothing to add, the bag pocket is full, or the game is not
  -- far enough along to have an inventory yet -- a full pocket really does
  -- lose the item, exactly like a pickup's own bag-full branch.  `show` is
  -- the arm's own "found an item" box.
  function shared.flushTrainerDrop(show)
    if not pendingDrop then return false end
    local save = liveSave()
    local data = liveData()
    if not (save and type(save.inventory) == "table" and data) then
      return false
    end
    local id = pendingDrop
    local Bag = require("src.inventory.Bag")
    local ok, added = pcall(Bag.add, save, id, 1, data)
    if not (ok and added) then
      -- The bag itself refused it (pocket full, or the stack would pass 99).
      -- A real pickup loses the item on that branch and so does this one; the
      -- box is simply never shown.
      pendingDrop = nil
      return false
    end
    pendingDrop = nil
    if show then
      local rec = data.items and data.items[id]
      pcall(show, id, (rec and rec.name) or id)
    end
    return true
  end

  shared.pickSpecies = pickSpecies
  shared.buildPool = buildPool
  mod.log:info("g9_battle_sample: randomizer/difficulty systems installed "
    .. "(difficulty=%s, min team=%d, rand_wilds=%s, rand_trainers=%s)",
    difficulty(), minTeamSize(), tostring(randWildsOn()),
    tostring(randTrainersOn()))
  return shared
end

local function installGen2(mod, shared)
  local World = require("src.world.gen2.World")
  local Mon = require("src.battle.gen2.Mon")
  -- The Gen 1 name, answered by the Gen 2 facade: `ow.talkTo` is one of the
  -- four named seams World:interactBody deliberately dispatches through, and
  -- Gen2Compat.talkToWrapper hands it over only when it is no longer the
  -- facade's own default -- so assigning it here is exactly how a mod hooks
  -- the A-press dispatch on Gold/Silver/Crystal.
  local ow = require("src.world.OverworldController")
  -- The module World itself holds (same require cache), so replacing these two
  -- builders is what reaches every item ball and hidden item on the field.
  local HiddenItems = require("src.world.gen2.HiddenItems")
  local Strings = require("src.core.Strings")

  -- Eternatus-as-Eternamax -> g9-Battle-Scene's "bossFight" layout,
  -- explicit user request. This static placement (wild_forms's own
  -- data/legendaries.lua -- INDIGO_PLATEAU, level 75, form =
  -- "ETERNATUS_ETERNAMAX") is confirmed Gen-1-only (wild_forms/main.lua's
  -- own `if gen2 then [warn, no Gen 2 static placement] else
  -- legendaries.place(...) end` branch) and, more importantly for THIS
  -- trap, is triggered by an object_event -- an entirely different call
  -- path than the grass/water roll tryWildEncounter below intercepts, so
  -- the existing trap never sees it at all. A PERMANENT wrap here, not a
  -- scoped one, is what's needed to catch it too.
  --
  -- The object_event's own `pokemon` field is confirmed the BARE
  -- "ETERNATUS" id, never the form-suffixed one (data/legendaries.lua's
  -- own header: "never the form-suffixed id -- because a player never
  -- keeps Eternamax") -- wild_forms's own battle.started listener is what
  -- applies ETERNATUS_ETERNAMAX onto the live battler, AFTER
  -- World:startBattle constructs the real Battle.new (Runtime.emit
  -- "battle.started" fires unconditionally from inside that constructor,
  -- confirmed real and generation-agnostic) -- so this trap only ever
  -- needs to recognize the species+level signature at opts.wild, matching
  -- the placement's own data, and wild_forms's own form-swap keeps working
  -- completely unmodified regardless of which layout renders the fight.
  -- Every trainer battle -> g9-Battle-Scene's "doubles" layout, whenever
  -- the trainer actually has 2+ Pokemon -- explicit user request ("make
  -- all trainer battles be double battles if possible"). Same permanent-
  -- wrap reasoning as Eternatus above: a trainer battle is triggered by
  -- the script VM (dialogue/approach), never tryWildEncounter, so only a
  -- permanent World:startBattle wrap sees it. The REAL trainer table
  -- (opts.trainer -- class/name/baseMoney/party, the same shape
  -- World:startBattle itself always builds one from) is forwarded
  -- through unmodified so the payout/gym-leader-happiness/name all stay
  -- correct -- see buildBattle's own fix in g9-Battle-Scene/battle_screen
  -- .lua for why a plain boolean flag would have silently zeroed the
  -- payout.
  local function tryDoublesTrainer(self, opts)
    if not (opts and opts.trainer and type(opts.trainer.party) == "table"
        and #opts.trainer.party >= 1) then
      return false
    end
    -- Defer entirely to a trainer explicitly registered via
    -- g9-battle-engine's own mod.exports.registerTrainer -- that
    -- registration's own combatType (vanilla/doubles/triples) is the
    -- one real authority for what it wants, and this blanket "2+ mons ->
    -- doubles" heuristic has no way to know it might actually want
    -- "vanilla" (or triples). Real, confirmed conflict, 2026-08-28: this
    -- wrap installs AFTER (and therefore runs BEFORE, being the
    -- outermost) registerTrainer's own World:startBattle wrap, so
    -- without this check a registered trainer's own choice never gets a
    -- turn at all whenever it happens to have 2+ Pokemon.
    local dex = mod.find("g9-battle-engine")
    if dex and dex.exports and dex.exports.hasRegisteredTrainer
        and dex.exports.hasRegisteredTrainer(
          opts.trainer.classId or opts.trainer.class,
          opts.trainer.memberId or opts.trainer.id) then
      return false
    end
    local exportMod = shared.sceneHandle()
    local save = self.game and self.game.save
    if not (exportMod and exportMod.exports and exportMod.exports.pushLayoutBattle
        and save and save.party) then
      if not exportMod then
        shared.reportSceneProblem(self,
          "The battle scene is on but g9-Battle-Scene could not be reached (not "
          .. "installed, disabled, or failed to load), so this trainer battle "
          .. "used the native screen. Install/enable g9-Battle-Scene in the "
          .. "Mod Manager.",
          "The battle scene is on but\ng9-Battle-Scene is missing.\nEnable it in the Mod Manager.")
      end
      return false
    end
    -- Combat type, explicit user request (2026-09-12): the Elite Four roll
    -- doubles-or-triples per battle, the Champion and Red get the bossFight
    -- layout, and every other 2+-mon trainer is a doubles.  A layout preset
    -- the scene does not actually ship refuses below and falls back to the
    -- ordinary trainer battle, exactly as before.
    -- The scene renders payload.enemies, not battle.enemyParty, so the swap
    -- and the difficulty team floor both have to happen HERE (before the
    -- push) for a scene trainer battle; the swapped mons are tagged, so the
    -- trainer.party hook Battle.new calls moments later leaves them exactly
    -- as they are -- and the engine's own difficulty pass then lands on the
    -- very mons the screen is drawing.
    local classId = opts.trainer.classId or opts.trainer.class
    -- A gym leader / Elite Four keeps its own type theme through both the
    -- team floor and the species swap (see GYM_THEMES).
    local theme = shared.themeTypesFor(classId)
    opts.trainer.party = shared.randomizeParty(
      shared.padTrainerParty(opts.trainer.party, nil, theme), nil, theme)
    -- LEAGUE ACES: the scene renders payload.enemies, not battle.enemyParty,
    -- so the ace swap has to land HERE too (the native hook that already did
    -- it for this party is a different array).  Same last-N rule, so a party
    -- that already carries the aces is returned untouched.
    opts.trainer.party = shared.applyLeagueAces(opts.trainer.party, classId,
      opts.trainer.memberId or opts.trainer.id)
    -- The existing enemy battle's own shape picks the preset (see
    -- shared.layoutForTrainer's note): a boss is always "bossFight", a
    -- one-mon team takes the scene's "singles" screen -- never the game's
    -- native one, which is what the old `#enemies < 2` bail used to do (the
    -- first Gen 2 rival battle, RIVAL1's single stolen starter, was the case
    -- that surfaced it) -- an Elite Four battle rolls doubles-or-triples and
    -- every other 2+-mon team is a "doubles".
    -- [2v2/3v3/4v1] OFF forces the scene's own "singles" layout for every
    -- trainer fight; ON picks doubles/triples/bossFight from the existing
    -- enemy battle (shared.layoutForTrainer is the one implementation).
    local layoutName = shared.multiLayoutOn()
      and shared.layoutForTrainer(classId, #opts.trainer.party) or "singles"
    local layoutData = exportMod.exports.getLayoutData
      and exportMod.exports.getLayoutData(layoutName)
    if not layoutData then
      shared.reportSceneProblem(self,
        "The battle scene is on and g9-Battle-Scene is loaded, but it has no '"
        .. layoutName .. "' layout preset, so this trainer battle used the "
        .. "native screen. Update g9-Battle-Scene.",
        "The battle scene is on but the\nscene has no '" .. layoutName
        .. "' layout.\\nUpdate g9-Battle-Scene.")
      return false
    end
    local allyCount = math.max(1, math.min(6, layoutData.allyCount or 2))
    -- The FULL party is handed over, not a slice: the scene benches every
    -- mon past the preset's own enemyCount and sends one in as an active
    -- faints, so a whole team is fought two/three at a time instead of the
    -- rest being dropped.  (A wild fight is never benched -- no trainer.)
    local enemies = {}
    for i = 1, #opts.trainer.party do
      enemies[#enemies + 1] = opts.trainer.party[i]
    end
    if #enemies < 1 then return false end
    local players = shared.playerRoster(allyCount)
    local pushed = exportMod.exports.pushLayoutBattle(layoutName, self.game, self, {
      enemies = enemies,
      players = players,
      trainer = opts.trainer,
    })
    if not pushed then
      shared.reportSceneProblem(self,
        "The battle scene is on and g9-Battle-Scene is loaded, but its '"
        .. layoutName .. "' layout refused to push, so this trainer battle "
        .. "used the native screen.",
        "The battle scene is on but the\nscene refused this layout.\nIt used the native screen.")
      mod.log:warn("g9_battle_sample: no " .. layoutName .. " preset on "
        .. "the export mod, falling back to the ordinary trainer battle")
      return false
    end
    if shared.isBossClass(classId) then shared.applyBossFlags(pushed) end
    return true
  end

  local nativeStartBattle = World.startBattle
  function World:startBattle(opts, onDone)
    -- Cumulative +level per rematch (see installRandomizer's own note on the
    -- setting).  Applied HERE, once per fight: opts.trainer is already built
    -- by the caller (World:startScriptedBattle assembles it a few lines above
    -- its own call), Battle.new then builds self.enemyParty out of exactly
    -- opts.trainer.party, and Mon.refreshStats runs over that array right
    -- after the trainer.party hook -- so a level bump lands on the real
    -- battlers without a second stat pass here.  Done in the hook instead
    -- would run twice, because this same roster also travels through the
    -- scene's own model build.
    if opts and opts.trainer and type(opts.trainer.party) == "table" then
      local bonus = shared.rematchBonus(shared.trainerKeyOf(opts.trainer))
      if bonus > 0 then
        local data = self.game and self.game.data
        for _, mon in ipairs(opts.trainer.party) do
          if type(mon) == "table" and type(mon.level) == "number" then
            mon.level = mon.level + bonus
            pcall(Mon.refreshStats, mon, data)
          end
        end
      end
    end
    -- THE CUSTOM SCENE IS OFF (g9-Battle-Scene's own BACKGROUND row) -- every
    -- fight (wild, trainer, boss) goes to the native screen; the scene is
    -- never consulted.  Checked AFTER the rematch level bump above, which
    -- belongs to the REMATCHES option, not the scene layer -- so a rematch
    -- keeps its +level even with the scene off.  `onDone` is the plain slot
    -- World:startBattle already forwards.
    if not shared.sceneWanted() then
      return shared.withoutScene(function()
        return nativeStartBattle(self, opts, onDone)
      end)
    end
    if opts and opts.wild and opts.wild.species == "ETERNATUS"
        and opts.wild.level == 75
        and not opts.roaming and not opts.contest and not opts.tutorial then
      local exportMod = shared.sceneHandle()
      local save = self.game and self.game.save
      if exportMod and exportMod.exports and exportMod.exports.pushLayoutBattle
          and save and save.party then
        local layoutData = exportMod.exports.getLayoutData
          and exportMod.exports.getLayoutData("bossFight")
        local allyCount = math.max(1, math.min(6, (layoutData and layoutData.allyCount) or 4))
        local players = shared.playerRoster(allyCount)
        local pushed = exportMod.exports.pushLayoutBattle("bossFight", self.game, self, {
          enemies = { opts.wild },
          players = players,
        })
        if pushed then return true end
        mod.log:warn("g9_battle_sample: no bossFight preset on the export "
          .. "mod, falling back to the ordinary battle screen for Eternatus")
        shared.reportSceneProblem(self,
          "The battle scene is on and g9-Battle-Scene is loaded, but its "
          .. "'bossFight' layout refused to push, so the Eternatus fight used "
          .. "the native screen.",
          "The battle scene is on but the\nscene refused the bossFight\nlayout. It used native.")
      end
    elseif tryDoublesTrainer(self, opts) then
      return true
    end
    return nativeStartBattle(self, opts, onDone)
  end

  -- realStartBattle is THIS mod's own wrapped startBattle above, not the
  -- raw native one -- so the fallbacks below (g9-Battle-Scene missing, or
  -- a layout push failing) still round-trip through the Eternatus check
  -- and the trainer wrap above, exactly like any other startBattle call,
  -- rather than jumping straight to raw native.
  local realStartBattle = World.startBattle
  local originalTryWildEncounter = World.tryWildEncounter

  function World:tryWildEncounter()
    -- THE CUSTOM SCENE IS OFF (g9-Battle-Scene's BACKGROUND row) -- hand the
    -- wild roll straight to the native path.  The scoped startBattle swap
    -- below only exists to capture the roll for the scene; with the scene off
    -- there is nothing to capture, so the unmodified original is called
    -- directly and its own return value (whether an encounter actually
    -- triggered) passes straight through.
    if not shared.sceneWanted() then
      return originalTryWildEncounter(self)
    end
    local save = self.game and self.game.save
    -- The old guard bailed straight to the native encounter whenever the
    -- party had fewer than 2 mons (the multi-mon layouts want a second
    -- ally). 2026-09-11: the native scene must never be called for a wild
    -- encounter any more, so a small party no longer bails out -- it is
    -- still intercepted and routed to "singles" (which needs only one
    -- ally); `multiAlly` just gates the multi-mon bands in the roll below.
    local multiAlly = (save and save.party and #save.party >= 2) and true or false

    local capturedOpts = nil
    World.startBattle = function(selfInner, opts, onDone)
      if opts and opts.wild and not opts.roaming and not opts.contest and not opts.tutorial then
        capturedOpts = opts
        return true
      end
      return realStartBattle(selfInner, opts, onDone)
    end

    local ok, triggered = pcall(originalTryWildEncounter, self)
    World.startBattle = realStartBattle

    if not ok then
      mod.log:warn("g9_battle_sample: tryWildEncounter errored: %s", tostring(triggered))
      return false
    end
    if not (triggered and capturedOpts) then
      return triggered
    end

    -- mod.find, not a direct require -- the sanctioned way to reach
    -- another mod's own exports table (nil if that mod is absent,
    -- disabled, or hasn't run yet).
    local exportMod = shared.sceneHandle()
    if not (exportMod and exportMod.exports and exportMod.exports.pushLayoutBattle) then
      mod.log:warn("g9_battle_sample: g9-Battle-Scene not available, "
        .. "falling back to a single wild battle")
      shared.reportSceneProblem(self,
        "The battle scene is on but g9-Battle-Scene could not be reached (not "
        .. "installed, disabled, or failed to load), so this wild encounter "
        .. "used the native screen. Install/enable g9-Battle-Scene in the "
        .. "Mod Manager.",
        "The battle scene is on but\ng9-Battle-Scene is missing.\nEnable it in the Mod Manager.")
      realStartBattle(self, capturedOpts)
      return true
    end

    -- Layout odds (2026-08-28, superseding the earlier flat 25%-doubles
    -- rule). The special bands are unchanged -- 1% hordes, 2% triples,
    -- 10% doubles -- but the remaining 87% now routes to g9-Battle-
    -- Scene's own "singles" preset. Explicit user request (2026-09-11):
    -- the native/vanilla scene must NEVER be called for an ordinary wild
    -- encounter -- "singles" replaces the old native default band (which
    -- the 2026-08-28 pass had deliberately sent to real vanilla; this
    -- supersedes that). A single 1-100 roll against adjoining bands
    -- (1=hordes, 2-3=triples, 4-13=doubles, 14-100=singles) rather than
    -- separate independent rolls, so the special cases can never overlap
    -- or double-fire on the same encounter. "singles"/"hordes" (plural)
    -- are the real, already-existing preset names (layouts/singles.lua,
    -- layouts/hordes.lua) -- confirmed by direct directory read.
    -- `multiAlly` gates the multi-mon bands: a one-mon party can't fill
    -- a doubles/triples/horde row, so it always takes "singles".
    -- THE 0.5% WILD BOSSFIGHT (2026-09-12, explicit user request): its own
    -- 1-in-1000 roll, checked FIRST, so the four ordinary bands keep exactly
    -- the odds they had.  A boss wild scales its HP x1..x5 and gets a random
    -- boss-protection flag set after the scene is pushed.
    -- [2v2/3v3/4v1] OFF skips the whole roll -- every wild fight is singles.
    local layoutName, isBossWild
    if shared.multiLayoutOn() then
      layoutName, isBossWild = shared.rollWildLayout(multiAlly)
    else
      layoutName, isBossWild = "singles", false
    end

    -- Extra enemy slots.  A HORDE clones the one real roll's own
    -- species+level (the cart's own rule: "roll one species and set it to all
    -- 5 Pokemon").  A DOUBLES/TRIPLES wild fight instead draws each extra
    -- slot INDEPENDENTLY (explicit user request): its own species pick off the
    -- same roll, and its own level inside the area's natural spread -- so the
    -- slots can differ, though nothing forbids two of them landing on the same
    -- species.  The engine commits to exactly one real spawn roll, so an
    -- "independent roll" is a fresh randomized pick per slot, not a second
    -- spawn-table roll.  Any other layout (singles, the 0.5% bossFight) has a
    -- single enemy slot anyway.
    local independent = (layoutName == "doubles" or layoutName == "triples")
      and shared.randWildsOn()
    local layoutData = exportMod.exports.getLayoutData and exportMod.exports.getLayoutData(layoutName)
    local enemyCount = math.max(1, math.min(6, (layoutData and layoutData.enemyCount) or 1))
    local allyCount = math.max(1, math.min(6, (layoutData and layoutData.allyCount) or 2))

    local base = capturedOpts.wild
    local enemies = { base }
    for _ = 2, enemyCount do
      local species, level = base.species, base.level
      if independent then
        level = shared.wildSlotLevel() or base.level
        species = shared.wildSlotSpecies(base, level) or base.species
      end
      local mon = Mon.new(self.game.data, species, level)
      if mon then enemies[#enemies + 1] = mon end
    end
    -- x1..x5 max HP for the 0.5% boss wild, before the scene reads it.
    if isBossWild then shared.scaleWildHp(capturedOpts.wild) end

    local players = shared.playerRoster(allyCount)

    local pushed = exportMod.exports.pushLayoutBattle(layoutName, self.game, self, {
      enemies = enemies,
      players = players,
    })
    if not pushed then
      mod.log:warn("g9_battle_sample: no " .. layoutName .. " preset on the export mod, "
        .. "falling back to a single wild battle")
      shared.reportSceneProblem(self,
        "The battle scene is on and g9-Battle-Scene is loaded, but its '"
        .. layoutName .. "' layout refused to push, so this wild encounter "
        .. "used the native screen.",
        "The battle scene is on but the\nscene refused this layout.\nIt used the native screen.")
      realStartBattle(self, capturedOpts)
    elseif isBossWild then
      shared.applyBossFlags(pushed)
    end
    return true
  end

  ------------------------------------------------------------ item systems
  -- Item randomizer.  Both item scripts BAKE the item into the list they
  -- return (HiddenItems.ballPickupScript / .pickupScript) and
  -- World:interactBody is their only caller, so substituting the argument is
  -- the whole change: the item's name, the give, the jingle and the
  -- `disappear` / `setevent` row that retires the spot all keep working
  -- untouched.  A spot whose real item is a key item is handed back unchanged.
  local nativeBallPickupScript = HiddenItems.ballPickupScript
  HiddenItems.ballPickupScript = function(item, quantity, objectId, sfxId)
    return nativeBallPickupScript(shared.randomizedItem(item), quantity,
      objectId, sfxId)
  end
  local nativePickupScript = HiddenItems.pickupScript
  HiddenItems.pickupScript = function(item, event)
    return nativePickupScript(shared.randomizedItem(item), event)
  end

  -- ONE random already-taken, non-key item spot on the map the player is
  -- standing on.  An item ball comes back through the engine's own
  -- World:appearObject -- the literal port of Script_appear, which clears the
  -- flag, unmasks the object, drops the pooled NPC and rebuilds the people --
  -- so the ball lands exactly where it was; a hidden item only needs its flag
  -- cleared, because HiddenItems.at reads that flag and not a taken list.
  local function respawnOneItemGen2(world)
    local def = world.map and world.map.def
    if not (def and world.events) then return false end
    local candidates = {}
    for i, obj in ipairs(def.objects or {}) do
      local ball = obj.itemball
      if type(ball) == "table" and ball.item and obj.eventFlag
          and obj.eventFlag ~= 0xFFFF
          and world.events:get(obj.eventFlag)
          and not shared.isKeyItem(ball.item) then
        candidates[#candidates + 1] = { hidden = false,
          id = (obj.index or i) + 1 }
      end
    end
    for _, ev in ipairs(def.bgEvents or {}) do
      local info = HiddenItems.dataOf(ev)
      if info and info.event and world.events:get(info.event)
          and not shared.isKeyItem(info.item) then
        candidates[#candidates + 1] = { hidden = true, event = info.event }
      end
    end
    if #candidates == 0 then return false end
    local pick = candidates[love.math.random(1, #candidates)]
    if pick.hidden then
      world.events:set(pick.event, false)
      return true
    end
    world:appearObject(pick.id)
    return true
  end

  -------------------------------------------------------------- rematches
  -- TalkToTrainerScript with its two beaten-check rows (the `trainerflagaction
  -- CHECK_FLAG` and the `iftrue` that jumps to scripttalkafter) taken out and
  -- nothing else touched.  Its tail is kept because both of those rows are
  -- idempotent: SET_FLAG on an already-set flag is a silent no-op, and
  -- scripttalkafter is what a first-time fight shows too.
  local REMATCH_TALK_SCRIPT = {
    { op = "faceplayer" },
    { op = "loadtemptrainer" },
    { op = "encountermusic" },
    { op = "opentext" },
    { op = "trainertext", index = 0 },
    { op = "waitbutton" },
    { op = "closetext" },
    { op = "loadtemptrainer" },
    { op = "startbattle" },
    { op = "reloadmapafterbattle" },
    { op = "trainerflagaction", action = 1 },
    { op = "scripttalkafter" },
  }

  -- The native TalkToTrainerScript verbatim -- the script a plain A press
  -- runs.  Used as the answer to NO, so declining a rematch is
  -- indistinguishable from never having been asked: its CHECK_FLAG sees the
  -- beaten flag and jumps straight to scripttalkafter (the trainer's own
  -- after-battle line or script).  Copied rather than called because World's
  -- own local is not reachable from a mod.
  local TALK_TO_TRAINER_SCRIPT_COPY = {
    { op = "faceplayer" },
    { op = "trainerflagaction", action = 2 }, -- CHECK_FLAG
    { op = "iftrue", script = { { op = "scripttalkafter" } } },
    { op = "loadtemptrainer" },
    { op = "encountermusic" },
    { op = "opentext" },
    { op = "trainertext", index = 0 },
    { op = "waitbutton" },
    { op = "closetext" },
    { op = "loadtemptrainer" },
    { op = "startbattle" },
    { op = "reloadmapafterbattle" },
    { op = "trainerflagaction", action = 1 },
    { op = "scripttalkafter" },
  }

  -- A press on a beaten trainer ASKS before rematching (explicit user request,
  -- 2026-09-14): beating someone no longer means every later A press silently
  -- starts another fight.  interactBody seams the Gen 1 talkTo dispatch in
  -- through Gen1Facade.talkToWrapper once the object is resolved, and a `true`
  -- return suppresses the built-in path -- which for a beaten trainer is
  -- TALK_TO_TRAINER_SCRIPT, i.e. only its after-battle line.  Anything this
  -- wrap does not claim falls through to whatever held the seam before it (the
  -- facade's own default is a bare `return false`, so a mod-free press behaves
  -- exactly as it did).
  --
  -- The gate is shared.isTrainerNpc + shared.isBeatenTrainer -- NOT a
  -- `def.scriptKey` screening.  0.9.3 asked for `not def.scriptKey` here, in
  -- the belief that a scriptKey marks a story scene to leave alone (true on
  -- Gen 1).  On Gen 2 the extractor sets `def.scriptKey` from the trainer
  -- struct's own after-battle script pointer (RomExtractorGen2's
  -- readTrainerHeader -> "dw after-script"), so it is set on essentially every
  -- G/S/C trainer and the beaten test was never reached: REMATCHES was simply
  -- dead in Gold/Silver/Crystal.  Nothing is lost by asking -- both answers
  -- end in `scripttalkafter`, which tail-calls that same after-script, so a
  -- leader's badge or TM hand-over still runs either way.
  --
  -- The question goes up exactly the way the engine's own `yesorno` does:
  -- World:showText with `stay` leaves the box standing once it has typed, and
  -- World:askYesNo stacks the YES/NO prompt on THAT box (so the question is
  -- never re-printed under the prompt).  The NPC is frozen up front so a
  -- wanderer cannot roll a new facing under the prompt.
  -- ------------------------------------------------- G/S/C league leaders
  -- In Gold/Silver/Crystal a gym leader -- and EVERY Elite Four member -- is
  -- an OBJECTTYPE_SCRIPT object: its A press runs a map script that does its
  -- own `loadtrainer FALKNER, FALKNER1` and its own `setflag ENGINE_ZEPHYRBADGE`,
  -- NOT a `trainer` struct.  So def.trainer is nil, shared.isTrainerNpc is
  -- false, and the gate below never saw a single gym: REMATCHES worked on the
  -- ordinary trainer objects around them and only the leaders were silent.
  --
  -- The two facts the gate needs are both written in that object's own script
  -- (its scriptKey is the leader's talk script), so read them off it instead
  -- of keeping a hand-maintained map of sixteen gyms: the class/member the
  -- press will load, and the already-beaten test the script opens on (its
  -- `checkevent EVENT_BEAT_*`, or the `checkflag ENGINE_*BADGE` Blue and Clair
  -- use).  A script with no loadtrainer, or whose loaded class is not in
  -- GYM_CLASSES (a rival, a Rocket, the Champion), is left alone entirely.
  local function gen2LeagueScript(world, npc)
    local d = npc and npc.def
    if type(d) ~= "table" or d.scriptKey == nil then return nil end
    -- A trainer OBJECT already carries def.trainer; the ordinary gate owns it.
    if type(d.trainer) == "table" then return nil end
    local scripts = world and world.scripts
    local list = type(scripts) == "table" and scripts[d.scriptKey] or nil
    if type(list) ~= "table" then return nil end
    local class, member, check, intro, win, loss
    for _, cmd in ipairs(list) do
      if type(cmd) == "table" then
        if cmd.op == "loadtrainer" and cmd.class ~= nil then
          class, member = cmd.class, cmd.member
          break
        end
        if check == nil and (cmd.op == "checkevent" or cmd.op == "checkflag") then
          check = cmd
        end
        if cmd.op == "winlosstext" then win, loss = cmd.winText, cmd.lossText end
        if cmd.op == "writetext" or cmd.op == "farwritetext" then
          intro = cmd.text
        end
      end
    end
    if class == nil or check == nil then return nil end
    local classId = shared.gen2ClassName(class)
    if not shared.isGymClass(classId) then return nil end
    return { class = class, member = member or 1, classId = classId,
             check = check, intro = intro, winText = win, lossText = loss }
  end

  -- Already beaten, by the leader's OWN test: the `checkevent EVENT_BEAT_*`
  -- its FightDone branch hangs on, or the `checkflag ENGINE_*BADGE` that opens
  -- Blue's and Clair's scripts.  Both read through the same stores the scripts
  -- themselves read, so a badge handed over by any route counts.
  local function gen2LeagueBeaten(world, league)
    local check = league.check
    if check.op == "checkevent" then
      if world.events and type(world.events.get) == "function" then
        local ok, set = pcall(world.events.get, world.events, check.event)
        if ok and set then return true end
      end
      local save = shared.liveSave and shared.liveSave() or nil
      return type(save) == "table" and type(save.events) == "table"
        and save.events[check.event] == true
    elseif check.op == "checkflag" then
      if type(world.engineFlag) == "function" then
        local ok, set = pcall(world.engineFlag, world, check.flag)
        if ok and set then return true end
      end
      local save = shared.liveSave and shared.liveSave() or nil
      return type(save) == "table" and type(save.engineFlags) == "table"
        and save.engineFlags[check.flag] == true
    end
    return false
  end

  -- What YES starts: the leader's own intro line, win/loss text and
  -- `loadtrainer` with the class/member its script would have loaded -- and
  -- NOTHING after `reloadmapafterbattle`.  The badge/TM rows the native script
  -- runs on a win are deliberately absent, so a rematch can never hand out a
  -- badge or a second TM; the level ramp and the gym type theme ride the
  -- ordinary trainer.party hook and startBattle wrap, exactly as for any other
  -- rematch.
  local function gen2LeagueRematchScript(league)
    local script = { { op = "faceplayer" } }
    if league.intro then
      script[#script + 1] = { op = "opentext" }
      script[#script + 1] = { op = "writetext", text = league.intro }
      script[#script + 1] = { op = "waitbutton" }
      script[#script + 1] = { op = "closetext" }
    end
    if league.winText then
      script[#script + 1] = { op = "winlosstext",
        winText = league.winText, lossText = league.lossText }
    end
    script[#script + 1] = { op = "loadtrainer", class = league.class,
                            member = league.member }
    script[#script + 1] = { op = "startbattle" }
    script[#script + 1] = { op = "reloadmapafterbattle" }
    script[#script + 1] = { op = "end" }
    return script
  end

  local nativeTalkTo = ow.talkTo
  ow.talkTo = function(world, npc)
    if shared.rematchesOn() and shared.isTrainerNpc(npc)
        and shared.isBeatenTrainer(world, npc)
        and (not shared.isGymClass(shared.trainerClassOf(npc))
             or shared.gymRematchesOn()) then
      world:freezeNpc(npc)
      world:showText("Do you want to battle again?", function()
        world:askYesNo(function(yes)
          if yes then
            world:startTrainerScript(npc, REMATCH_TALK_SCRIPT, nil)
          else
            world:startTrainerScript(npc, TALK_TO_TRAINER_SCRIPT_COPY, nil)
          end
        end)
      end, true)
      return true
    end
    -- GYM LEADERS / ELITE FOUR on Gen 2 (see gen2LeagueScript).  The ask and
    -- the two answers are the same shape as the ordinary arm above: YES starts
    -- the rematch, NO runs the leader's own script untouched -- its beaten
    -- check sends it straight to the FightDone advice/TM line, exactly as if
    -- the question had never been asked.
    local league
    if shared.rematchesOn() and shared.gymRematchesOn() then
      league = gen2LeagueScript(world, npc)
    end
    if league and gen2LeagueBeaten(world, league) then
      world:freezeNpc(npc)
      world:showText("Do you want to battle again?", function()
        world:askYesNo(function(yes)
          if yes then
            world:startTrainerScript(npc, gen2LeagueRematchScript(league), nil)
          else
            world:startTrainerScript(npc, npc.def.scriptKey, nil)
          end
        end)
      end, true)
      return true
    end
    if type(nativeTalkTo) == "function" then
      return nativeTalkTo(world, npc)
    end
    return false
  end

  -- Win detection.  THREE emitters raise battle.ended -- the native model
  -- (Battle:endBattle), the native UI screen (completeBattle) and
  -- g9-Battle-Scene -- and a native fight raises it TWICE (model, then UI),
  -- so the underlying Battle is what gets deduped: the UI payload's `battle`
  -- is the SCREEN, whose own `.battle` is the model, while the model has no
  -- such field of its own.
  local lastEndedBattle = nil
  mod.events:on("battle.ended", function(ev)
    if type(ev) ~= "table" or ev.result ~= "win" then return end
    local payload = ev.battle
    if type(payload) ~= "table" then return end
    local inner = payload.battle
    if type(inner) == "table" and type(inner.enemyParty) == "table" then
      payload = inner
    end
    if payload == lastEndedBattle then return end
    local trainer = payload.trainer
    -- Only a REAL trainer.  A multi-enemy WILD fight drawn by g9-Battle-Scene
    -- is handed a synthetic {class = "TRAINER", name = "", baseMoney = 0}
    -- table (battle_screen.lua's own buildBattle), which carries neither a
    -- classId nor a member id -- so that is the test.
    if type(trainer) ~= "table" or trainer.classId == nil
        or trainer.memberId == nil then
      return
    end
    lastEndedBattle = payload
    local key = shared.trainerKeyOf(trainer)
    if key and shared.rematchTracking() then shared.noteTrainerWin(key) end
    shared.queueTrainerDrop()
  end)

  -- The overworld's own per-frame seam: World:step's tail calls
  -- Gen1Facade.worldTick -> ow.update(world, 1/60).  The previous value is
  -- chained, and everything below is gated on the world being IDLE --
  -- world:busy() covers the VM, a text box, a menu, the map-setup chain and
  -- the fishing / field-move / fly tails, so an item can never come back and a
  -- drop box can never land on top of a script.
  local nativeOwUpdate = ow.update
  ow.update = function(world, dt)
    if type(nativeOwUpdate) == "function" then nativeOwUpdate(world, dt) end
    if not (world.player and world.map) then return end
    if world:busy() then return end
    -- The scene is on (BACKGROUND not OFF) but unreachable: the one-off notice queued at
    -- the fallback shows here, on the first idle frame after it (see
    -- shared.reportSceneProblem).
    shared.flushSceneProblem(world)
    if shared.tickRespawn(dt) then
      local ok, err = pcall(respawnOneItemGen2, world)
      if not ok then
        mod.log:warn("g9_battle_sample: item respawn failed: %s", tostring(err))
      end
    end
    shared.flushTrainerDrop(function(_, name)
      local save = world.game and world.game.save
      local who = (save and save.player and save.player.name) or "You"
      pcall(world.playSfxNamed, world, "Sfx_Item", 1)
      world:showText(Strings("%s found\n%s!", who, name))
    end)
  end

  mod.log:info("g9_battle_sample: with the scene on (g9-Battle-Scene's "
    .. "BACKGROUND not OFF) and the 2v2/3v3/4v1 row on (the default), every "
    .. "wild encounter routes to "
    .. "g9-Battle-Scene -- 0.5%% \"bossFight\" (x1..x5 HP + random flags), then "
    .. "1%% \"hordes\", 2%% \"triples\", 10%% \"doubles\", ~86%% \"singles\" (the "
    .. "native scene is never called); every 2+-mon trainer battle routes to "
    .. "\"doubles\", the Elite Four rolls doubles/triples, and the Champion and "
    .. "Red route to \"bossFight\"; wild_forms's Eternatus-as-Eternamax static "
    .. "routes to \"bossFight\" (with BACKGROUND OFF every fight uses the "
    .. "native screen, and with 2v2/3v3/4v1 OFF every fight takes \"singles\")")
  return shared
end


-- =====================================================================
-- GENERATION 1 -- Red / Blue / Yellow.
--
-- The arm above wraps World:startBattle / World:tryWildEncounter.  Neither
-- method exists on Gen 1's overworld: there is no model/view split, so there
-- is no `startBattle` factory to intercept.  Gen 1 has ONE funnel every
-- battle passes through instead -- OverworldState:pushBattle(battle,
-- trainerNpc) in src/world/OverworldController.lua -- and that function is
-- little more than "play the battle theme, run the wipes, push the battle
-- screen".  So this arm wraps THAT: it decides whether the fight should
-- render through g9-Battle-Scene, and if so does the theme + the wipe itself
-- and pushes the scene screen instead of the native battle.
--
-- THE ROSTER COMES OFF THE REAL BATTLE.  BattleState.newWild / newTrainer
-- have already run by the time pushBattle is called, so the wild roll is
-- battle.enemy.mon (the real mon the roll committed to, dex-flagged by the
-- constructor) and a trainer's team is battle.enemyParty (the real mons,
-- built with the trainer's own DVs and special-move overrides).  The scene's
-- Gen 1 backend builds its own battlers from exactly those mon tables, so
-- every one of those properties carries over unmodified.  The layout bands,
-- the Eternatus signature and the 2+-mon trainer rule are the same ones the
-- Gen 2 arm uses.
--
-- THE ONE CONTRACT THAT MUST BE HONOURED: battle.onFinish.  On Gen 1 every
-- caller installs it (a wild step installs afterBattle; a sight trainer
-- installs the defeated-flag / victory-reward / afterBattle / onDone closure;
-- a static object_event installs the flag that retires the NPC and unfreezes
-- the player).  Native runs it when the battle screen finishes.  This scene
-- is a different screen on a different battle object, so it never would --
-- finishing a fight without it would leave the player frozen and a beaten
-- trainer un-beaten.  The captured onFinish is therefore run by hand once the
-- scene has popped, together with the rest of what native's BattleState:finish
-- would have done for a battle this scene replaced: Music.restoreMap, the
-- battle's own exit teardown, end-of-battle evolutions, and the
-- Transition.battleReturn fade.  Prize money is NOT among them: the native
-- screen's own win sequence is what normally pays it, and since the scene now
-- stands in for that screen, the scene pays it (Screen:awardTrainerPrize,
-- both generations) before this exit sequence runs.
--
-- battle.started is emitted here as well.  Gen 1's BattleState:enter emits it
-- from the screen this mod replaces, and the scene's own Gen 1 model is built
-- without it, so peers on Gen 1 would never hear it for a scene fight:
-- wild_forms applies a legendary placement's form to ev.battle.enemy on that
-- event (and Eternatus-as-Eternamax is EXACTLY this mod's bossFight case), and
-- battle_forms adopts the battle for its gimmick menu there.  The battle
-- object handed over is the scene's own model -- its .enemy is a real
-- BattleState.makeBattler wrapper, which is what wild_forms' becomeForm
-- mutates, so the form lands on the battler this fight actually resolves
-- through.
--
-- Deliberately still native on Gen 1: safari (its own BALL/BAIT/ROCK/RUN
-- menu), the Pokemon Tower's Silph-Scope ghost, the old-man demo, link
-- battles, and a battle with nothing healthy to send out (native blacks the
-- player out for that).  Deliberately simplified, in this file's own Gen 2
-- spirit: a trainer's roster is cut to the layout's enemyCount, exactly as
-- the Gen 2 arm cuts it, and every extra wild enemy slot clones the one real
-- roll's own species/level.
-- =====================================================================
local function installGen1(mod, shared)
  local Game = require("src.core.Game")
  local OverworldState = require("src.world.OverworldController")
  local BattleState = require("src.battle.BattleState")
  local Pokemon = require("src.pokemon.Pokemon")
  local Party = require("src.pokemon.Party")
  local Evolution = require("src.pokemon.Evolution")
  local Music = require("src.core.Music")
  local Runtime = require("src.mods.Runtime")
  local BattleTransition = require("src.render.BattleTransition")
  local Transition = require("src.render.Transition")
  local TextBox = require("src.render.TextBox")
  local Strings = require("src.core.Strings")

  -- The wipe's own context, captured at divert time.  The scene calls
  -- world:pushBattleTransition(nil, opts, fn) with no battle object in hand,
  -- so the two things the Gen 1 wipe needs off one (whether a trainer NPC
  -- should keep drawing through the wipe, and whether the enemy out-levels
  -- the lead by 3+) are read off the native battle here and handed to the
  -- shim below.
  local pendingTransition = nil

  -- Native's own lead: the first party mon still standing (BattleState's
  -- newWild/newTrainer both send Party.firstHealthy as the lead).
  local function leadMon()
    for _, mon in ipairs((Game.save and Game.save.party) or {}) do
      if (mon.hp or 0) > 0 then return mon end
    end
    return nil
  end

  -- The player roster: the first `count` LIVING party mons in party order.
  -- The scene draws whatever it is handed, so forwarding a fainted lead would
  -- put a 0-HP mon on the field with no switch prompt -- walking the whole
  -- party (rather than slicing 1..count) keeps the lead correct when
  -- party[1] is fainted.  Delegates to shared.playerRoster (2026-09-12) so
  -- both arms share one implementation of this rule.
  local function playerRoster(count)
    return shared.playerRoster(count)
  end

  local function layoutDataFor(exportMod, name)
    return exportMod.exports.getLayoutData
      and exportMod.exports.getLayoutData(name)
  end

  -- One of the layout preset's own roster fields (enemyCount/allyCount), with
  -- the same bounds the Gen 2 arm applies: at least 1, at most 6.
  local function rosterSize(exportMod, name, field, fallback)
    local data = layoutDataFor(exportMod, name)
    return math.max(1, math.min(6, (data and data[field]) or fallback))
  end

  -- Everything native's BattleState:finish would have done for the battle
  -- this scene replaced, in native's own order.  Called from the scene's own
  -- exit -- i.e. AFTER the screen has left the stack (StateStack:pop removes
  -- the state and only then calls exit) -- which is exactly when native pops
  -- the battle and calls onFinish, so anything this pushes (a blackout warp,
  -- a resumed script, a reward box) lands above the overworld rather than
  -- under a screen that is about to come down.
  local function finishGen1Battle(screen, battle, nativeOnFinish, leveledUp)
    local save = Game.save
    local outcome = (screen and screen.outcome) or "run"

    -- Native's own invariant (BattleState:finish): a battle can never hand the
    -- overworld a party with nothing healthy in it -- except the Oak's Lab
    -- starter rival, whose script heals immediately.  Anything else reads as
    -- a loss rather than stranding the player at 0 HP with no way back.
    if outcome ~= "lose" and not BattleState.isOaksLabStarterRival(battle)
        and not Party.firstHealthy(save.party) then
      outcome = "lose"
    end
    battle.result = outcome

    -- Prize money moved to the scene itself.  Native pays it out of its own
    -- win sequence (BattleState's MoneyForWinning arm -- baseMoney x the
    -- enemy's level), and a battle drawn through g9-Battle-Scene replaces that
    -- screen -- so the SCENE now pays it, for both generations, out of
    -- Screen:awardTrainerPrize (see g9-Battle-Scene/native.lua's
    -- N.awardTrainerPrize).  Paying it here as well would hand the player the
    -- prize twice on Gen 1.

    -- The native battle's own exit teardown.  StateStack:pop runs this for a
    -- battle that was pushed; this one never was, so it is run by hand.
    pcall(BattleState.exit, battle)
    Music.restoreMap(Game.data)

    local function handOff()
      if nativeOnFinish then nativeOnFinish(outcome) end
    end

    -- End-of-battle evolutions: native's own step (BattleState:finish calls
    -- Evolution.checkParty before it hands the map back).  Ended here for the
    -- same reason as everything else above -- the scene's Gen 1 model levels
    -- mons through Experience.apply but never runs this check.  `leveledUp`
    -- is this fight's own set of party mons that gained a level.
    local function evolveThenHandOff()
      if next(leveledUp) == nil then return handOff() end
      local ok, err = pcall(Evolution.checkParty, Game, handOff, leveledUp)
      if not ok then
        mod.log:warn("g9_battle_sample: post-battle evolution check "
          .. "failed: %s", tostring(err))
        handOff()
      end
    end

    -- The fade back to the map is the same Transition.battleReturn native
    -- pushes on the way out of a win/run/catch -- except on a plain loss,
    -- whose blackout warps with its own transition (the Oak's Lab starter
    -- rival is the exception that does use the fade).
    if outcome == "lose" and not BattleState.isOaksLabStarterRival(battle) then
      evolveThenHandOff()
      return
    end
    Game.stack:push(Transition.battleReturn(Game, evolveThenHandOff))
  end

  -- Decide whether this battle renders through g9-Battle-Scene, and if so take
  -- it over completely.  Returns true when it has (the caller must then NOT
  -- call the native pushBattle), false to let native handle it.
  local function tryDivert(self, battle, trainerNpc)
    pendingTransition = nil
    -- THE CUSTOM SCENE IS OFF (g9-Battle-Scene's BACKGROUND row) -- let the
    -- native pushBattle run for every battle (returning false is exactly the
    -- "let native handle it" contract this seam documents).  The native scene
    -- is generation-correct by itself: Gen 1's own
    -- OverworldState:pushBattle on Red/Blue/Yellow.
    if not shared.sceneWanted() then return false end
    local exportMod = shared.sceneHandle()
    if not (exportMod and exportMod.exports
        and exportMod.exports.pushLayoutBattle) then
      mod.log:warn("g9_battle_sample: g9-Battle-Scene not available, "
        .. "falling back to the ordinary Gen 1 battle screen")
      shared.reportSceneProblem(self,
        "The battle scene is on but g9-Battle-Scene could not be reached (not "
        .. "installed, disabled, or failed to load), so this battle used the "
        .. "native screen. Install/enable g9-Battle-Scene in the Mod Manager.",
        "The battle scene is on but\ng9-Battle-Scene is missing.\nEnable it in the Mod Manager.")
      return false
    end
    local save = Game.save
    if not (save and save.party) then return false end
    -- Never replace a battle the scene cannot honestly stand in for.  Safari
    -- runs its own BALL/BAIT/ROCK/RUN menu, the tower's ghost has its own
    -- rules, the old-man demo and link battles are not ordinary fights, and a
    -- battle with nothing healthy to send out is the native blackout.
    if battle.dead or battle.safari or battle.demo or battle.ghost
        or battle.kind == "link" then
      return false
    end
    local isTrainer = battle.kind == "trainer"
    if not (isTrainer or battle.kind == "wild") then return false end

    local layoutName, enemies, payloadTrainer, isBossWild

    if isTrainer then
      local team = battle.enemyParty
      if type(team) ~= "table" then return false end
      -- Difficulty team floor (see installRandomizer's own note).  The hook
      -- may already have padded the rows this party was built from; padding
      -- again here is a no-op when it did.  The padded array replaces the
      -- battle's enemyParty in place, so both the model and the scene's own
      -- Gen 1 battlers -- built from exactly these mon tables -- see the
      -- additions.
      local padded = shared.padTrainerParty(team, nil,
        shared.themeTypesFor(battle.oppClass))
      if padded ~= team then
        battle.enemyParty = padded
        team = padded
      end
      -- LEAGUE ACES: on Gen 1 the party the hook returned was plain rows, and
      -- the engine has since built real Pokemon from them -- so the held
      -- item / Tera / Dynamax fields are applied to the LAST N mons here.
      -- Idempotent, and the native screen applies the same fields from its
      -- own battle.started listener, so the two paths agree.
      shared.applyLeagueAceProperties(team, battle.oppClass, battle.partyIndex)
      -- Defer entirely to a trainer explicitly registered through
      -- g9-battle-engine's own mod.exports.registerTrainer -- that
      -- registration's own combatType is the one real authority for what it
      -- wants (see the Gen 2 arm's own tryDoublesTrainer for the full
      -- account of the conflict this avoids).
      local dex = mod.find("g9-battle-engine")
      if dex and dex.exports and dex.exports.hasRegisteredTrainer
          and dex.exports.hasRegisteredTrainer(battle.oppClass,
            battle.partyIndex) then
        return false
      end
      -- Combat type, matching the Gen 2 arm exactly (shared.layoutForTrainer
      -- is the one implementation): the Elite Four roll doubles-or-triples,
      -- the Champion (OPP_RIVAL3 on Gen 1) takes the bossFight layout, every
      -- other 2+-mon team is a doubles and a ONE-mon team takes the scene's
      -- own "singles" screen -- never the game's native one.  (The old
      -- `#team < 2` bail that sent a single-mon trainer fight to native is
      -- gone, so Gen 1 now matches Gen 2's RIVAL1 handling.)
      layoutName = shared.multiLayoutOn()
        and shared.layoutForTrainer(battle.oppClass, #team) or "singles"
      -- The FULL team, not a slice -- the scene benches the extra mons for
      -- a trainer battle and sends them in as actives faint (see the Gen 2
      -- arm's own note).
      enemies = {}
      for i = 1, #team do
        enemies[#enemies + 1] = team[i]
      end
      if #enemies < 1 then return false end
      -- The real trainer table (name/class/baseMoney/party), forwarded so the
      -- narration and the client's own trainer-battle flag stay correct on
      -- Gen 1 exactly as they do on Gen 2.
      payloadTrainer = battle.trainer or true
    else
      local enemy = battle.enemy and battle.enemy.mon
      if not enemy then return false end
      -- wild_forms's Eternatus-as-Eternamax static (INDIGO_PLATEAU, level 75)
      -- -> the scene's own "bossFight" layout, matched on the same
      -- species+level signature the Gen 2 arm uses.  Note this is a WILD
      -- battle on Gen 1 (an object_event's pokemon/level args), so it arrives
      -- through the same pushBattle funnel as a grass step.
      if enemy.species == "ETERNATUS" and enemy.level == 75 then
        layoutName = "bossFight"
        enemies = { enemy }
      else
        -- Layout odds, identical to the Gen 2 arm: one 1-100 roll against
        -- adjoining bands (1=hordes, 2-3=triples, 4-13=doubles, 14-100=
        -- singles), with `multiAlly` gating the multi-mon bands so a one-mon
        -- party always takes "singles".
        local multiAlly = #save.party >= 2
        -- 0.5% bossFight first, then the ordinary bands -- identical to the
        -- Gen 2 arm (shared.rollWildLayout is the one implementation).
        -- [2v2/3v3/4v1] OFF forces singles for every wild fight.
        if shared.multiLayoutOn() then
          layoutName, isBossWild = shared.rollWildLayout(multiAlly)
        else
          layoutName, isBossWild = "singles", false
        end
        -- Extra enemy slots, matching the Gen 2 arm exactly: a HORDE clones
        -- the one real roll (same species+level for all), while a
        -- DOUBLES/TRIPLES wild fight draws each slot independently -- its own
        -- randomized species and its own level inside the area's natural
        -- spread (explicit user request).  The engine commits to exactly one
        -- real spawn roll, so this is a fresh pick per slot, not a second
        -- spawn-table roll.
        local independent = (layoutName == "doubles" or layoutName == "triples")
          and shared.randWildsOn()
        local enemyCount = rosterSize(exportMod, layoutName, "enemyCount", 1)
        enemies = { enemy }
        for _ = 2, enemyCount do
          local species, level = enemy.species, enemy.level
          if independent then
            level = shared.wildSlotLevel() or enemy.level
            species = shared.wildSlotSpecies(enemy, level) or enemy.species
          end
          enemies[#enemies + 1] = Pokemon.new(Game.data, species, level)
        end
        -- x1..x5 max HP for the 0.5% boss wild, before the scene reads it.
        if isBossWild then shared.scaleWildHp(enemy) end
      end
    end

    -- pushLayoutBattle refuses a name with no real preset file.  Refusing here
    -- first keeps the battle theme and the wipe from playing for a fight that
    -- is about to fall back to native anyway.
    if not layoutDataFor(exportMod, layoutName) then
      mod.log:warn("g9_battle_sample: no " .. layoutName .. " preset on "
        .. "the export mod, falling back to the ordinary Gen 1 battle screen")
      shared.reportSceneProblem(self,
        "The battle scene is on and g9-Battle-Scene is loaded, but it has no '"
        .. layoutName .. "' layout preset, so this Gen 1 battle used the "
        .. "native screen. Update g9-Battle-Scene.",
        "The battle scene is on but the\nscene has no '" .. layoutName
        .. "' layout.\nUpdate g9-Battle-Scene.")
      return false
    end
    local players = playerRoster(rosterSize(exportMod, layoutName,
      "allyCount", 2))
    if #players == 0 then return false end

    -- The three things native pushBattle does.  The battle theme starts ahead
    -- of the wipe (audio/play_battle_music.asm runs before the transition,
    -- which is why the theme is already going while the wipe is still
    -- spinning), the wipe runs through the scene's own pushBattleTransition
    -- seam, and the scene screen replaces the battle push.
    local lead = leadMon()
    local enemyLevel = (battle.enemy and battle.enemy.mon
      and battle.enemy.mon.level) or 0
    pendingTransition = {
      npc = trainerNpc,
      stronger = lead ~= nil and enemyLevel >= lead.level + 3,
    }
    if battle.playBattleTheme then battle:playBattleTheme() end

    local screen = exportMod.exports.pushLayoutBattle(layoutName, Game, self, {
      enemies = enemies,
      players = players,
      trainer = payloadTrainer,
    })
    if not screen then
      pendingTransition = nil
      mod.log:warn("g9_battle_sample: " .. layoutName .. " refused to "
        .. "push, falling back to the ordinary Gen 1 battle screen")
      shared.reportSceneProblem(self,
        "The battle scene is on and g9-Battle-Scene is loaded, but its '"
        .. layoutName .. "' layout refused to push, so this Gen 1 battle used "
        .. "the native screen.",
        "The battle scene is on but the\nscene refused this layout.\nIt used the native screen.")
      return false
    end
    -- Random boss protections: the 0.5% wild bossFight, and a Champion/Red
    -- trainer routed to the bossFight layout.
    if isBossWild or (isTrainer and shared.isBossClass(battle.oppClass)) then
      shared.applyBossFlags(screen)
    end

    -- battle.started -- see this section's own header for why Gen 1 needs it
    -- emitted here and why the scene's model is the right battle object to
    -- hand over.
    local model = screen.battle
    local okEmit, errEmit = pcall(function()
      Runtime.emit("battle.started", {
        battle = model,
        kind = battle.kind,
        trainerId = battle.trainer and battle.trainer.id,
        species = battle.enemy and battle.enemy.mon
          and battle.enemy.mon.species,
        level = battle.enemy and battle.enemy.mon
          and battle.enemy.mon.level,
      })
    end)
    if not okEmit then
      mod.log:warn("g9_battle_sample: a battle.started listener raised: "
        .. "%s", tostring(errEmit))
    end

    -- Which party mons gained a level this fight, for the evolution check in
    -- finishGen1Battle.  The scene awards EXP by calling the model's own
    -- awardExperience (which runs Experience.apply over the same party the
    -- native screen would), so the levels are read either side of that call.
    local leveledUp = {}
    if model and type(model.awardExperience) == "function" then
      local nativeAward = model.awardExperience
      model.awardExperience = function(battleModel, loser)
        local party = (Game.save and Game.save.party) or {}
        local before = {}
        for _, mon in ipairs(party) do before[mon] = mon.level end
        local result = nativeAward(battleModel, loser)
        for _, mon in ipairs((Game.save and Game.save.party) or {}) do
          if before[mon] and mon.level and mon.level > before[mon] then
            leveledUp[mon] = true
          end
        end
        return result
      end
    end

    -- Wrap the scene's own exit so native's post-battle contract runs after
    -- the screen has left the stack.  An own field on the instance shadows the
    -- Screen metatable's method, which is what StateStack:pop reads.
    local nativeOnFinish = battle.onFinish
    local origExit = screen.exit
    local finished = false
    screen.exit = function(inst, ...)
      if origExit then origExit(inst, ...) end
      if finished then return end
      finished = true
      local ok, err = pcall(finishGen1Battle, screen, battle, nativeOnFinish,
        leveledUp)
      if not ok then
        mod.log:warn("g9_battle_sample: the Gen 1 battle-exit sequence "
          .. "failed: %s", tostring(err))
        -- Never leave the caller's own contract unrun: a dropped onFinish is
        -- a frozen player (a scripted trainer's onDone) or a trainer who can
        -- be fought again for ever.
        if nativeOnFinish then
          pcall(nativeOnFinish, screen.outcome or "run")
        end
      end
    end
    return true
  end

  -- The wipe, through the seam the scene already looks for.  Gen 2's World has
  -- pushBattleTransition; Gen 1's OverworldState never did, so without this the
  -- scene would push its screen with no battle transition at all.
  function OverworldState:pushBattleTransition(battle, opts, onDone)
    local pending = pendingTransition
    pendingTransition = nil
    if not (Game.stack and self.map) then return false end
    self.battleOamKeep = (pending and pending.npc) or false
    self.wipeSpritesFn = function() self:drawWipeSprites() end
    Game.stack:push(BattleTransition.new(Game, function()
      self.battleOamKeep = nil
      self.wipeSpritesFn = nil
      if onDone then onDone() end
    end, {
      trainer = (opts and opts.trainer) and true or false,
      stronger = (pending and pending.stronger) and true or false,
      dungeon = self.isDungeonTransitionMap
        and self:isDungeonTransitionMap() or false,
    }))
    return true
  end

  -- The one Gen 1 seam every battle passes through: wild step, fishing, a
  -- static object_event, a sighted trainer, a scripted battle.
  local nativePushBattle = OverworldState.pushBattle
  function OverworldState:pushBattle(battle, trainerNpc)
    if battle and tryDivert(self, battle, trainerNpc) then return end
    return nativePushBattle(self, battle, trainerNpc)
  end

  -- =====================================================================
  -- ITEM RANDOMIZER / ITEM RESPAWN / REMATCHES / TRAINER DROPS -- Gen 1.
  --
  -- The same four systems the Gen 2 arm installs, hung on Gen 1's own seams:
  -- the item id is swapped around the native pickup calls (so nothing at all
  -- about a pickup changes except which item it hands out), a per-frame tick
  -- on OverworldState:update brings one already-taken spot back, a beaten
  -- trainer's A press starts a rematch, and the win itself is read off
  -- afterBattle -- the one place BOTH the native screen and this mod's own
  -- scene arm reach on a finished fight.
  --
  -- Every one of these is a WRAP: with a setting off the wrap falls straight
  -- through to the method it captured, so the vanilla path is byte-for-byte
  -- the same code it was.
  -- =====================================================================

  -- True when a beaten trainer's A press may be turned into a rematch.  False
  -- when mapScripts owns this NPC's talk: talkTo's own first branch hands the
  -- press to that hand-ported script, and a rematch must never take a story
  -- scene away from it (rivals, Silph, the gym leaders' TM retry, ...).
  local function canRematch(self, d)
    local ok, mapScripts = pcall(require, "data.scripts.init")
    if not (ok and type(mapScripts) == "table" and mapScripts.talkScript) then
      return true
    end
    if type(d.text) ~= "string" then return true end
    local okTalk, script = pcall(mapScripts.talkScript, self.map.id, d.text)
    if okTalk and script then return false end
    return true
  end

  -- ONE random already-taken, non-key item spot on the map the player is
  -- standing on.  An item ball is put back by clearing the very
  -- itemsTaken[mapId.."_obj_"..index] key objectVisible reads and re-listing
  -- the NPC exactly the way setMap does (pooled, unfrozen, in npcs AND
  -- entities -- the item path removes it from both and leaves it frozen); a
  -- hidden item only needs its hiddenTaken key cleared, because
  -- tryHiddenObject reads that key and not a list of spots.
  local function respawnOneItemGen1(self)
    local mapId = self.map and self.map.id
    local save = Game.save
    if not (mapId and save) then return false end
    local candidates = {}
    for _, obj in ipairs(self.map.def.objects or {}) do
      local key = mapId .. "_obj_" .. tostring(obj.index)
      if obj.item and obj.item ~= "0" and obj.item ~= 0
          and save.itemsTaken and save.itemsTaken[key]
          and not shared.isKeyItem(obj.item) then
        candidates[#candidates + 1] = { hidden = false, key = key, obj = obj }
      end
    end
    local hidden = Game.data.field and Game.data.field.hiddenItems
      and Game.data.field.hiddenItems[mapId] or {}
    for _, h in ipairs(hidden) do
      local key = mapId .. "_" .. h.x .. "_" .. h.y
      if h.item and save.hiddenTaken and save.hiddenTaken[key]
          and not shared.isKeyItem(h.item) then
        candidates[#candidates + 1] = { hidden = true, key = key }
      end
    end
    if #candidates == 0 then return false end
    local pick = candidates[love.math.random(1, #candidates)]
    if pick.hidden then
      save.hiddenTaken[pick.key] = nil
      return true
    end
    save.itemsTaken[pick.key] = nil
    -- ...and only put it back while the engine's own visibility rule still
    -- shows it (objectVisible is what setMap filters on: an object hidden by a
    -- map toggle stays hidden, and the taken key is simply already cleared).
    if not OverworldState.objectVisible(save, mapId, pick.obj) then
      return true
    end
    local npc = OverworldState.pooledNPC(self.npcPool, Game.data, mapId,
      pick.obj)
    if npc then
      npc.frozen = false
      local listed = false
      for _, n in ipairs(self.npcs or {}) do
        if n == npc then listed = true break end
      end
      if not listed then table.insert(self.npcs, npc) end
      local inEntities = false
      for _, e in ipairs(self.entities or {}) do
        if e == npc then inEntities = true break end
      end
      if not inEntities then table.insert(self.entities, npc) end
    end
    return true
  end

  -- The same idle test handleInput uses before it runs a trainer's sight
  -- check: nothing scripted, nothing transitioning, and only while the
  -- overworld is the state on top.  `busy` enough to be safe, conservative
  -- enough that a respawn or a drop box can never land inside a scene.
  local function overworldIdle(self)
    if Game.stack:top() ~= self then return false end
    local runner = self.runner
    if runner and runner.isRunning and runner:isRunning() then return false end
    if self.engaging or self.emote or self.teleportOut or self.transitioning
        or self.flyAnim or self.flyArrive or self.spinArrive
        or self.holeFall or self.holeArrive then
      return false
    end
    if self.scriptMoves and #self.scriptMoves > 0 then return false end
    if (self.hopLand or 0) > 0 then return false end
    return true
  end

  -- Item randomizer.  The id is swapped around the native call and ALWAYS put
  -- back, so the object keeps the item the ROM gave it and only that one press
  -- sees the random one.  A spot that really holds a key item is left alone
  -- (randomizedItem returns the id it was handed), as is a press that is not
  -- an item ball at all.
  local nativeTalkTo = OverworldState.talkTo
  function OverworldState:talkTo(npc)
    if not (npc and type(npc.def) == "table") then
      return nativeTalkTo(self, npc)
    end
    local d = npc.def
    if d.item and d.item ~= "0" and d.item ~= 0 then
      local orig = d.item
      if not shared.isKeyItem(orig) then
        local swap = shared.randomizedItem(orig)
        if swap ~= orig then
          d.item = swap
          local ok, err = pcall(nativeTalkTo, self, npc)
          d.item = orig
          if not ok then error(err, 0) end
          return
        end
      end
      return nativeTalkTo(self, npc)
    end
    -- A press on a beaten trainer, when REMATCHES is on, ASKS first (explicit
    -- user request, 2026-09-14): beating someone no longer means every later A
    -- press silently starts another fight.  YES runs the ordinary
    -- engageTrainer flow -- the same two calls talkTo makes for a living
    -- trainer (native sets npc.frozen at its top, hence the matching
    -- unfreeze); checkVictoryRewards runs inside it and early-returns on an
    -- already-claimed reward, so a badge or TM is never handed out twice.  NO
    -- hands the press straight to the native beaten-trainer path, which shows
    -- the trainer's own after-battle line.
    --
    -- `isTrainerNpc` / `isBeatenTrainer` are the shared unions (see their own
    -- notes above): 0.9.3 tested `d.trainerClass` and `self:trainerDefeated`
    -- one at a time, so a save that recorded the win in only one of the
    -- engine's stores -- the defeatedTrainers set, the header event flag, the
    -- badge -- could leave a beaten trainer with no way to be re-fought.
    -- canRematch still stands in for the engine's own first branch: a press
    -- mapScripts already owns (a rival, the Rocket hideout, a gym leader's own
    -- retry line) keeps its script, exactly as if REMATCHES were off.
    if shared.rematchesOn() and shared.isTrainerNpc(npc)
        and shared.isBeatenTrainer(self, npc)
        and (canRematch(self, d)
             or (shared.gymRematchesOn()
                 and shared.isGymClass(shared.trainerClassOf(d)))) then
      npc.frozen = true
      self:makeNpcFacePlayer(npc)
      local function finish() npc.frozen = false end
      Game.stack:push(TextBox.new(Game, "Do you want to battle again?", nil, {
        choice = function(yes)
          if yes then
            self:engageTrainer(npc, finish)
          else
            nativeTalkTo(self, npc)
          end
        end,
      }))
      return
    end
    return nativeTalkTo(self, npc)
  end

  -- Hidden items, the same swap-and-restore around the native scan.  The
  -- taken-set is keyed by cell rather than by item, so putting the row back is
  -- always exact.
  local nativeTryHiddenObject = OverworldState.tryHiddenObject
  function OverworldState:tryHiddenObject(fx, fy)
    local mapId = self.map and self.map.id
    local rows = mapId and Game.data.field and Game.data.field.hiddenItems
      and Game.data.field.hiddenItems[mapId]
    local row
    for _, h in ipairs(rows or {}) do
      if h.x == fx and h.y == fy and h.item then row = h break end
    end
    if not row then return nativeTryHiddenObject(self, fx, fy) end
    if shared.isKeyItem(row.item) then
      return nativeTryHiddenObject(self, fx, fy)
    end
    local orig = row.item
    local swap = shared.randomizedItem(orig)
    if swap == orig then return nativeTryHiddenObject(self, fx, fy) end
    row.item = swap
    local ok, result = pcall(nativeTryHiddenObject, self, fx, fy)
    row.item = orig
    if not ok then error(result, 0) end
    return result
  end

  -- Win detection.  afterBattle is the one place a finished trainer battle
  -- lands on both paths -- the native screen's own win sequence calls it, and
  -- the scene arm's finishGen1Battle reaches it through the captured
  -- battle.onFinish -- so a single wrap covers every trainer fight.
  -- oppClass / partyIndex are the same pair the trainer.party hook builds the
  -- +level key from, which is what makes the ramp line up with the fight that
  -- is about to be scaled.
  local nativeAfterBattle = OverworldState.afterBattle
  function OverworldState:afterBattle(result, battle)
    if result == "win" and battle and battle.kind == "trainer" then
      local key = tostring(battle.oppClass or "?") .. "/"
        .. tostring(battle.partyIndex or 1)
      if shared.rematchTracking() then shared.noteTrainerWin(key) end
      shared.queueTrainerDrop()
    end
    return nativeAfterBattle(self, result, battle)
  end

  -- The per-frame tick: the respawn clock and the pending trainer drop.  Both
  -- run only while the overworld is idle and on top, exactly like the engine's
  -- own sight check, so neither can fire under a script or a text box.
  local nativeUpdate = OverworldState.update
  function OverworldState:update(dt)
    nativeUpdate(self, dt)
    if not (self.player and self.map and overworldIdle(self)) then return end
    -- The scene is on (BACKGROUND not OFF) but unreachable: the one-off notice queued at
    -- the fallback shows here, on the first idle frame after it (see
    -- shared.reportSceneProblem).
    shared.flushSceneProblem(self)
    if shared.tickRespawn(dt) then
      local ok, err = pcall(respawnOneItemGen1, self)
      if not ok then
        mod.log:warn("g9_battle_sample: item respawn failed: %s", tostring(err))
      end
    end
    shared.flushTrainerDrop(function(_, name)
      -- The same "found an item" box a real pickup pushes, SFX included
      -- (pick_up_item.asm FoundItemText / sound_get_item_1).
      Game.stack:push(TextBox.new(Game,
        Strings("%s found\n%s!", Game.save.player.name, name), nil,
        TextBox.soundOpts(Game, "Get_Item1")))
    end)
  end

  mod.log:info("g9_battle_sample: with the scene on (g9-Battle-Scene's "
    .. "BACKGROUND not OFF) and the 2v2/3v3/4v1 row on (the default), Gen 1 "
    .. "wild encounters route to "
    .. "g9-Battle-Scene (0.5%% \"bossFight\" with x1..x5 HP + random flags, "
    .. "1%% \"hordes\", 2%% \"triples\", 10%% \"doubles\", ~86%% \"singles\"); "
    .. "every 2+-mon trainer battle routes to \"doubles\", the Elite Four "
    .. "rolls doubles/triples, and the Champion (OPP_RIVAL3) routes to "
    .. "\"bossFight\"; wild_forms's Eternatus-as-Eternamax static routes to "
    .. "\"bossFight\" (with BACKGROUND OFF the native Gen 1 screen runs "
    .. "instead, and with 2v2/3v3/4v1 OFF every fight takes \"singles\")")
  return shared
end

-- The BLACKLIST window added 2026-09-18 (explicit user request): a custom
-- screen reached from the "BLACKLIST" row this installs on the OPTIONS menu.
-- It indexes every species AND alternate form by name, filters by generation
-- (START) and by starting letter (SELECT), and delists the hovered Pokemon (A),
-- a whole generation's roster (A on a grid cell), or a whole form group -- the
-- [MEGA] / [GIGA] row under the grid (explicit user request, 2026-09-19).  The
-- actual list (and its persistence) lives in installRandomizer's blacklist
-- system -- this screen is only its face.
local function installBlacklist(mod, gen, shared)
  if type(shared) ~= "table"
      or type(shared.buildBlacklistIndex) ~= "function"
      or type(shared.blacklistToggle) ~= "function" then
    mod.log:warn("g9_battle_sample: BLACKLIST screen not installed -- "
      .. "blacklist system unavailable")
    return
  end

  local Font = require("src.render.Font")

  -- The request fixes the grid at three generations per row, nine cells.
  local GEN_COUNT = 9
  local LETTER_COUNT = 26
  local VISIBLE_NAMES = 9

  -- A 16:9 surface that IS the whole playfield at the game's native 960x540
  -- window: 960/320 = 3 and 540/180 = 3, so the renderer's integer fit scale
  -- lands on a clean 3x with NO letterbox and every 8px frame and glyph stays
  -- on the grid.  The classic 160x144 window is 20x18 tiles; this is 40x22.5.
  -- The old 240x216 was 10:9 -- nearer square than the screen -- so on a 16:9
  -- window it letterboxed, and on Gold it was silently clipped to the classic
  -- 160x144 because Gen 2 never reads a state's uiSize() (see the two seams
  -- below).
  local UI_W, UI_H = 320, 180

  local function frame(x, y, w, h, level)
    love.graphics.rectangle("line", x, y, w, h)
    if (level or 1) > 1 then
      love.graphics.rectangle("line", x + 1, y + 1,
        math.max(0, w - 2), math.max(0, h - 2))
    end
  end
  local function cell(text, x, y)
    return Font.draw(text, x, y)
  end

  -- A native Game Boy window ring, tiled from the engine's own border glyphs.
  -- Font.drawBox is the usual way to get this look, but it takes TILE counts,
  -- and this surface's 180-pixel height is 22.5 tiles -- drawBox would put its
  -- bottom row at y=168 and leave a 4px gap down the sides.  Tiling the ring
  -- here is exact at ANY size and lays down the same corner and edge glyphs
  -- drawBox uses.
  local function drawBorder(w, h)
    local B = Font.BORDER
    if not (B and B.tl and B.tr and B.bl and B.br and B.h and B.v) then
      Font.drawBox(0, 0, w / 8, h / 8)
      return
    end
    Font.drawCode(B.tl, 0, 0)
    Font.drawCode(B.tr, w - 8, 0)
    Font.drawCode(B.bl, 0, h - 8)
    Font.drawCode(B.br, w - 8, h - 8)
    for x = 8, w - 16, 8 do
      Font.drawCode(B.h, x, 0)
      Font.drawCode(B.h, x, h - 8)
    end
    for y = 8, h - 8, 8 do
      Font.drawCode(B.v, 0, y)
      Font.drawCode(B.v, w - 8, y)
    end
  end

  -- The border ring is one 8px tile thick, so every band lives inside
  -- [MARGIN, UI_W - MARGIN] / [MARGIN, UI_H - MARGIN] and the header, the name
  -- rows, the grid and the hints all clear it.
  local MARGIN = 12
  local CONTENT_R = UI_W - MARGIN
  -- Header: the two filters in the top corners (START/SELECT cycle them)
  -- with the title centred between, then a hairline rule.
  local HEADER_Y, DIVIDER_Y = 12, 24
  -- Nine name rows down the left, each framed; the cursor's row is framed
  -- twice.  A 180-wide column fits a 21-glyph name at this font.
  local NAME_X, NAME_W = MARGIN, 180
  local NAME_Y0, NAME_STEP, NAME_H = 34, 12, 11
  local NAME_PAD = 4
  local NAME_MAX = 21
  -- The 3x3 generation grid down the right, then a [MEGA] [GIGA] row, then the
  -- RESET bar under it.  Cells are 34 wide on a 2px gutter: 202 + 34*3 + 2*2 =
  -- 308 = the content edge, and three 15-tall rows sit between y=34 and y=87.
  -- The form row reuses the same content width as two 52-wide cells (2px
  -- gutter), and RESET sits below it, pushed down out of the form row's way
  -- (explicit user request, 2026-09-19).
  local GRID_X = { 202, 238, 274 }
  local GRID_Y = { 34, 53, 72 }
  local GRID_W, GRID_H = 34, 15
  local FORM_Y, FORM_W, FORM_GAP = 94, 52, 2
  local FORM_X = { 202, 202 + FORM_W + FORM_GAP }
  local RESET_X, RESET_Y, RESET_W = 202, 113, 106
  -- Divider above the hints, then the two hint lines and the right-aligned
  -- status.  y=164 + the 8px glyph is the last row inside the bottom ring.
  local DIVIDER_Y2 = 148
  local HINT_Y1, HINT_Y2 = 154, 164

  local Screen = {}
  Screen.__index = Screen
  Screen.isOpaque = true
  Screen.screenId = "G9Blacklist"

  function Screen:uiSize() return UI_W, UI_H end

  -- This is a WIDE owner: it tells the engine the whole 320x180 surface is
  -- its own layout, the same marker the engine's own wide battle and the
  -- sprites mod's party screen carry.  Game:draw (Gen 1) then sizes the
  -- surface to this state's uiSize() wherever it sits in the stack, and draws
  -- the screen at the surface origin instead of shifting it by the classic-UI
  -- offset.  (A state that answers uiSize() alone is sized the same way when
  -- it is the top state; the marker additionally HOLDS the surface while a
  -- prompt is pushed over it.)  It never touches Renderer itself -- see
  -- Screen:draw.  Gen 2 has NO such seam; see the panel contract below.
  function Screen:isWideBattleLayout() return true end

  -- Fill the letterbox around the surface with the window's own paper rather
  -- than flat black, so a window that is not an exact multiple reads as one
  -- continuous screen (the same opt-in the engine's battle screens use).
  Screen.letterboxWhite = true

  -- Gen 2's panel contract.  src/core/Game2.lua composes the window itself
  -- and NEVER reads a state's uiSize() or calls Renderer:setUISize -- which is
  -- the only reason a 240x216 surface came out clipped to the classic 160x144
  -- on Gold, with the header and grid cut off at the edges.  A screen wider
  -- than 160x144 therefore has to supply that generation's own contract --
  -- drawsWidescreen() + drawWidescreen(winW, winH) + panelSize() -- exactly
  -- as src/ui/gen2/BattleState.lua, PartyMenu and the WideBattle scene do.
  -- Both seams answer from the SAME size, so one layout serves both gens.
  function Screen:panelSize() return UI_W, UI_H end

  function Screen:battlePanelScale(winW, winH) return self:panelScale(winW, winH) end

  -- Whole window pixels per surface pixel, so the 8px grid every frame and
  -- glyph sits on stays aligned.  Chrome owns the playfield/skin maths, so it
  -- is preferred; the plain floor is the same answer without a skin.
  function Screen:panelScale(winW, winH)
    local ok, Chrome = pcall(require, "src.ui.gen2.Chrome")
    if ok and type(Chrome) == "table" and Chrome.fitScaleFor then
      local okScale, scale = pcall(Chrome.fitScaleFor, winW, winH,
        UI_W / 8, UI_H / 8)
      if okScale and type(scale) == "number" and scale >= 1 then
        return scale
      end
    end
    if not (winW > 0 and winH > 0) then return 1 end
    return math.max(1, math.floor(math.min(winW / UI_W, winH / UI_H)))
  end

  function Screen:drawsWidescreen() return true end

  -- Gen 2's draw entry: paint the surround, then draw the surface at the
  -- whole-pixel scale into it.  draw() itself is always in surface pixels, so
  -- this is the only place the window scale lives on Gold.
  function Screen:drawWidescreen(winW, winH)
    local G = love.graphics
    local scale = self:panelScale(winW, winH)
    local ox, oy = 0, 0
    local ok, Chrome = pcall(require, "src.ui.gen2.Chrome")
    if ok and type(Chrome) == "table" and Chrome.letterbox then
      pcall(Chrome.letterbox, winW, winH, 1, 1, 1)
      local okO, x, y = pcall(Chrome.fitOriginFor, winW, winH, scale,
        UI_W / 8, UI_H / 8)
      if okO and type(x) == "number" then ox, oy = x, y end
    else
      G.setColor(1, 1, 1, 1)
      G.rectangle("fill", 0, 0, winW, winH)
      ox = math.floor((winW - UI_W * scale) / 2 + 0.5)
      oy = math.floor((winH - UI_H * scale) / 2 + 0.5)
    end
    G.push("all")
    G.translate(ox, oy)
    G.scale(scale, scale)
    self:draw()
    G.pop()
  end

  -- Rows 1..3 are the 3x3 generation grid, row 4 is the [MEGA] [GIGA] pair and
  -- row 5 is the full-width RESET bar (pushed below the form row; explicit user
  -- request, 2026-09-19).
  local ROW_FORMS, ROW_RESET = 4, 5
  function Screen:gridCellCount(row)
    if row >= ROW_RESET then return 1 end
    if row == ROW_FORMS then return 2 end
    return 3
  end

  function Screen:clampGridCol()
    local n = self:gridCellCount(self.gridRow)
    if self.gridCol > n then self.gridCol = n end
    if self.gridCol < 1 then self.gridCol = 1 end
  end

  function Screen:clampScroll()
    local n = #self.filtered
    if self.listIndex < 1 then self.listIndex = 1 end
    if n > 0 and self.listIndex > n then self.listIndex = n end
    if self.listIndex <= self.listScroll then
      self.listScroll = self.listIndex
    end
    if self.listIndex > self.listScroll + VISIBLE_NAMES - 1 then
      self.listScroll = self.listIndex - VISIBLE_NAMES + 1
    end
    local maxScroll = math.max(1, n - VISIBLE_NAMES + 1)
    if self.listScroll > maxScroll then self.listScroll = maxScroll end
    if self.listScroll < 1 then self.listScroll = 1 end
  end

  -- The current filter's list: generation AND starting letter, both active at
  -- once (the request's own example filters gen 1 on the letter A).
  function Screen:rebuild()
    self.filtered = {}
    local index = shared.buildBlacklistIndex()
    local letter = string.char(64 + self.letter)
    for _, entry in ipairs(index or {}) do
      if entry.gen == self.gen then
        local first = string.sub(entry.name, 1, 1):upper()
        if first == letter then self.filtered[#self.filtered + 1] = entry end
      end
    end
    self.listScroll = 1
    self.listIndex = #self.filtered > 0 and 1 or 0
  end

  function Screen.new(game)
    local self = setmetatable({
      game = game, gen = 1, letter = 1,
      focus = "list", listIndex = 1, listScroll = 1, filtered = {},
      gridRow = 1, gridCol = 1, status = "", broken = false,
    }, Screen)
    pcall(self.rebuild, self)
    return self
  end

  local function safeCall(self, label, fn)
    local ok, err = pcall(fn)
    if not ok then
      mod.log:warn(
        "g9_battle_sample: blacklist_screen: %s errored, closing (%s)",
        label, tostring(err))
      self.broken = true
    end
  end

  -- LEFT/RIGHT cross between the name list and the generation grid, which the
  -- request reads as one horizontal run of options: the list is the leftmost
  -- column, and RIGHT walks it into that row's cells -- G1 > G2 > G3 -- then
  -- back to the list, with LEFT the same run reversed.  The [MEGA] [GIGA] row
  -- and the RESET bar are rows of their own that only UP/DOWN reach, so a grid
  -- entry that lands outside the three generation rows (i.e. was left sitting
  -- on one of them) starts on the first.
  function Screen:enterGrid(col)
    self.focus = "grid"
    if self.gridRow < 1 or self.gridRow > 3 then self.gridRow = 1 end
    if col < 0 then col = self:gridCellCount(self.gridRow) end
    self.gridCol = col
  end

  function Screen:leaveGrid()
    self.focus = "list"
    if self.gridRow >= ROW_RESET then self.gridRow = 1 end
  end

  function Screen:updateList(input)
    if input:wasPressed("up") then
      if self.listIndex <= 1 then
        self.focus = "grid"
        self.gridRow = ROW_RESET
        self:clampGridCol()
      else
        self.listIndex = self.listIndex - 1
        self:clampScroll()
      end
    elseif input:wasPressed("down") then
      if #self.filtered == 0 or self.listIndex >= #self.filtered then
        self.focus = "grid"
        self.gridRow = 1
        self:clampGridCol()
      else
        self.listIndex = self.listIndex + 1
        self:clampScroll()
      end
    elseif input:wasPressed("right") then
      self:enterGrid(1)
    elseif input:wasPressed("left") then
      self:enterGrid(-1)
    elseif input:wasPressed("a") then
      local entry = self.filtered[self.listIndex]
      if entry then
        shared.blacklistToggle(entry.id)
        self.status = ""
      end
    end
  end

  function Screen:updateGrid(input)
    if input:wasPressed("up") then
      if self.gridRow > 1 then
        self.gridRow = self.gridRow - 1
        self:clampGridCol()
      end
    elseif input:wasPressed("down") then
      if self.gridRow < ROW_RESET then
        self.gridRow = self.gridRow + 1
        self:clampGridCol()
      else
        self.focus = "list"
      end
    elseif input:wasPressed("left") then
      -- The list sits immediately left of the row's first cell, so LEFT off
      -- that cell (or off the single-cell RESET bar) returns to it.
      if self.gridCol <= 1 then
        self:leaveGrid()
      else
        self.gridCol = self.gridCol - 1
      end
    elseif input:wasPressed("right") then
      -- ... and RIGHT off the last cell wraps back to the list, so the row's
      -- own cells > list > first cell cycle on the one key.
      if self.gridCol >= self:gridCellCount(self.gridRow) then
        self:leaveGrid()
      else
        self.gridCol = self.gridCol + 1
      end
    elseif input:wasPressed("a") then
      if self.gridRow >= ROW_RESET then
        shared.blacklistReset()
        self.status = "RESET"
      elseif self.gridRow == ROW_FORMS then
        -- Column 1 = Mega, column 2 = Gigantamax.
        shared.blacklistFormGroupToggle(self.gridCol == 2 and "gmax" or "mega")
        self.status = ""
      else
        local g = (self.gridRow - 1) * 3 + self.gridCol
        shared.blacklistGenToggle(g)
        self.status = ""
      end
    end
  end

  function Screen:update(dt)
    if self.broken then
      if self.game and self.game.stack then self.game.stack:pop() end
      return
    end
    safeCall(self, "update", function()
      local input = self.game and self.game.input
      if not input then return end
      -- START cycles the generation filter 1>2>...>9>1; SELECT cycles the
      -- starting letter a>b>...>z>a.  Both work from either focus, which is
      -- what the two top-corner indicators read.
      if input:wasPressed("start") then
        self.gen = (self.gen % GEN_COUNT) + 1
        self:rebuild()
        self.status = ""
        return
      end
      if input:wasPressed("select") then
        self.letter = (self.letter % LETTER_COUNT) + 1
        self:rebuild()
        self.status = ""
        return
      end
      if input:wasPressed("b") then
        if self.focus == "grid" then
          self.focus = "list"
          self.status = ""
        else
          self.game.stack:pop()
        end
        return
      end
      if self.focus == "list" then
        self:updateList(input)
      else
        self:updateGrid(input)
      end
    end)
  end

  function Screen:drawHeader()
    -- Top-left: the generation filter (START cycles it).  Top-right: the
    -- starting-letter filter (SELECT cycles it).  The title sits between.
    cell(string.format("GEN:[%d]", self.gen), NAME_X, HEADER_Y)
    local letter = string.char(64 + self.letter)
    local letterText = string.format("LET:[%s]", letter)
    cell(letterText, CONTENT_R - Font.width(letterText), HEADER_Y)
    local title = "BLACKLIST"
    cell(title, math.floor((UI_W - Font.width(title)) / 2 + 0.5), HEADER_Y)
    love.graphics.rectangle("fill", MARGIN, DIVIDER_Y, CONTENT_R - MARGIN, 1)
  end

  function Screen:drawNames()
    for slot = 1, VISIBLE_NAMES do
      local index = self.listScroll + slot - 1
      local entry = self.filtered[index]
      local y = NAME_Y0 + (slot - 1) * NAME_STEP
      local level = (self.focus == "list" and entry
        and index == self.listIndex) and 2 or 1
      frame(NAME_X, y, NAME_W, NAME_H, level)
      if entry then
        cell(string.sub(entry.name, 1, NAME_MAX), NAME_X + NAME_PAD, y + 2)
        -- The delist mark the request's own sketch shows, right-aligned in
        -- the row and read from the raw set so the row the player actually
        -- toggled is the row marked.
        if shared.blacklistRaw(entry.id) then
          local mark = "[x]"
          cell(mark, NAME_X + NAME_W - NAME_PAD - Font.width(mark), y + 2)
        end
      end
    end
  end

  function Screen:drawGrid()
    local labelY = 3
    for g = 1, GEN_COUNT do
      local row = math.floor((g - 1) / 3) + 1
      local col = ((g - 1) % 3) + 1
      local x, y = GRID_X[col], GRID_Y[row]
      local selected = (self.focus == "grid" and self.gridRow == row
        and self.gridCol == col)
      frame(x, y, GRID_W, GRID_H, selected and 2 or 1)
      local label = string.format("G%d", g)
      cell(label, x + math.floor((GRID_W - Font.width(label)) / 2 + 0.5),
        y + labelY)
      if shared.blacklistGenComplete(g) then
        local mark = "X"
        cell(mark, x + GRID_W - 4 - Font.width(mark), y + labelY)
      end
    end
    -- The [MEGA] [GIGA] row: two cell-wide tiles under the generations, each
    -- carrying the group's own complete mark.  A is the whole-group toggle.
    local forms = { { "MEGA", "mega" }, { "GIGA", "gmax" } }
    for i = 1, #forms do
      local x = FORM_X[i]
      local selected = (self.focus == "grid" and self.gridRow == ROW_FORMS
        and self.gridCol == i)
      frame(x, FORM_Y, FORM_W, GRID_H, selected and 2 or 1)
      local label = forms[i][1]
      cell(label, x + math.floor((FORM_W - Font.width(label)) / 2 + 0.5),
        FORM_Y + labelY)
      if shared.blacklistFormGroupComplete(forms[i][2]) then
        local mark = "X"
        cell(mark, x + FORM_W - 4 - Font.width(mark), FORM_Y + labelY)
      end
    end
    local selected = (self.focus == "grid" and self.gridRow >= ROW_RESET)
    frame(RESET_X, RESET_Y, RESET_W, GRID_H, selected and 2 or 1)
    local resetLabel = "RESET"
    cell(resetLabel,
      RESET_X + math.floor((RESET_W - Font.width(resetLabel)) / 2 + 0.5),
      RESET_Y + labelY)
  end

  function Screen:draw()
    if self.broken then return end
    safeCall(self, "draw", function()
      -- A plain native window, drawn the way the engine's own screens draw
      -- theirs: a white interior with the $79-$7e border tiles tiled around
      -- the WHOLE surface (40 x 22.5 tiles).  That is the bigger canvas the
      -- request asks for -- a vanilla Game Boy window made larger -- not a
      -- small box floating in a big empty field.
      --
      -- NEVER call Renderer:setUISize / love.graphics.setCanvas from a draw.
      -- Game:draw has already sized the surface from Screen:uiSize() before
      -- the draw loop; re-binding it mid-frame is exactly the silent-crash
      -- hazard stats/dev_stats_screen.lua's header documents, and the
      -- round-175 "clip guard" that turned this screen into a white field.
      -- Plain drawing only, the same contract adv.stats and
      -- modern_stats_screen follow.
      love.graphics.setColor(1, 1, 1, 1)
      love.graphics.rectangle("fill", 0, 0, UI_W, UI_H)
      drawBorder(UI_W, UI_H)
      love.graphics.setColor(0, 0, 0, 1)
      self:drawHeader()
      self:drawNames()
      self:drawGrid()
      love.graphics.rectangle("fill", MARGIN, DIVIDER_Y2, CONTENT_R - MARGIN, 1)
      cell("START:GEN  SELECT:LETTER", MARGIN, HINT_Y1)
      cell("A:TOGGLE  B:BACK  L/R:MOVE", MARGIN, HINT_Y2)
      if self.status ~= "" then
        cell(self.status, CONTENT_R - Font.width(self.status), HINT_Y2)
      end
      love.graphics.setColor(1, 1, 1, 1)
    end)
  end

  -- --------------------------------------------------------------- the row
  -- The same descriptor shape the engine's own OPTIONS rows use, so A opens
  -- the screen on BOTH generations' menus (src/ui/OptionsMenu.lua's activate
  -- and src/ui/gen2/OptionsMenu.lua's own A branch).
  mod.hooks:wrap("ui.options.rows", function(nextFn, game, rows)
    local result = nextFn(game, rows)
    if type(result) ~= "table" then result = rows end
    if type(result) ~= "table" then return result end
    result[#result + 1] = {
      id = "blacklist",
      label = "BLACKLIST",
      value = function()
        local index = shared.buildBlacklistIndex() or {}
        local n = 0
        for _, entry in ipairs(index) do
          if shared.blacklistRaw(entry.id) then n = n + 1 end
        end
        return string.format("%d HELD", n)
      end,
      activate = function(g)
        local ok, screen = pcall(Screen.new, g)
        if ok and screen then
          g.stack:push(screen)
        else
          mod.log:warn(
            "g9_battle_sample: BLACKLIST screen failed to open (%s)",
            tostring(screen))
        end
      end,
    }
    -- LEAGUE ACES: only offered while RAND TRAINER MONS is on, because the
    -- row is meaningless without it (the aces are the slots the randomizer
    -- would otherwise overwrite).  The Mod Manager carries the same row (see
    -- options.lua's `league_aces`, hidden by its own `visible_if` unless RAND
    -- TRAINER MONS is on); this OPTIONS-menu row is the in-session flip, and
    -- an explicit flip wins over the manager's configured value.
    if shared.randTrainersOn and shared.randTrainersOn() then
      result[#result + 1] = {
        id = "league_aces",
        label = "LEAGUE ACES",
        value = function()
          return (shared.leagueAcesOn and shared.leagueAcesOn()) and "ON" or "OFF"
        end,
        activate = function()
          if shared.leagueAcesToggle then shared.leagueAcesToggle() end
        end,
      }
    end
    return result
  end, 0)

  mod.log:info("g9_battle_sample: BLACKLIST screen installed (Gen %d)", gen)
end

-- ===========================================================================
-- LEAGUE ACES -- the signature Pokemon a league trainer keeps despite RAND
-- TRAINER MONS.
-- ===========================================================================
-- Explicit user request, 2026-09-23: a [LEAGUE ACES] ON/OFF row that only
-- appears on the OPTIONS menu while RAND TRAINER MONS is on, and a table of
-- the gym leaders / Elite Four / Champions / Red, each with the Pokemon that
-- should sit at the END of their team.
--
-- HOW IT WORKS.  `applyLeagueAces` runs AFTER the difficulty team floor and
-- after `randomizeParty`, and REPLACES the last N slots with the N listed
-- aces (N = the number of entries for that class; the early slots keep the
-- randomized/padded team they already had).  The aces are therefore never
-- run through the randomizer and never evolved by it -- which is exactly
-- what "ignoring randomizer for these specific slots" asks for -- while the
-- rest of the team behaves exactly as before.
--
-- WHAT AN ACE KEEPS, and what it does not:
--   * SPECIES and MOVESET are fixed.  "Original move set" is the species'
--     own vanilla level-up moves; an entry marked "(inherits X moves)" takes
--     the PRE-evolution's level-up set instead (Rhyperior keeps Rhydon's,
--     Magnezone keeps Magneton's, Venusaur-Mega keeps Venusaur's), and the
--     two entries that name an extra move (Lance's Dragonite -> Hurricane,
--     Red's Venusaur -> Weather Ball) have it forced into the four.
--   * NATURE / IVs / EVs come from the DIFFICULTY setting like every other
--     trainer mon -- the mod's own registerTrainerStatsProvider already
--     computes them, and these aces are ordinary party members.  A couple of
--     entries carry their own explicit spread instead (Lance's Dragonite is
--     "special and speed trained"), which is applied after the difficulty
--     pass so it wins.
--   * HELD ITEM is the one the entry names (Eviolite, a Mega Stone, Light
--     Ball), and it is what makes a Mega / Gigantamax form happen: the SAME
--     stored-property route a wild SPECIAL BOSS uses -- battle_forms deploys
--     the transformation when it deploys.  A Tera type and a Dynamax level
--     are stored the same way.
--   * "doesn't evolve" is informational: an ace is never pushed to its
--     latest evolution, so a Pidgeotto stays a Pidgeotto (which is why it
--     can hold an Eviolite).
--
-- LEVELS: an ace takes the level of the slot it fills, so the DIFFICULTY
-- team floor and the +LEVEL PER REMATCH ramp keep working and no league
-- fight is silently re-levelled.
--
-- INSTALLATION: a separate top-level function on purpose.  `installRandomizer`
-- is already enormous, and LÖVE/LuaJIT caps a function at 200 active locals;
-- keeping this here means that budget is untouched.  Only the small hooks
-- inside installRandomizer/installGen1/installGen2 call into it.
local function installLeagueAces(mod, shared)
  local LEAGUE_ACE_KEY = "league_aces"
  local unpack = table.unpack or unpack

  local function dataNow() return shared.liveData and shared.liveData() or nil end
  local function saveNow() return shared.liveSave and shared.liveSave() or nil end

  local function engineExports()
    local engine = mod.find and mod.find("g9-battle-engine")
    return engine and engine.exports or nil
  end

  -- The state, in two layers.  The Mod Manager's own LEAGUE ACES row
  -- (options.lua / the schema this file defines) is the CONFIGURED value and
  -- defaults ON; the in-game OPTIONS menu's row flips it in-session by writing
  -- a boolean into the save under the same key, and that explicit flip then
  -- WINS -- so a fresh game starts from the manager setting, and the OPTIONS
  -- row stays the quick toggle it has always been.  `leagueAcesOn` also folds
  -- in the randomizer gate (the ace slots only mean anything as protection
  -- FROM the randomizer), so every consumer -- the applier and both value
  -- displays -- agrees.
  local function leagueAcesOn()
    if not (shared.randTrainersOn and shared.randTrainersOn()) then return false end
    local save = mod.save
    if save and type(save.get) == "function" then
      local ok, value = pcall(save.get, save, LEAGUE_ACE_KEY)
      if ok and type(value) == "boolean" then return value end
    end
    local options = mod.options
    if options and type(options.get) == "function" then
      local ok, value = pcall(options.get, options, LEAGUE_ACE_KEY)
      if ok and type(value) == "boolean" then return value end
    end
    return true
  end
  shared.leagueAcesOn = leagueAcesOn

  function shared.leagueAcesToggle()
    local save = mod.save
    if not (save and type(save.set) == "function") then return end
    pcall(save.set, save, LEAGUE_ACE_KEY, not leagueAcesOn())
  end

  -- ------------------------------------------------ spec constructors
  -- battle_forms' own Mega Stone ids (the same table g9-Battle-Scene's
  -- special_boss.lua transcribes).  HOLDING the stone is what lets
  -- battle_forms' trainer AI Mega-evolve the mon.
  local MEGA_STONE = {
    ALAKAZAM = "ALAKAZITE", STEELIX = "STEELIXITE", STARMIE = "STARMIITE",
    GYARADOS = "GYARADOSITE", BEEDRILL = "BEEDRILLITE",
    HOUNDOOM = "HOUNDOOMINITE", SLOWBRO = "SLOWBRONITE", GENGAR = "GENGARITE",
    TYRANITAR = "TYRANITARITE", PIDGEOT = "PIDGEOTITE",
    VENUSAUR = "VENUSAURITE", BLASTOISE = "BLASTOISINITE",
    CHARIZARD_X = "CHARIZARDITE_X",
    RAICHU_X = "RAICHUITE_X", RAICHU_Y = "RAICHUITE_Y",
  }

  local function ace(species, fields)
    local spec = { species = species }
    for k, v in pairs(fields or {}) do spec[k] = v end
    return spec
  end
  local function mega(species, variant)
    local key = variant and (species .. "_" .. variant) or species
    return ace(species, { item = MEGA_STONE[key] })
  end
  local function gmax(species) return ace(species, { gmax = true }) end
  local function dyna(species) return ace(species, { dyna = true }) end
  local function tera(species, typeId) return ace(species, { tera = typeId }) end

  -- ------------------------------------------------ the Champion sets
  -- Gen 1's champion (the rival) is the one team that is not a fixed list.
  -- Yellow has no single rival starter, so one of the three sets is rolled
  -- FRESH EVERY BATTLE.  Red/Blue pick by the PLAYER's starter -- the rival's
  -- own starter is always the counterpick -- Squirtle -> the Venusaur set,
  -- Charmander -> the Blastoise set, Bulbasaur -> the Charizard set.  A save
  -- that has not recorded a starter yet falls back to the rival's own
  -- starter, then to the Venusaur set.
  local function gen1ChampionAces()
    local yellow = {
      { ace("SANDSLASH"), mega("ALAKAZAM"), ace("EXEGGUTOR"), ace("NINETALES"),
        ace("MAGNEZONE", { dyna = true, movesFrom = "MAGNETON" }),
        tera("VAPOREON", "FIRE") },
      { ace("SANDSLASH"), mega("ALAKAZAM"), ace("EXEGGUTOR"),
        dyna("CLOYSTER"), ace("NINETALES"), tera("JOLTEON", "ELECTRIC") },
      { ace("SANDSLASH"), mega("ALAKAZAM"), ace("EXEGGUTOR"),
        ace("MAGNEZONE", { movesFrom = "MAGNETON" }),
        tera("CLOYSTER", "WATER"), dyna("FLAREON") },
    }
    local save = saveNow()
    local playerStarter = save and save.playerStarter
    if playerStarter == "PIKACHU" then
      return yellow[love.math.random(1, #yellow)]
    end
    local byPlayer = {
      SQUIRTLE = { ace("PIDGEOT"), ace("ALAKAZAM"),
        ace("RHYPERIOR", { movesFrom = "RHYDON" }),
        tera("GYARADOS", "WATER"), dyna("ARCANINE"), mega("VENUSAUR") },
      CHARMANDER = { ace("PIDGEOT"), ace("ALAKAZAM"),
        ace("RHYPERIOR", { movesFrom = "RHYDON" }),
        dyna("EXEGGUTOR"), tera("ARCANINE", "FIRE"), mega("BLASTOISE") },
      BULBASAUR = { mega("PIDGEOT"), ace("ALAKAZAM"),
        ace("RHYPERIOR", { movesFrom = "RHYDON" }),
        tera("GYARADOS", "WATER"), ace("EXEGGUTOR"), gmax("CHARIZARD") },
    }
    local set = byPlayer[playerStarter]
    if set then return set end
    local byRival = { VENUSAUR = "SQUIRTLE", BLASTOISE = "CHARMANDER",
                      CHARIZARD = "BULBASAUR" }
    set = byPlayer[byRival[save and save.rivalStarter]]
    if set then return set end
    return byPlayer.SQUIRTLE
  end

  -- ------------------------------------------------ the teams
  -- One list per trainer class.  Class ids are the engine's own (Gen 1 spells
  -- Kanto OPP_*, Gen 2 uses the plain class name), so the Johto/Kanto and
  -- Gen 1/Gen 2 look-alikes never collide.  The LAST entry is the last slot.
  local LEAGUE_ACES = {
    -- Gen 1 Kanto gyms
    OPP_BROCK = { ace("ONIX") },
    OPP_MISTY = { ace("PSYDUCK"), ace("STARMIE") },
    OPP_LT_SURGE = { ace("RAICHU") },
    OPP_ERIKA = { ace("VILEPLUME") },
    OPP_KOGA = { ace("MUK"), ace("WEEZING") },
    OPP_SABRINA = { ace("ALAKAZAM") },
    OPP_BLAINE = { ace("ARCANINE"), ace("NINETALES") },
    OPP_GIOVANNI = { ace("NIDOKING"), ace("NIDOQUEEN"), ace("RHYPERIOR") },
    -- Gen 1 Elite Four
    OPP_LORELEI = { ace("SLOWBRO"), ace("LAPRAS"), ace("CLOYSTER") },
    OPP_BRUNO = { ace("MACHAMP"), ace("HITMONLEE"), ace("HITMONCHAN") },
    OPP_AGATHA = { ace("GENGAR"), ace("MISMAGIUS") },
    OPP_LANCE = { ace("DRAGONITE"), ace("GYARADOS") },
    -- Gen 1 Champion (the rival)
    OPP_RIVAL3 = gen1ChampionAces,
    -- Gen 2 Johto gyms
    FALKNER = { ace("PIDGEOTTO", { item = "EVIOLITE" }), ace("NOCTOWL") },
    BUGSY = { ace("SCYTHER", { item = "EVIOLITE" }) },
    WHITNEY = { ace("CLEFAIRY"), ace("MILTANK") },
    MORTY = { ace("GENGAR"), ace("MISMAGIUS") },
    CHUCK = { ace("POLIWRATH"), ace("ANNIHILAPE") },
    JASMINE = { ace("MAGNEZONE"), ace("STEELIX") },
    PRYCE = { ace("PILOSWINE", { item = "EVIOLITE" }), ace("MAMOSWINE") },
    CLAIR = { ace("KINGDRA"), ace("DRAGONAIR", { item = "EVIOLITE" }) },
    -- Gen 2 Kanto gyms
    BROCK = { ace("ONIX", { item = "EVIOLITE" }), mega("STEELIX") },
    MISTY = { ace("POLITOED"), ace("GOLDUCK"), ace("LAPRAS"), ace("QUAGSIRE"),
              mega("STARMIE") },
    LT_SURGE = { ace("PIKACHU", { item = "LIGHTBALL" }), ace("RAICHU_ALOLA"),
                 ace("ELECTIVIRE"),
                 { pick = { mega("RAICHU", "Y"), mega("RAICHU", "X") } } },
    ERIKA = { ace("TANGROWTH"), ace("VICTREEBEL"), tera("VILEPLUME", "POISON") },
    JANINE = { ace("WEEZING"), ace("CROBAT"), mega("BEEDRILL") },
    SABRINA = { ace("MR_MIME"), ace("ESPEON"), mega("ALAKAZAM") },
    BLAINE = { ace("MAGMORTAR"), mega("HOUNDOOM") },
    BLUE = { ace("PIDGEOT"), ace("ALAKAZAM"), ace("RHYPERIOR"),
             ace("EXEGGUTOR"), ace("ARCANINE"), mega("GYARADOS") },
    -- Gen 2 Elite Four
    WILL = { ace("XATU"), mega("SLOWBRO") },
    KOGA = { ace("CROBAT"), ace("ARIADOS"), mega("GENGAR") },
    BRUNO = { ace("HITMONTOP"), ace("HITMONLEE"), ace("HITMONCHAN"),
              ace("ANNIHILAPE"), gmax("MACHAMP") },
    KAREN = { ace("UMBREON"), ace("HONCHKROW"), mega("TYRANITAR") },
    -- Gen 2 Champion (Lance) and the secret final boss (Red)
    CHAMPION = { ace("DRAGONAIR", { item = "EVIOLITE" }), ace("AERODACTYL"),
                 ace("GYARADOS"), dyna("KINGDRA"),
                 ace("DRAGONITE", { tera = "FLYING",
                   alsoMoves = { "HURRICANE" }, nature = "MODEST",
                   ivs = { hp = 31, atk = 31, def = 31, spa = 31, spd = 31, spe = 31 },
                   evs = { hp = 4, atk = 0, def = 0, spa = 252, spd = 0, spe = 252 } }),
                 mega("CHARIZARD", "X") },
    RED = { { pick = { "JOLTEON", "FLAREON", "VAPOREON", "ESPEON", "UMBREON" } },
            ace("SNORLAX"), gmax("CHARIZARD"),
            ace("VENUSAUR", { tera = "FIRE", alsoMoves = { "WEATHERBALL" } }),
            mega("BLASTOISE"),
            ace("PIKACHU_STARTER", { item = "LIGHTBALL",
              moves = { "ZIPPYZAP", "FLOATYFALL", "SPLISHYSPLASH",
                        "PIKA_PAPOW" } }) },
  }

  -- ------------------------------------------------ move sets
  -- The level-up move ids a species knows at `level`, read straight off the
  -- running game's species record (Gen 2 spells them `levelMoves`; Gen 1 has
  -- `level1Moves` + `learnset`).  Only used for a "(inherits X moves)" entry
  -- and for forcing an extra move into one; an ace with neither leaves its
  -- moveset nil and the engine builds the species' own, exactly as every
  -- other trainer mon does.
  local function levelUpMoveIds(data, speciesId, level)
    local def = data and data.pokemon and data.pokemon[speciesId]
    if type(def) ~= "table" then return nil end
    local ids = {}
    local function add(id)
      if type(id) ~= "string" then return end
      for _, existing in ipairs(ids) do if existing == id then return end end
      ids[#ids + 1] = id
    end
    if type(def.levelMoves) == "table" then
      for _, entry in ipairs(def.levelMoves) do
        if type(entry) == "table" and (entry.level or 0) <= level then
          add(entry.move)
        end
      end
    else
      if type(def.level1Moves) == "table" then
        for _, id in ipairs(def.level1Moves) do add(id) end
      end
      if type(def.learnset) == "table" then
        for _, entry in ipairs(def.learnset) do
          if type(entry) == "table" and (entry.level or 0) <= level then
            add(entry.move)
          end
        end
      end
    end
    while #ids > 4 do table.remove(ids, 1) end
    return #ids > 0 and ids or nil
  end

  -- Every spelling of the fourth Let's Go partner-Pikachu move ("Pika Papow").
  -- The national_dex build this repo references registers Zippy Zap, Floaty
  -- Fall and Splishy Splash but NOT Pika Papow, so a hard-coded id can be an
  -- empty move slot.  Ask the RUNNING game's move table for each spelling and
  -- only fall back to Thunderbolt when none is present -- so a build that does
  -- have the real move uses it, and every other build still gets four moves.
  local PIKA_PAPOW_IDS = { "PIKA_PAPOW", "PIKAPAPOW", "PIKAPOW" }
  local function isPikaPapow(id)
    for _, candidate in ipairs(PIKA_PAPOW_IDS) do
      if id == candidate then return true end
    end
    return false
  end
  local function resolveMoveId(data, id)
    local moves = data and data.moves
    if type(moves) ~= "table" then
      return isPikaPapow(id) and "THUNDERBOLT" or id
    end
    if moves[id] then return id end
    if isPikaPapow(id) then
      for _, candidate in ipairs(PIKA_PAPOW_IDS) do
        if moves[candidate] then return candidate end
      end
      return "THUNDERBOLT"
    end
    return id
  end

  local function computeAceMoves(data, spec, level)
    local moves
    if type(spec.moves) == "table" and #spec.moves > 0 then
      moves = {}
      for _, id in ipairs(spec.moves) do
        moves[#moves + 1] = resolveMoveId(data, id)
      end
    else
      moves = levelUpMoveIds(data, spec.movesFrom or spec.species, level)
      if moves then
        local copy = {}
        for _, id in ipairs(moves) do copy[#copy + 1] = id end
        moves = copy
      end
    end
    if moves and type(spec.alsoMoves) == "table" then
      for _, extra in ipairs(spec.alsoMoves) do
        local present = false
        for _, id in ipairs(moves) do if id == extra then present = true end end
        if not present then
          moves[#moves + 1] = extra
          while #moves > 4 do table.remove(moves, 1) end
        end
      end
    end
    return moves
  end

  -- ------------------------------------------------ property application
  -- The stored gimmick/item fields, applied to a real mon object.  The
  -- engine's own setters are used when this engine exposes them (they also
  -- mirror the value into battle_forms' own field), with a plain-field
  -- fallback so this still works against an older engine.
  local ACE_STAT_KEYS = { "hp", "atk", "def", "spa", "spd", "spe" }

  local function applyAceStats(mon, spec)
    local MS = engineExports() and engineExports().ModernStats
    if not (type(MS) == "table" and type(MS.applySpec) == "function") then return end
    local ivs = spec.ivs or mon.ivs
    local evs = spec.evs or mon.evs
    local nature = spec.nature or mon.nature
    local order = MS.ORDER
    if type(order) ~= "table" then order = ACE_STAT_KEYS end
    local specT = { nature = nature }
    for _, k in ipairs(order) do
      specT[k] = { iv = (type(ivs) == "table" and ivs[k]) or 31,
                   ev = (type(evs) == "table" and evs[k]) or 0 }
    end
    if not pcall(MS.applySpec, mon, specT) then return end
    if type(MS.recalcAll) == "function" then
      local data = dataNow()
      local nd = mod.find and mod.find("national_dex")
      local def = data and data.pokemon and data.pokemon[mon.species]
      if type(MS.resolveBase) == "function" then
        local ok, resolved = pcall(MS.resolveBase, mon.species, def,
          nd and nd.exports)
        if ok and type(resolved) == "table" then def = resolved end
      end
      if type(def) == "table" then pcall(MS.recalcAll, def, mon) end
    end
    local maxHp = tonumber(mon.maxHp) or (type(mon.stats) == "table" and tonumber(mon.stats.hp))
    if maxHp and tonumber(mon.hp) and mon.hp > maxHp then mon.hp = maxHp end
  end

  local function applyAceToMon(mon, spec)
    if type(mon) ~= "table" or type(spec) ~= "table" then return end
    if spec.item then mon.item = spec.item end
    local ex = engineExports()
    if spec.tera then
      local setter = ex and ex.setTeraType
      local ok = type(setter) == "function" and pcall(setter, mon, spec.tera)
      if not ok then
        mon.teraType = spec.tera
        mon.battleFormsTeraType = spec.tera
      end
    end
    if spec.gmax then
      local setter = ex and ex.setGigantamaxFactor
      local ok = type(setter) == "function" and pcall(setter, mon, true)
      if not ok then mon.gigantamaxFactor = true end
    end
    if spec.gmax or spec.dyna then
      local setter = ex and ex.setMonDynamaxLevel
      local ok = type(setter) == "function" and pcall(setter, mon, 10)
      if not ok then mon.dynamaxLevel = 10 end
    end
    if spec.nature or spec.evs or spec.ivs then applyAceStats(mon, spec) end
  end

  -- One `pick` alternative resolved for this battle (a bare species string is
  -- just that species).  Called once per slot, at BOTH the injection and the
  -- property pass, so the two agree by construction (the property pass
  -- matches the resolved species against the mon actually standing there).
  local function resolveAcePick(spec)
    if type(spec) ~= "table" then return nil end
    if type(spec.pick) == "table" and #spec.pick > 0 then
      local alt = spec.pick[love.math.random(1, #spec.pick)]
      if type(alt) == "string" then return ace(alt) end
      return alt
    end
    return spec
  end

  local function concreteAceSpec(spec, species)
    if type(spec) ~= "table" then return nil end
    if type(spec.pick) == "table" then
      for _, alt in ipairs(spec.pick) do
        local resolved = (type(alt) == "string") and ace(alt) or alt
        if type(resolved) == "table" and resolved.species == species then
          return resolved
        end
      end
      return nil
    end
    if spec.species == species then return spec end
    return nil
  end

  -- A party entry is a real Mon object when it carries the Gen 1/Gen 2 stat
  -- fields the randomizer's own mon/row test keys on (see randomizeParty).
  local function isMonEntry(entry)
    return type(entry) == "table"
      and (type(entry.stats) == "table" or type(entry.dvs) == "table")
  end

  local function buildAceEntry(data, spec, level, monMode)
    if type(spec) ~= "table" or type(spec.species) ~= "string" then return nil end
    level = tonumber(level) or 5
    local ids = computeAceMoves(data, spec, level)
    if monMode then
      local ok, Mon = pcall(require, "src.battle.gen2.Mon")
      if not (ok and type(Mon) == "table" and type(Mon.new) == "function") then
        return nil
      end
      local opts = {}
      if spec.item then opts.item = spec.item end
      if ids then
        local slots = {}
        for _, id in ipairs(ids) do
          local md = data and data.moves and data.moves[id]
          slots[#slots + 1] = { id = id, pp = md and md.pp or 0,
            maxPp = md and md.pp or 0 }
        end
        opts.moves = slots
      end
      local okNew, mon = pcall(Mon.new, data, spec.species, level, opts)
      if not (okNew and type(mon) == "table") then return nil end
      mon.__g9sampleAce = true
      -- The RESOLVED spec (a `pick` already chosen), so the later property
      -- pass re-applies the very same item/gimmick rather than re-rolling
      -- an ambiguous pick (Lt. Surge's Raichu X/Y share a species).
      mon.__g9sampleAceSpec = spec
      applyAceToMon(mon, spec)
      return mon
    end
    -- A Gen 1 row: the base engine's own builder reads species/level/moves
    -- only, so the held item and the gimmick fields are applied to the real
    -- mon later (see applyLeagueAceProperties).  (The spec stamp is carried
    -- too, but a built Pokemon does not keep it -- the property pass then
    -- matches by species instead, which is exact because no Gen 1 ace is a
    -- `pick`.)
    return { species = spec.species, level = level, moves = ids,
             item = spec.item, __g9sampleAce = true, __g9sampleAceSpec = spec }
  end

  -- ------------------------------------------------ the public seams
  -- An entry that is a FUNCTION (only the Gen 1 champion, whose set is rolled
  -- fresh each battle) must resolve to the SAME set for a whole fight:
  -- `applyLeagueAces` builds the rows from it and `applyLeagueAceProperties`
  -- later matches those rows' species to apply their items/gimmicks.  The
  -- roll is therefore memoised for the build+property pair and cleared at the
  -- next `applyLeagueAces` (the one place a trainer's party is built).  The
  -- PUBLIC leagueAcesFor below deliberately rolls fresh every call.
  local rolledEntry = nil
  local function acesForBuild(classId, memberId)
    if type(classId) ~= "string" then return nil end
    if not leagueAcesOn() then return nil end
    local entry = LEAGUE_ACES[classId]
    if entry == nil then return nil end
    if type(entry) == "function" then
      if rolledEntry == nil then rolledEntry = entry(classId, memberId) end
      entry = rolledEntry
    end
    if type(entry) ~= "table" or #entry == 0 then return nil end
    return entry
  end

  -- What the champion will field, rolled fresh: the row the OPTIONS menu and
  -- any caller reads.
  function shared.leagueAcesFor(classId, memberId)
    if type(classId) ~= "string" then return nil end
    if not leagueAcesOn() then return nil end
    local entry = LEAGUE_ACES[classId]
    if entry == nil then return nil end
    if type(entry) == "function" then entry = entry(classId, memberId) end
    if type(entry) ~= "table" or #entry == 0 then return nil end
    return entry
  end

  -- Replace the final slots with the aces.  Returns the SAME array whenever
  -- nothing is done (row off, not a league class, or the party already
  -- carries an ace), so the engine's own identity-preserving passes are
  -- undisturbed.
  function shared.applyLeagueAces(party, classId, memberId)
    if type(party) ~= "table" or #party == 0 then return party end
    rolledEntry = nil -- a new party build re-rolls the champion's set
    local aces = acesForBuild(classId, memberId)
    if not aces then return party end
    for i = 1, #party do
      local entry = party[i]
      if type(entry) == "table" and entry.__g9sampleAce then return party end
    end
    local data = dataNow()
    local monMode = isMonEntry(party[1])
    local n = #aces
    local keep = #party - n
    if keep < 0 then keep = 0 end
    local fallbackLevel = party[#party] and party[#party].level or 5
    local out = {}
    for i = 1, keep do out[i] = party[i] end
    for i = 1, n do
      local src = party[keep + i]
      local level = (src and src.level) or fallbackLevel
      local spec = resolveAcePick(aces[i])
      out[keep + i] = buildAceEntry(data, spec, level, monMode) or src
    end
    return out
  end

  -- Apply the stored item/gimmick/stat properties to the aces already in
  -- `team` (the last N slots).  Idempotent, so the Gen 1 scene path and the
  -- battle.started listener can both call it.
  function shared.applyLeagueAceProperties(team, classId, memberId)
    if type(team) ~= "table" or #team == 0 then return end
    local aces = acesForBuild(classId, memberId)
    if not aces then return end
    local start = #team - #aces + 1
    if start < 1 then start = 1 end
    for i, spec in ipairs(aces) do
      local mon = team[start + i - 1]
      if type(mon) == "table" and type(mon.species) == "string" then
        -- The mon's own stamped spec wins: it is the `pick` alternative that
        -- was actually built, so a re-apply can never flip it to a sibling.
        local concrete = mon.__g9sampleAceSpec
          or concreteAceSpec(spec, mon.species)
        if concrete then applyAceToMon(mon, concrete) end
      end
    end
  end

  -- The NATIVE-battle seam, both generations: BattleState:enter emits
  -- battle.started on Gen 1 and Battle.new on Gen 2, and the enemy party is
  -- already built and reachable as battle.enemyParty by then.  A scene fight
  -- on Gen 1 is handled instead from the pushBattle wrap (installGen1's
  -- tryDivert), because the custom screen builds its own view before this
  -- event fires.
  mod.events:on("battle.started", function(ev)
    local battle = ev and ev.battle
    if type(battle) ~= "table" then return end
    local classId = battle.oppClass
    if type(classId) ~= "string" and type(battle.trainer) == "table" then
      classId = battle.trainer.classId or battle.trainer.class
    end
    if type(classId) ~= "string" then return end
    shared.applyLeagueAceProperties(battle.enemyParty, classId,
      battle.partyIndex)
  end)

  mod.log:info("g9_battle_sample: LEAGUE ACES installed")
end

-- Which arm to install.  GameVersion is the engine's own answer, and the same
-- one g9-Battle-Scene's own native.lua reads; a boot that cannot answer (a
-- trimmed build under test) is treated as Gen 1, the engine's own default.
-- Gold, Silver and Crystal are all generation 2 in this engine (src/core/
-- Game2.lua loads src.world.gen2.World for every one of them), so "gen2" here
-- means all three.
return function(mod)
  local gen = 1
  local ok, GameVersion = pcall(require, "src.core.GameVersion")
  if ok and GameVersion and GameVersion.generation then
    local okGen, value = pcall(GameVersion.generation)
    if okGen and (value == 1 or value == 2) then gen = value end
  end
  -- The generation-agnostic systems (species randomizer, difficulty
  -- provider, combat-type routing helpers) install first, whatever the
  -- generation -- both arms consume the same `shared` table.
  local shared = installRandomizer(mod, gen)
  -- LEAGUE ACES is generation-agnostic too (the same party hook and the same
  -- battle.started event on both gens), and installs from its own top-level
  -- function to keep installRandomizer's local budget untouched.
  local okAces, acesErr = pcall(installLeagueAces, mod, shared)
  if not okAces then
    mod.log:warn("g9_battle_sample: LEAGUE ACES install failed: %s",
      tostring(acesErr))
  end
  -- The BLACKLIST window is generation-agnostic too (one ui.options.rows hook,
  -- both gens); it reads and writes the blacklist state installRandomizer owns.
  local okBlack, blackErr = pcall(installBlacklist, mod, gen, shared)
  if not okBlack then
    mod.log:warn("g9_battle_sample: BLACKLIST screen install failed: %s",
      tostring(blackErr))
  end
  if gen == 2 then
    return installGen2(mod, shared)
  end
  return installGen1(mod, shared)
end
