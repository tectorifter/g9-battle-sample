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
      description = "ON: beating a trainer -- a first fight or a rematch (see REBATTLES) -- can drop one random NON-KEY item (drawn from the game's whole item list, same pool as ITEM RANDOMIZER) into your bag, shown as an ordinary \"{PLAYER} found X!\" box the moment you are back on the map. Whether a given win pays out is TRAINER ITEM CHANCE (100% by default). Key items are never dropped. If the bag pocket is full the item is quietly lost rather than shown, exactly as a real pickup would be. Works on both generations.",
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
  })

  local function option(key) return mod.options:get(key) end
  local function randWildsOn() return option("rand_wilds") == true end
  local function randTrainersOn() return option("rand_trainers") == true end
  local function difficulty() 
    local value = option("difficulty")
    if value == "easy" or value == "normal" or value == "hard" or value == "hell" then
      return value
    end
    return "normal"
  end

  -- ------------------------------------------------------------- live data
  -- require("src.core.Game") is the Gen2Compat-provided facade, so .data
  -- resolves against whichever game is actually running (same helper the
  -- engine's own install_gym_trainer_teams.lua uses).
  local function liveData()
    local ok, Game = pcall(require, "src.core.Game")
    if ok and type(Game) == "table" then return Game.data end
    return nil
  end

  -- ---------------------------------------------------------- species pool
  -- data.pokemon is the merged content registry (the cart's own species
  -- plus everything national_dex registered), so this is the "national dex
  -- expanded entries" pool the user asked for -- forms included -- without
  -- paying for a deepCopy per species the way national_dex's read API does.
  -- Built once, on first use, then cached: the roster does not change at
  -- runtime and a wild encounter should never walk ~1500 records.
  local pool, byType
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

  -- A random species sharing at least one type with origId and whose base
  -- total lands in the user's band: 95% of the original's BST up to
  -- 100% + 5*level percentage points of it.  Returns nil (leave the mon
  -- alone) when the species is unknown or nothing qualifies -- never a
  -- forced substitute.
  local function pickSpecies(origId, level)
    if not pool then return nil end
    local orig = pool[origId]
    if not orig then return nil end
    local low = orig.bst * 0.95
    local high = orig.bst * (1 + 5 * (tonumber(level) or 1) / 100)
    local seen, candidates = {}, {}
    for _, t in ipairs(orig.types) do
      for _, e in ipairs(byType[t] or {}) do
        if not seen[e.id] and e.id ~= origId
            and e.bst >= low and e.bst <= high then
          seen[e.id] = true
          candidates[#candidates + 1] = e.id
        end
      end
    end
    if #candidates == 0 then return nil end
    return candidates[love.math.random(1, #candidates)]
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
  -- battle.started listener.  Priority 100 deliberately outranks the
  -- engine's own gym_trainer_teams provider (priority 50) so the DIFFICULTY
  -- setting governs every trainer, including the 22 roster-replaced ones.
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
  function shared.randomizeParty(party, data)
    if type(party) ~= "table" then return party end
    if not randTrainersOn() then return party end
    data = data or liveData()
    if not buildPool(data) then return party end
    local out, changed = {}, false
    for i = 1, #party do
      local entry = party[i]
      if type(entry) == "table" and type(entry.species) == "string"
          and not entry.__g9sampleRand then
        local newId = pickSpecies(entry.species, entry.level)
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
  local function buildExtraMember(data, template, party)
    if type(template) ~= "table" then return nil end
    local level = teamLevel(template, party)
    local newId = template.species
    if randTrainersOn() and buildPool(data) then
      newId = pickSpecies(template.species, level) or template.species
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
  function shared.padTrainerParty(party, data)
    if type(party) ~= "table" or #party == 0 then return party end
    local want = minTeamSize()
    if want <= #party then return party end
    data = data or liveData()
    local out = {}
    for i = 1, #party do out[i] = party[i] end
    while #out < want do
      local template = party[love.math.random(1, #party)]
      local mon = buildExtraMember(data, template, party)
      if not mon then break end
      out[#out + 1] = mon
    end
    if #out == #party then return party end
    return out
  end
  shared.minTeamSize = minTeamSize

  mod.hooks:wrap("encounter.species", function(nextFn, enc, ctx)
    local rolled = nextFn(enc, ctx)
    if not randWildsOn() then return rolled end
    if type(rolled) ~= "table" or type(rolled.species) ~= "string" then
      return rolled
    end
    local data = (ctx and ctx.data) or liveData()
    if buildPool(data) then
      local newId = pickSpecies(rolled.species, rolled.level)
      if newId then rolled.species = newId end
    end
    return rolled
  end, 0)

  mod.hooks:wrap("trainer.party", function(nextFn, classId, memberId, party)
    local result = nextFn(classId, memberId, party)
    -- Difficulty team floor first, then the cumulative rebattle levels (Gen 1
    -- only -- on Gen 2 the bonus is applied once, in the arm's own
    -- World:startBattle wrap, because this hook runs a second time inside the
    -- scene's own model build there), then the species swap (added mons are
    -- tagged, so the swap leaves them exactly as built).
    result = shared.padTrainerParty(result)
    if gameGen == 1 then
      result = shared.scaleGen1RebattleLevels(classId, memberId, result)
    end
    return shared.randomizeParty(result)
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

  function shared.layoutForClass(classId)
    if type(classId) == "string" and BOSS_CLASSES[classId] then
      return "bossFight"
    end
    if type(classId) == "string" and E4_CLASSES[classId] then
      return (love.math.random(1, 2) == 1) and "doubles" or "triples"
    end
    return "doubles"
  end

  function shared.isBossClass(classId)
    return type(classId) == "string" and BOSS_CLASSES[classId] == true
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
  -- had: an item randomizer, an item respawn timer, rebattles, a cumulative
  -- +level per rebattle, and a random item drop from a beaten trainer.
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
  local function rebattlesOn() return option("rebattles") == true end
  local function trainerDropOn() return option("trainer_item_drop") == true end
  shared.itemRandomizerOn = itemRandomizerOn
  shared.itemRespawnOn = itemRespawnOn
  shared.rebattlesOn = rebattlesOn
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

  -- The cumulative per-rebattle level step, 0 when OFF.  Every step is read
  -- live off the Manager, so changing it takes effect on the next fight.
  local REBATTLE_STEPS = { ["1"] = 1, ["2"] = 2, ["4"] = 4, ["8"] = 8,
                           ["16"] = 16 }
  local function rebattleStep()
    if option("rebattle_levels") == "off" then return 0 end
    return REBATTLE_STEPS[tostring(option("rebattle_levels"))] or 0
  end
  -- Wins are only tallied while at least one of the two rebattle settings
  -- wants them, so a player who never turns this on pays nothing for it.
  local function rebattleTracking()
    return rebattlesOn() or rebattleStep() > 0
  end

  local RESPAWN_SECONDS = { ["30s"] = 30, ["1m"] = 60, ["2m"] = 120,
                            ["3m"] = 180, ["4m"] = 240, ["5m"] = 300 }
  local function respawnInterval()
    return RESPAWN_SECONDS[tostring(option("respawn_timer"))] or 60
  end
  shared.rebattleStep = rebattleStep
  shared.rebattleTracking = rebattleTracking
  shared.respawnInterval = respawnInterval

  -- The live save, through the same Gen2Compat-backed require liveData uses,
  -- so .save resolves against whichever game is actually running.
  local function liveSave()
    local ok, Game = pcall(require, "src.core.Game")
    if ok and type(Game) == "table" then return Game.save end
    return nil
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
  -- Every real, non-key item the game knows about, as one cached list.  TMs
  -- and HMs are deliberately IN the pool: the user asked for non-key items,
  -- and no HM is ever placed in an item ball or a hidden spot (HMs in both
  -- generations come from scripted gifts), so drawing one cannot soft-lock a
  -- run.  Built once, then cached -- the item table does not change at
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
          and rec.name ~= "" and not shared.isKeyItemId(id, rec) then
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

  -- ------------------------------------------------------- rebattle store
  -- How many times each trainer has been beaten, in the mod's OWN namespace --
  -- mod.save, which is save.modData[g9-battle-sample] -- because that is the
  -- save model's one rule for mod state (namespaced, never mixed into engine
  -- tables) and it is the same bucket on both generations.  get hands back the
  -- live table and set stores that same table, so the tallies accumulate with
  -- one write per win and survive a save/reload.  The key is the same string
  -- on both generations (class/member for a Gen 2 map object's own header,
  -- class/party-index on Gen 1), which is what makes the +level ramp and the
  -- win tally line up whichever seam saw the fight.
  local function rebattleStore(create)
    local store = mod.save:get("rebattles")
    if type(store) ~= "table" then
      if not create then return nil end
      store = {}
      mod.save:set("rebattles", store)
    end
    return store
  end

  function shared.rebattleCount(key)
    if type(key) ~= "string" then return 0 end
    local store = rebattleStore(false)
    local n = store and store[key]
    return type(n) == "number" and n or 0
  end

  function shared.noteTrainerWin(key)
    if type(key) ~= "string" then return end
    local store = rebattleStore(true)
    if not store then return end
    store[key] = (type(store[key]) == "number" and store[key] or 0) + 1
  end

  -- The level bonus the UPCOMING fight against `key` should get: 0 for the
  -- first fight, one step for the second, two for the third, and so on.
  function shared.rebattleBonus(key)
    local step = rebattleStep()
    if step <= 0 then return 0 end
    return step * shared.rebattleCount(key)
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
  function shared.scaleGen1RebattleLevels(classId, memberId, party)
    if type(party) ~= "table" or #party == 0 or rebattleStep() <= 0 then
      return party
    end
    local key = tostring(classId) .. "/" .. tostring(memberId or 1)
    local bonus = shared.rebattleBonus(key)
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
    local exportMod = mod.find("g9-Battle-Scene")
    local save = self.game and self.game.save
    if not (exportMod and exportMod.exports and exportMod.exports.pushLayoutBattle
        and save and save.party) then
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
    opts.trainer.party = shared.randomizeParty(
      shared.padTrainerParty(opts.trainer.party))
    local classId = opts.trainer.classId or opts.trainer.class
    local layoutName = shared.layoutForClass(classId)
    -- A ONE-Pokemon trainer cannot fill a doubles preset -- the scene needs a
    -- second enemy to stand in that layout's other slot -- so it is routed to
    -- "singles" here instead of being handed to the `#enemies < 2` bail below,
    -- which used to send the fight to the ORDINARY (vanilla) battle screen.
    -- The first Gen 2 rival battle is the case that surfaced this: RIVAL1, the
    -- single stolen starter, at Cherrygrove, and on EASY (vanilla team size --
    -- no difficulty padding) it stayed one mon and fell all the way through to
    -- native.  An intentional boss layout keeps its own preset even at one
    -- mon, so the Champion/Red single-boss shape is untouched.
    if #opts.trainer.party < 2 and not shared.isBossClass(classId) then
      layoutName = "singles"
    end
    local layoutData = exportMod.exports.getLayoutData
      and exportMod.exports.getLayoutData(layoutName)
    if not layoutData then return false end
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
    local players = {}
    for i = 1, allyCount do
      if save.party[i] then players[#players + 1] = save.party[i] end
    end
    local pushed = exportMod.exports.pushLayoutBattle(layoutName, self.game, self, {
      enemies = enemies,
      players = players,
      trainer = opts.trainer,
    })
    if not pushed then
      mod.log:warn("g9_battle_sample: no " .. layoutName .. " preset on "
        .. "the export mod, falling back to the ordinary trainer battle")
      return false
    end
    if shared.isBossClass(classId) then shared.applyBossFlags(pushed) end
    return true
  end

  local nativeStartBattle = World.startBattle
  function World:startBattle(opts, onDone)
    -- Cumulative +level per rebattle (see installRandomizer's own note on the
    -- setting).  Applied HERE, once per fight: opts.trainer is already built
    -- by the caller (World:startScriptedBattle assembles it a few lines above
    -- its own call), Battle.new then builds self.enemyParty out of exactly
    -- opts.trainer.party, and Mon.refreshStats runs over that array right
    -- after the trainer.party hook -- so a level bump lands on the real
    -- battlers without a second stat pass here.  Done in the hook instead
    -- would run twice, because this same roster also travels through the
    -- scene's own model build.
    if opts and opts.trainer and type(opts.trainer.party) == "table" then
      local bonus = shared.rebattleBonus(shared.trainerKeyOf(opts.trainer))
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
    if opts and opts.wild and opts.wild.species == "ETERNATUS"
        and opts.wild.level == 75
        and not opts.roaming and not opts.contest and not opts.tutorial then
      local exportMod = mod.find("g9-Battle-Scene")
      local save = self.game and self.game.save
      if exportMod and exportMod.exports and exportMod.exports.pushLayoutBattle
          and save and save.party then
        local layoutData = exportMod.exports.getLayoutData
          and exportMod.exports.getLayoutData("bossFight")
        local allyCount = math.max(1, math.min(6, (layoutData and layoutData.allyCount) or 4))
        local players = {}
        for i = 1, allyCount do
          if save.party[i] then players[#players + 1] = save.party[i] end
        end
        local pushed = exportMod.exports.pushLayoutBattle("bossFight", self.game, self, {
          enemies = { opts.wild },
          players = players,
        })
        if pushed then return true end
        mod.log:warn("g9_battle_sample: no bossFight preset on the export "
          .. "mod, falling back to the ordinary battle screen for Eternatus")
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
    local exportMod = mod.find("g9-Battle-Scene")
    if not (exportMod and exportMod.exports and exportMod.exports.pushLayoutBattle) then
      mod.log:warn("g9_battle_sample: g9-Battle-Scene not available, "
        .. "falling back to a single wild battle")
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
    local layoutName, isBossWild = shared.rollWildLayout(multiAlly)

    -- Every extra enemy slot beyond the one real wild roll clones that
    -- roll's own species/level (this file's own header, "Deliberately
    -- simplified... extra enemy slots... clone that roll's own species/
    -- level rather than rolling distinct wild mons per slot" -- this
    -- engine's own tryWildEncounter commits to exactly one real roll,
    -- there is no second, independent roll to ask for) -- which already
    -- satisfies the horde's own real rule ("roll only one species and set
    -- it to all 5 Pokemon") for free, via the SAME clone loop below
    -- doubles/triples already used, no horde-specific branch needed.
    local layoutData = exportMod.exports.getLayoutData and exportMod.exports.getLayoutData(layoutName)
    local enemyCount = math.max(1, math.min(6, (layoutData and layoutData.enemyCount) or 1))
    local allyCount = math.max(1, math.min(6, (layoutData and layoutData.allyCount) or 2))

    local enemies = { capturedOpts.wild }
    for _ = 2, enemyCount do
      enemies[#enemies + 1] = Mon.new(self.game.data, capturedOpts.wild.species, capturedOpts.wild.level)
    end
    -- x1..x5 max HP for the 0.5% boss wild, before the scene reads it.
    if isBossWild then shared.scaleWildHp(capturedOpts.wild) end

    local players = {}
    for i = 1, allyCount do
      if save.party[i] then players[#players + 1] = save.party[i] end
    end

    local pushed = exportMod.exports.pushLayoutBattle(layoutName, self.game, self, {
      enemies = enemies,
      players = players,
    })
    if not pushed then
      mod.log:warn("g9_battle_sample: no " .. layoutName .. " preset on the export mod, "
        .. "falling back to a single wild battle")
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

  -------------------------------------------------------------- rebattles
  -- TalkToTrainerScript with its two beaten-check rows (the `trainerflagaction
  -- CHECK_FLAG` and the `iftrue` that jumps to scripttalkafter) taken out and
  -- nothing else touched.  Its tail is kept because both of those rows are
  -- idempotent: SET_FLAG on an already-set flag is a silent no-op, and
  -- scripttalkafter is what a first-time fight shows too.
  local REBATTLE_TALK_SCRIPT = {
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

  -- A press on a beaten trainer starts a rematch.  interactBody seams the
  -- Gen 1 talkTo dispatch in through Gen1Facade.talkToWrapper once the object
  -- is resolved, and a `true` return suppresses the built-in path -- which for
  -- a beaten trainer is TALK_TO_TRAINER_SCRIPT, i.e. only its after-battle
  -- line.  An object whose A press is a hand-ported script (def.scriptKey) is
  -- left alone, and anything this wrap does not claim falls through to
  -- whatever held the seam before it (the facade's own default is a bare
  -- `return false`, so a mod-free press behaves exactly as it did).
  local nativeTalkTo = ow.talkTo
  ow.talkTo = function(world, npc)
    local def = npc and npc.def
    local header = def and def.trainer
    if shared.rebattlesOn() and type(header) == "table" and not def.scriptKey
        and world:trainerBeaten(header) then
      world:startTrainerScript(npc, REBATTLE_TALK_SCRIPT, nil)
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
    if key and shared.rebattleTracking() then shared.noteTrainerWin(key) end
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

  mod.log:info("g9_battle_sample: every wild encounter routes to "
    .. "g9-Battle-Scene -- 0.5%% \"bossFight\" (x1..x5 HP + random flags), then "
    .. "1%% \"hordes\", 2%% \"triples\", 10%% \"doubles\", ~86%% \"singles\" (the "
    .. "native scene is never called); every 2+-mon trainer battle routes to "
    .. "\"doubles\", the Elite Four rolls doubles/triples, and the Champion and "
    .. "Red route to \"bossFight\"; wild_forms's Eternatus-as-Eternamax static "
    .. "routes to \"bossFight\"")
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
  -- party[1] is fainted.
  local function playerRoster(count)
    local players = {}
    for _, mon in ipairs((Game.save and Game.save.party) or {}) do
      if #players >= count then break end
      if mon and (mon.hp or 0) > 0 then players[#players + 1] = mon end
    end
    return players
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
    local exportMod = mod.find("g9-Battle-Scene")
    if not (exportMod and exportMod.exports
        and exportMod.exports.pushLayoutBattle) then
      mod.log:warn("g9_battle_sample: g9-Battle-Scene not available, "
        .. "falling back to the ordinary Gen 1 battle screen")
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
      local padded = shared.padTrainerParty(team)
      if padded ~= team then
        battle.enemyParty = padded
        team = padded
      end
      if #team < 2 then return false end
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
      -- Combat type, matching the Gen 2 arm's 2026-09-12 rule: the Elite
      -- Four roll doubles-or-triples per battle, the Champion (OPP_RIVAL3
      -- on Gen 1) gets the bossFight layout, everyone else is a doubles.
      layoutName = shared.layoutForClass(battle.oppClass)
      -- The FULL team, not a slice -- the scene benches the extra mons for
      -- a trainer battle and sends them in as actives faint (see the Gen 2
      -- arm's own note).
      enemies = {}
      for i = 1, #team do
        enemies[#enemies + 1] = team[i]
      end
      if #enemies < 2 then return false end
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
        layoutName, isBossWild = shared.rollWildLayout(multiAlly)
        -- Every extra enemy slot clones the one real roll's own species/level
        -- (this engine's tryWildEncounter commits to exactly one roll; there
        -- is no second, independent roll to ask for), which already satisfies
        -- the horde's own "all of them the same species" rule for free.
        local enemyCount = rosterSize(exportMod, layoutName, "enemyCount", 1)
        enemies = { enemy }
        for _ = 2, enemyCount do
          enemies[#enemies + 1] = Pokemon.new(Game.data, enemy.species,
            enemy.level)
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
  -- ITEM RANDOMIZER / ITEM RESPAWN / REBATTLES / TRAINER DROPS -- Gen 1.
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
  local function canRebattle(self, d)
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
    -- A press on a beaten trainer, when REBATTLES is on, is a rematch: the
    -- same two calls talkTo itself makes for a living trainer (native sets
    -- npc.frozen at its top, hence the matching unfreeze).  checkVictoryRewards
    -- runs inside engageTrainer and early-returns on an already-claimed
    -- reward, so a badge or TM is never handed out a second time.
    if shared.rebattlesOn() and d.trainerClass and self:trainerDefeated(npc)
        and canRebattle(self, d) then
      npc.frozen = true
      self:makeNpcFacePlayer(npc)
      self:engageTrainer(npc, function() npc.frozen = false end)
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
      if shared.rebattleTracking() then shared.noteTrainerWin(key) end
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

  mod.log:info("g9_battle_sample: Gen 1 wild encounters route to "
    .. "g9-Battle-Scene (0.5%% \"bossFight\" with x1..x5 HP + random flags, "
    .. "1%% \"hordes\", 2%% \"triples\", 10%% \"doubles\", ~86%% \"singles\"); "
    .. "every 2+-mon trainer battle routes to \"doubles\", the Elite Four "
    .. "rolls doubles/triples, and the Champion (OPP_RIVAL3) routes to "
    .. "\"bossFight\"; wild_forms's Eternatus-as-Eternamax static routes to "
    .. "\"bossFight\"")
end

-- ============================================================= TRAIN screen
--
-- 2026-09-14, explicit user request: a "TRAIN" row in the party submenu, on
-- BOTH generations, that opens a two-screen editor for the selected Pokemon.
-- Modeled on the engine's own Adv.Stats party screen (stats/dev_stats_screen
-- .lua) -- the confirmed-working pattern on both generations: a plain window
-- (Gen 1 192x173, Gen 2 160x144) that never touches Renderer:setUISize, the
-- same ui.party.submenu hook, {id=,label=,onSelect=} rows, and a pcall-guarded
-- update/draw pair that pops the screen instead of raising.
--
--   Screen one -- STATS: IV / EV / Nature / gender.
--     A framed tab strip across the top -- IV, EV, NAT, the <male>/<female>
--     symbols and MOVES -- walked with LEFT/RIGHT; the gender tab prints BOTH
--     symbols as its label with a rule under the one currently set, and the
--     footer's gender box prints that one symbol on its own, so the tab is the
--     menu and the footer is the value; UP/DOWN from it drops to
--     the APPLY button under the table.  Every option on the screen is drawn
--     inside a rectangle rather than as bracketed text, and the option the
--     cursor is on is framed twice (explicit user spec).  The six stats
--     (ModernStats.ORDER) are always listed with their IV, EV and resulting
--     stat in framed rows.  On IV/EV, A enters the rows, LEFT/RIGHT cycles the
--     + / - / 0 / 31 buttons, UP/DOWN walks the six stats and A applies the
--     chosen button; on NAT and the gender tab, LEFT/RIGHT (or A) changes that
--     value directly.  A on MOVES opens screen two.  Every change is committed
--     through the battle engine's
--     OWN ModernStats.recalcAll -- the same function stats/ev_yield_on_faint
--     .lua uses -- with the current damage carried across, so the edited
--     numbers are what g9-battle-engine's combat reads.  A committed mon is
--     flagged (mon.g9TrainEdited) so the NATIVE recomputes re-apply the edit
--     instead of silently undoing it:
--       * Gen 2: src/ui/gen2/PartyMenu.lua calls Mon.refreshStats on EVERY
--         party-menu open and Battle.new does on every battle start, both
--         rebuilding mon.stats from dvs/statExp -- Mon.refreshStats is wrapped
--         so an edited mon's modern stats are re-applied right after.
--       * pokemon.level_up (raised by both generations' own experience code
--         after the level change) re-applies at the new level.
--       * battle.started re-applies for the whole party (Gen 2's Battle.new
--         runs its refresh BEFORE it raises that event).
--     Gen 1 also keeps mon.stats.special complete, mirrored from Spa: the
--     native Stats.ensure rebuilds a stat block from DVs when any of its five
--     Gen 1 keys is missing, which would otherwise quietly undo the edit.
--     All edits live on the mon itself (ivs/evs/nature/gender), so they ride
--     the save like any other field.
--
--   Screen two -- MOVES: Egg, Relearn (level-up) and Tutor moves the species
--     can learn, straight from national_dex's UNFILTERED movepool
--     (statsBySpecies(id).movesFull / .movesByMethod), each costing 5000.
--     Machines are deliberately NOT offered -- neither TMs nor TRs, explicit
--     user spec, so movesByMethod.machine is never read -- and a move the mon
--     already knows is never listed.  A move g9-battle-engine cannot actually
--     run yet (its own isMoveUsable) is filtered out too.  A full moveset asks
--     which slot to forget; an HM slot is refused, exactly like the native
--     move deleter.  Money is read/written through the same Gen2Compat-backed
--     save the rest of this mod uses (save.money on Gen 1, save.player.money
--     on Gold).
local function installTrainScreen(mod, gen, shared)
  local engine = mod.find and mod.find("g9-battle-engine")
  local engineExports = engine and engine.exports
  local ModernStats = engineExports and engineExports.ModernStats
  if type(ModernStats) ~= "table" then
    -- The engine is a declared dependency, but stay quiet-safe if it is not
    -- there: the row simply never appears rather than erroring every menu.
    mod.log:warn("g9_battle_sample: TRAIN screen not installed -- "
      .. "g9-battle-engine ModernStats unavailable")
    return
  end

  local Font = require("src.render.Font")

  local STAT_ORDER = ModernStats.ORDER
  local STAT_LABEL = { hp = "HP", atk = "ATK", def = "DEF",
    spa = "SPA", spd = "SPD", spe = "SPE" }
  local NATURES = ModernStats.NATURES or {}
  local MOVE_COST = 5000
  local MOVE_FIELD_LABELS = { "EGG", "RELEARN", "TUTOR" }
  -- Moves the native move deleter refuses to forget (engine/pokemon/learn.asm
  -- HM_MOVES); a paid slot replacement is held to the same rule.
  local HM_MOVES = {
    CUT = true, FLY = true, SURF = true, STRENGTH = true, FLASH = true,
    WHIRLPOOL = true, WATERFALL = true, DIVE = true,
  }
  -- The Gen 2 party submenu box holds NumMonMenuItems (8) rows; Gen 1's grows
  -- upward with no ceiling.  Same guard the engine's own adv.stats screen uses.
  local NUM_MONMENU_ITEMS = 8

  -- --------------------------------------------------------------- plumbing
  -- national_dex is optional; every lookup below degrades to "no data" rather
  -- than erroring when it is absent, the same contract ModernStats itself uses.
  local function ndExports()
    local nd = mod.find and mod.find("national_dex")
    return nd and nd.exports
  end

  local function defFromData(data, mon)
    local fallback = data and data.pokemon and data.pokemon[mon.species]
    return ModernStats.resolveBase(mon.species, fallback, ndExports())
  end
  local function defFor(game, mon)
    return defFromData(game and game.data, mon)
  end

  local function liveSave()
    local ok, Game = pcall(require, "src.core.Game")
    if ok and type(Game) == "table" then return Game.save end
    return nil
  end
  local function liveData()
    local ok, Game = pcall(require, "src.core.Game")
    if ok and type(Game) == "table" then return Game.data end
    return nil
  end

  -- Gen 2 keeps the wallet on save.player.money; Gen 1 on save.money.  Read the
  -- Gen 2 field FIRST so the Gen 2Compat facade's `save.money` (documented as
  -- absent on Gold) is never touched there.
  local function moneyOf(save)
    if type(save) ~= "table" then return 0 end
    local player = save.player
    if type(player) == "table" and type(player.money) == "number" then
      return player.money
    end
    return tonumber(save.money) or 0
  end
  local function setMoney(save, value)
    if type(save) ~= "table" then return end
    value = math.max(0, math.floor(value or 0))
    local player = save.player
    if type(player) == "table" and player.money ~= nil then
      player.money = value
    else
      save.money = value
    end
  end

  -- Commit an edited mon's modern fields to mon.stats.  Same body as the
  -- engine's own ev_yield_on_faint recompute: carry the missing HP across
  -- rather than healing to full, mirror the split specials into whichever key
  -- names this generation's native code reads, and keep maxHp in step on Gen 2.
  local function applyModern(def, mon)
    if type(mon) ~= "table" then return end
    if type(def) ~= "table" or type(def.baseStats) ~= "table" then return end
    mon.stats = mon.stats or {}
    local oldMax = mon.stats.hp or 1
    local oldHp = math.max(0, math.min(mon.hp or 0, oldMax))
    local missing = math.max(0, oldMax - oldHp)
    ModernStats.recalcAll(def, mon)
    if gen == 2 then
      mon.stats.specialAttack = mon.stats.spa
      mon.stats.specialDefense = mon.stats.spd
      mon.maxHp = mon.stats.hp
    else
      -- Keep Gen 1's five-key stat block complete (and current) so the native
      -- Stats.ensure never treats it as unfinished and rebuilds it from DVs.
      mon.stats.special = mon.stats.spa
    end
    if oldHp <= 0 then
      mon.hp = 0
    else
      mon.hp = math.max(1, mon.stats.hp - missing)
    end
    mon.modernStatsInitialized = true
    mon.g9TrainEdited = true
  end

  -- ---------------------------------------------------- change preservation
  -- (1) Gen 2: re-apply after every native refreshStats.
  if gen == 2 then
    local okMon, Mon = pcall(require, "src.battle.gen2.Mon")
    if okMon and type(Mon) == "table"
        and type(Mon.refreshStats) == "function"
        and not Mon.__g9TrainRefreshWrapped then
      Mon.__g9TrainRefreshWrapped = true
      local nativeRefresh = Mon.refreshStats
      Mon.refreshStats = function(mon, data)
        local result = nativeRefresh(mon, data)
        if type(mon) == "table" and mon.g9TrainEdited then
          pcall(applyModern, defFromData(data, mon), mon)
        end
        return result
      end
    end
  end

  -- (2) Either generation: re-apply after a level change (both Experience.lua
  -- and gen2/Mon.lua raise this AFTER writing the new level's stats).
  mod.events:on("pokemon.level_up", function(ev)
    local mon = ev and ev.mon
    if type(mon) ~= "table" or not mon.g9TrainEdited then return end
    local ok, err = pcall(function()
      applyModern(defFromData(liveData(), mon), mon)
    end)
    if not ok then
      mod.log:warn("g9_battle_sample: TRAIN level-up reapply failed: %s",
        tostring(err))
    end
  end)

  -- (3) Either generation: re-apply the whole party at battle start.  Gen 2's
  -- Battle.new refreshes stats BEFORE raising battle.started, so without this
  -- an edited mon would fight with its DV-derived numbers.
  mod.events:on("battle.started", function()
    local ok, err = pcall(function()
      local save = liveSave()
      if type(save) ~= "table" then return end
      local data = liveData()
      for _, mon in ipairs(save.party or {}) do
        if type(mon) == "table" and mon.g9TrainEdited then
          applyModern(defFromData(data, mon), mon)
        end
      end
    end)
    if not ok then
      mod.log:warn("g9_battle_sample: TRAIN battle-start reapply failed: %s",
        tostring(err))
    end
  end)

  -- --------------------------------------------------------------- geometry
  -- Gen 1 gets the same 20%-larger window the engine's adv.stats screen uses
  -- (explicit precedent); Gen 2 keeps 160x144 and identity coordinates.
  local isGen1Boot = (gen == 1)
  local S = isGen1Boot and 1.2 or 1.0
  local UI_W = math.floor(160 * S + 0.5)
  local UI_H = math.floor(144 * S + 0.5)
  local function SX(v) return math.floor(v * S + 0.5) end

  local function cell(text, x, y)
    Font.draw(text, SX(x), SX(y))
  end

  -- Every option on this screen -- tab, button, stat row, nature/gender,
  -- APPLY -- is drawn inside a frame.  `level` 2 adds a second, 1px-inner
  -- frame and is how the cursor is shown: the tile font draws black glyphs on
  -- transparent whatever the colour, so inversion is not available and the
  -- weight of the frame is the only selection cue.
  local function frame(x, y, w, h, level)
    love.graphics.rectangle("line", SX(x), SX(y), SX(w), SX(h))
    if (level or 1) > 1 then
      love.graphics.rectangle("line", SX(x) + 1, SX(y) + 1,
        math.max(0, SX(w) - 2), math.max(0, SX(h) - 2))
    end
  end

  -- <male> and <female> are single font tiles on BOTH generations: codes 239
  -- and 245 (constants/charmap.asm; the yellow ROM manifest carries the same
  -- pair, and the engine's own naming/summary screens print them).  Drawn by
  -- code rather than by the charmap's multi-byte sequence so the symbol is
  -- there whatever a generation's charmap happens to carry.
  local GENDER_CODE = { male = 239, female = 245 }
  local function drawGender(gender, x, y)
    local code = GENDER_CODE[gender]
    if code then Font.drawCode(code, SX(x), SX(y)) end
  end

  -- The gender tab prints BOTH symbols as its label, so the one the mon is
  -- currently set to is marked with a 1px rule along the tile's own baseline.
  -- That is the only pixel row still free inside the tab -- a focused tab's
  -- double frame already owns the rows above and below the tile -- and the
  -- 1px weight is the cue this screen uses for every other selection, since
  -- the tile font draws black on transparent whatever the colour.  An unknown
  -- gender (a mon the engine never gave one) is simply left unmarked.
  local function drawGenderRule(gender, x, y)
    if not GENDER_CODE[gender] then return end
    love.graphics.rectangle("fill", SX(x), SX(y + 8), SX(8), 1)
  end

  local function clamp(v, lo, hi)
    if v < lo then return lo end
    if v > hi then return hi end
    return v
  end

  -- --------------------------------------------------------------- the screen
  -- Editing fees.  An IV point costs IV_COST, an EV point EV_COST, and a
  -- nature change a flat NATURE_COST; gender is free.  A fee is charged per
  -- point of difference from the mon's CURRENT (last committed) value, so
  -- moving a value back toward where it started refunds its points.  Nothing
  -- is charged until the screen's APPLY action, which pays the whole total.
  local IV_COST = 50
  local EV_COST = 35
  local NATURE_COST = 2000

  -- Tab indices.  The gender tab carries no text label -- it prints the two
  -- single-tile gender symbols instead -- so it is marked by `gender = true`.
  local TAB_IV, TAB_EV, TAB_NAT, TAB_GENDER, TAB_MOVES = 1, 2, 3, 4, 5
  local TAB_COUNT = 5

  -- The nudge row, one button set per editing page (explicit user spec: the EV
  -- page gets the wide jumps).  An EV point is a fifth of an IV point and a
  -- stock EV runs to 252, so single-point steps are useless there: the EV page
  -- steps in 4s, 12s and 128s with a 0 reset, while the IV page keeps its
  -- single-point +/- and its 0/31 binders.  A button either adds `delta` to the
  -- stat under the cursor or writes `set` outright.  `pad` is the frame
  -- padding around each label and `gap` the space between buttons; the EV row
  -- is seven buttons wide and only just fits the 160-wide window, so it runs
  -- with 1px padding and no gaps (adjacent frames share their edge line, which
  -- reads as one segmented strip).
  local BUTTONS = {
    [TAB_IV] = { pad = nil, gap = 8, buttons = {
      { label = "+", delta = 1 },
      { label = "-", delta = -1 },
      { label = "0", set = 0 },
      { label = "31", set = 31 },
    } },
    [TAB_EV] = { pad = 1, gap = 0, buttons = {
      { label = "4", delta = 4 },
      { label = "-4", delta = -4 },
      { label = "+12", delta = 12 },
      { label = "-12", delta = -12 },
      { label = "+128", delta = 128 },
      { label = "-128", delta = -128 },
      { label = "0", set = 0 },
    } },
  }
  -- The set the given page edits with; the IV set is the fallback for any page
  -- that has no nudge row at all (the tab walks and applyButton both guard on
  -- IV/EV anyway, but the accessor stays total).
  local function buttonsFor(page) return BUTTONS[page] or BUTTONS[TAB_IV] end

  local TABS = {
    { label = "IV" }, { label = "EV" }, { label = "NAT" },
    { gender = true }, { label = "MOVES" },
  }

  -- Design space is the Gen 2 window, 160x144; Gen 1 scales every coordinate
  -- through SX().  Each band below is a row of framed options.
  local DESIGN_W = 160
  local TAB_Y, TAB_H = 9, 12
  local TAB_PAD, TAB_GAP = 2, 2
  local SET_Y, SET_H = 22, 12
  local HEADER_Y = 35
  local ROW_TOP, ROW_STEP, ROW_H = 44, 10, 10
  local TABLE_X, TABLE_W = 2, 122
  local FOOTER_Y, FOOTER_H = 105, 12
  local STATUS_Y = 119
  local COST_Y = 129
  local COL_LABEL, COL_IV, COL_EV, COL_ST = 10, 44, 68, 96
  local VISIBLE_MOVES = 8

  -- Lay a row of framed labels out centred in the window: each option is its
  -- own text width plus `pad` either side, with `gap` between them.  `pad`
  -- defaults to TAB_PAD.
  local function layoutRow(labels, gap, pad)
    pad = pad or TAB_PAD
    local widths, total = {}, 0
    for i, label in ipairs(labels) do
      widths[i] = label * 8 + 2 * pad
      total = total + widths[i]
      if i > 1 then total = total + gap end
    end
    local xs = {}
    local x = math.floor((DESIGN_W - total) / 2 + 0.5)
    for i = 1, #labels do
      xs[i] = x
      x = x + widths[i] + gap
    end
    return xs, widths
  end

  -- Measure and place each page's nudge row once, up front.
  for _, set in pairs(BUTTONS) do
    local glyphs = {}
    for i, button in ipairs(set.buttons) do glyphs[i] = #button.label end
    set.x, set.w = layoutRow(glyphs, set.gap, set.pad)
  end

  -- The tab strip mixes text tabs and the symbol tab, so measure by glyphs.
  local TAB_GLYPHS = {}
  for i, tab in ipairs(TABS) do
    TAB_GLYPHS[i] = tab.gender and 2 or #tab.label
  end
  local TAB_X, TAB_W = layoutRow(TAB_GLYPHS, TAB_GAP)

  local Screen = {}
  Screen.__index = Screen
  Screen.isOpaque = true
  Screen.screenId = "G9Train"

  function Screen:uiSize() return UI_W, UI_H end

  local function natureIndex(mon)
    local nature = mon and mon.nature
    for i, name in ipairs(NATURES) do
      if name == nature then return i end
    end
    return nil
  end

  function Screen.new(game, mon)
    local def = defFor(game, mon)
    -- Idempotent top-ups, same as the engine's own adv.stats screen: a mon
    -- that has never been through a battle still shows a real nature/gender.
    pcall(ModernStats.generateNature, mon)
    pcall(ModernStats.generateGender, mon)
    if def then pcall(ModernStats.ensure, def, mon) end

    local self = setmetatable({
      game = game, mon = mon, def = def,
      mode = "stats", focus = "tabs", page = TAB_IV, row = 1, col = 1,
      nature = mon.nature, gender = mon.gender,
      baseNature = mon.nature, baseGender = mon.gender,
      category = 1, moveIndex = 1, moveList = {},
      pending = nil, pickingSlot = false, slotIndex = 1,
      status = "", broken = false,
      ivs = {}, evs = {}, baseIvs = {}, baseEvs = {},
    }, Screen)
    for _, key in ipairs(STAT_ORDER) do
      self.ivs[key] = clamp(tonumber(mon.ivs and mon.ivs[key]) or 0, 0, 31)
      self.evs[key] = clamp(tonumber(mon.evs and mon.evs[key]) or 0, 0, 252)
    end
    for _, key in ipairs(STAT_ORDER) do
      self.baseIvs[key] = self.ivs[key]
      self.baseEvs[key] = self.evs[key]
    end
    return self
  end

  function Screen:evTotal()
    local total = 0
    for _, key in ipairs(STAT_ORDER) do total = total + (self.evs[key] or 0) end
    return total
  end

  -- How many rows of stats the current tab edits: the six stats on IV and EV,
  -- and a single value on the NAT and gender tabs (whose value is drawn in
  -- the footer rather than the table).  APPLY is no longer a row of its own
  -- -- it is a focus of the whole screen (explicit user spec).
  function Screen:statRowCount()
    return (self.page == TAB_IV or self.page == TAB_EV) and #STAT_ORDER or 1
  end

  -- What the STAGED edits would cost: IV_COST per IV point changed plus
  -- EV_COST per EV point changed -- each counted from the mon's last
  -- committed value, so an undone edit costs nothing again -- plus a flat
  -- NATURE_COST when the nature differs.  Gender is free.
  function Screen:pendingCost()
    local cost = 0
    for _, key in ipairs(STAT_ORDER) do
      cost = cost + IV_COST
        * math.abs((self.ivs[key] or 0) - (self.baseIvs[key] or 0))
      cost = cost + EV_COST
        * math.abs((self.evs[key] or 0) - (self.baseEvs[key] or 0))
    end
    if self.nature ~= self.baseNature then cost = cost + NATURE_COST end
    return cost
  end

  function Screen:hasChanges()
    if self:pendingCost() > 0 then return true end
    return (self.gender or "") ~= (self.baseGender or "")
  end

  -- The live preview of the six computed stats for the working copy -- the pure
  -- ModernStats.computeAll, so nothing on the mon is touched until commit.
  function Screen:preview()
    if not (self.def and type(self.def.baseStats) == "table") then return nil end
    return ModernStats.computeAll(self.def.baseStats, self.ivs, self.evs,
      self.mon.level, self.nature)
  end

  -- Write the working copy onto the mon and recompute through the engine's own
  -- recalcAll.  Only the APPLY action calls this: every button and page just
  -- stages the working copy, so an unaffordable purchase leaves the mon
  -- exactly as it was.
  function Screen:commit()
    local mon = self.mon
    mon.ivs = mon.ivs or {}
    mon.evs = mon.evs or {}
    for _, key in ipairs(STAT_ORDER) do
      mon.ivs[key] = self.ivs[key] or 0
      mon.evs[key] = self.evs[key] or 0
    end
    if self.nature ~= nil then mon.nature = self.nature end
    if self.gender ~= nil then mon.gender = self.gender end
    applyModern(self.def, mon)
  end

  function Screen:applyButton()
    if self.page ~= TAB_IV and self.page ~= TAB_EV then return end
    if self.row > #STAT_ORDER then return end
    local store = (self.page == TAB_IV) and self.ivs or self.evs
    local key = STAT_ORDER[self.row]
    local button = buttonsFor(self.page).buttons[self.col]
    if not button then return end
    local value
    if button.set ~= nil then
      value = button.set
    else
      value = (store[key] or 0) + button.delta
    end
    if self.page == TAB_IV then
      store[key] = clamp(value, 0, 31)
    else
      -- Real EV rules: 252 per stat, 510 across all six.
      local others = self:evTotal() - (store[key] or 0)
      store[key] = clamp(math.min(clamp(value, 0, 252), 510 - others), 0, 252)
    end
    self.status = ""
  end

  function Screen:cycleNature(step)
    if #NATURES == 0 then return end
    local index = natureIndex(self) or 0
    index = ((index - 1 + step) % #NATURES) + 1
    self.nature = NATURES[index]
    self.status = ""
  end

  function Screen:toggleGender()
    self.gender = (self.gender == "female") and "male" or "female"
    self.status = ""
  end

  -- Charge the staged total and write the working copy onto the mon.  An
  -- unaffordable total changes nothing at all (no partial spend, no partial
  -- commit); a successful one moves the baseline forward, so the cost reads 0
  -- again and the next edits are priced from the mon's new values.
  function Screen:applyAll()
    if not self:hasChanges() then self.status = "NO CHANGE"; return end
    local cost = self:pendingCost()
    local save = liveSave()
    if moneyOf(save) < cost then
      self.status = string.format("NEED %d", cost)
      return
    end
    if cost > 0 then setMoney(save, moneyOf(save) - cost) end
    self:commit()
    for _, key in ipairs(STAT_ORDER) do
      self.baseIvs[key] = self.ivs[key]
      self.baseEvs[key] = self.evs[key]
    end
    self.baseNature = self.nature
    self.baseGender = self.gender
    self.status = cost > 0 and string.format("APPLIED -%d", cost) or "APPLIED"
  end

  -- ------------------------------------------------------------ move pool
  local movePoolCache = {}
  function Screen:buildMoveList()
    self.moveList = {}
    self.moveHint = nil
    local nd = ndExports()
    if not (nd and type(nd.statsBySpecies) == "function") then
      self.moveHint = "NEEDS NATIONAL DEX"
      return
    end
    local ok, rec = pcall(nd.statsBySpecies, self.mon.species)
    if not (ok and type(rec) == "table") then
      self.moveHint = "NO DEX DATA"
      return
    end
    self.mon.moves = self.mon.moves or {}
    local known = {}
    for _, move in ipairs(self.mon.moves) do
      if move and move.id then known[move.id] = true end
    end
    local data = self.game and self.game.data
    local seen = {}
    local function consider(moveId)
      if type(moveId) ~= "string" or moveId == "" then return end
      if seen[moveId] or known[moveId] then return end
      local moveDef = data and data.moves and data.moves[moveId]
      if not moveDef then return end
      -- The engine's own "can this actually be run yet" gate, when exported.
      if engineExports and type(engineExports.isMoveUsable) == "function" then
        local okCall, usable = pcall(engineExports.isMoveUsable, moveId)
        if okCall and usable == false then return end
      end
      seen[moveId] = true
      self.moveList[#self.moveList + 1] = {
        id = moveId, name = moveDef.name or moveId,
      }
    end
    if self.category == 1 then
      -- Relearn: level-up moves at or below the mon's current level.
      for _, entry in ipairs(rec.movesFull or {}) do
        if (entry.level or 1) <= (self.mon.level or 1) then
          consider(entry.move)
        end
      end
    elseif self.category == 2 then
      for _, entry in ipairs((rec.movesByMethod or {}).egg or {}) do
        consider(entry.move)
      end
    else
      for _, entry in ipairs((rec.movesByMethod or {}).tutor or {}) do
        consider(entry.move)
      end
    end
    table.sort(self.moveList, function(a, b) return a.name < b.name end)
    if self.moveIndex > #self.moveList then
      self.moveIndex = math.max(1, #self.moveList)
    end
  end

  function Screen:chooseMove()
    local entry = self.moveList[self.moveIndex]
    self.status = ""
    if not entry then self.status = "NO MOVE"; return end
    if moneyOf(liveSave()) < MOVE_COST then self.status = "NEED 5000"; return end
    local moves = self.mon.moves or {}
    if #moves < 4 then
      self.pending = { entry = entry, slot = #moves + 1 }
    else
      self.pickingSlot = true
      self.slotIndex = 1
    end
  end

  function Screen:writeMove(entry, slot)
    local mon = self.mon
    mon.moves = mon.moves or {}
    local data = self.game and self.game.data
    local moveDef = data and data.moves and data.moves[entry.id]
    local pp = (moveDef and moveDef.pp) or 0
    local newEntry = { id = entry.id, pp = pp }
    -- Gen 2's move records carry maxPp; Gen 1's do not (Mon.learnMove vs
    -- BattleState:learnMove).
    if gen == 2 then newEntry.maxPp = pp end
    mon.moves[slot] = newEntry
    local ok, Runtime = pcall(require, "src.mods.Runtime")
    if ok and type(Runtime) == "table" and type(Runtime.emit) == "function" then
      pcall(Runtime.emit, "pokemon.move_learned",
        { mon = mon, moveId = entry.id })
    end
  end

  function Screen:doTeach()
    local pending = self.pending
    self.pending = nil
    if not pending then return end
    local save = liveSave()
    if moneyOf(save) < MOVE_COST then self.status = "NEED 5000"; return end
    local old = (self.mon.moves or {})[pending.slot]
    if old and HM_MOVES[old.id] then self.status = "CAN'T FORGET HM"; return end
    setMoney(save, moneyOf(save) - MOVE_COST)
    self:writeMove(pending.entry, pending.slot)
    self.status = "LEARNED " .. pending.entry.name
    self:buildMoveList()
  end

  -- --------------------------------------------------------------- input
  local function safeCall(self, label, fn)
    local ok, err = pcall(fn)
    if not ok then
      mod.log:warn("g9_battle_sample: train_screen: %s errored, closing (%s)",
        label, tostring(err))
      self.broken = true
    end
  end

  -- Three focuses, moved between by the D-pad (explicit user spec):
  --   "tabs"  -- the framed tab strip along the top.  LEFT/RIGHT walks the
  --              five tabs; UP/DOWN drops to APPLY; A enters the tab's rows
  --              (or, on MOVES, opens screen two).
  --   "rows"  -- the tab's own rows.  On IV/EV: LEFT/RIGHT cycles that page's
  --              nudge buttons (the IV set: + / - / 0 / 31; the EV set: 4 / -4
  --              / +12 / -12 / +128 / -128 / 0), UP/DOWN walks the six stats,
  --              A runs the button.  On NAT and the gender tab there is a
  --              single value, so LEFT/RIGHT (or A) changes it and UP/DOWN goes
  --              back up to APPLY.
  --   "apply" -- the APPLY button.  A buys the staged edits, UP/DOWN returns
  --              to the tab strip.
  function Screen:updateStats(input)
    if self.focus == "apply" then
      if input:wasPressed("a") then
        self:applyAll()
      elseif input:wasPressed("up") or input:wasPressed("down") then
        self.focus = "tabs"
      end
      return
    end

    if self.focus == "tabs" then
      if input:wasPressed("left") then
        self.page = ((self.page - 2) % TAB_COUNT) + 1
        self.row = 1
        self.col = 1
        self.status = ""
      elseif input:wasPressed("right") then
        self.page = (self.page % TAB_COUNT) + 1
        self.row = 1
        self.col = 1
        self.status = ""
      elseif input:wasPressed("up") or input:wasPressed("down") then
        self.focus = "apply"
      elseif input:wasPressed("a") then
        if self.page == TAB_MOVES then
          self.mode = "moves"
          self:buildMoveList()
          self.moveIndex = 1
        else
          self.focus = "rows"
          self.row = 1
        end
      end
      return
    end

    -- focus == "rows"
    if self.page == TAB_IV or self.page == TAB_EV then
      if input:wasPressed("up") then
        self.row = ((self.row - 2) % #STAT_ORDER) + 1
      elseif input:wasPressed("down") then
        self.row = (self.row % #STAT_ORDER) + 1
      elseif input:wasPressed("left") or input:wasPressed("right") then
        local step = input:wasPressed("right") and 1 or -1
        self.col = ((self.col - 1 + step) % #buttonsFor(self.page).buttons) + 1
      elseif input:wasPressed("a") then
        self:applyButton()
      end
      return
    end

    if input:wasPressed("left") or input:wasPressed("right") then
      local step = input:wasPressed("right") and 1 or -1
      if self.page == TAB_NAT then
        self:cycleNature(step)
      else
        self:toggleGender()
      end
    elseif input:wasPressed("up") or input:wasPressed("down") then
      self.focus = "apply"
    elseif input:wasPressed("a") then
      if self.page == TAB_NAT then
        self:cycleNature(1)
      else
        self:toggleGender()
      end
    end
  end

  function Screen:updateMoves(input)
    if input:wasPressed("left") then
      self.category = ((self.category - 2) % 3) + 1
      self:buildMoveList()
    elseif input:wasPressed("right") then
      self.category = (self.category % 3) + 1
      self:buildMoveList()
    elseif input:wasPressed("up") then
      if #self.moveList > 0 then
        self.moveIndex = ((self.moveIndex - 2) % #self.moveList) + 1
      end
    elseif input:wasPressed("down") then
      if #self.moveList > 0 then
        self.moveIndex = (self.moveIndex % #self.moveList) + 1
      end
    elseif input:wasPressed("a") then
      self:chooseMove()
    end
  end

  function Screen:updateSlotPicker(input)
    local moves = self.mon.moves or {}
    local count = math.max(1, #moves)
    if input:wasPressed("up") then
      self.slotIndex = ((self.slotIndex - 2) % count) + 1
    elseif input:wasPressed("down") then
      self.slotIndex = (self.slotIndex % count) + 1
    elseif input:wasPressed("b") then
      self.pickingSlot = false
    elseif input:wasPressed("a") then
      local old = moves[self.slotIndex]
      self.pickingSlot = false
      if old and HM_MOVES[old.id] then
        self.status = "CAN'T FORGET HM"
        return
      end
      self.pending = { entry = self.moveList[self.moveIndex],
        slot = self.slotIndex }
    end
  end

  function Screen:updateConfirm(input)
    if input:wasPressed("a") then
      self:doTeach()
    elseif input:wasPressed("b") then
      self.pending = nil
      self.status = "CANCELLED"
    end
  end

  function Screen:update(dt)
    if self.broken then
      if self.game and self.game.stack then self.game.stack:pop() end
      return
    end
    safeCall(self, "update", function()
      local input = self.game.input
      if not input then return end
      if self.pending then self:updateConfirm(input); return end
      if self.pickingSlot then self:updateSlotPicker(input); return end
      if input:wasPressed("start") then
        self.status = ""
        if self.mode == "stats" then
          self.mode = "moves"
          self.page = TAB_MOVES
          self:buildMoveList()
          self.moveIndex = 1
        else
          self.mode = "stats"
          self.page = TAB_MOVES
          self.focus = "tabs"
        end
        return
      end
      -- B steps back one level at a time: a row/APPLY cursor returns to the
      -- tab strip, the moves screen returns to the stats screen, and only a
      -- B on the tab strip itself leaves the TRAIN screen.
      if input:wasPressed("b") then
        if self.mode == "moves" then
          self.mode = "stats"
          self.page = TAB_MOVES
          self.focus = "tabs"
          self.status = ""
        elseif self.focus ~= "tabs" then
          self.focus = "tabs"
        else
          self.game.stack:pop()
        end
        return
      end
      if self.mode == "stats" then
        self:updateStats(input)
      else
        self:updateMoves(input)
      end
    end)
  end

  -- --------------------------------------------------------------- drawing
  -- The tab strip: five framed options, the current one framed twice.  The
  -- gender tab carries no text -- it prints the two single-tile symbols as its
  -- label, with a rule under whichever one the mon is currently set to (so the
  -- tab reads as a two-way menu with its current value marked).
  function Screen:drawTabs()
    for i, tab in ipairs(TABS) do
      local level = (self.focus == "tabs" and self.page == i) and 2 or 1
      frame(TAB_X[i], TAB_Y, TAB_W[i], TAB_H, level)
      local tx, ty = TAB_X[i] + TAB_PAD, TAB_Y + 2
      if tab.gender then
        drawGender("male", tx, ty)
        drawGender("female", tx + 8, ty)
        local current = (self.gender == "female") and tx + 8 or tx
        drawGenderRule(self.gender, current, ty)
      else
        Font.draw(tab.label, SX(tx), SX(ty))
      end
    end
  end

  -- The six stats, always visible whatever tab is current: the IV column, the
  -- EV column and the resulting stat.  Every row is framed; the row the
  -- cursor is on is framed twice.
  function Screen:drawTable(preview, editable)
    cell("IV", COL_IV, HEADER_Y)
    cell("EV", COL_EV, HEADER_Y)
    cell("ST", COL_ST, HEADER_Y)
    for i, key in ipairs(STAT_ORDER) do
      local y = ROW_TOP + (i - 1) * ROW_STEP
      local level = (editable and self.focus == "rows" and self.row == i)
        and 2 or 1
      frame(TABLE_X, y, TABLE_W, ROW_H, level)
      cell(STAT_LABEL[key], COL_LABEL, y + 1)
      cell(string.format("%2d", self.ivs[key] or 0), COL_IV, y + 1)
      cell(string.format("%3d", self.evs[key] or 0), COL_EV, y + 1)
      local stat = preview and preview[key]
      cell(stat and string.format("%3d", stat) or "---", COL_ST, y + 1)
    end
  end

  -- The value strip under the table: the nature and the gender symbol, each
  -- framed like every other option.  The one the cursor is on is framed twice.
  -- The gender box is the VALUE, not a menu: it prints the current gender's
  -- single symbol -- LEFT/RIGHT on the gender tab cycles the box in place --
  -- and only falls back to printing both tiles for a mon the engine never gave
  -- a gender at all.
  function Screen:drawFooter()
    local label = "NAT:" .. string.sub(tostring(self.nature or "----"), 1, 7)
    local natLevel = (self.page == TAB_NAT and self.focus == "rows") and 2 or 1
    frame(TABLE_X, FOOTER_Y, #label * 8 + 2 * TAB_PAD, FOOTER_H, natLevel)
    Font.draw(label, SX(TABLE_X + TAB_PAD), SX(FOOTER_Y + 2))
    local gx = TABLE_X + #label * 8 + 2 * TAB_PAD + 6
    local genLevel = (self.page == TAB_GENDER and self.focus == "rows")
      and 2 or 1
    frame(gx, FOOTER_Y, 16 + 2 * TAB_PAD, FOOTER_H, genLevel)
    if GENDER_CODE[self.gender] then
      drawGender(self.gender, gx + 6, FOOTER_Y + 2)
    else
      drawGender("male", gx + TAB_PAD, FOOTER_Y + 2)
      drawGender("female", gx + TAB_PAD + 8, FOOTER_Y + 2)
    end
  end

  function Screen:drawHint()
    local hint
    if self.focus == "tabs" then
      hint = "L/R:PICK A:OK"
    elseif self.focus == "apply" then
      hint = "A:APPLY B:BACK"
    elseif self.page == TAB_IV or self.page == TAB_EV then
      hint = "U/D:STAT L/R:VAL"
    elseif self.page == TAB_NAT then
      hint = "L/R:NATURE A:OK"
    else
      hint = "L/R:GENDER A:OK"
    end
    cell(self.status ~= "" and self.status or hint, 4, STATUS_Y)
  end

  -- Bottom-right corner: the staged total and the APPLY button beside it.
  -- Drawn in design coordinates like everything else, so the right edge lands
  -- on the window edge whatever the generation's scale is; the button is
  -- framed, and framed twice while it holds the cursor.
  function Screen:drawCostBar()
    local costText = string.format("COST:%d", self:pendingCost())
    local bw = #"APPLY" * 8 + 2 * TAB_PAD
    local bx = DESIGN_W - 2 - bw
    local cx = bx - 6 - #costText * 8
    if cx < 2 then cx = 2 end
    Font.draw(costText, SX(cx), SX(COST_Y))
    frame(bx, COST_Y - 2, bw, 12, self.focus == "apply" and 2 or 1)
    Font.draw("APPLY", SX(bx + TAB_PAD), SX(COST_Y))
  end

  function Screen:drawStats()
    local mon = self.mon
    local name = mon.nickname or (self.def and self.def.name) or mon.species
      or "?"
    cell("TRAIN " .. string.sub(tostring(name), 1, 12), 4, 1)
    self:drawTabs()

    local editable = (self.page == TAB_IV or self.page == TAB_EV)
    if editable then
      local set = buttonsFor(self.page)
      for i, button in ipairs(set.buttons) do
        local level = (self.focus == "rows" and self.col == i) and 2 or 1
        frame(set.x[i], SET_Y, set.w[i], SET_H, level)
        Font.draw(button.label, SX(set.x[i] + (set.pad or TAB_PAD)),
          SX(SET_Y + 2))
      end
    end

    self:drawTable(self:preview(), editable)
    self:drawFooter()
    self:drawHint()
    self:drawCostBar()
  end

  function Screen:drawMoves()
    cell("TRAIN MOVES", 4, 2)
    cell("CAT: " .. MOVE_FIELD_LABELS[self.category], 4, 11)
    cell(string.format("MONEY:%d COST:%d", moneyOf(liveSave()), MOVE_COST),
      4, 20)

    local list = self.moveList
    if #list == 0 then
      cell(self.moveHint or "NONE TO LEARN", 4, 40)
    else
      local top = 1
      if #list > VISIBLE_MOVES then
        top = clamp(self.moveIndex - math.floor(VISIBLE_MOVES / 2), 1,
          #list - VISIBLE_MOVES + 1)
      end
      for i = 0, VISIBLE_MOVES - 1 do
        local index = top + i
        local entry = list[index]
        if not entry then break end
        local y = 32 + i * ROW_STEP
        if index == self.moveIndex then cell(">", 2, y) end
        cell(string.sub(entry.name, 1, 14), 12, y)
      end
    end
    cell(self.status ~= "" and self.status or "L/R:CAT A:TEACH", 4, 122)
    cell("ST/B:BACK TO TRAIN", 4, 132)

    if self.pickingSlot then
      local moves = self.mon.moves or {}
      love.graphics.setColor(0, 0, 0, 1)
      love.graphics.rectangle("fill", SX(16), SX(70), SX(128), SX(50))
      love.graphics.setColor(1, 1, 1, 1)
      love.graphics.rectangle("fill", SX(18), SX(72), SX(124), SX(46))
      love.graphics.setColor(0, 0, 0, 1)
      cell("FORGET WHICH?", 22, 74)
      for i = 1, math.max(1, #moves) do
        local y = 82 + (i - 1) * 9
        if i == self.slotIndex then cell(">", 22, y) end
        local move = moves[i]
        local data = self.game and self.game.data
        local def = move and data and data.moves and data.moves[move.id]
        local label = def and def.name or (move and move.id) or "----"
        if move and HM_MOVES[move.id] then label = label .. " (HM)" end
        cell(string.sub(label, 1, 12), 30, y)
      end
      cell("A:OK B:BACK", 22, 112)
    end

    if self.pending then
      love.graphics.setColor(0, 0, 0, 1)
      love.graphics.rectangle("fill", SX(8), SX(58), SX(144), SX(36))
      love.graphics.setColor(1, 1, 1, 1)
      love.graphics.rectangle("fill", SX(10), SX(60), SX(140), SX(32))
      love.graphics.setColor(0, 0, 0, 1)
      cell("LEARN " .. string.sub(self.pending.entry.name, 1, 11) .. "?", 12, 64)
      cell(string.format("FOR %d  A:YES B:NO", MOVE_COST), 12, 76)
    end
  end

  function Screen:draw()
    if self.broken then return end
    safeCall(self, "draw", function()
      love.graphics.setColor(1, 1, 1, 1)
      love.graphics.rectangle("fill", 0, 0, UI_W, UI_H)
      love.graphics.setColor(0, 0, 0, 1)
      if self.mode == "stats" then self:drawStats() else self:drawMoves() end
      love.graphics.setColor(1, 1, 1, 1)
    end)
  end

  -- --------------------------------------------------------------- the hook
  mod.hooks:wrap("ui.party.submenu", function(nextFn, game, items, mon, ctx)
    local result = nextFn(game, items, mon, ctx)
    if type(result) ~= "table" then result = items end
    if type(result) ~= "table" then return result end
    -- Field list only (never the in-battle SWITCH/STATS box), and never an egg
    -- -- an egg has nothing to train.
    local isBattle = ctx and ctx.battle
    local isEgg = type(mon) == "table" and mon.isEgg
    local hasRoom = (isGen1Boot and true) or (#result < NUM_MONMENU_ITEMS)
    if not isBattle and not isEgg and hasRoom then
      result[#result + 1] = {
        id = "TRAIN", label = "TRAIN",
        onSelect = function(selectedMon, selectedGame)
          local ok, screen = pcall(Screen.new, selectedGame, selectedMon)
          if ok and screen then
            selectedGame.stack:push(screen)
          else
            mod.log:warn("g9_battle_sample: TRAIN screen failed to open (%s)",
              tostring(screen))
          end
        end,
      }
    end
    return result
  end, 0)

  mod.log:info("g9_battle_sample: TRAIN party screen installed (Gen %d)", gen)
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
  -- The TRAIN party screen is generation-agnostic (one hook, both gens); it
  -- installs here, before either arm, so its Gen 2 Mon.refreshStats re-apply
  -- wrap is the outermost one on that module.
  local okTrain, trainErr = pcall(installTrainScreen, mod, gen, shared)
  if not okTrain then
    mod.log:warn("g9_battle_sample: TRAIN screen install failed: %s",
      tostring(trainErr))
  end
  if gen == 2 then
    return installGen2(mod, shared)
  end
  return installGen1(mod, shared)
end
