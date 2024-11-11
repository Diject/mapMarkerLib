local objectCache = include("diject.map_markers.objectCache")
local activeCells = include("diject.map_markers.activeCells")
local markerLib = include("diject.map_markers.marker")
local interop = include("diject.map_markers.interop")
local log = include("diject.map_markers.utils.log")

--- @param e loadedEventData
local function loadedCallback(e)
    if not markerLib.isReady() then
        markerLib.init()
    end
end
event.register(tes3.event.loaded, loadedCallback, {priority = 99999})

--- @param e loadEventData
local function loadCallback(e)
    markerLib.reset()
end
event.register(tes3.event.load, loadCallback)

--- @param e saveEventData
local function saveCallback(e)
    markerLib.save()
end
event.register(tes3.event.save, saveCallback)

--- @param e uiActivatedEventData
local function menuMapActivated(e)
    if not markerLib.isReady() then
        markerLib.init()
        markerLib.registerWorld()
    end

    local menu = e.element
    local worldMap = menu:findChild("MenuMap_world")
    if not worldMap then return end
    local worldPane = worldMap:findChild("MenuMap_world_pane")
    if not worldPane then return end
    local localMap = menu:findChild("MenuMap_local")
    if not localMap then return end
    local localPane = localMap:findChild("MenuMap_pane")
    if not localPane then return end
    local playerMarker = localPane:findChild("MenuMap_local_player")
    if not playerMarker then return end

    e.element:getTopLevelMenu():register(tes3.uiEvent.preUpdate, function (e1)
        if localMap.visible then
            markerLib.activeMenu = "MenuMapLocal"
            markerLib.createLocalMarkers()
            markerLib.updateLocalMarkers()
        elseif worldMap.visible then
            markerLib.activeMenu = "MenuMapWorld"
            markerLib.createWorldMarkers()
            markerLib.updateWorldMarkers()
        end
        markerLib.removeDeletedMarkers()
    end)

    e.element:updateLayout()
end

event.register(tes3.event.uiActivated, menuMapActivated, {filter = "MenuMap"})

--- @param e simulatedEventData
local function simulatedCallback(e)
    if os.clock() - markerLib.lastLocalUpdate > markerLib.updateInterval then
        local menu = tes3ui.findMenu("MenuMap")
        if not menu then
            markerLib.lastLocalUpdate = os.clock()
            return
        end
        if menu.visible then
            menu:updateLayout()
        else
            markerLib.activeMenu = "MenuMulti"
            markerLib.createLocalMarkers()
            markerLib.updateLocalMarkers()
            markerLib.removeDeletedMarkers()
        end
    end
end
event.register(tes3.event.simulated, simulatedCallback)



--- @param e referenceActivatedEventData
local function referenceActivatedCallback(e)
    objectCache.addRef(e.reference)
    markerLib.tryAddMarkersForRef(e.reference)
end
event.register(tes3.event.referenceActivated, referenceActivatedCallback)

--- @param e referenceDeactivatedEventData
local function referenceDeactivatedCallback(e)
    objectCache.removeRef(e.reference)
end
event.register(tes3.event.referenceDeactivated, referenceDeactivatedCallback)


--- @param e cellActivatedEventData
local function cellActivatedCallback(e)
    if not markerLib.isReady() then
        markerLib.init()
    end
    activeCells.registerCell(e.cell)
    markerLib.registerMarkersForCell(e.cell.editorName)
end
event.register(tes3.event.cellActivated, cellActivatedCallback)

--- @param e cellDeactivatedEventData
local function cellDeactivatedCallback(e)
    activeCells.unregisterCell(e.cell)
end
event.register(tes3.event.cellDeactivated, cellDeactivatedCallback)

--- @param e cellChangedEventData
local function cellChangedCallback(e)
    markerLib.registerMarkersForCell()
end
event.register(tes3.event.cellChanged, cellChangedCallback)