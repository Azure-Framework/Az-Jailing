Config = {}

Config.FrameworkResource = 'Az-Framework'

Config.Access = {
  AdminAce = 'az.jailer.admin',
  JailerAce = 'az.jailer.use',
  CourtAce = 'az.jailer.court',
  JailerJobs = {
    police = true,
    sheriff = true,
    corrections = true,
    doc = true
  },
  CourtJobs = {
    judge = true,
    doj = true,
    lawyer = true
  }
}

Config.Court = {
  LawyerPayment = 500,
  MaxSentenceMinutes = 720,
  MaxFine = 250000,
  InteractionDistance = 8.0,
  AllowRemoteAdmin = true
}

Config.Clothes = {
  mapping = {
    components = {
      tshirt = 8,
      torso = 11,
      decals = 10,
      arms = 3,
      pants = 4,
      shoes = 6,
      accessories = 7,
      kevlar = 9,
      badge = 7
    },
    textures = {
      tshirt = "tshirt_2",
      torso = "torso_2",
      decals = "decals_2",
      arms = "arms_2",
      pants = "pants_2",
      shoes = "shoes_2",
      accessories = "accessories_2",
      kevlar = "kevlar_2",
      badge = "badge_2"
    },
    props = {
      hat = { id1 = 0, id2 = 0 },
      ears = { id1 = 2, id2 = 2 },
      watch = { id1 = 6, id2 = 0 },
      bracelet = { id1 = 7, id2 = 0 }
    }
  }
}

Config.Jail = {
  coords = { 1673.697, 2510.594, 45.565 },
  releaseCoords = { 1956.901, 2617.651, 45.913 },
  zoneSize = { 150.0, 220.0, 60.0 },
  fadeTime = 500,
  punchPenalty = 60,
  punchMessage = "You punched someone, +%s seconds added.",
  escapePenalty = 300,
  escapeMessage = "You tried to escape. 300 seconds were added.",
  releaseMessage = "You have been released from jail.",
  useBus = true,
  cleaningSpots = {
    { x = 2.0, y = 4.0, z = 0.0 },
    { x = -10.0, y = 20.0, z = 0.0 }
  },
  cleaningDurationSeconds = 20,
  cleaningReductionSeconds = 60,
  cleaningCooldown = 30,
  busModel = "pbus",
  busDriverModel = "s_m_m_prisguard_01",
  busSpawnOffset = { x = 0.0, y = 0.0, z = 0.0, h = 309.477 },
  busDestCoords = { x = 1180.580, y = 2691.233, z = 37.826 },
  busArriveRadius = 10.0,
  busDriveSpeed = 20.0,
  busOverallTimeoutMs = 150000,
  debugZone = false,
  pedModel = "mp_m_freemode_01",
  componentSlots = Config.Clothes.mapping.components,
  propSlots = {
    hat = Config.Clothes.mapping.props.hat.id1,
    ears = Config.Clothes.mapping.props.ears.id1,
    watch = Config.Clothes.mapping.props.watch.id1,
    bracelet = Config.Clothes.mapping.props.bracelet.id1
  },
  uniforms = {
    male = {
      tshirt = { drawable = 15, texture = 0 },
      torso = { drawable = 65, texture = 0 },
      decals = { drawable = 0, texture = 0 },
      arms = { drawable = 15, texture = 0 },
      pants = { drawable = 38, texture = 0 },
      shoes = { drawable = 25, texture = 0 },
      kevlar = { drawable = 0, texture = 0 },
      accessories = { drawable = 0, texture = 0 },
      badge = { drawable = 0, texture = 0 },
      hat = { drawable = -1, texture = 0 },
      ears = { drawable = 0, texture = 0 },
      watch = { drawable = 0, texture = 0 },
      bracelet = { drawable = 0, texture = 0 }
    },
    female = {
      tshirt = { drawable = 14, texture = 0 },
      torso = { drawable = 48, texture = 0 },
      decals = { drawable = 0, texture = 0 },
      arms = { drawable = 14, texture = 0 },
      pants = { drawable = 63, texture = 0 },
      shoes = { drawable = 25, texture = 0 },
      kevlar = { drawable = 0, texture = 0 },
      accessories = { drawable = 0, texture = 0 },
      badge = { drawable = 0, texture = 0 },
      hat = { drawable = -1, texture = 0 },
      ears = { drawable = 0, texture = 0 },
      watch = { drawable = 0, texture = 0 },
      bracelet = { drawable = 0, texture = 0 }
    }
  }
}

Config.Timer = {
  font = 0,
  proportional = 1,
  scale = 0.5,
  color = { 255, 255, 255, 255 },
  outline = true,
  position = { 0.5, 0.94 }
}

return Config
