-- Ensure Config is loaded
local Config = Config or require 'config'

local jailed        = false
local timeLeft      = 0
local jailZone      = nil
local jailCoords    = Config.Jail.coords
local releaseCoords = Config.Jail.releaseCoords

-- Utility: format seconds into days/hours/minutes/seconds string
local function formatDuration(sec)
  local days  = math.floor(sec / 86400); sec = sec % 86400
  local hours = math.floor(sec / 3600);  sec = sec % 3600
  local mins  = math.floor(sec / 60);    local secs = sec % 60

  if days  > 0 then
    return string.format("%d day%s %02d:%02d:%02d",
      days, days>1 and "s" or "", hours, mins, secs)
  elseif hours > 0 then
    return string.format("%d hr%s %02d:%02d",
      hours, hours>1 and "s" or "", mins, secs)
  elseif mins  > 0 then
    return string.format("%d min %02d sec", mins, secs)
  else
    return string.format("%d sec", secs)
  end
end

-- Commands & NUI callbacks
RegisterCommand('jailer', function()
  TriggerServerEvent('jail:checkPermission')
end, false)

RegisterNetEvent('jail:permissionResult')
AddEventHandler('jail:permissionResult', function(allowed)
  if allowed then
    SetNuiFocus(true, true)
    SendNUIMessage({ action = 'open' })
  else
    TriggerEvent('chat:addMessage', {
      args = { '^1SYSTEM', 'You do not have permission to use this.' }
    })
  end
end)

RegisterCommand('casesearch', function()
  SetNuiFocus(true, true)
  SendNUIMessage({ action = 'openCaseSearch' })
end)

RegisterNUICallback('close', function(_, cb)
  SetNuiFocus(false, false)
  cb('ok')
end)

RegisterNUICallback('submitJail', function(data, cb)
  local targetId = tonumber(data.targetId)
  local jailTime = tonumber(data.time)
  local charges  = data.charges
  TriggerServerEvent('jailer:requestJail', targetId, jailTime, charges)
  cb({ status = 'pending' })
end)

RegisterNetEvent('jailer:jailResult')
AddEventHandler('jailer:jailResult', function(res)
  if res.success then
    SetNuiFocus(false, false)
    SendNUIMessage({ action = 'close' })
  else
    SendNUIMessage({ action = 'jailError', message = res.message or 'Unknown error' })
  end
end)

RegisterNUICallback('fetchCases', function(data, cb)
  local targetId = tonumber(data.userId)
  if not targetId then return cb({ error = 'Invalid User ID' }) end
  TriggerServerEvent('jailer:requestCaseRecords', targetId)
  cb({})
end)

RegisterNetEvent('jailer:returnCaseRecords')
AddEventHandler('jailer:returnCaseRecords', function(records)
  SendNUIMessage({ action = 'caseRecords', records = records })
end)

-- Clothing save/restore setup
local jailClothes    = Config.Jail.uniforms
local componentSlots = Config.Jail.componentSlots
local propSlots      = Config.Jail.propSlots
local oldClothes     = {}

local function GetConvertedClothes(raw)
  local clothes    = {}
  local components = Config.Clothes.mapping.components
  local textures   = Config.Clothes.mapping.textures

  for k, v in pairs(raw) do
    local compId = components[k]
    if compId then
      local texKey = textures[k]
      local tex   = texKey and (raw[texKey] or 0) or 0
      clothes[k] = { drawable = v, texture = tex }
    end
  end

  for propName, ids in pairs(Config.Clothes.mapping.props) do
    clothes[propName] = {
      drawable = raw[ids.id1] or -1,
      texture  = raw[ids.id2] or 0
    }
  end

  return clothes
end

local function SaveOldClothes()
  local ped = PlayerPedId()
  for name, slot in pairs(componentSlots) do
    oldClothes[name]   = GetPedDrawableVariation(ped, slot)
    oldClothes[name.."_tex"] = GetPedTextureVariation(ped, slot)
  end
  for name, slot in pairs(propSlots) do
    oldClothes[name]   = GetPedPropIndex(ped, slot)
    oldClothes[name.."_tex"] = GetPedPropTextureIndex(ped, slot)
  end
end

local function RestoreOldClothes()
  local ped   = PlayerPedId()
  local conv  = GetConvertedClothes(oldClothes)
  for name, vals in pairs(conv) do
    local draw, tex = vals.drawable, vals.texture or 0
    if componentSlots[name] then
      SetPedComponentVariation(ped, componentSlots[name], draw, tex, 0)
    elseif propSlots[name] then
      if draw >= 0 then
        SetPedPropIndex(ped, propSlots[name], draw, tex, true)
      else
        ClearPedProp(ped, propSlots[name])
      end
    end
  end
end

local function applyJailUniform()
  local ped = PlayerPedId()
  ClearAllPedProps(ped)
  local model = GetEntityModel(ped)
  local isMale = (model == GetHashKey(Config.Jail.pedModel))
  local outfit = isMale and jailClothes.male or jailClothes.female

  for name, vals in pairs(outfit) do
    local draw, tex = vals.drawable, vals.texture or 0
    if componentSlots[name] then
      SetPedComponentVariation(ped, componentSlots[name], draw, tex, 0)
    elseif propSlots[name] then
      if draw >= 0 then
        SetPedPropIndex(ped, propSlots[name], draw, tex, true)
      else
        ClearPedProp(ped, propSlots[name])
      end
    end
  end
