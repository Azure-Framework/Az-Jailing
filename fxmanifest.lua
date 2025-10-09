fx_version 'cerulean'
game 'gta5'
lua54 'yes'

author 'Azure(TheStoicBear)'
description 'AZ-FW Jailer resource'
version '1.4.0'

-- Shared scripts
shared_scripts {
    '@ox_lib/init.lua',
    'config.lua'
}

-- Server-side scripts
server_scripts {
    '@oxmysql/lib/MySQL.lua',
    'source/server.lua'
}

-- Client-side scripts
client_scripts {
    'source/client.lua'
}

-- UI page
ui_page 'UI/index.html'

-- Files to be included
files {
    'UI/index.html',
    'UI/config.js'
}
