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
-- server.lua
-- Usage: handles browser fetch requests from client NUI via bladder client callback flow
-- It will attempt direct PerformHttpRequest; on network failure (status==0) it will optionally
-- call an external render proxy (PUPPETEER) if configured.

-- Simple local config here; move to config.lua if you prefer.
local Config = {
  ALLOW_ALL = false, -- dangerous if true; dev only
  ALLOWED_DOMAINS = { "duckduckgo.com", "example.com", "azurewebsites.xyz", "127.0.0.1", "localhost" },
  JS_WHITELIST = { "my-internal-site.local", "localhost" }, -- hosts allowed to keep <script> tags (trusted)
  RENDER_PROXY_URL = nil, -- e.g. "https://my-render-proxy.example.com/render" ; set to use fallback rendered snapshots
  RENDER_PROXY_APIKEY = nil -- optional: set if your proxy requires an API key
}

-- Helper: extract host from url
local function extractHost(url)
  if not url then return nil end
  local s = tostring(url):gsub("^%s+", ""):gsub("%s+$", "")
  local host = s:match('^%w+://([^/]+)') or s:match('^([^/]+)')
  if not host then return nil end
  host = host:match('@(.+)') or host
  host = host:match('^([^:]+)') or host
  if not host then return nil end
  return host:lower()
end

