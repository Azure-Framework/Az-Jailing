





local Config = Config or require('config')
local lib = lib or {} 


local jailed        = false
local timeLeft      = 0
local activeCaseId  = nil
local jailZone      = nil
local jailCoords    = Config.Jail.coords
local releaseCoords = Config.Jail.releaseCoords

local jailClothes    = Config.Jail.uniforms or {}
local componentSlots = Config.Clothes and Config.Clothes.mapping and Config.Clothes.mapping.components or Config.Jail.componentSlots or {}
local propSlots      = Config.Jail.propSlots or {}
local oldClothes     = {}


local cleaningLastUsed = 0
local isCleaning = false


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
  local fine     = tonumber(data.fine) or 0
  local notes    = tostring(data.notes or '')
  TriggerServerEvent('jailer:requestJail', targetId, jailTime, charges, fine, notes)
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

RegisterNUICallback('fetchDocket', function(_, cb)
  TriggerServerEvent('jailer:requestCourtDocket')
  cb({})
end)

RegisterNUICallback('payLawyer', function(data, cb)
  TriggerServerEvent('jailer:requestLawyerPayment', tonumber(data.targetId))
  cb({})
end)

RegisterNUICallback('courtAction', function(data, cb)
  TriggerServerEvent('jailer:requestCourtAction', tonumber(data.caseId), data.action, data.payload or {})
  cb({})
end)

RegisterNUICallback('unjailPlayer', function(data, cb)
  TriggerServerEvent('jailer:requestUnjail', tonumber(data.targetId))
  cb({})
end)

RegisterNetEvent('jailer:returnCourtDocket')
AddEventHandler('jailer:returnCourtDocket', function(records)
  SendNUIMessage({ action = 'courtDocket', records = records or {} })
end)


local function GetConvertedClothes(raw)
  local clothes    = {}
  local components = Config.Clothes and Config.Clothes.mapping and Config.Clothes.mapping.components or {}
  local textures   = Config.Clothes and Config.Clothes.mapping and Config.Clothes.mapping.textures or {}

  for k, v in pairs(raw) do
    local compId = components[k]
    if compId then
      local texKey = textures[k]
      local tex   = texKey and (raw[texKey] or 0) or 0
      clothes[k] = { drawable = v, texture = tex }
    end
  end

  for propName, ids in pairs((Config.Clothes and Config.Clothes.mapping and Config.Clothes.mapping.props) or {}) do
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

RegisterNetEvent('jailer:updateSentence')
AddEventHandler('jailer:updateSentence', function(seconds)
  timeLeft = math.max(0, tonumber(seconds) or timeLeft)
  lib.notify({
    id = 'sentence_update',
    title = 'Sentence Updated',
    description = string.format('Your remaining sentence is %s.', formatDuration(timeLeft)),
    type = 'inform',
    position = 'top'
  })
end)

RegisterNetEvent('jailer:releaseNow')
AddEventHandler('jailer:releaseNow', function(reason)
  jailed = false
  timeLeft = 0
  activeCaseId = nil
  if jailZone then jailZone:remove() jailZone = nil end
  DoScreenFadeOut(Config.Jail.fadeTime or 500)
  Citizen.Wait(Config.Jail.fadeTime or 500)
  SetEntityCoords(PlayerPedId(), table.unpack(releaseCoords))
  RestoreOldClothes()
  DoScreenFadeIn(Config.Jail.fadeTime or 500)
  lib.notify({
    id = 'court_release',
    title = 'Release',
    description = tostring(reason or Config.Jail.releaseMessage or 'You have been released.'),
    type = 'success',
    position = 'top'
  })
end)

local function applyJailUniform()
  local ped = PlayerPedId()
  ClearAllPedProps(ped)
  local model = GetEntityModel(ped)
  local isMale = (model == GetHashKey(Config.Jail.pedModel))
  local outfit = isMale and (jailClothes.male or {}) or (jailClothes.female or {})

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


local function RemoveWeapons()
  RemoveAllPedWeapons(PlayerPedId(), true)
end


AddEventHandler('gameEventTriggered', function(name, args)
  if name == "CEventNetworkEntityDamage" and jailed then
    if args[2] == PlayerPedId() then
      timeLeft = timeLeft + (Config.Jail.punchPenalty or 300)
      lib.notify({
        id          = 'punch_penalty',
        title       = 'Jail Violation',
        description = string.format(Config.Jail.punchMessage or "You got a penalty of %d seconds.", (Config.Jail.punchPenalty or 300)),
        type        = 'error',
        position    = 'top'
      })
    end
  end
end)


