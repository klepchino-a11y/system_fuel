-- ========== إضافة: HUD + استهلاك الوقود لكل مركبة ==========
-- هذا الملف مستقل ولا يغيّر منطق التزوّد من المضخات.
-- يعتمد على إعدادات Config.VehicleFuelLines و Config.DefaultVehicleFuel.
-- تمّت إضافة Speedometer HUD + Gear Indicator + تحسين HUD الوقود (⛽ وميض تحت العتبة).

local function _parseVehicleLines()
    local map = {}
    if not Config.VehicleFuelLines then return map end
    for _, line in ipairs(Config.VehicleFuelLines) do
        -- صيغة: model [capacity] [moving_per_sec] [idle_per_sec]
        local model, cap, move, idle = string.match(line, "^%s*(%S+)%s*%[(%d+)%]%s*%[(%d+%.?%d*)%]%s*%[(%d+%.?%d*)%]%s*$")
        if model and cap and move and idle then
            map[string.lower(model)] = {
                capacity = tonumber(cap),
                moving = tonumber(move),
                idle = tonumber(idle),
            }
        end
    end
    return map
end

local _vehConfigByModel = _parseVehicleLines()
local _default = Config.DefaultVehicleFuel or { capacity = 100, moving = 1.5, idle = 0.5 }

local function _resolveVehConfig(veh)
    local model = GetEntityModel(veh)
    local key = string.lower(GetDisplayNameFromVehicleModel(model) or "")
    return _vehConfigByModel[key] or _default
end

-- HUD: Fuel
local HUD = {
    visible = false,
    x = (Config.FuelHUD and Config.FuelHUD.position and Config.FuelHUD.position.x) or 0.90,
    y = (Config.FuelHUD and Config.FuelHUD.position and Config.FuelHUD.position.y) or 0.85,
    w = (Config.FuelHUD and Config.FuelHUD.width) or 0.12,
    h = (Config.FuelHUD and Config.FuelHUD.height) or 0.02,
    alert = (Config.FuelHUD and Config.FuelHUD.alertPercent) or 20,
    blinkSpeed = (Config.FuelHUD and Config.FuelHUD.blinkSpeed) or 2.0, -- تذبذب ناعم
}

-- HUD: Speedometer
local SPEEDO = {
    enabled = (Config.SpeedoHUD and Config.SpeedoHUD.enabled) ~= false,
    x = (Config.SpeedoHUD and Config.SpeedoHUD.position and Config.SpeedoHUD.position.x) or 0.90,
    y = (Config.SpeedoHUD and Config.SpeedoHUD.position and Config.SpeedoHUD.position.y) or 0.81,
    w = (Config.SpeedoHUD and Config.SpeedoHUD.width) or 0.12,
    h = (Config.SpeedoHUD and Config.SpeedoHUD.height) or 0.018,
    maxKmh = (Config.SpeedoHUD and Config.SpeedoHUD.maxKmh) or 240,
    bgA = (Config.SpeedoHUD and Config.SpeedoHUD.bgAlpha) or 120,
    rimA = (Config.SpeedoHUD and Config.SpeedoHUD.rimAlpha) or 80,
}

local function _drawText(x, y, text, scale, r,g,b,a, centre)
    SetTextFont(4)
    SetTextProportional(1)
    SetTextScale(scale or 0.35, scale or 0.35)
    SetTextColour(r or 255, g or 255, b or 255, a or 220)
    if centre then SetTextCentre(true) end
    SetTextOutline()
    SetTextEntry("STRING")
    AddTextComponentString(tostring(text))
    DrawText(x, y)
end

-- مستطيل بخلفية رمادية شفافة + خط أبيض بحواف ناعمة (تقريبية)
local function _drawBar(x, y, w, h, pct, backA, rimA)
    -- إطار خفيف رمادي
    DrawRect(x, y, w + 0.004, h + 0.004, 150, 150, 150, rimA or 80)
    -- خلفية شفافة
    DrawRect(x, y, w, h, 0, 0, 0, backA or 120)
    -- تعبئة بيضاء
    local fill = math.max(0.0, math.min(1.0, pct))
    local barW = w * fill
    if barW > 0.0 then
        -- شريط أبيض
        DrawRect(x - w/2 + barW/2, y, barW, h - 0.003, 255, 255, 255, 235)
        -- “حواف ناعمة” تقريبية: أطراف باهتة صغيرة
        local cap = math.min(barW, h) * 0.5
        if cap > 0.0 then
            DrawRect(x - w/2 + barW - cap/2, y, cap, h - 0.003, 255, 255, 255, 180)
            DrawRect(x - w/2 + cap/2, y, cap, h - 0.003, 255, 255, 255, 180)
        end
    end
