-- ====================|| VARIABLES || ==================== --

local ESX = exports['es_extended']:getSharedObject()
local CurrentPump = nil
local CurrentObjects = { nozzle = nil, rope = nil }
local CurrentVehicle = nil
local Blips = {}
local __inited = false

-- ====================|| ESX HELPERS (بدائل لـ QBCore) || ==================== --

-- تنبيه بسيط بدل QBCore.Functions.Notify
local function Notify(msg, ntype)
    ntype = ntype or "info" -- info | success | error | warning
    if ESX and ESX.ShowNotification then
        ESX.ShowNotification(tostring(msg), ntype, 3000)
    else
        -- احتياطي
        BeginTextCommandThefeedPost("STRING")
        AddTextComponentSubstringPlayerName(tostring(msg))
        EndTextCommandThefeedPostMessagetext("CHAR_DEFAULT", "CHAR_DEFAULT", false, 0, "", "")
        EndTextCommandThefeedPostTicker(false, true)
    end
end

-- Progressbar بسيط بدل QBCore.Functions.Progressbar (تعطيل تحكم + انتظار)
local function SimpleProgress(name, label, duration, useWhileDead, canCancel, disable, anim, prop, propTwo, onFinish, onCancel)
    duration = tonumber(duration or 1000)
    local start = GetGameTimer()
    CreateThread(function()
        while GetGameTimer() - start < duration do
            if disable then
                if disable.disableMovement then
                    DisableControlAction(0, 30, true); DisableControlAction(0, 31, true)
                    DisableControlAction(0, 32, true); DisableControlAction(0, 33, true)
                    DisableControlAction(0, 34, true); DisableControlAction(0, 35, true)
                end
                if disable.disableCarMovement then
                    DisableControlAction(0, 63, true); DisableControlAction(0, 64, true)
                    DisableControlAction(0, 71, true); DisableControlAction(0, 72, true)
                end
                if disable.disableMouse == true then
                    DisableControlAction(0, 1, true); DisableControlAction(0, 2, true)
                end
                if disable.disableCombat then
                    DisableControlAction(0, 24, true); DisableControlAction(0, 25, true)
                    DisableControlAction(0, 47, true); DisableControlAction(0, 58, true)
                end
            end
            Wait(0)
        end
        if onFinish then onFinish() end
    end)
end

-- بديل متزامن لـ TriggerServerCallback
local function ESX_AwaitServerCallback(name, ...)
    local p = promise.new()
    ESX.TriggerServerCallback(name, function(result)
        p:resolve(result)
    end, ...)
    return Citizen.Await(p)
end

-- أقرب مركبة + مسافة
local function GetClosestVehicleESX()
    local ped = PlayerPedId()
    local pcoords = GetEntityCoords(ped)
    local veh = GetClosestVehicle(pcoords.x, pcoords.y, pcoords.z, 7.5, 0, 70)
    local dist = 9999.0
    if veh ~= 0 and DoesEntityExist(veh) then
        local vcoords = GetEntityCoords(veh)
        dist = #(pcoords - vcoords)
        return veh, dist
    end
    return nil, dist
end

-- رصيد اللاعب (كاش/بنك) للعرض فقط
local function GetMoneyBalanceESX(mtype)
    local pdata = ESX.GetPlayerData()
    if not pdata then return 0 end
    if mtype == 'bank' and pdata.accounts then
        for _,acc in ipairs(pdata.accounts) do
            if acc.name == 'bank' then return acc.money or 0 end
        end
        return 0
    end
    return pdata.money or 0
end

-- ====================|| FUNCTIONS || ==================== --

local loadAnimDict = function (dict)
    if not DoesAnimDictExist(dict) then return end
    while not HasAnimDictLoaded(dict) do
        RequestAnimDict(dict)
        Wait(20)
    end
end

