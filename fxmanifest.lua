fx_version 'cerulean'
game 'gta5'
lua54 'yes'
author 'Azure(TheStoicBear)'
description 'Azure Framework Jailing'
version '1.0.0'

shared_scripts {
    '@ox_lib/init.lua',
    'config.lua'
}

server_scripts {
    '@oxmysql/lib/MySQL.lua',
    'source/server.lua'
}

client_scripts {
    'source/client.lua'
}

ui_page 'UI/index.html'

files {
    'UI/index.html',
    'UI/config.js'
}
