-- Координаты и карта для зоны дуэли
local duelZoneX = 1205.856323
local duelZoneY = 270.024231
local duelZoneZ = 354.964630
local duelZoneMap = 37
local duelZoneO = 5.427881 -- Пример ориентации, можно изменить

local duelZone2X = 1256.343506
local duelZone2Y = 205.950150
local duelZone2Z = 353.924866
local duelZoneMap2 = 37
local duelZone2O = 2.270466 -- Пример ориентации, можно изменить

local duelRequests = {}

-- Массивы запрещенных предметов и способностей
local forbiddenItems = {6948, 49703} -- Замените числа на ID запрещенных предметов
local forbiddenSpells = {10059} -- Замените числа на ID запрещенных способностей
local savedItemsAndSpells = {}
local playerOriginalLocations = {}
local activeDuels = {}



local function KickPlayer(player)
    print("KickPlayer: Kicking player from duel - " .. player:GetName())

    -- Удаление игрока из массива активных дуэлей
    local playerGUID = player:GetGUIDLow()
    activeDuels[playerGUID] = nil

    -- Непосредственный кик игрока
    player:KickPlayer()
end

local function RemoveForbiddenItemsAndSpells(player, forbiddenItems, forbiddenSpells)
    local playerGUID = player:GetGUIDLow()
    savedItemsAndSpells[playerGUID] = { items = {}, spells = {} }

    for _, itemID in ipairs(forbiddenItems) do
        if player:HasItem(itemID) then
            local itemCount = player:GetItemCount(itemID)
            player:RemoveItem(itemID, itemCount)
            table.insert(savedItemsAndSpells[playerGUID].items, { itemID = itemID, count = itemCount })
        end
    end

    for _, spellID in ipairs(forbiddenSpells) do
        if player:HasSpell(spellID) then
            player:RemoveSpell(spellID)
            table.insert(savedItemsAndSpells[playerGUID].spells, spellID)
        end
    end
end

local function RestoreItemsAndSpellsForWinner(winner)
    local winnerGUID = winner:GetGUIDLow()
    if savedItemsAndSpells[winnerGUID] then
        for _, itemInfo in ipairs(savedItemsAndSpells[winnerGUID].items) do
            winner:AddItem(itemInfo.itemID, itemInfo.count)
        end

        for _, spellID in ipairs(savedItemsAndSpells[winnerGUID].spells) do
            winner:LearnSpell(spellID)
        end

        savedItemsAndSpells[winnerGUID] = nil -- Очистка данных после восстановления
    end
end


local function StartDuelCountdown(playerGUID, targetGUID)
    for i = 10, 1, -1 do
        CreateLuaEvent(function()
            local player = GetPlayerByGUID(playerGUID)
            local target = GetPlayerByGUID(targetGUID)
			player:SetPlayerLock(true)
			target:SetPlayerLock(true)
            if player and target then
                player:SendBroadcastMessage("До начала дуэли: " .. i)
                target:SendBroadcastMessage("До начала дуэли: " .. i)
            end
        end, 1000 * (11 - i), 1)
    end

    CreateLuaEvent(function()
        local player = GetPlayerByGUID(playerGUID)
        local target = GetPlayerByGUID(targetGUID)
        if player and target then
            player:SetPlayerLock(false)
            target:SetPlayerLock(false)
            player:SetFFA(true)
            target:SetFFA(true)
        end
    end, 10000, 1)
end

local function TeleportWinnerBack(winner)
    local winnerGUID = winner:GetGUIDLow()
    local location = playerOriginalLocations[winnerGUID]

    if location then
        winner:Teleport(location.map, location.x, location.y, location.z, location.o)
        playerOriginalLocations[winnerGUID] = nil -- Очищаем сохраненное местоположение
    end
end

