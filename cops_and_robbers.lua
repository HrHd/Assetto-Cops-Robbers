local active = true
local cfg = { hitWalls = true, hitCars = true, radarAudio = true, beepVolume = 0.8, speedLimit = 160, copRandomSpawn = true, compactMode = false, chirpSpeed = 1.0, chirpTone = 1.0, robberPitsOnly = true, chaseStartSecs = 30, radarPreset = 3, penaltySecs = 120, copRadarRange = 75 }

local function radarRange()     return ({750, 1000, 1500})[cfg.radarPreset] end
local function radarBehind()     return cfg.copRadarRange end
local function radarBehindDot()  return ({-0.7, -0.82, -0.95})[cfg.radarPreset] end
local function radarBeepRange()  return ({750, 1000, 1500})[cfg.radarPreset] end
local function radarTargeted()   return ({15, 22, 30})[cfg.radarPreset] end
local teamChoice = 0
local cooldown = 0
local cooldownDuration = 8
local collisionThreshold = 12
local minSpeedCheck = 5
local proximityCheck = 5
local spawnPoints = {}
local nearestCopDist = math.huge
local nearestCopDirection = 0
local copBehindDist = math.huge
local copProximityTimer = 0
local chaseActive = false
local chaseFlashTimer = 0
local chaseAwayTimer = 0
local chaseStartTime = 0
local chaseSearchPhase = false
local escapedTextTimer = 0
local copSearchTimer = 0
local wasTracking = false
local copEscapedTimer = 0
local copScore = 0
local robberScore = 0
local lastWreckTime = 0
local lastWreckTeam = 0
local robberPrevSpeed = 0
local copPrevSpd = 0
local penaltyActive = false
local penaltyTimer = 0
local penaltyViolations = 0
local penaltyDuration = 0
local radarBeep = nil
local radarLastBeep = 0
local radarReady = false
local beepPath = nil
local nearestSpeed = 0
local nearestSpeedDist = math.huge
local speedTracks = {}
local activeNotifications = {}
local primaryTargetIdx = nil
local clearedTargets = {}
local teleportPhase = 0
local teleportTarget = nil
local teleportTimer = 0
local teleportRetries = 0
local selectedCopSpawn = nil
local prevSpeed = 0
local playerIndex = 0
local copLockButton = ac.ControlButton("CopsAndRobbers/LockTarget")
local robberMuteButton = ac.ControlButton("CopsAndRobbers/MuteChirp")
local muteWasDown = false
local copLockHoldTime = 0
local copLockHoldIdx = nil
local copLockHoldName = ""

local lastTargetedAlert = 0
local spawnsLoaded = false
local reloadTimer = 0
local copKeywords = {'police', 'cop ', 'cop_', '_cop', 'sheriff', '911', 'chp', 'polizia', 'policia', 'nfs', 'crown vic', 'taurus', 'fpis', 'fpiu', 'cvpi', 'impala', 'caprice', 'explorer interceptor', 'tahoe ppv', 'durango pursuit', 'unmarked', 'o4rs'}

-- SPAWN SYSTEM --
local function getSpawnPath()
    return ac.getFolder(ac.FolderID.ACApps) .. "/lua/cops_and_robbers/spawns/" .. ac.getTrackFullID('/') .. ".ini"
end

local function loadServerTeleports()
    local sim = ac.getSim()
    if not (sim and sim.isOnlineRace and ac.INIConfig.onlineExtras) then return end
    local ini = ac.INIConfig.onlineExtras()
    local raw = {}
    for _, key in ini:iterateValues('TELEPORT_DESTINATIONS', 'POINT') do
        local n = tonumber(key:match('%d+'))
        if n then
            n = n + 1
            while #raw < n do table.insert(raw, {}) end
            local suffix = key:match('_(%a+)$')
            if suffix == nil then raw[n].name = ini:get('TELEPORT_DESTINATIONS', key, 'noname' .. (n - 1))
            elseif suffix == 'POS' then raw[n].pos = ini:get('TELEPORT_DESTINATIONS', key, vec3())
            elseif suffix == 'HEADING' then raw[n].heading = ini:get('TELEPORT_DESTINATIONS', key, 0)
            elseif suffix == 'GROUP' then raw[n].group = ini:get('TELEPORT_DESTINATIONS', key, '')
            end
        end
    end
    for i, p in ipairs(raw) do
        if p.pos and p.pos.x ~= nil then
            local name = p.group and p.group ~= '' and (p.group .. ' #' .. i) or (p.name or 'spawn')
            table.insert(spawnPoints, { pos = p.pos, heading = p.heading or 0, name = name, serverIndex = i - 1 })
        end
    end
end

local function loadLocalSpawns()
    local config = ac.INIConfig.load(getSpawnPath(), ac.INIFormat.Extended)
    if not config then return end
    for i = 0, 99 do
        local pos = config:get("SPAWN_" .. i, "POS", nil)
        if not pos then break end
        table.insert(spawnPoints, { pos = pos, heading = config:get("SPAWN_" .. i, "HEADING", 0), name = config:get("SPAWN_" .. i, "NAME", "Spawn " .. i), serverIndex = nil })
    end
end

local function loadSpawnPoints()
    spawnPoints = {}
    selectedCopSpawn = nil
    loadServerTeleports()
    if #spawnPoints == 0 then loadLocalSpawns() end
    spawnsLoaded = true
end