end

-- Gear label: R / N / 1..n
local function _gearLabel(veh, kmh)
    local g = 1
    if veh ~= 0 then
        -- ملاحظة: GET_VEHICLE_CURRENT_GEAR تُرجع 0 للرجوع للخلف، 1..N للتعشيقات الأمامية. :contentReference[oaicite:0]{index=0}
        g = GetVehicleCurrentGear(veh) or 1
        -- بعض الإصدارات توفّر GET_VEHICLE_DASHBOARD_CURRENT_GEAR (gear float كما في لوحة العدادات). :contentReference[oaicite:1]{index=1}
        if GetVehicleDashboardCurrentGear then
            local dg = GetVehicleDashboardCurrentGear()
            if dg and dg >= 1.0 then g = math.floor(dg + 0.01) end
        end
        if g == 0 then
            return "R"
        end
        -- إظهار N عندما السيارة متوقفة فعليًا
        if (kmh or 0) < 1.0 and (IsVehicleStopped(veh) or false) then -- متوقفة تقريبًا :contentReference[oaicite:2]{index=2}
            return "N"
        end
    end
    return tostring(g)
end

-- (تعديل) استبدال كامل للدالة: _drawFuelHUD
local function _drawFuelHUD(percent)
    local x, y, w, h = HUD.x, HUD.y, HUD.w, HUD.h
    local pct = math.max(0.0, math.min(100.0, tonumber(percent) or 0.0))
    local fill = pct / 100.0

    -- خلفية وإطار
    DrawRect(x, y, w+0.006, h+0.008, 0, 0, 0, 160)        -- ظل خارجي
    DrawRect(x, y, w,       h,       15, 15, 15, 180)     -- خلفية
    DrawRect(x, y, w,       0.003,   255, 255, 255, 40)   -- رِم علوي
    DrawRect(x, y, 0.002,   h,       255, 255, 255, 40)   -- رِم يمين/يسار
    DrawRect(x, y, w,       0.003,   255, 255, 255, 40)   -- رِم سفلي

    -- تعبئة (شبه-تدرّج بخطّين)
    local barW = (w - 0.008) * fill
    if barW > 0 then
        DrawRect(x - w/2 + 0.004 + barW/2, y, barW, h - 0.008, 36, 164, 83, 220) -- أخضر
        DrawRect(x - w/2 + 0.004 + barW/2, y, barW, (h - 0.010)/2, 46, 204, 113, 180)
    end

    -- تحذير عند القليل
    local low = pct <= HUD.alert
    if low then
        local blink = (math.sin(GetGameTimer()/ (400.0 / (HUD.blinkSpeed or 2.0))) + 1.0) * 0.5
        local r = math.floor(200 + 55*blink)
        local a = math.floor(140 + 80*blink)
        DrawRect(x, y, w, h, r, 50, 50, a)
    end

    -- أيقونة ونص
    _drawText(x - w/2 - 0.016, y - h/2 - 0.007, "⛽", 0.40, 255,255,255, 240, true)
    local label = string.format("%d%%", math.floor(pct + 0.5))
    _drawText(x + w/2 + 0.016, y - h/2 - 0.007, label, 0.40, 255,255,255, 240, true)
end