-- Функция для записи результата дуэли в базу данных
local function RecordDuelResult(winner, loser)
    local winnerGUID = winner:GetGUIDLow()
    local loserGUID = loser:GetGUIDLow()
    
    -- Сообщения всем игрокам о результате дуэли
    local players = GetPlayersInWorld()
    for _, player in ipairs(players) do
        player:SendAreaTriggerMessage("|cFFFF0000Мак'Гора:|r |cFF00FF00" .. winner:GetName() .. "|r |cFFFFFFFFодержал победу в Мак'Гора! Поздравляем!|r")
        player:SendBroadcastMessage("|cFFFF0000Мак'Гора:|r |cFF00FF00" .. winner:GetName() .. "|r |cFFFFFFFFодержал победу в Мак'Гора! Поздравляем!|r")
    end

    -- Запись в статистику дуэли
    CharDBQuery("INSERT INTO duel_statistics (winner_guid, loser_guid) VALUES (" .. winnerGUID .. ", " .. loserGUID .. ");")

    -- Восстановление предметов и способностей для победителя и его телепортация обратно
    RestoreItemsAndSpellsForWinner(winner)
    TeleportWinnerBack(winner)
	winner:RemoveAura(47840)
	
	 -- Начисление 10 очков лояльности победителю
    local currentPoints = GetDuelPlayerLoyalPoints(winner)
    UpdateDuelPlayerLoyalPoints(winner, currentPoints + 10)
    winner:SendBroadcastMessage("Поздравляем с победой! Вам начислено 10 очков лояльности.")

    -- Телепортация проигравшего игрока
    loser:Teleport(37, -614.380005, -239.690002, 379.350006, 0.690000)
	loser:ResurrectPlayer(100)

    -- Кик проигравшего игрока
    KickPlayer(loser)

    -- Обновление данных в базе данных после кика
    CharDBQuery("DELETE FROM character_homebind WHERE guid = " .. loserGUID .. ";")
	CharDBQuery("INSERT INTO character_homebind (guid, mapId, zoneId, posX, posY, posZ, posO) VALUES (" .. loserGUID .. ", 0, 1, 6240, 331, 383, 0);")


end


local function GetAllDuelWinStatistics(player)
    -- SQL запрос для получения статистики побед каждого игрока
    local query = CharDBQuery("SELECT characters.name, COUNT(duel_statistics.winner_guid) AS wins FROM duel_statistics JOIN characters ON duel_statistics.winner_guid = characters.guid GROUP BY duel_statistics.winner_guid;")

    if query then
        player:SendBroadcastMessage("Статистика побед:")
        repeat
            local name = query:GetString(0)
            local wins = query:GetUInt32(1)
            player:SendBroadcastMessage("Имя: " .. name .. " Побед: " .. wins)
        until not query:NextRow()
    else
        player:SendBroadcastMessage("Статистика побед не найдена.")
    end
end





local function ApplyAuraAndStartCheck(player, target)
	    print("ApplyAuraAndStartCheck: Adding auras and setting up duel")  -- Отладочное сообщение
    player:AddAura(47840, player)
    target:AddAura(47840, target)
    activeDuels[player:GetGUIDLow()] = target:GetGUIDLow()
    activeDuels[target:GetGUIDLow()] = player:GetGUIDLow()

    local function checkAura()
    for playerGUID, targetGUID in pairs(activeDuels) do
        local player = GetPlayerByGUID(playerGUID)
        local target = GetPlayerByGUID(targetGUID)

        -- Проверка наличия ауры и состояния игроков
        if player and target then
            if not player:HasAura(47840) then
                print("checkAura: Player " .. player:GetName() .. " lost aura")  -- Отладочное сообщение
                RecordDuelResult(target, player)
                KickPlayer(player)
                activeDuels[playerGUID] = nil
                activeDuels[targetGUID] = nil
            elseif not target:HasAura(47840) then
			                    print("checkAura: Target lost aura, handling result")  -- Отладочное сообщение
                RecordDuelResult(player, target)
                KickPlayer(target)
                activeDuels[playerGUID] = nil
                activeDuels[targetGUID] = nil
            end
        end
    end

    CreateLuaEvent(checkAura, 1000, 1)
	end
	
	checkAura()
end

local function TeleportToDuelZone(requesterGUID, targetGUID)
    local player = GetPlayerByGUID(requesterGUID)
    local target = GetPlayerByGUID(targetGUID) 

    if not player or not target then
        return
    end

	 player:SetPlayerLock(true)
     target:SetPlayerLock(true)

    player:Teleport(duelZoneMap, duelZoneX, duelZoneY, duelZoneZ, duelZoneO)
    target:Teleport(duelZoneMap2, duelZone2X, duelZone2Y, duelZone2Z, duelZone2O)
	player:SetPlayerLock(true)
     target:SetPlayerLock(true)
  
	    local players = GetPlayersInWorld()
		 for _, players in ipairs(players) do
    players:SendBroadcastMessage("|cFFFF0000Мак'Гора:|r |cFF00FF00" .. player:GetName() .. "|r |cFFFFFFFFи|r |cFF00FF00" .. target:GetName() .. "|r |cFFFFFFFFвступают в дуэль насмерть!|r")
	players:SendAreaTriggerMessage("|cFFFF0000Мак'Гора:|r |cFF00FF00" .. player:GetName() .. "|r |cFFFFFFFFи|r |cFF00FF00" .. target:GetName() .. "|r |cFFFFFFFFвступают в дуэль насмерть!|r")
	end
    RemoveForbiddenItemsAndSpells(player, forbiddenItems, forbiddenSpells)
    RemoveForbiddenItemsAndSpells(target, forbiddenItems, forbiddenSpells)

    StartDuelCountdown(requesterGUID, targetGUID)

    player:ResetAllCooldowns()
    target:ResetAllCooldowns()
    player:SetHealth(player:GetMaxHealth())
    player:SetPower(player:GetMaxPower(0), 0)
    target:SetHealth(target:GetMaxHealth())
    target:SetPower(target:GetMaxPower(0), 0)

    ApplyAuraAndStartCheck(player, target)