Citizen.CreateThread(function()
  while true do
    Citizen.Wait(0)
    if jailed and timeLeft > 0 then
      local txt = formatDuration(timeLeft)
      SetTextFont(Config.Timer.font or 4)
      SetTextProportional(Config.Timer.proportional or 1)
      SetTextScale(Config.Timer.scale or 0.4, Config.Timer.scale or 0.4)
      SetTextColour(table.unpack(Config.Timer.color or {255,255,255,255}))
      if Config.Timer.outline then SetTextOutline() end
      BeginTextCommandDisplayText("STRING")
      AddTextComponentSubstringPlayerName(txt)
      EndTextCommandDisplayText(table.unpack(Config.Timer.position or {0.9, 0.05}))
    end
  end
end)




function DrawText3D(x,y,z, text)
  local onScreen, _x, _y = World3dToScreen2d(x, y, z)
  if onScreen then
    SetTextScale(0.35, 0.35)
    SetTextFont(4)
    SetTextProportional(1)
    SetTextColour(255, 255, 255, 215)
    SetTextOutline()
    SetTextEntry("STRING")
    AddTextComponentString(text)
    DrawText(_x, _y)
  end
end

local function RequestModelAsync(hash)
  if not HasModelLoaded(hash) then
    RequestModel(hash)
    local timeout = GetGameTimer() + 5000
    while not HasModelLoaded(hash) and GetGameTimer() < timeout do Citizen.Wait(10) end
  end
  return HasModelLoaded(hash)
end





local function playGardenerFallbackAnimOnce(ped, durationMs)
  local dicts = {
    "amb@world_human_gardener_plant@male@base",
    "amb@world_human_gardener_plant@female@base",
    "amb@world_human_gardener_plant@base"
  }
  local anims = { "work_base", "base", "idle_a" }

  for _, dict in ipairs(dicts) do
    RequestAnimDict(dict)
    local timeout = GetGameTimer() + 2000
    while not HasAnimDictLoaded(dict) and GetGameTimer() < timeout do Citizen.Wait(10) end
    if HasAnimDictLoaded(dict) then
      for _, anim in ipairs(anims) do
        
        TaskPlayAnim(ped, dict, anim, 8.0, -8.0, durationMs, 1, 0.0, false, false, false)
        return dict, anim
      end
    end
  end
  return nil, nil
end


