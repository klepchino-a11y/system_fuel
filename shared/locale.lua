-- Minimal Locale shim (بديل خفيف لـ @qb-core/shared/locale.lua)
-- يوفّر: Locale:new({ phrases = {...}, warnOnMissing = true }), و Lang:t('key.subkey', {var=...})

Locale = {}
Locale.__index = Locale

function Locale:new(opts)
    local o = {}
    setmetatable(o, self)
    o.phrases = (opts and opts.phrases) or {}
    o.warnOnMissing = (opts and opts.warnOnMissing) or false
    return o
end

local function deep_get(tbl, path)
    local cur = tbl
    for seg in string.gmatch(path, "[^%.]+") do
        if type(cur) ~= "table" then return nil end
        cur = cur[seg]
        if cur == nil then return nil end
    end
    return cur
end

function Locale:t(key, data)
    local phrase = deep_get(self.phrases, key)
    if not phrase then
        if self.warnOnMissing then
            print(("[locale] missing phrase: %s"):format(key))
        end
        return key
    end
    if data and type(phrase) == "string" then
        phrase = phrase:gsub("%%{(.-)}", function(k)
            return tostring(data[k] or ("${"..k.."}"))
        end)
    end
    return phrase
end