-- (تعديل) استبدال كامل للدالة: _drawSpeedo
local _speedVis = 0.0 -- سلاسة للعرض فقط (لا تؤثر على سرعة المركبة)
local function _drawSpeedo(veh)
    if not SPEEDO.enabled then return end
    if veh == 0 or not DoesEntityExist(veh) then return end

    local x, y, w, h = SPEEDO.x, SPEEDO.y, SPEEDO.w, SPEEDO.h
    local kmh = (GetEntitySpeed(veh) or 0.0) * 3.6
    _speedVis = _speedVis + (kmh - _speedVis) * 0.15 -- LERP بسيط

    -- خلفية/ظل
    DrawRect(x, y, w+0.006, h+0.008, 0, 0, 0, SPEEDO.bgA or 120)
    DrawRect(x, y, w,       h,       10, 10, 10, 180)
    DrawRect(x, y, w,       0.002,   255,255,255, SPEEDO.rimA or 80)
    DrawRect(x, y, 0.002,   h,       255,255,255, SPEEDO.rimA or 80)
    DrawRect(x, y, w,       0.002,   255,255,255, SPEEDO.rimA or 80)

    -- نسبة السرعة
    local cap = math.max(1.0, SPEEDO.maxKmh or 240.0)
    local fill = math.max(0.0, math.min(1.0, _speedVis / cap))
    local barW = (w - 0.008) * fill
    if barW > 0 then
        DrawRect(x - w/2 + 0.004 + barW/2, y, barW, h - 0.008, 52, 152, 219, 220)
        DrawRect(x - w/2 + 0.004 + barW/2, y, barW, (h - 0.010)/2, 41, 128, 185, 180)
    end

    -- قيمة السرعة نصًا + التعشيقة
    local label = string.format("%03d", math.floor(_speedVis + 0.5))
    _drawText(x, y - h/2 - 0.010, label .. " km/h", 0.40, 255,255,255, 230, true)

    local gear = _gearLabel(veh, kmh)
    _drawText(x + w/2 + 0.016, y - h/2 - 0.008, "["..gear.."]", 0.40, 255,255,255, 230, true)
end


-- حالة القيادة
local wasInVeh = false
local curVeh = nil
local curCfg = _default

-- رسم الـ HUD كل فريم
CreateThread(function()
    while true do
        if HUD.visible and curVeh and DoesEntityExist(curVeh) then
            local perc = GetVehicleFuelLevel(curVeh) or 0.0
            _drawFuelHUD(perc)
            _drawSpeedo(curVeh)
        end
        Wait(0)
    end
end)

-- إظهار/إخفاء HUD بناءً على ركوب/نزول اللاعب من مقعد السائق
CreateThread(function()
    while true do
        local ped = PlayerPedId()
        local veh = GetVehiclePedIsIn(ped, false)
        local isDriver = veh ~= 0 and GetPedInVehicleSeat(veh, -1) == ped
        if isDriver and not wasInVeh then
            wasInVeh = true
            curVeh = veh
            curCfg = _resolveVehConfig(veh)
            HUD.visible = (Config.FuelHUD and Config.FuelHUD.enabled) ~= false
            -- تأكد من أن المركبة لديها قيمة وقود ابتدائية
            local fuel = GetVehicleFuelLevel(veh)
            if not fuel or fuel <= 0 then
                SetVehicleFuelLevel(veh, 100.0) -- قراءة/كتابة المستوى بالنيتف الرسمي. :contentReference[oaicite:4]{index=4}
            end
        elseif (not isDriver) and wasInVeh then
            wasInVeh = false
            HUD.visible = false
            curVeh = nil
        end
        Wait(250)
    end
end)

-- استهلاك الوقود كل ثانية (يتحوّل إلى نسبة 0-100%)
CreateThread(function()
    while true do
        if wasInVeh and curVeh and DoesEntityExist(curVeh) then
            local speed = GetEntitySpeed(curVeh) or 0.0 -- m/s
            local consuming = (speed > 0.5) and (curCfg.moving or _default.moving) or (curCfg.idle or _default.idle)
            local capacity = curCfg.capacity or _default.capacity
            local deltaPercent = (consuming / capacity) * 100.0
            local fuel = (GetVehicleFuelLevel(curVeh) or 0.0) - deltaPercent
            if fuel < 0 then fuel = 0 end
            SetVehicleFuelLevel(curVeh, fuel)
        end
        Wait(1000)
    end
end)

-- Exports للتوافق
exports('GetFuel', function(veh)
    if not veh or veh == 0 then return 0.0 end
    return GetVehicleFuelLevel(veh) or 0.0
end)

exports('SetFuel', function(veh, level)
    if not veh or veh == 0 then return end
    local lvl = tonumber(level) or 0.0
    if lvl < 0 then lvl = 0 elseif lvl > 100 then lvl = 100 end
    SetVehicleFuelLevel(veh, lvl)
end)
