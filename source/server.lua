local Config = Config or require('config')

local function notify(src, title, message, kind)
  TriggerClientEvent('ox_lib:notify', src, {
    title = title or 'Jailer',
    description = message or '',
    type = kind or 'inform',
    position = 'top'
  })
end

local function getDiscordId(src)
  for _, id in ipairs(GetPlayerIdentifiers(src)) do
    if id:match("^discord:%d+$") then return id:sub(9) end
  end
  return nil
end

local function getPlayerJob(src)
  local ok, job = pcall(function()
    if exports[Config.FrameworkResource] and exports[Config.FrameworkResource].getPlayerJob then
      return exports[Config.FrameworkResource]:getPlayerJob(src)
    end
  end)
  if not ok or job == nil then return 'civ' end
  if type(job) == 'table' then job = job.name or job.job or job.id or job.label end
  job = tostring(job or 'civ'):lower():gsub("^%s+", ""):gsub("%s+$", "")
  return job ~= '' and job or 'civ'
end

local function hasAce(src, ace)
  return src == 0 or (ace and ace ~= '' and IsPlayerAceAllowed(src, ace))
end

local function hasAccess(src, mode)
  if hasAce(src, Config.Access.AdminAce) then return true end
  if mode == 'court' and hasAce(src, Config.Access.CourtAce) then return true end
  if mode ~= 'court' and hasAce(src, Config.Access.JailerAce) then return true end

  local job = getPlayerJob(src)
  if mode == 'court' then
    return Config.Access.CourtJobs[job] == true or Config.Access.JailerJobs[job] == true
  end
  return Config.Access.JailerJobs[job] == true
end

local function playerName(src)
  return GetPlayerName(src) or ('Player %s'):format(tostring(src))
end

