-- server.lua
-- Full server-side for the jail system: permission checks (Discord role), jail records, request handling, case records.
-- Make sure Config.Discord.guildId and Config.Discord.botToken and Config.Discord.allowedRoles exist in your config.

local Config = Config or require('config')
local json = json

-- Helper: get numeric discord id like "123456789012345678" from player source
local function getDiscordIdFromSource(src)
  for _, id in ipairs(GetPlayerIdentifiers(src)) do
    if id:match("^discord:%d+$") then
      return id:sub(9)
    end
  end
  return nil
end

-- Async check against Discord Guild API (server-side HTTP)
local function hasPermission(src, cb)
  local discordId = getDiscordIdFromSource(src)
  if not discordId then
    return cb(false)
  end

  local url = string.format(
    "https://discord.com/api/guilds/%s/members/%s",
    Config.Discord.guildId,
    discordId
  )

  PerformHttpRequest(url,
    function(status, body)
      if status ~= 200 then
        return cb(false)
      end
      local ok, data = pcall(json.decode, body)
      if not ok or not data then return cb(false) end
      for _, role in ipairs(data.roles or {}) do
        if Config.Discord.allowedRoles and Config.Discord.allowedRoles[role] then
          return cb(true)
        end
      end
      cb(false)
    end,
    "GET", nil,
    {
      ["Authorization"]   = "Bot " .. Config.Discord.botToken,
      ["Content-Type"]    = "application/json"
    }
  )
end

-- Event the client calls to check jailer permission
RegisterNetEvent('jail:checkPermission')
AddEventHandler('jail:checkPermission', function()
  local src = source
  hasPermission(src, function(allowed)
    TriggerClientEvent('jail:permissionResult', src, allowed)
  end)
end)

-- Ensure jail_records table exists
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
      ]], {}, function()
        print('[jailer] Created jail_records table')
      end)
    else
      print('[jailer] jail_records table exists')
    end
  end)
end)

-- Helper: tries to extract Discord ID for any player index (for use when targetId provided)
local function getDiscordIdFromPlayer(targetPlayerId)
  -- targetPlayerId may be server ID
  for _, id in ipairs(GetPlayerIdentifiers(targetPlayerId)) do
    if id:match("^discord:%d+$") then
      return id:sub(9)
    end
  end
  return nil
end

-- Jail request (called by client UI)
-- targetId (server id), jailTime (minutes), charges (string or table)
RegisterNetEvent('jailer:requestJail')
AddEventHandler('jailer:requestJail', function(targetId, jailTime, charges)
  local src = source

  -- Security: ensure inputs are sane
  targetId = tonumber(targetId)
  jailTime = tonumber(jailTime) or 0
  if not targetId or jailTime <= 0 then
    return TriggerClientEvent('jailer:jailResult', src, {
      success = false,
      message = 'Invalid target or time.'
    })
  end

  -- Retrieve Discord IDs for both players
  local jailerD = getDiscordIdFromSource(src)
  local inmateD = getDiscordIdFromPlayer(targetId)
  if not jailerD or not inmateD then
    return TriggerClientEvent('jailer:jailResult', src, {
      success = false,
      message = 'Could not resolve Discord IDs for one of the players.'
    })
  end

  local ts = os.date('%Y-%m-%d %H:%M:%S')

  -- Normalize charges
  local chStr = ""
  if type(charges) == "table" then
    chStr = table.concat(charges, ", ")
  elseif type(charges) == "string" then
    chStr = charges
  else
    chStr = ""
  end

  MySQL.execute([[
    INSERT INTO jail_records
      (jailer_discord, inmate_discord, time_minutes, date, charges)
    VALUES (?, ?, ?, ?, ?)
  ]], {
    jailerD,
    inmateD,
    jailTime,
    ts,
    chStr
  }, function()
    -- perform jail on target
    TriggerClientEvent('jailer:performJail', targetId, jailTime)

    -- inform requester of success
    TriggerClientEvent('jailer:jailResult', src, { success = true })

    -- optional chat message back to requester
    TriggerClientEvent('chat:addMessage', src, {
      args = {
        '^2System',
        ('Player %d jailed %d min'):format(targetId, jailTime)
      }
    })
  end)
end)

-- Case records retrieval
RegisterNetEvent('jailer:requestCaseRecords')
AddEventHandler('jailer:requestCaseRecords', function(targetId)
  local src = source
  targetId = tonumber(targetId)
  if not targetId then
    return TriggerClientEvent('chat:addMessage', src, {
      args = {'^1System','Invalid ID.'}
    })
  end

  local inmateD = getDiscordIdFromPlayer(targetId)
  if not inmateD then
    return TriggerClientEvent('chat:addMessage', src, {
      args = {'^1System','Player not found.'}
    })
  end

  MySQL.query([[
    SELECT date, time_minutes, charges
    FROM jail_records
    WHERE inmate_discord = ?
    ORDER BY date DESC
  ]], { inmateD }, function(records)
    TriggerClientEvent('jailer:returnCaseRecords', src, records)
  end)
end)