end

local function RemoveDuelRequest(targetGUID, notify)
    local requesterGUID = duelRequests[targetGUID]
    if requesterGUID then
        -- Дополнительная проверка, чтобы убедиться, что дуэль не началась
        if not activeDuels[requesterGUID] and not activeDuels[targetGUID] then
            local target = GetPlayerByGUID(targetGUID)
            local requester = GetPlayerByGUID(requesterGUID)
            if notify then
                if target then
                    target:SendBroadcastMessage("Время ожидания дуэли истекло.")
                end
                if requester then
                    requester:SendBroadcastMessage("Ваш запрос на дуэль был отменен из-за истечения времени ожидания.")
                end
            end
            duelRequests[targetGUID] = nil
        end
    end
end


local function MakgoraRequest(player, target)
    local targetGUID = target:GetGUIDLow()
    local playerGUID = player:GetGUIDLow()
    
    if duelRequests[targetGUID] or duelRequests[playerGUID] then
        player:SendBroadcastMessage("У вас уже есть активный запрос на дуэль.")
        return
    end

	 playerOriginalLocations[playerGUID] = {
        x = player:GetX(),
        y = player:GetY(),
        z = player:GetZ(),
        map = player:GetMapId(),
        o = player:GetO()
    }
	
	 playerOriginalLocations[targetGUID] = {
        x = target:GetX(),
        y = target:GetY(),
        z = target:GetZ(),
        map = target:GetMapId(),
        o = target:GetO()
    }
	
    duelRequests[targetGUID] = playerGUID
    target:SendBroadcastMessage(player:GetName().." вызывает вас на дуэль. Введите '.accept' для принятия вызова или .cancel для отмены.")
end


-- Функция для получения статистики побед игрока
local function GetDuelWinStatistics(player)
    local playerGUID = player:GetGUIDLow()
    local query = CharDBQuery("SELECT COUNT(*) AS wins FROM duel_statistics WHERE winner_guid = " .. playerGUID .. ";")

    if query then
        local wins = query:GetUInt32(0)
        player:SendBroadcastMessage("У вас " .. wins .. " побед в дуэлях.")
    else
        player:SendBroadcastMessage("Статистика побед не найдена.")
    end
end

local function MakgoraCommand(event, player, command)
    -- Разбиваем команду на слова для проверки аргументов
    local args = {}
    for word in string.gmatch(command, "%S+") do table.insert(args, word) end

    -- Проверяем, является ли команда .makgora и обрабатываем аргументы
    if args[1] == "makgora" then
        -- Если после .makgora идет аргумент stats, вызываем функцию GetDuelWinStatistics
        if args[2] == "stats" then
            GetAllDuelWinStatistics(player)
            return false
        end

        -- Обработка вызова на дуэль
        local target = player:GetSelection()
        if target and target ~= player then
            MakgoraRequest(player, target)
            player:SendBroadcastMessage("Вы вызвали "..target:GetName().." на дуэль.")
        else
            player:SendBroadcastMessage("Вам нужно выбрать игрока в качестве цели.")
        end
        return false
    elseif command == "accept" and duelRequests[player:GetGUIDLow()] then
        local requesterGUID = duelRequests[player:GetGUIDLow()]
        TeleportToDuelZone(requesterGUID, player:GetGUIDLow())
        duelRequests[player:GetGUIDLow()] = nil
        return false
    elseif command == "cancel" and duelRequests[player:GetGUIDLow()] then
        RemoveDuelRequest(player:GetGUIDLow(), true)
        player:SendBroadcastMessage("Вы отменили запрос на дуэль.")
        return false
    end
end


RegisterPlayerEvent(42, MakgoraCommand)
