Config = {}

-- Discord bot and guild settings
Config.Discord = {
    botToken    = "YOUR_DISCORD_BOTTOKEN",
    guildId     = "1378183960215032000",
    allowedRoles = {
        ["1383518537628389406"] = true,  -- Moderator
        ["234567890123456789"] = true,  -- Admin
        -- add more RoleIDs as needed
    }
}
-- If true, bypass domain checks (DANGEROUS: do NOT enable on public servers)
Config.ALLOW_ALL = false

-- Allowed domains. Examples:
-- "example.com"  -> allows example.com and sub.example.com
-- "*.example.net" -> also allows sub.example.net (matching logic below treats both similarly)
Config.ALLOWED_DOMAINS = {
  "duckduckgo.com",
  "example.com",
  "azurewebsites.xyz",
  "127.0.0.1"
}


-- Clothing mapping (component & prop slots)
Config.Clothes = {
  mapping = {
    components = {
      tshirt      = 8,
      torso       = 11,
      decals      = 10,
      arms        = 3,
      pants       = 4,
      shoes       = 6,
      accessories = 7,
      kevlar      = 9,
      badge       = 7, -- custom badge overlay if needed
    },
    textures = {
      tshirt      = "tshirt_2",
      torso       = "torso_2",
      decals      = "decals_2",
      arms        = "arms_2",
      pants       = "pants_2",
      shoes       = "shoes_2",
      accessories = "accessories_2",
      kevlar      = "kevlar_2",
      badge       = "badge_2",
    },
    props = {
      hat       = { id1 = 0, id2 = 0 },
      ears      = { id1 = 2, id2 = 2 },
      watch     = { id1 = 6, id2 = 0 },
      bracelet  = { id1 = 7, id2 = 0 },
      -- glasses removed as per request
    },
  },
}

-- Jail settings
Config.Jail = {
-- Config.Jail (replace old coords/zoneSize with these or merge)

  coords        = { 1673.697, 2510.594, 45.565 },        -- teleport location inside jail (center)
  releaseCoords = { 1956.901, 2617.651, 45.913 },       -- where to release them (bus spawn point)
  -- BIG jail box (approx size of the GTA prison footprint)
  zoneSize      = { 150.0, 220.0, 60.0 },         -- X, Y, Z (very large — adjust if you want)
  fadeTime      = 500,                           -- reuse from your code
  punchPenalty  = 300,                           -- existing
  escapePenalty = 600,                           -- existing
  escapeMessage = "You cannot leave the prison area!",
  releaseMessage = "You have been released.",


  -- NEW: toggle whether to use bus transport on release (true = bus spawn/ride, false = teleport)
  useBus = true,                                 -- set to false to simply teleport to releaseCoords

  -- cleaning/task options (reduces time)
  cleaningSpots = {                              -- offsets relative to Jail.coords (or use absolute coords)
    { x = 2.0,   y = 4.0,  z = 0.0 },
    { x = -10.0, y = 20.0, z = 0.0 },
  },
  cleaningDurationSeconds = 20,                  -- how long a cleaning action runs
  cleaningReductionSeconds = 60,                 -- how many seconds removed per cleaningDuration
  cleaningCooldown = 30,                         -- cooldown between cleaning attempts (seconds)

  -- bus options
  busModel      = "pbus",                         -- vehicle model to spawn (change if you want pbus or coach)
  busDriverModel= "s_m_m_prisguard_01",          -- ped model for driver
  busSpawnOffset = { x = 0.0, y = 0.0, z = 0.0, h = 309.477 }, -- offset from releaseCoords to spawn the bus
  busDestCoords  = { x = 1180.580, y = 2691.233, z = 37.826 }, -- example destination for the bus route
  busArriveRadius = 10.0,                       -- how close before allowing F to exit
  busDriveSpeed = 20.0,                         -- driving speed for the AI

  debugZone     = true,                          -- enable to visualize jail zone
  fadeTime      = 500,                           -- ms for fade in/out
  pedModel      = "mp_m_freemode_01",           -- freemode ped model check
  -- map out component/prop slots for uniform application
  componentSlots = Config.Clothes.mapping.components,
  propSlots = {
    hat       = Config.Clothes.mapping.props.hat.id1,
    ears      = Config.Clothes.mapping.props.ears.id1,
    watch     = Config.Clothes.mapping.props.watch.id1,
    bracelet  = Config.Clothes.mapping.props.bracelet.id1,
  },

  -- Uniform definitions (drawable = -1 means NO PROP)
  uniforms = {
    male = {
      tshirt      = { drawable = 15,  texture = 0 },
      torso       = { drawable = 65,  texture = 0 },
      decals      = { drawable = 0,   texture = 0 },
      arms        = { drawable = 15,  texture = 0 },
      pants       = { drawable = 38,  texture = 0 },
      shoes       = { drawable = 25,  texture = 0 },
      kevlar      = { drawable = 0,   texture = 0 },
      accessories = { drawable = 0,   texture = 0 },
      badge       = { drawable = 0,   texture = 0 },
      hat         = { drawable = -1,  texture = 0 }, -- NO PROP
      ears        = { drawable = 0,   texture = 0 }, -- you can set ears or leave default
      watch       = { drawable = 0,   texture = 0 },
      bracelet    = { drawable = 0,   texture = 0 },
      -- glasses removed
    },
    female = {
      tshirt      = { drawable = 14,  texture = 0 },
      torso       = { drawable = 48,  texture = 0 },
      decals      = { drawable = 0,   texture = 0 },
      arms        = { drawable = 14,  texture = 0 },
      pants       = { drawable = 63,  texture = 0 },
      shoes       = { drawable = 25,  texture = 0 },
      kevlar      = { drawable = 0,   texture = 0 },
      accessories = { drawable = 0,   texture = 0 },
      badge       = { drawable = 0,   texture = 0 },
      hat         = { drawable = -1,  texture = 0 }, -- NO PROP
      ears        = { drawable = 0,   texture = 0 },
      watch       = { drawable = 0,   texture = 0 },
      bracelet    = { drawable = 0,   texture = 0 },
      -- glasses removed
    },
  },

  -- Penalty & message settings
  punchPenalty   = 60,                            -- seconds added when punching
  punchMessage   = "You punched someone, +%s seconds added!",
  escapePenalty  = 300,                           -- seconds added on escape
  escapeMessage  = "You tried to escape! 300s penalty.",
  releaseMessage = "You have been released from jail.",
}


-- Timer display settings (when jailed)
Config.Timer = {
  format       = "%02d:%02d",
  font         = 0,
  proportional = 1,
  scale        = 0.5,
  color        = { 255, 255, 255, 255 },
  outline      = true,
  position     = { 0.5, 0.94 },
}

return Config
