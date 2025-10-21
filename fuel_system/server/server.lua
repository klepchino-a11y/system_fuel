-- ====================|| VARIABLES || ==================== --

ESX = exports["es_extended"]:getSharedObject()

-- ====================|| EVENTS || ==================== --
-- (تعديل) استبدال كامل لدالة الدفع للتعبئة: يخصم أولاً من money ثم من bank إذا لم يكفِ
ESX.RegisterServerCallback('qb-fuel:server:refillVehicle', function (src, cb, litres)
    local xPlayer = ESX.GetPlayerFromId(src)
    if not xPlayer then cb(false) return end

    local l = tonumber(litres)
    if not l or l <= 0 then cb(false) return end

    local finalPrice = math.ceil(l * (Config.FuelPrice or 0))
    local paid = false

    -- رصيد الكاش (money)
    local cash = 0
    if xPlayer.getAccount then
        local acc = xPlayer.getAccount('money'); cash = acc and acc.money or 0
    elseif xPlayer.getMoney then
        cash = tonumber(xPlayer.getMoney()) or 0
    end

    if cash >= finalPrice then
        if xPlayer.removeAccountMoney then
            xPlayer.removeAccountMoney('money', finalPrice, 'fuel_refill')
        elseif xPlayer.removeMoney then
            xPlayer.removeMoney(finalPrice, 'fuel_refill')
        end
        paid = true
    else
        -- رصيد البنك (bank) كخيار ثانٍ
        local bank = 0
        if xPlayer.getAccount then
            local acc = xPlayer.getAccount('bank'); bank = acc and acc.money or 0
        end
        if bank >= finalPrice then
            if xPlayer.removeAccountMoney then
                xPlayer.removeAccountMoney('bank', finalPrice, 'fuel_refill')
                paid = true
            end
        end
    end

    cb(paid)
end)


-- شراء جالون (ESX يتعامل معه كسلاح WEAPON_PETROLCAN بذخيرة = لترات)
RegisterServerEvent('qb-fuel:server:buyJerryCan', function ()
    local src = source
    local xPlayer = ESX.GetPlayerFromId(src)
    if not xPlayer then return end

    local cost = Config.JerryCanCost
    local paid = false

    if Config.MoneyType == 'bank' then
        local account = xPlayer.getAccount and xPlayer.getAccount('bank')
        if account and (account.money or 0) >= cost then
            if xPlayer.removeAccountMoney then xPlayer.removeAccountMoney('bank', cost) end
            paid = true
        end
    else
        if xPlayer.getMoney and xPlayer.getMoney() >= cost then
            if xPlayer.removeMoney then xPlayer.removeMoney(cost) end
            paid = true
        end
    end

    if not paid then return end

    local weapon = string.lower('WEAPON_PETROLCAN')

    -- لا يمكن امتلاك أكثر من جالون كسلاح، لذا نضيف/نحدّث الذخيرة (تعادل اللترات)
    if xPlayer.hasWeapon and xPlayer:hasWeapon(weapon) then
        if xPlayer.updateWeaponAmmo then
            xPlayer.updateWeaponAmmo(weapon, Config.JerryCanLitre)
        elseif xPlayer.addWeaponAmmo then
            xPlayer.addWeaponAmmo(weapon, Config.JerryCanLitre)
        else
            xPlayer.addWeapon(weapon, Config.JerryCanLitre)
        end
    else
        if xPlayer.addWeapon then
            xPlayer.addWeapon(weapon, Config.JerryCanLitre)
        end
    end
end)

-- تعبئة الجالون
RegisterServerEvent('qb-fuel:server:refillJerryCan', function ()
    local src = source
    local xPlayer = ESX.GetPlayerFromId(src)
    if not xPlayer then return end

    local cost = Config.JerryCanRefillCost
    local paid = false

    if Config.MoneyType == 'bank' then
        local account = xPlayer.getAccount and xPlayer.getAccount('bank')
        if account and (account.money or 0) >= cost then
            if xPlayer.removeAccountMoney then xPlayer.removeAccountMoney('bank', cost) end
            paid = true
        end
    else
        if xPlayer.getMoney and xPlayer.getMoney() >= cost then
            if xPlayer.removeMoney then xPlayer.removeMoney(cost) end
            paid = true
        end
    end

    if not paid then return end

    local weapon = string.lower('WEAPON_PETROLCAN')

    if xPlayer.hasWeapon and xPlayer:hasWeapon(weapon) then
        if xPlayer.updateWeaponAmmo then
            xPlayer.updateWeaponAmmo(weapon, Config.JerryCanLitre)
        elseif xPlayer.addWeaponAmmo then
            xPlayer.addWeaponAmmo(weapon, Config.JerryCanLitre)
        else
            xPlayer.addWeapon(weapon, Config.JerryCanLitre)
        end
    else
        local msg = (Lang and Lang:t('error.no_jerrycan')) or 'You do not have a jerry can.'
        if xPlayer.showNotification then
            xPlayer.showNotification(msg)
        else
            TriggerClientEvent('esx:showNotification', src, msg)
        end
    end
end)

-- ضبط كمية الوقود داخل الجالون (تحديث "ذخيرة" السلاح)
RegisterServerEvent('qb-fuel:server:setCanFuel', function (fuel)
    local src = source
    local xPlayer = ESX.GetPlayerFromId(src)
    if not xPlayer then return end

    local weapon = string.lower('WEAPON_PETROLCAN')
    local litres = math.floor(tonumber(fuel) or 0)

    if xPlayer.hasWeapon and xPlayer:hasWeapon(weapon) then
        if xPlayer.updateWeaponAmmo then
            xPlayer.updateWeaponAmmo(weapon, litres)
        elseif xPlayer.addWeaponAmmo then
            -- لا يوجد "تعيين مباشر" في بعض الإصدارات، نستخدم قناة ESX الداخلية كحل احتياطي
            TriggerClientEvent('esx:setWeaponAmmo', src, weapon, litres)
        else
            xPlayer.addWeapon(weapon, litres)
        end
    else
        local msg = (Lang and Lang:t('error.no_jerrycan')) or 'You do not have a jerry can.'
        if xPlayer.showNotification then
            xPlayer.showNotification(msg)
        else
            TriggerClientEvent('esx:showNotification', src, msg)
        end
    end
end)
