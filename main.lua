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
  -- The SAME schema options.lua returns (kept in sync by hand, exactly like
  -- g9-trainer-sample's own pair: the manager reads options.lua while a
  -- disabled mod is shown, and mod.options:get needs the defaults from this
  -- define() call at load time).
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
    -- this is the same safe fallback g9-trainer-sample uses when it isn't.
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
    -- Difficulty team floor first, then the species swap (added mons are
    -- tagged, so the swap leaves them exactly as built).
    return shared.randomizeParty(shared.padTrainerParty(result))
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
    if #enemies < 2 then return false end
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
-- Transition.battleReturn fade.  Prize money is paid here too, for the same
-- reason -- the native screen's own win sequence is what normally pays it.
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
  local function finishGen1Battle(screen, battle, nativeOnFinish, isTrainer,
                                  leveledUp)
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

    -- Prize money: native pays it out of its own win sequence
    -- (BattleState's MoneyForWinning arm -- baseMoney * the enemy's level).
    -- This scene replaces that screen, so nothing else would pay it.
    if outcome == "win" and isTrainer and battle.trainer then
      local level = (battle.enemy and battle.enemy.mon
        and battle.enemy.mon.level) or 0
      local prize = (battle.trainer.baseMoney or 0) * level
      if prize > 0 then save.money = (save.money or 0) + prize end
    end

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
        isTrainer, leveledUp)
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

  mod.log:info("g9_battle_sample: Gen 1 wild encounters route to "
    .. "g9-Battle-Scene (0.5%% \"bossFight\" with x1..x5 HP + random flags, "
    .. "1%% \"hordes\", 2%% \"triples\", 10%% \"doubles\", ~86%% \"singles\"); "
    .. "every 2+-mon trainer battle routes to \"doubles\", the Elite Four "
    .. "rolls doubles/triples, and the Champion (OPP_RIVAL3) routes to "
    .. "\"bossFight\"; wild_forms's Eternatus-as-Eternamax static routes to "
    .. "\"bossFight\"")
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
  if gen == 2 then
    return installGen2(mod, shared)
  end
  return installGen1(mod, shared)
end
