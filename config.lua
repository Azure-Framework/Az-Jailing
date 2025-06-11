Config = {}

-- Discord bot and guild settings
Config.Discord = {
    botToken    = "",    -- include the 'Bot ' prefix
    guildId     = "1237234540561436673",
    allowedRoles = {
        ["1237262220241535018"] = true,  -- Moderator
        ["234567890123456789"] = true,  -- Admin
        -- add more RoleIDs as needed
    }
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
  coords        = { 451.0, -987.5, 30.6 },        -- where to teleport jailed players
  releaseCoords = { 461.1, -995.4, 24.9 },        -- where to release them
  zoneSize      = { 6.0, 6.0, 2.0 },              -- jail boundary box
  debugZone     = false,                          -- enable to visualize jail zone
  fadeTime      = 500,                            -- ms for fade in/out
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