local function normalizeCharges(charges)
  if type(charges) == 'table' then
    local out = {}
    for _, charge in ipairs(charges) do
      charge = tostring(charge or ''):gsub("^%s+", ""):gsub("%s+$", "")
      if charge ~= '' then out[#out + 1] = charge end
    end
    return table.concat(out, ', ')
  end
  return tostring(charges or ''):sub(1, 2000)
end

local function targetInRange(src, targetId)
  if src == 0 then return true end
  if Config.Court.AllowRemoteAdmin and hasAce(src, Config.Access.AdminAce) then return true end
  local ped = GetPlayerPed(src)
  local targetPed = GetPlayerPed(targetId)
  if ped == 0 or targetPed == 0 then return false end
  local dist = #(GetEntityCoords(ped) - GetEntityCoords(targetPed))
  return dist <= (Config.Court.InteractionDistance or 8.0)
end

local function addMoney(src, amount)
  amount = math.floor(tonumber(amount) or 0)
  if amount <= 0 then return false end

  local fw = exports[Config.FrameworkResource]
  if fw then
    local ok = pcall(function()
      if fw.addMoney then fw:addMoney(src, amount) return end
      if fw.AddMoney then fw:AddMoney(src, amount) return end
    end)
    if ok then return true end
  end

  return false
end

local function onlineByDiscord(discordId)
  if not discordId then return nil end
  for _, id in ipairs(GetPlayers()) do
    local src = tonumber(id)
    if getDiscordId(src) == discordId then return src end
  end
  return nil
end

local function ensureColumn(name, ddl)
  MySQL.query(('SHOW COLUMNS FROM jail_records LIKE ?'), { name }, function(rows)
    if rows and rows[1] then return end
    MySQL.update(('ALTER TABLE jail_records ADD COLUMN %s'):format(ddl), {})
  end)
end

MySQL.ready(function()
  MySQL.update([[
    CREATE TABLE IF NOT EXISTS jail_records (
      id INT NOT NULL AUTO_INCREMENT,
      jailer_discord VARCHAR(64) NULL,
      jailer_name VARCHAR(128) NULL,
      inmate_discord VARCHAR(64) NULL,
      inmate_name VARCHAR(128) NULL,
      time_minutes INT NOT NULL DEFAULT 0,
      remaining_seconds INT NOT NULL DEFAULT 0,
      fine INT NOT NULL DEFAULT 0,
      date DATETIME NOT NULL,
      charges TEXT NULL,
      notes TEXT NULL,
      status VARCHAR(32) NOT NULL DEFAULT 'active',
      lawyer_discord VARCHAR(64) NULL,
      lawyer_name VARCHAR(128) NULL,
      updated_at DATETIME NULL,
      PRIMARY KEY (id),
      INDEX idx_inmate_discord (inmate_discord),
      INDEX idx_status (status)
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
  ]], {}, function()
    ensureColumn('jailer_name', 'jailer_name VARCHAR(128) NULL')
    ensureColumn('inmate_name', 'inmate_name VARCHAR(128) NULL')
    ensureColumn('remaining_seconds', 'remaining_seconds INT NOT NULL DEFAULT 0')
    ensureColumn('fine', 'fine INT NOT NULL DEFAULT 0')
    ensureColumn('notes', 'notes TEXT NULL')
    ensureColumn('status', "status VARCHAR(32) NOT NULL DEFAULT 'active'")
    ensureColumn('lawyer_discord', 'lawyer_discord VARCHAR(64) NULL')
    ensureColumn('lawyer_name', 'lawyer_name VARCHAR(128) NULL')
    ensureColumn('updated_at', 'updated_at DATETIME NULL')
  end)
end)

RegisterNetEvent('jail:checkPermission', function()
  TriggerClientEvent('jail:permissionResult', source, hasAccess(source, 'jailer'))
end)

RegisterNetEvent('jailer:requestJail', function(targetId, jailTime, charges, fine, notes)
  local src = source
  if not hasAccess(src, 'jailer') then
    TriggerClientEvent('jailer:jailResult', src, { success = false, message = 'You do not have jailer access.' })
    return
  end

  targetId = tonumber(targetId)
  jailTime = math.floor(tonumber(jailTime) or 0)
  fine = math.max(0, math.floor(tonumber(fine) or 0))
  notes = tostring(notes or ''):sub(1, 2000)

  if not targetId or not GetPlayerName(targetId) then
    TriggerClientEvent('jailer:jailResult', src, { success = false, message = 'Target player is not online.' })
    return
  end
  if jailTime < 1 or jailTime > (Config.Court.MaxSentenceMinutes or 720) then
    TriggerClientEvent('jailer:jailResult', src, { success = false, message = 'Sentence time is outside the allowed range.' })
    return
  end
  if fine > (Config.Court.MaxFine or 250000) then
    TriggerClientEvent('jailer:jailResult', src, { success = false, message = 'Fine is above the configured limit.' })
    return
  end
  if not targetInRange(src, targetId) then
    TriggerClientEvent('jailer:jailResult', src, { success = false, message = 'Move closer to the target before sentencing.' })
    return
  end

  local jailerD = getDiscordId(src)
  local inmateD = getDiscordId(targetId)
  local chStr = normalizeCharges(charges)
  if chStr == '' then chStr = 'Unlisted charge' end

  MySQL.insert([[
    INSERT INTO jail_records
      (jailer_discord, jailer_name, inmate_discord, inmate_name, time_minutes, remaining_seconds, fine, date, charges, notes, status, updated_at)
    VALUES (?, ?, ?, ?, ?, ?, ?, NOW(), ?, ?, 'active', NOW())
  ]], {
    jailerD,
    playerName(src),
    inmateD,
    playerName(targetId),
    jailTime,
    jailTime * 60,
    fine,
    chStr,
    notes
  }, function(caseId)
    TriggerClientEvent('jailer:performJail', targetId, jailTime, caseId)
    TriggerClientEvent('jailer:jailResult', src, { success = true, caseId = caseId })
    notify(src, 'Sentence Filed', ('%s was sentenced for %d minutes.'):format(playerName(targetId), jailTime), 'success')
    notify(targetId, 'Sentenced', ('You were sentenced for %d minutes.'):format(jailTime), 'inform')
  end)
end)

RegisterNetEvent('jailer:requestCaseRecords', function(targetId)
  local src = source
  targetId = tonumber(targetId)
  if not targetId or not GetPlayerName(targetId) then
    notify(src, 'Case Search', 'Player not found.', 'error')
    return
  end

  local inmateD = getDiscordId(targetId)
  MySQL.query([[
    SELECT id, date, jailer_name, inmate_name, time_minutes, remaining_seconds, fine, charges, notes, status, lawyer_name
    FROM jail_records
    WHERE inmate_discord = ?
    ORDER BY date DESC
    LIMIT 25
  ]], { inmateD }, function(records)
    TriggerClientEvent('jailer:returnCaseRecords', src, records or {})
  end)
end)

RegisterNetEvent('jailer:requestCourtDocket', function()
  local src = source
  if not hasAccess(src, 'court') then
    TriggerClientEvent('jailer:returnCourtDocket', src, {})
    notify(src, 'Court', 'You do not have court access.', 'error')
    return
  end

  MySQL.query([[
    SELECT id, date, jailer_name, inmate_name, inmate_discord, time_minutes, remaining_seconds, fine, charges, notes, status, lawyer_name
    FROM jail_records
    WHERE status IN ('active', 'reduced', 'review')
    ORDER BY date DESC
    LIMIT 50
  ]], {}, function(records)
    TriggerClientEvent('jailer:returnCourtDocket', src, records or {})
  end)
end)

RegisterNetEvent('jailer:requestLawyerPayment', function(targetId)
  local src = source
  if not hasAccess(src, 'court') then return notify(src, 'Court', 'You do not have court access.', 'error') end
  targetId = tonumber(targetId)
  if not targetId or not GetPlayerName(targetId) then return notify(src, 'Court', 'Lawyer is not online.', 'error') end

  local job = getPlayerJob(targetId)
  if not Config.Access.CourtJobs[job] then
    return notify(src, 'Court', 'That player is not registered as a lawyer/court employee.', 'error')
  end

  local amount = Config.Court.LawyerPayment or 500
  if addMoney(targetId, amount) then
    notify(src, 'Court', ('Paid %s $%d.'):format(playerName(targetId), amount), 'success')
    notify(targetId, 'Court Payment', ('You received $%d for legal work.'):format(amount), 'success')
  else
    notify(src, 'Court', 'Could not pay through the configured framework export.', 'error')
  end
end)

RegisterNetEvent('jailer:requestCourtAction', function(caseId, action, payload)
  local src = source
  if not hasAccess(src, 'court') then return notify(src, 'Court', 'You do not have court access.', 'error') end
  caseId = tonumber(caseId)
  payload = type(payload) == 'table' and payload or {}
  if not caseId then return notify(src, 'Court', 'Invalid case ID.', 'error') end

  MySQL.single('SELECT * FROM jail_records WHERE id = ?', { caseId }, function(row)
    if not row then return notify(src, 'Court', 'Case not found.', 'error') end

    local target = onlineByDiscord(row.inmate_discord)
    if action == 'release' then
      MySQL.update("UPDATE jail_records SET status = 'released', remaining_seconds = 0, updated_at = NOW() WHERE id = ?", { caseId })
      if target then TriggerClientEvent('jailer:releaseNow', target, 'Court release') end
      notify(src, 'Court', 'Case released.', 'success')
    elseif action == 'reduce' then
      local reduction = math.max(1, math.floor(tonumber(payload.minutes) or 0)) * 60
      local remaining = math.max(0, (tonumber(row.remaining_seconds) or 0) - reduction)
      local status = remaining == 0 and 'released' or 'reduced'
      MySQL.update("UPDATE jail_records SET status = ?, remaining_seconds = ?, updated_at = NOW() WHERE id = ?", { status, remaining, caseId })
      if target then
        if remaining == 0 then TriggerClientEvent('jailer:releaseNow', target, 'Sentence reduced') else TriggerClientEvent('jailer:updateSentence', target, remaining) end
      end
      notify(src, 'Court', ('Sentence reduced by %d minutes.'):format(math.floor(reduction / 60)), 'success')
    elseif action == 'assign_lawyer' then
      local lawyerId = tonumber(payload.lawyerId)
      if not lawyerId or not GetPlayerName(lawyerId) then return notify(src, 'Court', 'Lawyer is not online.', 'error') end
      MySQL.update("UPDATE jail_records SET status = 'review', lawyer_discord = ?, lawyer_name = ?, updated_at = NOW() WHERE id = ?", {
        getDiscordId(lawyerId),
        playerName(lawyerId),
        caseId
      })
      notify(src, 'Court', ('Assigned %s to case #%d.'):format(playerName(lawyerId), caseId), 'success')
      notify(lawyerId, 'Court Case', ('You were assigned to case #%d.'):format(caseId), 'inform')
    else
      notify(src, 'Court', 'Unknown court action.', 'error')
    end
  end)
end)

RegisterNetEvent('jailer:requestUnjail', function(targetId)
  local src = source
  if not hasAccess(src, 'court') then return notify(src, 'Court', 'You do not have court access.', 'error') end
  targetId = tonumber(targetId)
  if not targetId or not GetPlayerName(targetId) then return notify(src, 'Court', 'Player is not online.', 'error') end
  local discordId = getDiscordId(targetId)
  MySQL.update("UPDATE jail_records SET status = 'released', remaining_seconds = 0, updated_at = NOW() WHERE inmate_discord = ? AND status IN ('active', 'reduced', 'review')", { discordId })
  TriggerClientEvent('jailer:releaseNow', targetId, 'Manual release')
  notify(src, 'Court', ('Released %s.'):format(playerName(targetId)), 'success')
end)

RegisterNetEvent('jailer:updateRemaining', function(caseId, remaining)
  local src = source
  caseId = tonumber(caseId)
  remaining = math.max(0, math.floor(tonumber(remaining) or 0))
  if not caseId then return end

  local discordId = getDiscordId(src)
  MySQL.update([[
    UPDATE jail_records
    SET remaining_seconds = ?, status = IF(? = 0, 'released', status), updated_at = NOW()
    WHERE id = ? AND inmate_discord = ?
  ]], { remaining, remaining, caseId, discordId })
end)

RegisterCommand('paylawyer', function(source, args)
  local src = source
  if not hasAccess(src, 'court') then return notify(src, 'Court', 'You do not have court access.', 'error') end
  local targetId = tonumber(args[1])
  if not targetId or not GetPlayerName(targetId) then return notify(src, 'Court', 'Lawyer is not online.', 'error') end
  local job = getPlayerJob(targetId)
  if not Config.Access.CourtJobs[job] then return notify(src, 'Court', 'That player is not registered as a lawyer/court employee.', 'error') end
  local amount = Config.Court.LawyerPayment or 500
  if addMoney(targetId, amount) then
    notify(src, 'Court', ('Paid %s $%d.'):format(playerName(targetId), amount), 'success')
    notify(targetId, 'Court Payment', ('You received $%d for legal work.'):format(amount), 'success')
  else
    notify(src, 'Court', 'Could not pay through the configured framework export.', 'error')
  end
end, false)

RegisterCommand('unjail', function(source, args)
  local src = source
  if not hasAccess(src, 'court') then return notify(src, 'Court', 'You do not have court access.', 'error') end
  local targetId = tonumber(args[1])
  if not targetId or not GetPlayerName(targetId) then return notify(src, 'Court', 'Player is not online.', 'error') end
  local discordId = getDiscordId(targetId)
  MySQL.update("UPDATE jail_records SET status = 'released', remaining_seconds = 0, updated_at = NOW() WHERE inmate_discord = ? AND status IN ('active', 'reduced', 'review')", { discordId })
  TriggerClientEvent('jailer:releaseNow', targetId, 'Manual release')
  notify(src, 'Court', ('Released %s.'):format(playerName(targetId)), 'success')
end, false)
