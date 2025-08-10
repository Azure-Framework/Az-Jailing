local function getDiscordIeved(playerId)
  for _, id in ipairs(GetPlayerIdentifiers(playerId)) do
    if id:match("^discord:") then return id:sub(9) end
  end
  return nil
end

-- Grabs just the numeric part of the player’s Discord identifier
local function getDiscordId(src)
    for _, id in ipairs(GetPlayerIdentifiers(src)) do
        if id:match("^discord:%d+$") then
            return id:sub(9)
        end
    end
    return nil
end

-- Async check against Discord Guild API
local function hasPermission(src, cb)
    local discordId = getDiscordId(src)
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
            local data = json.decode(body)
            for _, role in ipairs(data.roles or {}) do
                if Config.Discord.allowedRoles[role] then
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

-- Event the client calls
RegisterServerEvent('jail:checkPermission')
AddEventHandler('jail:checkPermission', function()
    local src = source
    hasPermission(src, function(allowed)
        -- Send back true/false
        TriggerClientEvent('jail:permissionResult', src, allowed)
    end)
end)

-- Ensure table exists
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

-- Jail request without permission check
RegisterNetEvent('jailer:requestJail', function(targetId, jailTime, charges)
  local src = source

  -- Retrieve Discord IDs for both players
  local jailerD = getDiscordIeved(src)
  local inmateD = getDiscordIeved(targetId)
  if not jailerD or not inmateD then
    return TriggerClientEvent('jailer:jailResult', src, {
      success = false,
      message = 'Could not resolve Discord IDs for one of the players.'
    })
  end

  -- (Optional) validate jailTime > 0, etc.

  local ts = os.date('%Y-%m-%d %H:%M:%S')
  MySQL.execute([[
    INSERT INTO jail_records
      (jailer_discord, inmate_discord, time_minutes, date, charges)
    VALUES (?, ?, ?, ?, ?)
  ]], {
    jailerD,
    inmateD,
    jailTime,
    ts,
    table.concat(charges, ', ')
  })

  -- perform the actual jail on the target
  TriggerClientEvent('jailer:performJail', targetId, jailTime)

  -- notify the requesting client UI of success
  TriggerClientEvent('jailer:jailResult', src, {
    success = true
  })

  -- (Optional) also send a chat confirmation
  TriggerClientEvent('chat:addMessage', src, {
    args = {
      '^2System',
      ('Player %d jailed %d min'):format(targetId, jailTime)
    }
  })
end)


-- Case records without permission check
RegisterNetEvent('jailer:requestCaseRecords', function(targetId)
  local src = source

  targetId = tonumber(targetId)
  if not targetId then
    return TriggerClientEvent('chat:addMessage', src, {
      args = {'^1System','Invalid ID.'}
    })
  end

  local inmateD = getDiscordIeved(targetId)
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
