local markerLib = include("diject.map_markers.marker")
local log = include("diject.map_markers.utils.log")

--- @param e loadedEventData
local function loadedCallback(e)
    markerLib.init()
end
event.register(tes3.event.loaded, loadedCallback, {priority = 99999})

--- @param e loadEventData
local function loadCallback(e)
    markerLib.reset()
end
event.register(tes3.event.load, loadCallback)

--- @param e uiActivatedEventData
local function uiActMap(e)
    if not markerLib.isReady() then
        markerLib.init()
    end

    e.element:getTopLevelMenu():register(tes3.uiEvent.preUpdate, function (e1)
        markerLib.drawLocaLMarkers()
        markerLib.drawWorldMarkers()
    end)

    markerLib.drawLocaLMarkers(true)
    markerLib.drawWorldMarkers(true)
    e.element:updateLayout()
end

event.register(tes3.event.uiActivated, uiActMap, {filter = "MenuMap"})

--- @param e simulatedEventData
local function simulatedCallback(e)
    if markerLib.hasFloatMarkers and os.clock() - markerLib.lastLocalUpdate > 0.05 then
        markerLib.drawLocaLMarkers(false, true)
    end
end
event.register(tes3.event.simulated, simulatedCallback)



--- @param e referenceActivatedEventData
local function referenceActivatedCallback(e)
    local ref = e.reference
    if not ref or ref.disabled or ref.object.objectType == tes3.objectType.static or not ref.cell then return end

    if not markerLib.isReady() then
        markerLib.init()
    end

    local cellName = ref.cell.editorName:lower()

    markerLib.cacheDataOfTrackingObjects()
    markerLib.cacheDataOfTrackingObjects(cellName)

    local function addMarker(objData)
        if not objData then return end
        for markerId, data in pairs(objData) do
            markerLib.addFloatingLocal{ id = data.id, ref = ref }
        end
    end

    local objData = markerLib.cachedFloatMarkerData[ref.baseObject.id:lower()]
    addMarker(objData)
    objData = markerLib.cachedFloatMarkerData[ref]
    addMarker(objData)
end
event.register(tes3.event.referenceActivated, referenceActivatedCallback)

--- @param e referenceDeactivatedEventData
local function referenceDeactivatedCallback(e)
    local ref = e.reference
    if not ref then return end

    markerLib.cachedFloatMarkerData[ref] = nil
    markerLib.cachedFloatMarkerData[ref.baseObject.id:lower()] = nil
end
event.register(tes3.event.referenceDeactivated, referenceDeactivatedCallback)


-- local markerPos
-- local marker

-- local function myOnKeyCallback(e)
--     if not markerPos then
--         markerPos = tes3.player.position:copy()
--         return
--     end
--     local camera = tes3.getCamera()
--     -- local camVec = tes3.getCameraVector()
--     local camVec = camera.worldDirection
--     local camPos = tes3.getCameraPosition()
--     local pointPos = camera:worldPointToScreenPoint(markerPos)

--     local function calc(v)
--         local vec = v - camPos
--         local dist = vec.x * camVec.x + vec.y * camVec.y + vec.z + camVec.z
--         local vres = v - camVec * dist

--         return vres
--     end
--     local vres = calc(markerPos)

--     local screenP = camera:windowPointToRay{-1, 0}

--     log(
--         math.floor(camVec:angle(vres) / (math.pi / 180)),
--         math.floor(camVec:angle(calc(screenP) - camPos) / (math.pi / 180)),
--         math.floor((camPos - vres):angle(camPos - calc(screenP)) / (math.pi / 180))
--     )

--     if not pointPos then
--         -- local playerPos = tes3.player.position
--         -- local vec1 = tes3vector3.new(playerPos.x - markerPos.x, playerPos.y - markerPos.y, playerPos.y - markerPos.y)
--         -- local vec2 = tes3vector3.new(0,0,0)
--         -- local angle = vec2:angle(vec1) / (math.pi / 180)
--         return
--     end
--     local menu = tes3ui.findMenu("MenuMulti")
--     local pane = menu:findChild("PartNonDragMenu_main")
--     if not marker then

--         marker = pane:createBlock{}
--         marker.autoHeight = true
--         marker.autoWidth = true
--         marker:createImage{path = "textures\\diject\\quest guider\\circleMarker8.dds"}
--     end
--     -- log((pane.width / 2 + pointPos.x) / pane.width, (pane.height - (pane.height / 2 + pointPos.y)) / pane.height)
--     marker.absolutePosAlignX = (pane.width / 2 + pointPos.x) / pane.width
--     marker.absolutePosAlignY = (pane.height - (pane.height / 2 + pointPos.y)) / pane.height
--     marker:getTopLevelMenu():updateLayout()
-- end

-- event.register(tes3.event.keyDown, myOnKeyCallback, { filter = tes3.scanCode.y } )

local function myOnKeyCallback(e)
    local recordId = markerLib.addRecord(nil, {path = "diject\\quest guider\\circleMarker8.dds"})
    local res, cell = markerLib.addLocal{
        id = recordId,
        -- x = tes3.player.position.x,
        -- y = tes3.player.position.y,
        -- trackedRef = tes3.player,
        objectId = "hlaalu guard_outside"
    }
    -- local res, cell = markerLib.addLocal{
    --     id = recordId,
    --     x = tes3.player.position.x,
    --     y = tes3.player.position.y,
    --     z = tes3.player.position.z,
    --     -- trackedRef = tes3.player,
    --     -- objectId = "hlaalu guard_outside"
    -- }
    -- cellActivatedCallback({cell = tes3.player.cell})
    markerLib.drawLocaLMarkers(true)
end

event.register(tes3.event.keyDown, myOnKeyCallback, { filter = tes3.scanCode.y } )