local function StartCleaningTask()
  if not jailed or isCleaning then return end
  if (GetGameTimer() / 1000) - cleaningLastUsed < (Config.Jail.cleaningCooldown or 30) then
    lib.notify({ title = "Cleaning", description = "Cooling down.", type = 'error', position = 'top' })
    return
  end

  isCleaning = true
  local ped = PlayerPedId()

  
  SetCurrentPedWeapon(ped, GetHashKey("weapon_unarmed"), true)

  lib.notify({ title = "Cleaning", description = "You start pulling weeds with a shovel...", type = 'inform', position = 'top' })

  
  local cleaningActive = true
  local fallbackDict, fallbackAnim

  
  local dicts = {
    "amb@world_human_gardener_plant@male@base",
    "amb@world_human_gardener_plant@female@base",
    "amb@world_human_gardener_plant@base"
  }
  local anims = { "work_base", "base", "idle_a" }

  
  TaskStartScenarioInPlace(ped, "WORLD_HUMAN_GARDENER_PLANT", 0, true)
  Citizen.Wait(250)
  local usingScenario = (IsPedUsingScenario and IsPedUsingScenario(ped)) or false

  
  if not usingScenario then
    for _, d in ipairs(dicts) do
      RequestAnimDict(d)
      local to = GetGameTimer() + 1500
      while not HasAnimDictLoaded(d) and GetGameTimer() < to do Citizen.Wait(10) end
      if HasAnimDictLoaded(d) then
        fallbackDict = d
        break
      end
    end
    if fallbackDict then
      fallbackAnim = anims[1] or anims[2] or anims[3]
      
      TaskPlayAnim(ped, fallbackDict, fallbackAnim, 8.0, -8.0, -1, 1, 0.0, false, false, false)
    end
  end

  
  Citizen.CreateThread(function()
    while cleaningActive and jailed and isCleaning do
      
      if IsPedUsingScenario and IsPedUsingScenario(ped) then
        
      else
        
        if not usingScenario then
          
          TaskStartScenarioInPlace(ped, "WORLD_HUMAN_GARDENER_PLANT", 0, true)
          Citizen.Wait(100)
          if IsPedUsingScenario and IsPedUsingScenario(ped) then
            usingScenario = true
            
          else
            
            if fallbackDict and fallbackAnim then
              if not IsEntityPlayingAnim(ped, fallbackDict, fallbackAnim, 3) then
                TaskPlayAnim(ped, fallbackDict, fallbackAnim, 8.0, -8.0, -1, 1, 0.0, false, false, false)
              end
            end
          end
        end
      end

      
      SetCurrentPedWeapon(ped, GetHashKey("weapon_unarmed"), true)

      Citizen.Wait(250)
    end
  end)

  
  local ok = false
  local success, perr = pcall(function()
    ok = lib.progressBar({
      duration = 1500, 
      label = "Pulling weeds...",
      useWhileDead = false,
      canCancel = true,
      disable = {
        car = true,
        combat = true,
        move = true,
        sprint = true,
        mouse = true
      },
      
    })
  end)

  
  cleaningActive = false
  Citizen.Wait(80) 
  ClearPedTasksImmediately(ped)

  
  isCleaning = false
  cleaningLastUsed = GetGameTimer() / 1000

  if not success then
    lib.notify({ title = "Cleaning", description = "An error occurred while trying to clean.", type = 'error', position = 'top' })
    return
  end

  if ok then
    
    local reduction = math.random(5, 10)
    timeLeft = math.max(0, timeLeft - reduction)
    if activeCaseId then TriggerServerEvent('jailer:updateRemaining', activeCaseId, timeLeft) end
    lib.notify({
      id = 'clean_reduce',
      title = 'Cleaning Complete',
      description = string.format('You reduced %d seconds from your sentence.', reduction),
      type = 'success',
      position = 'top'
    })
  else
    
    lib.notify({
      id = 'clean_cancel',
      title = 'Cleaning Cancelled',
      description = 'You stopped pulling weeds.',
      type = 'warning',
      position = 'top'
    })
  end
end


local function CreateCleaningMarkers()
  local markers = {}
  for _, off in ipairs(Config.Jail.cleaningSpots or {}) do
    local cx = Config.Jail.coords[1] + (off.x or 0)
    local cy = Config.Jail.coords[2] + (off.y or 0)
    local cz = Config.Jail.coords[3] + (off.z or 0)
    table.insert(markers, vector3(cx, cy, cz))
  end
  return markers
end