-- domain matching (supports plain pattern and wildcard like *.example.com)
local function domainMatches(host, pattern)
  if not host or not pattern then return false end
  host = host:lower(); pattern = pattern:lower()
  if pattern:sub(1,2) == "*." then
    local base = pattern:sub(3)
    if host == base then return true end
    if host:sub(-#base) == base then
      local idx = #host - #base
      if idx == 0 then return true end
      return host:sub(idx, idx) == '.'
    end
    return false
  end
  if host == pattern then return true end
  if host:sub(-#pattern) == pattern then
    local idx = #host - #pattern
    if idx == 0 then return true end
    return host:sub(idx, idx) == '.'
  end
  return false
end

local function isAllowedDomain(host)
  if Config.ALLOW_ALL then return true end
  if not host then return false end
  for _, pat in ipairs(Config.ALLOWED_DOMAINS) do
    if domainMatches(host, pat) then return true end
  end
  return false
end

local function hostInJsWhitelist(host)
  if not host then return false end
  for _, w in ipairs(Config.JS_WHITELIST) do
    if host:find(w, 1, true) then return true end
  end
  return false
end

-- Basic server-side sanitizer (still minimal — tighten as needed)
local function sanitizeHtml(html, host)
  if not html then return '' end
  local out = html
  -- if host is trusted to allow scripts we keep them (use with caution)
  if not hostInJsWhitelist(host) then
    out = out:gsub('<script[%s%S]-</script>', '')
    out = out:gsub('%s(on[%w]+)%s*=%s*"[^"]*"', '')
    out = out:gsub("%s(on[%w]+)%s*=%s*'[^']*'", '')
  else
    -- remove meta refresh and javascript: hrefs even for trusted hosts
    out = out:gsub('<meta[^>]-http%-equiv%s*=%s*["\']?refresh["\']?[^>]->', '')
  end
  out = out:gsub('<meta[^>]-http%-equiv%s*=%s*["\']?refresh["\']?[^>]->', '')
  out = out:gsub('href%s*=%s*["\']%s*javascript:[^"\']*["\']', 'href="#"')
  return out
end

-- Inject base tag to help resolve relative assets
local function injectBase(html, baseUrl)
  if not html then return html end
  local lower = html:lower()
  local headStart = lower:find('<head')
  if headStart then
    local openTagEnd = html:find('>', headStart)
    if openTagEnd then
      local baseTag = string.format('<base href="%s">', baseUrl)
      local before = html:sub(1, openTagEnd)
      local after = html:sub(openTagEnd + 1)
      return before .. baseTag .. after
    end
  end
  return '<base href="' .. baseUrl .. '">' .. html
end

-- Call external render proxy (if configured). Proxy should accept POST { url } -> JSON { success, html, title, url }
local function callRenderProxy(url, cb)
  if not Config.RENDER_PROXY_URL then
    cb(nil, 'no_render_proxy_configured')
    return
  end
  local payload = json.encode({ url = url })
  local headers = { ['Content-Type'] = 'application/json' }
  if Config.RENDER_PROXY_APIKEY then headers['x-api-key'] = Config.RENDER_PROXY_APIKEY end

  PerformHttpRequest(Config.RENDER_PROXY_URL, function(statusCode, responseText, headersResp)
    if not statusCode or statusCode == 0 then
      cb(nil, 'render_proxy_network_error')
      return
    end
    if statusCode >= 200 and statusCode < 400 and responseText then
      local ok, parsed = pcall(function() return json.decode(responseText) end)
      if not ok or not parsed then
        cb(nil, 'render_proxy_bad_response')
        return
      end
      -- expected parsed = { success=true, html=..., title=..., url=... }
      if not parsed.success then
        cb(nil, parsed.error or 'render_proxy_error')
        return
      end
      cb(parsed, nil)
    else
      cb(nil, 'render_proxy_http_'..tostring(statusCode))
    end
  end, 'POST', payload, headers)
end

-- Main handler called by client via server event
RegisterNetEvent('jailer:browserFetch_request')
AddEventHandler('jailer:browserFetch_request', function(requestId, url)
  local src = source
  print(('[jailer] browserFetch_request from src=%s requestId=%s url=%s'):format(tostring(src), tostring(requestId), tostring(url)))

  if not requestId or type(requestId) ~= 'string' then
    TriggerClientEvent('jailer:browserFetch_result', src, requestId, { success=false, error='invalid_request_id' })
    return
  end
  if not url or type(url) ~= 'string' then
    TriggerClientEvent('jailer:browserFetch_result', src, requestId, { success=false, error='invalid_url' })
    return
  end

  local host = extractHost(url)
  print(('[jailer] extracted host=%s'):format(tostring(host)))

  if not host then
    TriggerClientEvent('jailer:browserFetch_result', src, requestId, { success=false, error='could_not_parse_host', url=url })
    return
  end

  if not isAllowedDomain(host) then
    print(('[jailer] domain not allowed: %s'):format(host))
    TriggerClientEvent('jailer:browserFetch_result', src, requestId, { success=false, error='domain_not_allowed', host = host, url = url })
    return
  end

  -- try direct fetch first
  PerformHttpRequest(url, function(statusCode, responseText, headers)
    if statusCode and statusCode >= 200 and statusCode < 400 and responseText then
      local sanitized = sanitizeHtml(responseText, host)
      local finalHtml = injectBase(sanitized, url)
      local title = finalHtml:match('<title[^>]*>([%s%S]-)</title>') or nil
      TriggerClientEvent('jailer:browserFetch_result', src, requestId, { success=true, html=finalHtml, title=title, url=url, fromProxy=false })
      return
    end

    -- non-success or network-level failure (status==0)
    local code = tostring(statusCode or 'nil')
    print(('[jailer] direct fetch failed status=%s host=%s requestId=%s src=%s'):format(code, host, requestId, tostring(src)))

    -- if a render proxy is configured, try it now (Puppeteer rendering)
    if Config.RENDER_PROXY_URL then
      print('[jailer] attempting render proxy fallback for url='..tostring(url))
      callRenderProxy(url, function(proxyResp, proxyErr)
        if proxyErr then
          print(('[jailer] render proxy failed: %s'):format(tostring(proxyErr)))
          TriggerClientEvent('jailer:browserFetch_result', src, requestId, { success=false, error = 'http_error_'..tostring(statusCode), url=url })
          return
        end
        -- proxyResp expected to include html/title/url
        local finalHtml = proxyResp.html or ''
        -- server trusts the proxy snapshot, but we still inject base for assets
        finalHtml = injectBase(finalHtml, url)
        local title = proxyResp.title or finalHtml:match('<title[^>]*>([%s%S]-)</title>') or nil
        TriggerClientEvent('jailer:browserFetch_result', src, requestId, {
          success = true,
          html = finalHtml,
          title = title,
          url = proxyResp.url or url,
          fromProxy = true
        })
      end)
      return
    end

    -- no proxy configured -> return the http error back to client
    TriggerClientEvent('jailer:browserFetch_result', src, requestId, { success=false, error='http_error_'..tostring(statusCode or 0), url=url })
  end, 'GET', '', { ['User-Agent'] = 'FiveM-NUI-Browser/1.0' })
end)