local function pickRandomTarget()
    if #spawnPoints == 0 then return nil end
    local p = spawnPoints[math.random(1, #spawnPoints)]
    return p.serverIndex ~= nil and p.serverIndex or nil
end

local function teleportPlayer()
    prevSpeed = 0
    clearedTargets = {}
    if teamChoice == 1 and cfg.robberPitsOnly then
        teleportPhase = 1; teleportRetries = 0; return
    end
    if teamChoice == 0 and not cfg.copRandomSpawn and selectedCopSpawn then
        local p = spawnPoints[selectedCopSpawn]
        if p and p.serverIndex ~= nil then teleportTarget = p.serverIndex; teleportPhase = 1; teleportRetries = 5; return end
    end
    local target = pickRandomTarget()
    if target then teleportTarget = target; teleportPhase = 1; teleportRetries = 5; return end
    teleportPhase = 1; teleportRetries = 0
end

local function processTeleport(dt)
    if teleportPhase == 0 then return end
    if teleportPhase == 1 then
        ac.tryToTeleportToPits()
        teleportPhase = 2; teleportTimer = 0
    elseif teleportPhase == 2 then
        teleportTimer = teleportTimer + dt
        if teleportTimer > 0.5 then
            if teleportTarget and ac.canTeleportToServerPoint(teleportTarget) then
                ac.teleportToServerPoint(teleportTarget)
                teleportPhase = 0; teleportTarget = nil
            elseif teleportRetries > 1 then
                teleportRetries = teleportRetries - 1
                if teamChoice ~= 0 or cfg.copRandomSpawn then teleportTarget = pickRandomTarget() end
                teleportTimer = 0
            else
                teleportPhase = 0; teleportTarget = nil
            end
        end
    end
end

-- COP DETECTION --
local function isCop(carId)
    if not carId then return false end
    local lower = carId:lower()
    for _, kw in ipairs(copKeywords) do
        if lower:find(kw, 1, true) then return true end
    end
    return false
end

local function isLineOfSightBlocked(from, target, sim, ignoreA, ignoreB)
    local dir = (target - from):normalize()
    local maxDist = from:distance(target)
    for i = 0, sim.carsCount - 1 do
        if i ~= ignoreA and i ~= ignoreB then
            local car = ac.getCar(i)
            if car and car.isActive and car.isConnected then
                local toCar = car.position - from
                local proj = toCar:dot(dir)
                if proj > 2 and proj < maxDist - 2 then
                    local perp = (toCar - dir * proj):length()
                    if perp < 5 then return true end
                end
            end
        end
    end
    return false
end

-- AUDIO BEEP --
local function initBeep()
    local path = ac.getFolder(ac.FolderID.ACApps) .. "/lua/cops_and_robbers/audio/ka_alert.wav"
    local f = io.open(path, "rb")
    if f then f:close(); return path end
    return nil
end

-- ROBBER RADAR --
local function updateRadar(dt)
    if teamChoice ~= 1 then nearestCopDist = math.huge; return end
    if not radarReady then beepPath = initBeep(); radarReady = true end
    local sim = ac.getSim()
    if not sim then return end
    local player = ac.getCar(playerIndex)
    if not player or not player.isConnected then return end
    if player.speedKmh < 15 then
        nearestCopDist = math.huge; copBehindDist = math.huge
        copProximityTimer = 0; chaseActive = false; chaseSearchPhase = false
        radarLastBeep = 0; if radarBeep then radarBeep:stop(); radarBeep = nil end
        if penaltyActive then penaltyTimer = penaltyTimer + dt end
        return
    end

    if penaltyActive then
        penaltyTimer = penaltyTimer + dt
        local limit = cfg.speedLimit + 5
        if player.speedKmh > limit then
            penaltyViolations = penaltyViolations + dt
            if penaltyViolations >= 10 then
                teleportPlayer()
                penaltyActive = false; penaltyTimer = 0; penaltyViolations = 0; penaltyDuration = 0
            end
        else
            penaltyViolations = 0
        end
        if penaltyTimer >= penaltyDuration then
            penaltyActive = false; penaltyTimer = 0; penaltyViolations = 0; penaltyDuration = 0
        end
    end
    local ppos = player.position
    local plook = player.transform.look
    nearestCopDist = math.huge
    nearestCopDirection = 0
    copBehindDist = math.huge
    for i = 0, sim.carsCount - 1 do
        if i ~= playerIndex then
            local car = ac.getCar(i)
            if car and car.isActive and car.isConnected then
                if isCop(ac.getCarID(i)) then
                    local toCar = car.position - ppos
                    local dist = toCar:length()
                    local dir = toCar:normalize()
                    local dot = plook:dot(dir)
                    if dist < nearestCopDist and dist < radarRange() then nearestCopDist = dist; nearestCopDirection = math.deg(math.atan2(plook.x * dir.z - plook.z * dir.x, dot)) end
                    if dist < radarBehind() and dot < radarBehindDot() and dist < copBehindDist then copBehindDist = dist end
                end
            end
        end
    end

    local curCopSpd = 0
    if nearestCopDist < 1000 then
        for i = 0, sim.carsCount - 1 do
            local car = ac.getCar(i)
            if car and car.isActive and car.isConnected and isCop(ac.getCarID(i)) then
                if car.position:distance(ppos) < nearestCopDist + 1 then
                    curCopSpd = car.speedKmh
                    break
                end
            end
        end
    end

    if copBehindDist < radarBehind() then
        if player.speedKmh >= cfg.speedLimit then copProximityTimer = copProximityTimer + dt
        else copProximityTimer = math.max(0, copProximityTimer - dt * 2) end
    else copProximityTimer = math.max(0, copProximityTimer - dt * 2) end

    if copProximityTimer > cfg.chaseStartSecs and not chaseActive then chaseActive = true; chaseFlashTimer = 4; chaseStartTime = os.preciseClock() end

    if chaseActive then
        if copBehindDist < 68 and player.speedKmh >= cfg.speedLimit then chaseAwayTimer = 0
        else chaseAwayTimer = chaseAwayTimer + dt end
        if chaseAwayTimer > 60 then chaseActive = false; chaseSearchPhase = true; chaseAwayTimer = 0; escapedTextTimer = 5 end
    elseif chaseSearchPhase then
        chaseAwayTimer = chaseAwayTimer + dt
        if chaseAwayTimer > 60 then chaseSearchPhase = false; chaseAwayTimer = 0; copProximityTimer = 0 end
    end

    escapedTextTimer = math.max(0, escapedTextTimer - dt)
    robberPrevSpeed = player.speedKmh
    copPrevSpd = curCopSpd

    if nearestCopDist < radarBeepRange() and beepPath and cfg.radarAudio then
        local interval, pitch
        local br = radarBeepRange()
        if nearestCopDist < br * 0.02 then interval = 0.16; pitch = 1.5
        elseif nearestCopDist < br * 0.15 then interval = 0.36; pitch = 1.3
        elseif nearestCopDist < br * 0.40 then interval = 0.70; pitch = 1.1
        elseif nearestCopDist < br * 0.70 then interval = 1.20; pitch = 0.9
        else interval = 3.00; pitch = 0.7 end
        interval = interval * cfg.chirpSpeed
        pitch = pitch * cfg.chirpTone
        if chaseActive then interval = interval * 0.5; pitch = pitch * 1.3 end
        if not radarBeep or not radarBeep.isValid then radarBeep = ac.AudioEvent.fromFile({filename = beepPath}) end
        if radarBeep then radarBeep.volume = cfg.beepVolume; radarBeep.pitch = pitch; radarBeep:setPosition(ppos, plook) end
        radarLastBeep = radarLastBeep + dt
        if radarLastBeep >= interval and radarBeep then radarLastBeep = 0; radarBeep:stop(); radarBeep:start() end
    else
        radarLastBeep = 0
        if radarBeep then radarBeep:stop(); radarBeep = nil end
    end
end

-- COP SPEED RADAR --
local function updateSpeedRadar(dt)
    if teamChoice ~= 0 then nearestSpeedDist = math.huge; return end
    local sim = ac.getSim()
    if not sim then return end
    local player = ac.getCar(playerIndex)
    if not player or not player.isConnected then return end
    if player.speedKmh < 15 then nearestSpeedDist = math.huge; return end
    local ppos = player.position
    local plook = player.transform.look
    nearestSpeedDist = math.huge
    nearestSpeed = 0

    if copLockButton:pressed() then
        copLockHoldTime = 0
        local bestTime, bestIdx = 0, nil
        for i, t in pairs(speedTracks) do
            if t.speed >= cfg.speedLimit and t.time > bestTime then
                bestTime = t.time; bestIdx = i; copLockHoldName = t.name or ""
            end
        end
        copLockHoldIdx = bestIdx
    end

    if copLockButton:released() then
        copLockHoldTime = 0; copLockHoldIdx = nil; copLockHoldName = ""
    end

    local activeKeys = {}
    for i = 0, sim.carsCount - 1 do
        if i ~= playerIndex then
            local car = ac.getCar(i)
            if car and car.isActive and car.isConnected then
                local cid = ac.getCarID(i)
                if not isCop(cid) and not clearedTargets[i] then
                    local spd = car.speedKmh
                    if spd >= cfg.speedLimit and spd <= 350 then
                        local toCar = car.position - ppos
                        local dist = toCar:length()
                        if dist < cfg.copRadarRange then
                            local dir = toCar:normalize()
                            if plook:dot(dir) > 0.98 then
                                activeKeys[i] = true
                                if not speedTracks[i] then speedTracks[i] = {time = 0, name = ac.getCarName(i) or cid, driver = ac.getDriverName(i) or "", speed = spd, dist = dist}
                                else
                                    speedTracks[i].time = speedTracks[i].time + dt
                                    speedTracks[i].speed = spd
                                    speedTracks[i].dist = dist
                                end
                            end
                        end
                    end
                end
            end
        end
    end

    if copLockHoldIdx and speedTracks[copLockHoldIdx] then
        copLockHoldTime = copLockHoldTime + dt
        if not activeKeys[copLockHoldIdx] then
            copLockHoldTime = 0; copLockHoldIdx = nil; copLockHoldName = ""
        elseif copLockHoldTime >= 4 and not speedTracks[copLockHoldIdx].hardLocked then
            local t = speedTracks[copLockHoldIdx]
            t.hardLocked = true; t.fade = nil; t.searching = nil
            activeNotifications[copLockHoldIdx] = t
        end
        if copLockHoldTime >= 5 then
            copLockHoldTime = 0; copLockHoldIdx = nil; copLockHoldName = ""
        end
    end

    for k, t in pairs(speedTracks) do
        if activeKeys[k] or t.hardLocked then t.fade = nil; t.searching = nil
        elseif not t.fade then t.fade = 0 end
    end
    for k, t in pairs(speedTracks) do
        if t.hardLocked then t.time = t.time + dt end
    end
    for k, t in pairs(speedTracks) do
        if t.fade then
            t.fade = t.fade + dt
            if t.fade > 60 then
                if t.searching then clearedTargets[k] = true; speedTracks[k] = nil; activeNotifications[k] = nil
                else t.searching = true; t.fade = 0 end
            end
        end
    end
    for k, _ in pairs(clearedTargets) do
        local car = ac.getCar(k)
        if not car or not car.isConnected then clearedTargets[k] = nil end
    end
    for k, _ in pairs(speedTracks) do
        local car = ac.getCar(k)
        if not car or not car.isConnected then speedTracks[k] = nil; activeNotifications[k] = nil end
    end

    local hasTargets = next(speedTracks) ~= nil
    if wasTracking and not hasTargets then
        copSearchTimer = 60; copEscapedTimer = 5
    end
    if copSearchTimer > 0 then
        copSearchTimer = copSearchTimer - dt
        copEscapedTimer = math.max(0, copEscapedTimer - dt)
        if copSearchTimer <= 0 then copSearchTimer = 0 end
    end
    wasTracking = hasTargets

    primaryTargetIdx = nil
    local best = math.huge
    for i, t in pairs(activeNotifications) do
        if t.dist < best then best = t.dist; primaryTargetIdx = i end
    end
end

-- UI --
function script.windowMain(dt)
    ui.text("Cops & Robbers By Jp")
    ui.sameLine()
    local hsColor = rgbm(0.4, 0.4, 0.4, 1)
    local hsText = "No signal"
    if teamChoice == 0 then
        if next(activeNotifications) then hsText = "Lock Active"; hsColor = rgbm(1, 0.2, 0, 1)
        elseif next(speedTracks) then hsText = "Scanning"; hsColor = rgbm(0, 1, 0, 1) end
    else
        if chaseActive then hsText = "Chase Active"; hsColor = rgbm(1, 0.3, 0, 1)
        elseif copBehindDist < 50 then hsText = "Targeted"; hsColor = rgbm(1, 0.5, 0, 1)
        elseif copBehindDist < 200 then hsText = "Cop Nearby"; hsColor = rgbm(1, 0.9, 0, 1) end
    end
    ui.textColored("  [" .. hsText .. "]", hsColor)
    ui.separator()
    ui.textColored(teamChoice == 0 and "  COP" or "  ROBBER", teamChoice == 0 and rgbm(0.2, 0.5, 1, 1) or rgbm(1, 0.3, 0, 1))
    ui.sameLine()
    if ui.button(cfg.compactMode and "[+]" or "[-]", 28, 16) then cfg.compactMode = not cfg.compactMode end

    ui.newLine(3)
    ui.textColored(string.format("Cop: %d  |  Robber: %d", copScore, robberScore), rgbm(0.7, 0.7, 0.7, 1))

    if not cfg.compactMode then
        ui.text(string.format("Spawns: %d   Sens: %.0f km/h", #spawnPoints, collisionThreshold))
    end

    if teamChoice == 1 then
        ui.newLine(5)
        ui.text("-- RADAR --")
        ui.sameLine()
        if ui.button(" \226\134\187 ", 20, 18) then
            chaseActive = false; chaseSearchPhase = false; copProximityTimer = 0; chaseAwayTimer = 0
        end
        if nearestCopDist < math.huge then
            local r = radarRange()
            local dc = nearestCopDist < radarTargeted() and rgbm(1, 0, 0, 1) or (nearestCopDist < r * 0.2 and rgbm(1, 0.5, 0, 1) or rgbm(0, 1, 0, 1))
            local strength = math.floor(math.max(0, math.min(9, (r - nearestCopDist) / r * 9 + 1)))
            local bars = string.rep("|", strength) .. string.rep(".", 9 - strength)
            local arrow = nearestCopDirection < -20 and "L" or (nearestCopDirection > 20 and "R" or (nearestCopDist < radarBehind() and "!" or "A"))
            ui.textColored(string.format("Ka %.4f  S%d  %s  %.0fm", 24.125 + nearestCopDist * 0.002, strength, arrow, nearestCopDist), dc)
            ui.textColored(string.format("  [%s]", bars), dc)
        else
            if ac.getCar(playerIndex) and ac.getCar(playerIndex).speedKmh < 15 then
                ui.textColored("Pits  -- GHz", rgbm(0.5, 0.5, 0.2, 1))
            else
                ui.textColored("No signal  -- GHz", rgbm(0.4, 0.4, 0.4, 1))
            end
        end
        ui.newLine(5)
        if chaseActive then
            chaseFlashTimer = math.max(0, chaseFlashTimer - dt)
            local elapsed = os.preciseClock() - chaseStartTime
            local mins = math.floor(elapsed / 60)
            local secs = math.floor(elapsed % 60)
            if chaseFlashTimer > 0 and math.sin(os.preciseClock() * 8) > 0 then
                ui.textColored("** CHASE **", rgbm(1, 0.5, 0, 1))
            elseif copBehindDist < radarBehind() then
                ui.textColored(string.format("CHASE %02d:%02d  %.0fm", mins, secs, copBehindDist), rgbm(1, 0.2, 0, 1))
            else
                ui.textColored(string.format("CHASE %02d:%02d  Esc: %.0fs", mins, secs, 60 - chaseAwayTimer), rgbm(1, 0.4, 0.1, 1))
            end
        elseif chaseSearchPhase then
            if escapedTextTimer > 0 then
                ui.textColored("ESCAPED!", rgbm(0, 1, 0, 1))
            else
                ui.textColored(string.format("Searching... %.0fs", 60 - chaseAwayTimer), rgbm(0.5, 0.5, 0.1, 1))
            end
        elseif copProximityTimer > 4 then
            ui.textColored(string.format("** Lock %.0fs **", copProximityTimer), rgbm(1, 0.4, 0, 1))
        elseif copBehindDist < radarBehind() then
            ui.textColored(string.format("Signal: %.0fm", copBehindDist), rgbm(1, 0.8, 0.1, 1))
        end

        if copBehindDist < radarTargeted() and ac.getCar(playerIndex) and ac.getCar(playerIndex).speedKmh >= cfg.speedLimit then
            ui.textColored("** TARGETED **", rgbm(1, 0, 0, 1))
            lastTargetedAlert = os.preciseClock()
        end

        ui.newLine(5)
        if penaltyActive then
            local limit = cfg.speedLimit + 5
            local left = math.max(0, penaltyDuration - penaltyTimer)
            local spd = ac.getCar(playerIndex) and ac.getCar(playerIndex).speedKmh or 0
            local over = spd > limit
            if over then
                local warnLeft = math.max(0, 10 - penaltyViolations)
                ui.textColored(string.format("SLOW DOWN! Pits in %.0fs", warnLeft), rgbm(1, 0, 0, 1))
                ui.textColored(string.format("PENALTY: %.0fs left  < %d km/h", left, limit), rgbm(1, 0.5, 0, 1))
            else
                ui.textColored(string.format("PENALTY: %.0fs left  < %d km/h", left, limit), rgbm(0, 1, 0, 1))
            end
        else
            ui.textColored("Use Penalty Panel window", rgbm(0.4, 0.4, 0.4, 1))
        end
    else
        ui.newLine(5)
        ui.text("-- RADAR GUN --")
        ui.sameLine()
        if ui.button(" \226\134\187 ", 20, 18) then
            speedTracks = {}; activeNotifications = {}; clearedTargets = {}; primaryTargetIdx = nil
        end
        local scanning = 0
        local bestTime, bestDist, bestSpd = 0, math.huge, 0
        for _, t in pairs(speedTracks) do
            if t.time > 0 then scanning = scanning + 1 end
            if t.time > bestTime then bestTime = t.time; bestDist = t.dist; bestSpd = t.speed end
        end
        if scanning > 0 then
            local signal = math.min(9, math.floor(bestTime * 1.5))
            local bars = string.rep("|", signal) .. string.rep(".", 9 - signal)
            if copLockHoldTime > 0 and copLockHoldName ~= "" then
                if copLockHoldTime < 4 then
                    ui.textColored(string.format("Aim: %s  %.1fs", copLockHoldName, copLockHoldTime), rgbm(0, 1, 0, 1))
                else
                    ui.textColored(string.format("LOCK %s  %.1fs", copLockHoldName, copLockHoldTime), rgbm(1, 0.1, 0, 1))
                end
                ui.textColored(string.format("  %.0f km/h  %.0fm", bestSpd, bestDist), rgbm(1, 0.5, 0, 1))
            else
                ui.textColored(string.format("Aim: %.0f km/h  %.0fm", bestSpd, bestDist), rgbm(0, 1, 0, 1))
            end
            ui.textColored(string.format("  S%d  [%s]", signal, bars), rgbm(0, 1, 0.3, 1))
            ui.textColored("Hold key to lock", rgbm(0.35, 0.35, 0.35, 1))
        else
            if copSearchTimer > 0 then
                if copEscapedTimer > 0 then
                    ui.textColored("ESCAPED!", rgbm(0, 1, 0, 1))
                else
                    ui.textColored(string.format("Searching... %.0fs", copSearchTimer), rgbm(0.5, 0.5, 0.1, 1))
                end
            elseif ac.getCar(playerIndex) and ac.getCar(playerIndex).speedKmh < 15 then
                ui.textColored("Pits  -- GHz", rgbm(0.5, 0.5, 0.2, 1))
            else
                ui.textColored("Scanning...  -- GHz", rgbm(0.4, 0.4, 0.4, 1))
            end
        end
        local notified = 0
        for _ in pairs(activeNotifications) do notified = notified + 1 end
        if notified > 0 then
            ui.separator()
            local toRemove = {}
            for i, t in pairs(activeNotifications) do
                local lockMins = math.floor(t.time / 60); local lockSecs = math.floor(t.time % 60)
                ui.textColored(string.format("%.0f km/h  %.0fm  [%02d:%02d]  %s", t.speed, t.dist, lockMins, lockSecs, t.name or ""), rgbm(1, 0.15, 0, 1))
                if t.driver and t.driver ~= "" then ui.text(string.format("  %s", t.driver)) end
                if ui.button("Clear##" .. i, 48, 18) then table.insert(toRemove, i) end
            end
            for _, i in ipairs(toRemove) do clearedTargets[i] = true; activeNotifications[i] = nil; speedTracks[i] = nil end
        end
    end

    if teamChoice == 0 and not cfg.copRandomSpawn then
        local sp = spawnPoints[selectedCopSpawn or 1]
        ui.text("Spawn: " .. (sp and sp.name or "None"))
    end
    if cooldown > 0 then ui.text(string.format("Cooldown: %.1fs", cooldown)) end
end

function script.windowSettings()
    if ui.button(active and "[X] Enabled" or "[ ] Enabled", 100, 20) then active = not active end
    ui.separator()
    ui.text("Team:")
    if ui.button("Switch to " .. (teamChoice == 0 and "Robber" or "Cop"), 110, 20) then teamChoice = teamChoice == 0 and 1 or 0; copScore = 0; robberScore = 0; lastWreckTime = 0 end
    ui.separator()
    ui.text("Scores:")
    ui.text(string.format("Cop: %d  |  Robber: %d", copScore, robberScore))
    ui.text("Cop:"); ui.sameLine()
    if ui.button("-##cops", 18, 20) then copScore = math.max(0, copScore - 1) end
    ui.sameLine()
    if ui.button("+##cops", 18, 20) then copScore = copScore + 1 end
    ui.sameLine()
    ui.text(" Robber:"); ui.sameLine()
    if ui.button("-##robs", 18, 20) then robberScore = math.max(0, robberScore - 1) end
    ui.sameLine()
    if ui.button("+##robs", 18, 20) then robberScore = robberScore + 1 end
    if ui.button("Reset Scores", 80, 20) then copScore = 0; robberScore = 0; lastWreckTime = 0 end
    ui.separator()
    if ui.button(cfg.hitWalls and "[X] Wall collisions" or "[ ] Wall collisions", 110, 20) then cfg.hitWalls = not cfg.hitWalls end
    if ui.button(cfg.hitCars and "[X] Car collisions" or "[ ] Car collisions", 110, 20) then cfg.hitCars = not cfg.hitCars end
    ui.separator()
    ui.text("Sensitivity: " .. tostring(collisionThreshold) .. " km/h")
    if ui.button("-", 18, 20) then collisionThreshold = math.max(3, collisionThreshold - 1) end
    ui.sameLine()
    if ui.button("+", 18, 20) then collisionThreshold = math.min(50, collisionThreshold + 1) end
    ui.text("Range: " .. tostring(proximityCheck) .. "m")
    if ui.button("-##prox", 18, 20) then proximityCheck = math.max(2, proximityCheck - 1) end
    ui.sameLine()
    if ui.button("+##prox", 18, 20) then proximityCheck = math.min(15, proximityCheck + 1) end
    ui.text("Min speed: " .. tostring(minSpeedCheck) .. " km/h")
    if ui.button("-##min", 18, 20) then minSpeedCheck = math.max(0, minSpeedCheck - 1) end
    ui.sameLine()
    if ui.button("+##min", 18, 20) then minSpeedCheck = math.min(30, minSpeedCheck + 1) end
    ui.text("Cooldown: " .. tostring(cooldownDuration) .. "s")
    if ui.button("-##cd", 18, 20) then cooldownDuration = math.max(3, cooldownDuration - 1) end
    ui.sameLine()
    if ui.button("+##cd", 18, 20) then cooldownDuration = math.min(30, cooldownDuration + 1) end
    ui.separator()
    ui.text("Robber Radar:")
    if ui.button(cfg.radarAudio and "[X] Beep" or "[ ] Beep", 80, 20) then cfg.radarAudio = not cfg.radarAudio end
    ui.sameLine()
    ui.text("Vol: " .. string.format("%.1f", cfg.beepVolume))
    if ui.button("-##rv", 18, 20) then cfg.beepVolume = math.max(0.1, cfg.beepVolume - 0.1) end
    ui.sameLine()
    if ui.button("+##rv", 18, 20) then cfg.beepVolume = math.min(2.0, cfg.beepVolume + 0.1) end
    ui.text("Chirp: " .. string.format("%.1fx", cfg.chirpSpeed))
    if ui.button("-##ch", 18, 20) then cfg.chirpSpeed = math.max(0.1, cfg.chirpSpeed - 0.1) end
    ui.sameLine()
    if ui.button("+##ch", 18, 20) then cfg.chirpSpeed = math.min(3.0, cfg.chirpSpeed + 0.1) end
    ui.text("Tone: " .. string.format("%.1fx", cfg.chirpTone))
    if ui.button("-##ct", 18, 20) then cfg.chirpTone = math.max(0.3, cfg.chirpTone - 0.1) end
    ui.sameLine()
    if ui.button("+##ct", 18, 20) then cfg.chirpTone = math.min(3.0, cfg.chirpTone + 0.1) end
    ui.text("Chase start: " .. tostring(cfg.chaseStartSecs) .. "s")
    if ui.button("-##chase", 18, 20) then cfg.chaseStartSecs = math.max(10, cfg.chaseStartSecs - 10) end
    ui.sameLine()
    if ui.button("+##chase", 18, 20) then cfg.chaseStartSecs = math.min(120, cfg.chaseStartSecs + 10) end
    ui.text("Radar detector:")
    local presetLabel = ({ "Poor (750m)", "Decent (1000m)", "Good (1500m)" })[cfg.radarPreset]
    if ui.button(presetLabel, 140, 20) then cfg.radarPreset = cfg.radarPreset % 3 + 1 end
    ui.text("Mute keybind:")
    robberMuteButton:control()
    ui.text("Penalty: use Penalty Panel")
    ui.separator()
    ui.text("Cop Radar:")
    ui.text("Speed limit: " .. tostring(cfg.speedLimit) .. " km/h")
    if ui.button("-##lim", 18, 20) then cfg.speedLimit = math.max(30, cfg.speedLimit - 10) end
    ui.sameLine()
    if ui.button("+##lim", 18, 20) then cfg.speedLimit = math.min(300, cfg.speedLimit + 10) end
    ui.text("Radar range: " .. tostring(cfg.copRadarRange) .. "m")
    if ui.button("-##rr", 18, 20) then cfg.copRadarRange = math.max(25, cfg.copRadarRange - 5) end
    ui.sameLine()
    if ui.button("+##rr", 18, 20) then cfg.copRadarRange = math.min(200, cfg.copRadarRange + 5) end
    ui.text("Lock target keybind:")
    copLockButton:control()
    ui.separator()
    ui.text("Robber Spawn:")
    if ui.button(cfg.robberPitsOnly and "[X] Pits only" or "[ ] Pits only", 80, 20) then cfg.robberPitsOnly = not cfg.robberPitsOnly end
    ui.separator()
    ui.text("Cop Spawn:")
    if ui.button(cfg.copRandomSpawn and "[X] Random" or "[ ] Random", 80, 20) then cfg.copRandomSpawn = not cfg.copRandomSpawn end
    if not cfg.copRandomSpawn and teamChoice == 0 then
        for i, p in ipairs(spawnPoints) do
            if ui.button((i == selectedCopSpawn and "> " or "  ") .. (p.name or "Spawn " .. i), 180, 18) then selectedCopSpawn = i end
        end
    end
end

local charges = {
    {"Speeding", 150, 800},
    {"Reckless Driving", 500, 2500},
    {"Street Racing", 1000, 5000},
    {"Evading Police", 2500, 10000},
    {"Failure to Yield", 200, 600},
    {"Running Red Light", 250, 750},
    {"Illegal Lane Change", 150, 400},
    {"Exhibition of Speed", 500, 2000},
    {"Hit and Run", 2000, 8000},
    {"No Valid License", 500, 1500},
}

local ticketCopied = ""
local ticketStatus = ""
local cachedCharges = {}
local cachedTarget = ""

ffi.cdef[[
    int OpenClipboard(void*);
    int EmptyClipboard();
    void* GlobalAlloc(int, size_t);
    void* GlobalLock(void*);
    int GlobalUnlock(void*);
    void* SetClipboardData(int, void*);
    int CloseClipboard();
    void* memcpy(void*, const void*, size_t);
]]

local function copyToClipboard(text)
    local CF_TEXT = 1
    local GMEM_MOVEABLE = 2
    local ok = false
    for _ = 1, 10 do
        if ffi.C.OpenClipboard(nil) ~= 0 then
            ffi.C.EmptyClipboard()
            local len = #text + 1
            local hMem = ffi.C.GlobalAlloc(GMEM_MOVEABLE, len)
            if hMem ~= nil then
                local pMem = ffi.C.GlobalLock(hMem)
                if pMem ~= nil then
                    ffi.C.memcpy(pMem, text, len)
                    ffi.C.GlobalUnlock(hMem)
                end
                if ffi.C.SetClipboardData(CF_TEXT, hMem) ~= nil then ok = true end
            end
            ffi.C.CloseClipboard()
            break
        end
        os.sleep(0.01)
    end
    return ok
end

function script.ticketWindow()
    ui.text("Ticket Panel")
    ui.separator()
    if teamChoice ~= 0 then ui.text("Switch to Cop to use"); return end
    local hasLocked = false
    local targetName = ""
    for _, t in pairs(activeNotifications) do
        hasLocked = true; targetName = t.driver or t.name or "Player"; break
    end
    if not hasLocked then cachedTarget = ""; ui.textColored("No target locked", rgbm(0.4, 0.4, 0.4, 1)); return end
    if targetName ~= cachedTarget then
        cachedTarget = targetName; cachedCharges = {}
        for _, c in ipairs(charges) do
            local fine = math.random(c[2], c[3])
            local code = string.format("%02d-%03d", math.random(10, 99), math.random(100, 999))
            local ticket = string.format("[TICKET] %s -- %s | $%d | Code: %s", targetName, c[1], fine, code)
            table.insert(cachedCharges, {label = string.format("%s  - $%d", c[1], fine), ticket = ticket})
        end
    end
    ui.text(string.format("Target: %s", targetName))
    ui.separator()
    for _, ch in ipairs(cachedCharges) do
        if ui.button(ch.label, 220, 18) then
            ticketCopied = ch.ticket
            local ok = copyToClipboard(ch.ticket)
            ticketStatus = ok and "Copied! Ctrl+V to paste" or "View ticket below"
        end
    end
    if ticketCopied ~= "" then
        ui.separator()
        ui.textColored("TICKET:", rgbm(1, 0.8, 0, 1))
        ui.textWrapped(ticketCopied)
    end
end

function script.radarMini()
    if teamChoice == 1 then
        if nearestCopDist < math.huge then
            local strength = math.floor(math.max(0, math.min(9, (radarRange() - nearestCopDist) / radarRange() * 9 + 1)))
            local bars = string.rep("|", strength) .. string.rep(".", 9 - strength)
            local dc = nearestCopDist < radarTargeted() and rgbm(1, 0, 0, 1) or rgbm(0, 1, 0, 1)
            ui.textColored(string.format("S%d %.0fm %s", strength, nearestCopDist, bars), dc)
            if chaseActive then
                local elapsed = os.preciseClock() - chaseStartTime
                ui.textColored(string.format("CHASE %02d:%02d", math.floor(elapsed/60), math.floor(elapsed%60)), rgbm(1, 0.3, 0, 1))
            elseif chaseSearchPhase then
                if escapedTextTimer > 0 then ui.textColored("ESCAPED!", rgbm(0, 1, 0, 1))
                else ui.textColored(string.format("Search %.0fs", 60-chaseAwayTimer), rgbm(0.5, 0.5, 0.1, 1)) end
            elseif copBehindDist < radarBehind() then
                ui.textColored(string.format("Lock %.0fs", copProximityTimer), rgbm(1, 0.6, 0, 1))
            end
        else
            ui.textColored("-- GHz", rgbm(0.4, 0.4, 0.4, 1))
        end
    else
        local scanning = 0
        local bestSpd, bestDist = 0, math.huge
        for _, t in pairs(speedTracks) do
            if t.time > 0 then scanning = scanning + 1 end
            if t.time > 0 and t.dist < bestDist then bestSpd = t.speed; bestDist = t.dist end
        end
        if scanning > 0 then
            ui.textColored(string.format("%.0f km/h  %.0fm", bestSpd, bestDist), rgbm(0, 1, 0.3, 1))
            local locked = 0; for _ in pairs(activeNotifications) do locked = locked + 1 end
            if locked > 0 then ui.textColored(string.format("%d locked %d tracking", locked, scanning), rgbm(1, 0.2, 0, 1)) end
        else
            if copSearchTimer > 0 then
                if copEscapedTimer > 0 then
                    ui.textColored("ESCAPED!", rgbm(0, 1, 0, 1))
                else
                    ui.textColored(string.format("Search %.0fs", copSearchTimer), rgbm(0.5, 0.5, 0.1, 1))
                end
            else
                ui.textColored("-- GHz", rgbm(0.4, 0.4, 0.4, 1))
            end
        end
    end
end

local penalties = {
    {"Speeding", 60},
    {"Reckless Driving", 120},
    {"Street Racing", 180},
    {"Evading Police", 240},
    {"Failure to Yield", 60},
    {"Running Red Light", 90},
    {"Illegal Lane Change", 45},
    {"Exhibition of Speed", 120},
    {"Hit and Run", 300},
    {"No Valid License", 150},
}

function script.penaltyWindow()
    ui.text("Penalty Panel")
    ui.separator()
    if teamChoice ~= 1 then ui.text("Switch to Robber to use"); return end
    if penaltyActive then
        local left = math.max(0, penaltyDuration - penaltyTimer)
        local mins = math.floor(left / 60)
        local secs = math.floor(left % 60)
        ui.textColored(string.format("Active: %02d:%02d remaining", mins, secs), rgbm(1, 0.5, 0, 1))
        ui.text(string.format("Stay under %d km/h", cfg.speedLimit + 5))
        if ui.button("Clear Penalty", 120, 20) then
            penaltyActive = false; penaltyTimer = 0; penaltyViolations = 0; penaltyDuration = 0
        end
        local spd = ac.getCar(playerIndex) and ac.getCar(playerIndex).speedKmh or 0
        if spd > cfg.speedLimit + 5 then
            ui.textColored(string.format("Pits in %.0fs!", math.max(0, 10 - penaltyViolations)), rgbm(1, 0, 0, 1))
        end
        return
    end
    for _, p in ipairs(penalties) do
        local mins = math.floor(p[2] / 60)
        local secs = p[2] % 60
        local label
        if secs > 0 then label = string.format("%s (%d:%02d)", p[1], mins, secs)
        else label = string.format("%s (%d min)", p[1], mins) end
        if ui.button(label, 220, 18) then
            penaltyActive = true; penaltyTimer = 0; penaltyViolations = 0; penaltyDuration = p[2]
        end
    end
end

function script.update(dt)
    if not active then return end

    local muteDown = robberMuteButton:pressed()
    if muteDown and not muteWasDown then
        cfg.radarAudio = not cfg.radarAudio
        if not cfg.radarAudio and radarBeep then radarBeep:stop(); radarBeep = nil; radarLastBeep = 0 end
    end
    muteWasDown = muteDown

    updateRadar(dt)
    updateSpeedRadar(dt)
    if not spawnsLoaded then loadSpawnPoints() end
    reloadTimer = reloadTimer + dt
    if reloadTimer > 2 and #spawnPoints == 0 then reloadTimer = 0; spawnsLoaded = false end
    if teleportPhase > 0 then processTeleport(dt); cooldown = cooldown - dt; return end
    if cooldown > 0 then cooldown = cooldown - dt; if cooldown <= 0 then prevSpeed = 0 end; return end
    local sim = ac.getSim()
    if not sim then return end
    local car = ac.getCar(playerIndex)
    if not car or not car.isConnected or not car.isActive then return end
    local speed = car.speedKmh
    if speed < minSpeedCheck then prevSpeed = speed; return end
    local speedChange = speed - prevSpeed
    prevSpeed = speed
    if speedChange > -collisionThreshold then return end
    for i = 1, sim.carsCount - 1 do
        local other = ac.getCar(i)
        if other and other.isActive and other.isConnected then
            if cfg.hitCars and car.position:distance(other.position) < proximityCheck then teleportPlayer(); cooldown = cooldownDuration; return end
        end
    end
    if cfg.hitWalls then teleportPlayer(); cooldown = cooldownDuration end
end