local function SpawnPrisonBusAndTakeTrip(spawnCoords, destCoords)
  local function normalizeCoord(t)
    if not t then return nil end
    if t.x and t.y then return { x = tonumber(t.x), y = tonumber(t.y), z = tonumber(t.z) or 0.0 } end
    if t[1] and t[2] then return { x = tonumber(t[1]), y = tonumber(t[2]), z = tonumber(t[3]) or 0.0 } end
    return nil
  end

  local cfgDest = normalizeCoord(destCoords) or normalizeCoord(Config.Jail.busDestCoords)
  if not cfgDest then
    if Config.Jail.debugZone then print("[jail] invalid destination coords; aborting bus spawn") end
    return
  end

  
  if (math.abs(cfgDest.x) < 0.0001 and math.abs(cfgDest.y) < 0.0001) then
    if Config.Jail.debugZone then print(("[jail] destination is 0,0 -> aborting spawn (x=%.4f y=%.4f)"):format(cfgDest.x, cfgDest.y)) end
    return
  end

  
  if not cfgDest.z or math.abs(cfgDest.z) < 0.01 then
    for h = 0, 100 do
      local ok, z = GetGroundZFor_3dCoord(cfgDest.x, cfgDest.y, h + 0.0, 0)
      if ok then
        cfgDest.z = z
        break
      end
    end
    cfgDest.z = cfgDest.z or 0.0
  end

  local vehModel    = GetHashKey(Config.Jail.busModel or "pbus")
  local driverModel = GetHashKey(Config.Jail.busDriverModel or "s_m_m_prisguard_01")

  
  SetNewWaypoint(cfgDest.x, cfgDest.y)
  local destBlip = AddBlipForCoord(cfgDest.x, cfgDest.y, cfgDest.z or 0.0)
  if destBlip then
    SetBlipSprite(destBlip, 380)
    SetBlipColour(destBlip, 2)
    SetBlipRoute(destBlip, true)
    SetBlipRouteColour(destBlip, 3)
  end

  
  RequestModelAsync(vehModel)
  RequestModelAsync(driverModel)

  
  local spawnZ = (spawnCoords.z or 0.0) + 0.8
  local bus = CreateVehicle(vehModel, spawnCoords.x, spawnCoords.y, spawnZ, spawnCoords.h or 0.0, true, false)
  if not DoesEntityExist(bus) then
    if Config.Jail.debugZone then print("[jail] failed to create bus vehicle") end
    if destBlip then RemoveBlip(destBlip) end
    return
  end

  SetVehicleOnGroundProperly(bus)
  SetVehicleHasBeenOwnedByPlayer(bus, false)
  SetEntityAsMissionEntity(bus, true, true)
  SetVehicleEngineOn(bus, true, true, true)
  SetVehicleDoorsLocked(bus, 1)

  
  local driver = CreatePedInsideVehicle(bus, 4, driverModel, -1, true, false)
  if not DoesEntityExist(driver) then
    if Config.Jail.debugZone then print("[jail] failed to create driver ped") end
    if destBlip then RemoveBlip(destBlip) end
    SetEntityAsNoLongerNeeded(bus); DeleteVehicle(bus)
    return
  end

  SetBlockingOfNonTemporaryEvents(driver, true)
  SetPedKeepTask(driver, true)
  SetEntityAsMissionEntity(driver, true, true)

  
  TaskWarpPedIntoVehicle(driver, bus, -1)
  Citizen.Wait(200)
  if not IsPedInVehicle(driver, bus, true) then
    TaskWarpPedIntoVehicle(driver, bus, -1)
    Citizen.Wait(200)
  end

  
  local speed = Config.Jail.busDriveSpeed or 18.0
  pcall(function() SetDriverAbility(driver, 1.0) end)
  pcall(function() SetDriverAggressiveness(driver, 0.0) end)
  pcall(function() SetDriveTaskCruiseSpeed(driver, speed) end)
  pcall(function() SetDriveTaskDrivingStyle(driver, 786603) end)

  
  local busBlip = AddBlipForEntity(bus)
  if DoesBlipExist(busBlip) then
    SetBlipSprite(busBlip, 56)
    BeginTextCommandSetBlipName("STRING")
    AddTextComponentString("Prison Bus")
    EndTextCommandSetBlipName(busBlip)
  end

  
  local playerPed = PlayerPedId()
  Citizen.Wait(150)
  if DoesEntityExist(bus) then
    TaskWarpPedIntoVehicle(playerPed, bus, 0)
    Citizen.Wait(150)
  end

  
  if IsScreenFadedOut() then
    DoScreenFadeIn(Config.Jail.fadeTime or 500)
    Citizen.Wait(Config.Jail.fadeTime or 500)
  end

  
  local tripActive = true
  Citizen.CreateThread(function()
    while tripActive and DoesEntityExist(bus) do
      Citizen.Wait(0)
      DisableControlAction(0, 75, true) 
      DisableControlAction(0, 59, true)
      DisableControlAction(0, 60, true)
      DisableControlAction(0, 62, true)
      DisableControlAction(0, 63, true)
      DisableControlAction(0, 64, true)
      SetEntityInvincible(playerPed, true)
    end
    SetEntityInvincible(playerPed, false)
  end)

  
  TaskVehicleDriveToCoordLongrange(driver, bus, cfgDest.x, cfgDest.y, cfgDest.z, speed, 786603, 1.0)

  
  local arrived = false
  local startTick = GetGameTimer()
  local overallTimeout = (Config.Jail.busOverallTimeoutMs and Config.Jail.busOverallTimeoutMs) or 150000 

  while DoesEntityExist(bus) and not arrived and (GetGameTimer() - startTick) < overallTimeout do
    Citizen.Wait(800)
    local bx,by,bz = table.unpack(GetEntityCoords(bus, true))
    local dist = #(vector3(bx,by,bz) - vector3(cfgDest.x, cfgDest.y, cfgDest.z))
    if Config.Jail.debugZone then
      print(('[jail] Bus at %.1f,%.1f (dist=%.1f)'):format(bx,by,dist))
    end
    if dist <= (Config.Jail.busArriveRadius or 10.0) then
      arrived = true
      break
    end
  end

  
  if arrived and DoesEntityExist(bus) then
    if destBlip then RemoveBlip(destBlip) end
    if DoesBlipExist(busBlip) then RemoveBlip(busBlip) end

    
    SetVehicleForwardSpeed(bus, 0.0)
    SetVehicleBrakeLights(bus, true)
    SetVehicleEngineOn(bus, false, true, true)
    FreezeEntityPosition(bus, true)

    lib.notify({ title = "Bus Arrived", description = "Press ~INPUT_VEH_FLY_YAW_DOWN~ (F) to exit the bus.", type = 'inform', position = 'top' })
    local canLeave = false
    while DoesEntityExist(bus) and not canLeave do
      Citizen.Wait(0)
      DrawText3D(cfgDest.x, cfgDest.y, (cfgDest.z or 0.0) + 1.0, "Press ~y~F ~w~to exit the bus")
      if IsControlJustReleased(0, 23) then canLeave = true end
    end

    
    FreezeEntityPosition(bus, false)
    TaskLeaveVehicle(playerPed, bus, 0)

    
    local waitStart = GetGameTimer()
    local maxWait = 20000 
    while DoesEntityExist(bus) and IsPedInVehicle(playerPed, bus, true) and (GetGameTimer() - waitStart) < maxWait do
      Citizen.Wait(100)
    end

    
    if not IsPedInVehicle(playerPed, bus, true) then
      
      local px,py,pz = table.unpack(GetEntityCoords(playerPed, true))
      local bx,by,bz = table.unpack(GetEntityCoords(bus, true))
      local distAfterExit = #(vector3(px,py,pz) - vector3(bx,by,bz))
      local safeDelay = 600
      if distAfterExit < 3.0 then
        Citizen.Wait(500) 
      else
        Citizen.Wait(safeDelay)
      end

      if DoesEntityExist(driver) then
        SetBlockingOfNonTemporaryEvents(driver, false)
        
        TaskVehicleDriveWander(driver, bus, speed, 786603)
      end

      
      Citizen.CreateThread(function()
        local t0 = GetGameTimer()
        while DoesEntityExist(bus) and (GetGameTimer() - t0) < 20000 do Citizen.Wait(500) end
        if DoesEntityExist(driver) then SetEntityAsNoLongerNeeded(driver); DeleteEntity(driver) end
        if DoesEntityExist(bus) then SetEntityAsNoLongerNeeded(bus); DeleteVehicle(bus) end
      end)
    else
      
      if Config.Jail.debugZone then print("[jail] player did not exit bus in time; teleporting player") end
      SetEntityCoords(playerPed, cfgDest.x + 1.0, cfgDest.y + 1.0, cfgDest.z or 0.0)
      if DoesEntityExist(driver) then SetBlockingOfNonTemporaryEvents(driver, false); TaskVehicleDriveWander(driver, bus, speed, 786603) end
      Citizen.CreateThread(function()
        local t0 = GetGameTimer()
        while DoesEntityExist(bus) and (GetGameTimer() - t0) < 20000 do Citizen.Wait(500) end
        if DoesEntityExist(driver) then SetEntityAsNoLongerNeeded(driver); DeleteEntity(driver) end
        if DoesEntityExist(bus) then SetEntityAsNoLongerNeeded(bus); DeleteVehicle(bus) end
      end)
    end

  else
    
    if destBlip then RemoveBlip(destBlip) end
    if DoesBlipExist(busBlip) then RemoveBlip(busBlip) end
    if Config.Jail.debugZone then print("[jail] bus failed to reach destination in time; cleaning up and teleporting player") end

    if DoesEntityExist(driver) then SetEntityAsNoLongerNeeded(driver); DeleteEntity(driver) end
    if DoesEntityExist(bus) then SetEntityAsNoLongerNeeded(bus); DeleteVehicle(bus) end

    lib.notify({ title = "Bus Error", description = "Transport failed - teleporting to release point.", type = 'error', position = 'top' })
    SetEntityCoords(PlayerPedId(), cfgDest.x, cfgDest.y, cfgDest.z)
  end

  tripActive = false
