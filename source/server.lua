local function getDiscordIdFromIdentifiers(ids)
  for _, id in ipairs(ids) do
    if id:match("^discord:%d+$") then return id:sub(9) end
  end
  return nil
end

local function getDiscordIdent(src)
  return getDiscordIdFromIdentifiers(GetPlayerIdentifiers(src))
end

local function hasPermission(src, cb)
  local discordId = getDiscordIdent(src)
  if not discordId then return cb(false) end
  local url = string.format(
    "https://discord.com/api/guilds/%s/members/%s",
    Config.Discord.guildId,
    discordId
  )
  PerformHttpRequest(url, function(status, body)
    if status ~= 200 then return cb(false) end
    local data = json.decode(body)
    for _, role in ipairs(data.roles or {}) do
      if Config.Discord.allowedRoles[role] then return cb(true) end
    end
    cb(false)
  end, "GET", nil, {
    ["Authorization"] = "Bot " .. Config.Discord.botToken,
    ["Content-Type"] = "application/json"
  })
end

MySQL.ready(function()
  MySQL.query('SHOW TABLES LIKE ?', {'jail_records'}, function(res)
    if #res == 0 then
      MySQL.execute([[
        CREATE TABLE IF NOT EXISTS `jail_records` (
          `id` INT NOT NULL AUTO_INCREMENT,
          `jailer_discord` VARCHAR(50) NOT NULL,
          `inmate_discord` VARCHAR(50) NOT NULL,
          `time_minutes` INT NOT NULL,
          `date` DATETIME NOT NULL,
          `charges` TEXT NOT NULL,
          PRIMARY KEY (`id`)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
      ]], {}, function() print('[jailer] Created jail_records table') end)
    end
  end)
end)

-- core functionality
local function recordJailEvent(jailerD, inmateD, jailTime, charges)
  local ts = os.date('%Y-%m-%d %H:%M:%S')
  MySQL.execute([[
    INSERT INTO jail_records (jailer_discord, inmate_discord, time_minutes, date, charges) VALUES (?, ?, ?, ?, ?)
  ]], { jailerD, inmateD, jailTime, ts, table.concat(charges, ', ') })
end

local function fetchRecordsForInmate(inmateD, cb)
  MySQL.query([[SELECT id, date, time_minutes, charges FROM jail_records WHERE inmate_discord = ? ORDER BY date DESC]], { inmateD }, cb)
end

local function fetchAllRecords(cb)
  MySQL.query([[SELECT id, jailer_discord, inmate_discord, date, time_minutes, charges FROM jail_records ORDER BY date DESC]], {}, cb)
end

local function fetchRecordById(recordId, cb)
  MySQL.query([[SELECT id, jailer_discord, inmate_discord, date, time_minutes, charges FROM jail_records WHERE id = ?]], { recordId }, function(res)
    cb(res and res[1] or nil)
  end)
end

local function deleteRecord(recordId, cb)
  MySQL.execute([[DELETE FROM jail_records WHERE id = ?]], { recordId }, function()
    if cb then cb(true) end
  end)
end

-- perform jail on client
local function performJail(targetId, jailTime)
  TriggerClientEvent('jailer:performJail', targetId, jailTime)
end

-- manual unjail
local function performUnjail(targetId)
  TriggerClientEvent('jailer:performUnjail', targetId)
end

-- exports
exports('hasPermission', hasPermission)
exports('requestJail', function(src, targetId, jailTime, charges)
  local jailerD, inmateD = getDiscordIdent(src), getDiscordIdent(targetId)
  if not jailerD or not inmateD then return false, 'Invalid Discord IDs' end
  recordJailEvent(jailerD, inmateD, jailTime, charges)
  performJail(targetId, jailTime)
  TriggerClientEvent('jailer:jailResult', src, { success = true })
  return true
end)
exports('getCaseRecords', function(src, targetId, cb)
  local inmateD = getDiscordIdent(targetId)
  if not inmateD then return cb(nil) end
  fetchRecordsForInmate(inmateD, cb)
end)
exports('getAllJailRecords', fetchAllRecords)
exports('getJailRecordById', fetchRecordById)
exports('deleteJailRecord', deleteRecord)
exports('unjailPlayer', performUnjail)

-- legacy events
RegisterServerEvent('jail:checkPermission')
AddEventHandler('jail:checkPermission', function()
  local src = source
  hasPermission(src, function(allowed) TriggerClientEvent('jail:permissionResult', src, allowed) end)
end)

RegisterNetEvent('jailer:requestJail')
AddEventHandler('jailer:requestJail', function(targetId, jailTime, charges)
  local src, ok, err = source, exports['jailer']:requestJail(source, targetId, jailTime, charges)
  if not ok then TriggerClientEvent('jailer:jailResult', src, { success = false, message = err }) end
end)

RegisterNetEvent('jailer:requestCaseRecords')
AddEventHandler('jailer:requestCaseRecords', function(targetId)
  local src = source
  exports['jailer']:getCaseRecords(src, tonumber(targetId), function(records)
    TriggerClientEvent('jailer:returnCaseRecords', src, records or {})
  end)
end)