local removeObjects = function ()
    CurrentPump = nil
    if CurrentVehicle then
        Entity(CurrentVehicle).state:set('nozzleAttached', false, true)
        FreezeEntityPosition(CurrentVehicle, false)
        CurrentVehicle = nil
    end
    if CurrentObjects.nozzle then
        DeleteEntity(CurrentObjects.nozzle)
        CurrentObjects.nozzle = nil
        ClearPedTasks(PlayerPedId())
    end
    if CurrentObjects.rope then
        DeleteRope(CurrentObjects.rope)
        RopeUnloadTextures()
        CurrentObjects.rope = nil
    end
    LocalPlayer.state:set('hasNozzle', false, true)
end

local refuelVehicle = function (veh)
    if not veh or not DoesEntityExist(veh) then return Notify(Lang:t('error.no_vehicle')) end

    local ped = PlayerPedId()
    ClearPedTasks(ped)
    local canLiter = GetAmmoInPedWeapon(ped, `WEAPON_PETROLCAN`)
    local vehFuel = math.floor(exports['fuel_system']:GetFuel(veh) or 0)

    if canLiter == 0 then return Notify(Lang:t('error.no_fuel_can'), 'error') end
    if vehFuel == 100 then return Notify(Lang:t('error.vehicle_full'), 'error') end

    local liter = canLiter + vehFuel > 100 and 100 - vehFuel or canLiter

    loadAnimDict('timetable@gardener@filling_can')
    TaskPlayAnim(ped, 'timetable@gardener@filling_can', 'gar_ig_5_filling_can', 2.0, 8.0, -1, 50, 0, false, false, false)

    SimpleProgress('fueling_vehicle', Lang:t('progress.refueling'), Config.RefillTimePerLitre * liter * 1000, false, true, {
        disableMovement = true,
        disableCarMovement = true,
        disableMouse = false,
        disableCombat = true,
    }, {}, {}, {}, function()
        TriggerServerEvent('qb-fuel:server:setCanFuel', canLiter - liter)
        SetPedAmmo(ped, `WEAPON_PETROLCAN`, canLiter - liter)
-- (تعديل) استخدام LegacyFuel بدل fuel_system و ضمان الحدّ [0..100]
local targetFuel = vehFuel + liter
if targetFuel > 100 then targetFuel = 100 end
if targetFuel < 0   then targetFuel = 0   end

exports['LegacyFuel']:SetFuel(veh, targetFuel)
Notify(Lang:t('success.refueled'), 'success')
ClearPedTasks(ped)

end


local grabFuelFromPump = function(ent)
    CurrentPump = ent
    if not CurrentPump then return end

    local ped = PlayerPedId()
    local pump = GetEntityCoords(CurrentPump)
    loadAnimDict('anim@am_hold_up@male')
    TaskPlayAnim(ped, 'anim@am_hold_up@male', 'shoplift_high', 2.0, 8.0, -1, 50, 0, false, false, false)
    Wait(300)

    CurrentObjects.nozzle = CreateObject('prop_cs_fuel_nozle', 0, 0, 0, true, true, true)

    AttachEntityToEntity(CurrentObjects.nozzle, ped, GetPedBoneIndex(ped, 0x49D9), 0.11, 0.02, 0.02, -80.0, -90.0, 15.0, true, true, false, true, 1, true)
    RopeLoadTextures()
    while not RopeAreTexturesLoaded() do
        Wait(0)
    end

    CurrentObjects.rope = AddRope(pump.x, pump.y, pump.z - 1.0, 0.0, 0.0, 0.0, 3.5, 3, 2000.0, 0.0, 2.0, false, false, false, 1.0, true)
    ActivatePhysics(CurrentObjects.rope)
    Wait(50)

    local nozzlePos = GetOffsetFromEntityInWorldCoords(CurrentObjects.nozzle, 0.0, -0.033, -0.195)
    AttachEntitiesToRope(CurrentObjects.rope, CurrentPump, CurrentObjects.nozzle, pump.x, pump.y, pump.z + 1.45, nozzlePos.x, nozzlePos.y + 0.02, nozzlePos.z, 5.0, false, false, '', '')
    LocalPlayer.state:set('hasNozzle', true, true)

    CreateThread(function()
        while DoesRopeExist(CurrentObjects.rope) do
            Wait(500)
            if RopeGetDistanceBetweenEnds(CurrentObjects.rope) > 8.0 then
                Notify(Lang:t('error.too_far'), 'error')
                break
            end
        end
        removeObjects()
    end)
end

local getVehicleCurrentSide = function(veh)
    local pump = CurrentPump
    if not pump or not DoesEntityExist(pump) then return end

    local pumpPos = GetEntityCoords(pump)
    local vehPos = GetEntityCoords(veh)
    local vehForward = GetEntityForwardVector(veh)

    local toPump = {
        x = pumpPos.x - vehPos.x,
        y = pumpPos.y - vehPos.y
    }

    local crossZ = vehForward.x * toPump.y - vehForward.y * toPump.x

    if crossZ > 0 then
        return "left"
    else
        return "right"
    end
end

local nozzleToVehicle = function (veh)
    if getVehicleCurrentSide(veh) ~= 'left' then return Notify(Lang:t('error.wrong_side'), 'error') end

    local isBike = false
    local nozzleModifiedPosition = { x = 0.0, y = 0.0, z = 0.0 }
    local tankBone = -1
    local vehClass = GetVehicleClass(veh)

    if vehClass == 8 then
        tankBone = GetEntityBoneIndexByName(veh, "petrolcap")
        if tankBone == -1 then tankBone = GetEntityBoneIndexByName(veh, "petroltank") end
        if tankBone == -1 then tankBone = GetEntityBoneIndexByName(veh, "engine") end
        isBike = true
    elseif vehClass ~= 13 then
        tankBone = GetEntityBoneIndexByName(veh, "petrolcap")
        if tankBone == -1 then tankBone = GetEntityBoneIndexByName(veh, "petroltank_l") end
        if tankBone == -1 then tankBone = GetEntityBoneIndexByName(veh, "hub_lr") end
        if tankBone == -1 then
            tankBone = GetEntityBoneIndexByName(veh, "handle_dside_r")
            nozzleModifiedPosition.x = 0.1
            nozzleModifiedPosition.y = -0.5
            nozzleModifiedPosition.z = -0.6
        end
    end

    local wheelPos = GetWorldPositionOfEntityBone(veh, GetEntityBoneIndexByName(veh, "wheel_lr"))
    local wheelRPos = GetOffsetFromEntityGivenWorldCoords(veh, wheelPos.x, wheelPos.y, wheelPos.z)

    DetachEntity(CurrentObjects.nozzle, false, true)
    local dimMin, dimMax = GetModelDimensions(GetEntityModel(veh))

    local diff = dimMax.z - wheelRPos.z

    local divisor = (dimMax - dimMin).z < 1.4 and (1.87 * (dimMax - dimMin).z) / 1.24 or (2.7 * (dimMax - dimMin).z) / 2.3
    local zCoords = diff / divisor

    LocalPlayer.state:set('hasNozzle', false, true)

    if isBike then
        AttachEntityToEntity(CurrentObjects.nozzle, veh, tankBone, 0.0 + nozzleModifiedPosition.x, -0.2 + nozzleModifiedPosition.y, 0.2 + nozzleModifiedPosition.z, -80.0, 0.0, 0.0, true, true, false, false, 1, true)
    else
        AttachEntityToEntity(CurrentObjects.nozzle, veh, tankBone, -0.18 + nozzleModifiedPosition.x, 0.0 + nozzleModifiedPosition.y, zCoords, -125.0, -90.0, -90.0, true, true, false, false, 1, true)
    end

    Entity(veh).state:set('nozzleAttached', true, true)
    CurrentVehicle = veh
    FreezeEntityPosition(CurrentObjects.nozzle, true)
    FreezeEntityPosition(CurrentVehicle, true)

    CreateThread((function ()
        while DoesEntityExist(CurrentObjects.nozzle) and DoesEntityExist(CurrentVehicle) and Entity(veh).state.nozzleAttached do
            Wait(1000)
        end
        removeObjects()
    end))
end

-- ====================|| تعديل: refillVehicleFuel (إلغاء فحص الرصيد الكلاينتي) ||==================== --
local refillVehicleFuel = function (liter)
    if not liter then return end

    -- ملاحظة:
    -- تم حذف فحص الرصيد على الكلاينت حتى لا يوقف العملية لو كان الرصيد في حساب آخر.
    -- الخصم يتم سيرفريًا (money ثم bank)، وهو المكان الصحيح لاتخاذ القرار الفعلي.

    if not CurrentPump then return end

    local veh, dis = GetClosestVehicleESX()
    if not veh or veh == -1 or not DoesEntityExist(veh) then return Notify(Lang:t('error.no_nozzle'), 'error') end
    if not Entity(veh).state['nozzleAttached'] then return Notify(Lang:t('error.no_nozzle'), 'error') end
    if dis > 5 then return end

    local ped = PlayerPedId()
    ClearPedTasks(ped)
    TaskTurnPedToFaceEntity(ped, veh, 1000)
    TaskGoStraightToCoordRelativeToEntity(ped, CurrentObjects.nozzle, 0.0, 0.0, 0.0, 1.0, 1000)
    Wait(1500)

    TaskLookAtEntity(ped, veh, 5000, 2048, 3)
    Wait(500)

    loadAnimDict('timetable@gardener@filling_can')
    TaskPlayAnim(ped, 'timetable@gardener@filling_can', 'gar_ig_5_filling_can', 2.0, 8.0, -1, 50, 0, false, false, false)

    SimpleProgress('fueling_vehicle', Lang:t('progress.refueling'), Config.RefillTimePerLitre * liter * 1000, false, true, {
        disableMovement = true,
        disableCarMovement = true,
        disableMouse = false,
        disableCombat = true,
    }, {}, {}, {}, function()
        -- القرار هنا سيرفري (ESX callback): يخصم من money ثم bank هناك
        local success = ESX_AwaitServerCallback('qb-fuel:server:refillVehicle', liter)
        if not success then
            -- في حالة الرفض من السيرفر (ما عنده رصيد كافٍ لا بالكاش ولا البنك)
            return Notify(Lang:t('error.no_money'), 'error')
        end

-- تم الدفع: فكّ الأغراض وحدّث الوقود  (تعديل)
removeObjects()

-- استخدم LegacyFuel بدل fuel_system
local currentFuel = exports['LegacyFuel']:GetFuel(veh) or 0
local newFuel = math.floor(currentFuel) + tonumber(liter)
if newFuel > 100 then newFuel = 100 end
if newFuel < 0   then newFuel = 0   end

exports['LegacyFuel']:SetFuel(veh, newFuel)

Notify(Lang:t('success.refueled'), 'success')
ClearPedTasks(ped)

    end)
end



-- تصريح مسبق حتى تلتقطه الكلوجرات داخل setUpTarget كمحلّي بدل global nil
local showFuelMenu

-- ====================|| OX_TARGET بدلاً من QB-TARGET || ==================== --
local setUpTarget = function ()
    for _, hash in pairs(Config.PumpModels) do
        exports.ox_target:addModel(hash, {
            {
                name = 'qb_fuel_get_nozzle',
                icon = 'fa-solid fa-gas-pump',
                label = Lang:t('target.get_nozzle'),
                distance = 1.5,
                canInteract = function(entity, distance, coords, name, bone)
                    return CurrentObjects.nozzle == nil
                end,
                onSelect = function(data)
                    grabFuelFromPump(data.entity)
                end
            },
            {
                name = 'qb_fuel_return_nozzle',
                icon = 'fa-solid fa-gas-pump',
                label = Lang:t('target.return_nozzle'),
                distance = 1.5,
                canInteract = function(entity, distance, coords, name, bone)
                    return LocalPlayer.state['hasNozzle']
                end,
                onSelect = function(data)
                    removeObjects()
                end
            },
            {
                name = 'qb_fuel_put_fuel',
                icon = 'fa-solid fa-gas-pump',
                label = Lang:t('target.put_fuel'),
                distance = 1.5,
                canInteract = function(entity, distance, coords, name, bone)
                    return CurrentPump ~= nil
                end,
                onSelect = function(data)
                    showFuelMenu()
                end
            },
            {
                name = 'qb_fuel_buy_jerrycan',
                icon = 'fa-solid fa-jar',
                label = Lang:t('target.buy_jerrycan', { price = Config.JerryCanCost }),
                distance = 1.5,
                serverEvent = 'qb-fuel:server:buyJerryCan'
            },
            {
                name = 'qb_fuel_refill_jerrycan',
                icon = 'fa-solid fa-arrows-rotate',
                label = Lang:t('target.refill_jerrycan', { price = Config.JerryCanCost }),
                distance = 1.5,
                canInteract = function(entity, distance, coords, name, bone)
                    return GetSelectedPedWeapon(PlayerPedId()) == `WEAPON_PETROLCAN`
                end,
                serverEvent = 'qb-fuel:server:refillJerryCan'
            }
        })
    end


    exports.ox_target:addGlobalVehicle({
        {
            name = 'qb_fuel_refill_fuel',
            icon = 'fa-solid fa-gas-pump',
            label = Lang:t('target.refill_fuel'),
            distance = 3.0,
            canInteract = function(entity, distance, coords, name, bone)
                return GetSelectedPedWeapon(PlayerPedId()) == `WEAPON_PETROLCAN`
            end,
            onSelect = function(data)
                refuelVehicle(data.entity)
            end
        },
        {
            name = 'qb_fuel_nozzle_put',
            icon = 'fa-solid fa-gas-pump',
            label = Lang:t('target.nozzle_put'),
            distance = 3.0,
            canInteract = function(entity, distance, coords, name, bone)
                return LocalPlayer.state['hasNozzle']
            end,
            onSelect = function(data)
                nozzleToVehicle(data.entity)
            end
        },
        {
            name = 'qb_fuel_nozzle_remove',
            icon = 'fa-solid fa-gas-pump',
            label = Lang:t('target.nozzle_remove'),
            distance = 3.0,
            canInteract = function(entity, distance, coords, name, bone)
                return Entity(entity).state['nozzleAttached']
            end,
            onSelect = function(data)
                removeObjects()
            end
        }
    })
end

showFuelMenu = function ()
    if not CurrentPump then return end
    local veh, dis = GetClosestVehicleESX()
    if not veh or veh == -1 then return Notify(Lang:t('error.no_vehicle')) end
    if dis > 5 then return Notify(Lang:t('error.no_vehicle')) end
    SendNUIMessage({
        action = 'show',
        price = Config.FuelPrice,
        currentFuel = math.floor(exports['fuel_system']:GetFuel(veh) or 0),
    })
    SetNuiFocus(true, true)
end



local hideFuelMenu = function ()
    SendNUIMessage({ action = 'hide' })
    SetNuiFocus(false, false)
end

local displayBlips = function ()
    for _, station in ipairs(Config.GasStations) do
        local blip = AddBlipForCoord(station.x, station.y, station.z)
        SetBlipSprite(blip, Config.Blip.Sprite)
        SetBlipColour(blip, Config.Blip.Color)
        SetBlipScale(blip, Config.Blip.Scale)
        SetBlipDisplay(blip, Config.Blip.Display)
        SetBlipAsShortRange(blip, Config.Blip.ShortRange)
        BeginTextCommandSetBlipName('STRING')
        AddTextComponentString(Config.Blip.Text)
        EndTextCommandSetBlipName(blip)
        Blips[#Blips + 1] = blip
    end
end

local deloadBlips = function ()
    for _, blip in ipairs(Blips) do
        RemoveBlip(blip)
    end
end

local init = function ()
    if __inited then return end
    __inited = true

    SetFuelConsumptionState(true)
    SetFuelConsumptionRateMultiplier(Config.GlobalFuelConsumptionMultiplier)

    displayBlips()
    setUpTarget()

    SendNUIMessage({
        action = 'setLanguage',
        language = GetConvar('locale', 'ar')
    })
end

-- ====================|| NUI CALLBACKS || ==================== --

RegisterNuiCallback('close', function (_, cb)
    hideFuelMenu()
    cb('ok')
end)

RegisterNuiCallback('refill', function (data, cb)
    if not data or not data.liter then return end
    hideFuelMenu()
    refillVehicleFuel(data.liter)
    cb('ok')
end)

-- ====================|| EVENTS || ==================== --

AddEventHandler('onResourceStop', function (res)
    if GetCurrentResourceName() ~= res then return end
    removeObjects()
    deloadBlips()
end)

RegisterNetEvent('esx:onPlayerLogout', function()
    removeObjects()
    deloadBlips()
end)

RegisterNetEvent('esx:setAccountMoney', function(account)
    if not ESX.PlayerData then ESX.PlayerData = {} end
    ESX.PlayerData.accounts = ESX.PlayerData.accounts or {}
    local found = false
    for i,acc in ipairs(ESX.PlayerData.accounts) do
        if acc.name == account.name then
            ESX.PlayerData.accounts[i] = account
            found = true
            break
        end
    end
    if not found then table.insert(ESX.PlayerData.accounts, account) end
end)

-- ====================|| INITIALIZATION || ==================== --

RegisterNetEvent('esx:playerLoaded', function(xPlayer)
    ESX.PlayerData = xPlayer or ESX.GetPlayerData()
    init()
end)

CreateThread(function()
    Wait(500)
    if not __inited then init() end
end)

-- =========================
-- NUI Bridge: Fuel UI
-- ضع هذا القسم في client/main.lua
-- =========================
local fuelUiOpen = false

local function OpenFuelUi(data)
    if fuelUiOpen then return end
    fuelUiOpen = true

    -- أعطِ الصفحة بيانات العرض (لو عندك أكشن/ترجمة… عدّلها هنا)
    SendNUIMessage({
        action = 'show',
        litres = data and data.litres or nil,
        pricePerLitre = data and data.price or nil
    })

    -- فعّل الماوس والتفاعل مع الصفحة
    SetNuiFocus(true, true)
end

local function CloseFuelUi()
    if not fuelUiOpen then return end
    fuelUiOpen = false

    -- أخفِ الواجهة وأغلق الفوكس
    SendNUIMessage({ action = 'hide' })
    SetNuiFocus(false, false)
end

-- نداءٌ من سكربت المضخة لحظة ضغط "تعبئة"
-- نادِ هذا الحدث من مكان ضغطة ox_target / زر التزويد
RegisterNetEvent('fuel:client:openUi', function(data)
    OpenFuelUi(data)
end)

-- كولباك يُستدعى من JS: fetch('https://{resource}/refill', {method:'POST', body: JSON.stringify({...})})
RegisterNUICallback('refill', function(payload, cb)
    -- payload.litres: لتر المستخدم
    local litres = tonumber(payload and payload.litres) or 0

    -- اطلب من السيرفر دفع المبلغ وتعبئة الوقود
    ESX.TriggerServerCallback('qb-fuel:server:refillVehicle', function(paid)
        if paid then
            -- حدّث عداد الوقود هنا حسب نظامك:
            -- exports['your_fuel_resource']:SetFuel(vehicle, newFuel)  -- مثال
            cb({ ok = true })
            CloseFuelUi()
        else
            cb({ ok = false, error = 'no_money' })
            -- بإمكانك عرض نوتيفيكيشن هنا
        end
    end, litres)
end)

-- كولباك إغلاق من الواجهة: fetch('https://{resource}/close', {method:'POST'})
RegisterNUICallback('close', function(_, cb)
    CloseFuelUi()
    cb({ ok = true })
end)

-- مفتاح طوارئ (ESC) لو حبيت تقفّل الواجهة حتى لو JS ما رد
CreateThread(function()
    while true do
        if fuelUiOpen and IsControlJustReleased(0, 322) then -- ESC
            CloseFuelUi()
        end
        Wait(0)
    end
end)

-- تأكد نفك الفوكس لو توقّف الريسورس
AddEventHandler('onResourceStop', function(res)
    if res == GetCurrentResourceName() then
        SetNuiFocus(false, false)
    end
end)