end




RegisterNetEvent('jailer:performJail')
AddEventHandler('jailer:performJail', function(minutes, caseId)
  if jailZone then jailZone:remove() jailZone = nil end
  jailed   = true
  timeLeft = minutes * 60
  activeCaseId = tonumber(caseId)

  local ped = PlayerPedId()
  DoScreenFadeOut(Config.Jail.fadeTime or 500)
  Citizen.Wait(Config.Jail.fadeTime or 500)

  SaveOldClothes()
  RemoveWeapons()
  SetEntityCoords(ped, table.unpack(jailCoords))
  applyJailUniform()

  DoScreenFadeIn(Config.Jail.fadeTime or 500)

  
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

  
  jailZone = lib.zones.box({
    coords = vector3(table.unpack(jailCoords)),
    size   = vector3(table.unpack(Config.Jail.zoneSize)),
    onExit = function()
      if not jailed then return end
      SetEntityCoords(ped, table.unpack(jailCoords))
      timeLeft = timeLeft + (Config.Jail.escapePenalty or 600)
      lib.notify({
        id          = 'escape_penalty',
        title       = 'Escape Attempt',
        description = Config.Jail.escapeMessage or "You cannot leave the prison area!",
        type        = 'warning',
        position    = 'top'
      })
    end,
    debug = Config.Jail.debugZone,
  })

  
  local cleaningMarkers = CreateCleaningMarkers()

  
  Citizen.CreateThread(function()
    while jailed do
      Citizen.Wait(0)
      local ped = PlayerPedId()
      local px,py,pz = table.unpack(GetEntityCoords(ped))
      for _, mpos in ipairs(cleaningMarkers) do
        local dist = #(vector3(px,py,pz) - mpos)
        if dist < 10.0 then
          DrawText3D(mpos.x, mpos.y, mpos.z + 1.0, "[E] Pull Weeds")
          if dist < 2.0 and IsControlJustReleased(0, 38) then 
            StartCleaningTask()
          end
        end
      end
    end
  end)

  
  Citizen.CreateThread(function()
    while jailed and timeLeft > 0 do
      Citizen.Wait(1000)
      timeLeft = timeLeft - 1
      if activeCaseId and timeLeft % 60 == 0 then
        TriggerServerEvent('jailer:updateRemaining', activeCaseId, timeLeft)
      end
    end

    jailed   = false
    timeLeft = 0
    if activeCaseId then
      TriggerServerEvent('jailer:updateRemaining', activeCaseId, 0)
      activeCaseId = nil
    end
    if jailZone then jailZone:remove() jailZone = nil end

    
    DoScreenFadeOut(Config.Jail.fadeTime or 500)
    Citizen.Wait(Config.Jail.fadeTime or 500)

    
    if not Config.Jail.useBus then
      
      SetEntityCoords(PlayerPedId(), table.unpack(releaseCoords))
      DoScreenFadeIn(Config.Jail.fadeTime or 500)
      RestoreOldClothes()

      lib.notify({
        id          = 'release_notice',
        title       = 'Release',
        description = Config.Jail.releaseMessage or "You have been released.",
        type        = 'success',
        position    = 'top'
      })
      return
    end

    
    local spawnBase = vector3(table.unpack(releaseCoords))
    local spawnOff  = Config.Jail.busSpawnOffset or { x = 0.0, y = 0.0, z = 0.0, h = 0.0 }
    local spawn = {
      x = spawnBase.x + spawnOff.x,
      y = spawnBase.y + spawnOff.y,
      z = spawnBase.z + (spawnOff.z or 0.0) + 1.0,
      h = spawnOff.h or 0.0
    }

    
    local dest = Config.Jail.busDestCoords

    
    SetEntityCoords(PlayerPedId(), spawn.x, spawn.y, spawn.z)
    
    RestoreOldClothes()

    lib.notify({ id = 'release_notice', title = 'Release', description = Config.Jail.releaseMessage or "You have been released.", type = 'success', position = 'top' })

    Citizen.Wait(300)

    Citizen.CreateThread(function()
      SpawnPrisonBusAndTakeTrip(spawn, dest)
    end)
  end)
end)


RegisterCommand('stopfade', function()
  local ped = PlayerPedId()
  if IsScreenFadedOut() then DoScreenFadeIn(100) end
  jailed   = false
  timeLeft = 0
  activeCaseId = nil
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


return
