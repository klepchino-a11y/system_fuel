fx_version 'cerulean'
game 'gta5'

author 'Cocodrulo (base) + custom edits'
version '0.0.5'
description 'Fuel System (ESX + ox_target) with per-vehicle config and HUD'

ui_page 'html/index.html'

shared_scripts {
    '@es_extended/imports.lua',
    'shared/locale.lua',
    'locales/*.lua',
    'Config.lua',
}

client_scripts {
    'client/client.lua',
    'client/hud_and_consumption.lua', -- إضافة HUD + استهلاك
}

server_scripts {
    'server/server.lua',
}

files {
    'html/index.html',
    'html/app.js',          -- الملف الموجود فعليًا داخل المورد
    'html/translations.js',
    'html/style.css',
}

dependency 'ox_target'
provide 'LegacyFuel'

-- تصدير دوال للوصول لمستوى الوقود (عميل)
exports {
    'GetFuel',
    'SetFuel',
}