end

-- Remove weapons
local function RemoveWeapons()
  RemoveAllPedWeapons(PlayerPedId(), true)
end

-- Penalty on damage
AddEventHandler('gameEventTriggered', function(name, args)
  if name == "CEventNetworkEntityDamage" and jailed then
    if args[2] == PlayerPedId() then
      timeLeft = timeLeft + Config.Jail.punchPenalty
      lib.notify({
        id          = 'punch_penalty',
        title       = 'Jail Violation',
        description = string.format(Config.Jail.punchMessage, Config.Jail.punchPenalty),
        type        = 'error',
        position    = 'top'
      })
    end
  end
end)

-- Timer display
Citizen.CreateThread(function()
  while true do
    Citizen.Wait(0)
    if jailed and timeLeft > 0 then
      local txt = formatDuration(timeLeft)
      SetTextFont(Config.Timer.font)
      SetTextProportional(Config.Timer.proportional)
      SetTextScale(Config.Timer.scale, Config.Timer.scale)
      SetTextColour(table.unpack(Config.Timer.color))
      if Config.Timer.outline then SetTextOutline() end
      BeginTextCommandDisplayText("STRING")
      AddTextComponentSubstringPlayerName(txt)
      EndTextCommandDisplayText(table.unpack(Config.Timer.position))
    end
  end
end)

-- Perform Jail
RegisterNetEvent('jailer:performJail')
AddEventHandler('jailer:performJail', function(minutes)
  if jailZone then jailZone:remove() jailZone = nil end
  jailed   = true
  timeLeft = minutes * 60

  local ped = PlayerPedId()
  DoScreenFadeOut(Config.Jail.fadeTime)
  Citizen.Wait(Config.Jail.fadeTime)

  SaveOldClothes()
  RemoveWeapons()
  SetEntityCoords(ped, table.unpack(jailCoords))
  applyJailUniform()

  DoScreenFadeIn(Config.Jail.fadeTime)

  -- BIG red scaleform banner
  StartScreenEffect("DeathFailOut", 0, false)
  local scaleform = RequestScaleformMovie("MP_BIG_MESSAGE_FREEMODE")
  while not HasScaleformMovieLoaded(scaleform) do Citizen.Wait(0) end
  PlaySoundFrontend(-1, "Bed", "WastedSounds", true)
  ShakeGameplayCam("DEATH_FAIL_IN_EFFECT_SHAKE", 1.0)
  PushScaleformMovieFunction(scaleform, "SHOW_SHARD_WASTED_MP_MESSAGE")
    BeginTextComponent("STRING")
    AddTextComponentString("~r~SENTENCED")
    EndTextComponent()
  PopScaleformMovieFunctionVoid()
  Citizen.Wait(500)
  PlaySoundFrontend(-1, "TextHit", "WastedSounds", true)
  Citizen.CreateThread(function()
    local start = GetGameTimer()
    while GetGameTimer() - start < 5000 do
      DrawScaleformMovieFullscreen(scaleform, 255,255,255,255)
      Citizen.Wait(0)
    end
    StopScreenEffect("DeathFailOut")
  end)

  lib.notify({
    id          = 'jail_start',
    title       = 'Jailed',
    description = string.format('You have been sentenced to %s.', formatDuration(timeLeft)),
    type        = 'inform',
    position    = 'top'
  })

  -- jail zone & escape
  jailZone = lib.zones.box({
    coords = vector3(table.unpack(jailCoords)),
    size   = vector3(table.unpack(Config.Jail.zoneSize)),
    onExit = function()
      if not jailed then return end
      SetEntityCoords(ped, table.unpack(jailCoords))
      timeLeft = timeLeft + Config.Jail.escapePenalty
      lib.notify({
        id          = 'escape_penalty',
        title       = 'Escape Attempt',
        description = Config.Jail.escapeMessage,
        type        = 'warning',
        position    = 'top'
      })
    end,
    debug = Config.Jail.debugZone,
  })

  -- countdown & release
  Citizen.CreateThread(function()
    while jailed and timeLeft > 0 do
      Citizen.Wait(1000)
      timeLeft = timeLeft - 1
    end

    jailed   = false
    timeLeft = 0
    if jailZone then jailZone:remove() jailZone = nil end

    DoScreenFadeOut(Config.Jail.fadeTime)
    Citizen.Wait(Config.Jail.fadeTime)
    SetEntityCoords(ped, table.unpack(releaseCoords))
    DoScreenFadeIn(Config.Jail.fadeTime)

    RestoreOldClothes()

    lib.notify({
      id          = 'release_notice',
      title       = 'Release',
      description = Config.Jail.releaseMessage,
      type        = 'success',
      position    = 'top'
    })
  end)
end)

-- Emergency override
RegisterCommand('stopfade', function()
  local ped = PlayerPedId()
  if IsScreenFadedOut() then DoScreenFadeIn(100) end
  jailed   = false
  timeLeft = 0
  if jailZone then jailZone:remove() jailZone = nil end
  SetEntityCoords(ped, table.unpack(releaseCoords))
  RestoreOldClothes()
  lib.notify({
    id          = 'stopfade_cmd',
    title       = 'Jail Override',
    description = 'Fade/lock cleared.',
    type        = 'success',
    position    = 'top'
  })
end, false)
