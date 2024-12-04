local objectCache = include("diject.map_markers.objectCache")
local activeCells = include("diject.map_markers.activeCells")
local log = include("diject.map_markers.utils.log").log

local storageName = "markers_byDiject"

local markerLabelId = "MarkerLib_Marker"
local tooltipBlock = "MarkerLib_Tooltip_Block"
local tooltipName = "MarkerLib_Tooltip_Name"
local tooltipDescription = "MarkerLib_Tooltip_Description"

local mcp_mapExpansion = tes3.hasCodePatchFeature(tes3.codePatchFeature.mapExpansionForTamrielRebuilt)
local minCellGridX = mcp_mapExpansion and -51 or -28
local minCellGridY = mcp_mapExpansion and -64 or -28
local maxCellGridX = mcp_mapExpansion and 51 or 28
local maxCellGridY = mcp_mapExpansion and 38 or 28

local worldBounds = {
    minX = minCellGridX,
    maxX = maxCellGridX,
    minY = minCellGridY,
    maxY = maxCellGridY,
    cellResolution = mcp_mapExpansion and 5 or 9,
}

local positionDifferenceToUpdate = 16


local allMapLabelName = "__all_map__"

local this = {}

this.activeMenu = nil

this.shouldAddLocal = false
this.shouldAddWorld = false

this.shouldUpdateWorld = false

this.minDelayBetweenUpdates = 0.01 -- only for MenuMulti
this.updateInterval = 0.10
this.lastLocalUpdate = 0
this.lastWorldUpdate = 0

this.zDifference = 256

local storageData

local lastLocalPaneWidth
local lastLocalPaneHeight
local lastPlayerMarkerTileX
local lastPlayerMarkerTileY

local axisAngle = 0
local axisAngleSin = 0
local axisAngleCos = 0
local interior0PointPositionX = 0
local interior0PointPositionY = 0
local lastCell = nil
local lastActiveMenu = nil
---@type table<string, markerLib.markerContainer>
local localMarkerPositionMap = {}

local lastWorldPaneWidth = 0
local lastWorldPaneHeight = 0
---@type table<string, markerLib.markerContainer>
local worldMarkerPositionMap = {}

local last0XCoord = 0
local last0YCoord = 0
local menu00CoordinateSteadyCounter = 0
local is00CoordinateSteady = false

local last0GridX = 0
local last0GridY = 0


---@class markerLib.activeWorldMarkerContainer
---@field id string
---@field record markerLib.markerRecord
---@field marker tes3uiElement
---@field position {x : number, y : number}

---@class markerLib.activeLocalMarkerElement
---@field id string
---@field record markerLib.markerRecord
---@field markerData markerLib.markerData
---@field priority number|nil
---@field itemId string|nil should be lowercase
---@field conditionFunc (fun(data: markerLib.activeLocalMarkerElement):boolean)|nil

---@class markerLib.markerContainer
---@field items table<string, markerLib.activeLocalMarkerElement> by record id
---@field marker tes3uiElement?
---@field markerData markerLib.markerData|nil for object id trackers
---@field ref mwseSafeObjectHandle|nil
---@field objectId string|nil
---@field position tes3vector3|{x : number, y : number, z : number|nil} last position when the marker was redrawn
---@field lastZDiff number|nil difference in z coordinate between player and the object
---@field cell tes3cell|nil
---@field offscreen boolean|nil
---@field shouldUpdate boolean|nil

---@type table<string|tes3reference, markerLib.markerContainer> by id
this.activeLocalMarkers = {}

---@type table<string, markerLib.markerContainer> by id
this.activeWorldMarkers = {}

---@type table<string, markerLib.markerData> by marker id
this.waitingToCreate_local = {}

---@type table<string, markerLib.markerData> by marker id
this.waitingToCreate_world = {}

---@type table<string, boolean> by marker id
this.markersToRemove = {}

---@type table<tes3uiElement, boolean>
this.markerElementsToDelete = {}


---@type table<string, table<string, markerLib.markerData>>
this.localMap = nil
---@type table<string, table<string, markerLib.markerRecord>>
this.records = nil
---@type table<string, markerLib.markerData>
this.world = nil

this.worldBounds = worldBounds

---@class markerLib.recordOOP
---@

---@class markerLib.markerData
---@field recordId string recordId
---@field position tes3vector3|{x : number, y : number, z : number}
---@field id string
---@field cellId string
---@field cellName string|nil should be nil if the cell is exterior
---@field objectId string|nil should be lowercase
---@field itemId string|nil should be lowercase
---@field conditionFunc (fun(data: markerLib.activeLocalMarkerElement):boolean)|nil
---@field temporary boolean|nil
---@field trackedRef mwseSafeObjectHandle|nil
---@field offscreen boolean|nil
---@field shortTerm boolean|nil if true, the marker will be deleted after the cell has changed

---@class markerLib.markerRecord
---@field id string|nil
---@field path string texture path relative to Data Files\Textures
---@field pathAbove string|nil texture path relative to Data Files\Textures
---@field pathBelow string|nil texture path relative to Data Files\Textures
---@field width integer|nil texture width
---@field height integer|nil texture height
---@field textureShiftX integer|nil
---@field textureShiftY integer|nil
---@field scale number|nil
---@field priority number|nil
---@field name string|nil
---@field description string|nil
---@field color number[]|nil {r, g, b} [0, 1]
---@field temporary boolean|nil

local function getId()
    local id = string.format("%.0f", storageData.id)
    storageData.id = storageData.id + 1
    return id
end

function this.init()
    local player = tes3.player
    if not player.data[storageName] then
        player.data[storageName] = {map = {}, world = {}, records = {}, id = 0}
    end
    storageData = player.data[storageName]
    this.localMap = table.deepcopy(storageData.map)
    this.records = storageData.records
    this.world = storageData.world

    for id, record in pairs(this.records) do
        if record.temporary then
            this.markersToRemove[id] = true
            this.records[id] = nil
        end
    end

    local uiexpCommon = include("UI Expansion.common")
    if uiexpCommon and uiexpCommon.config and uiexpCommon.config.components and
            uiexpCommon.config.components.mapPlugin and uiexpCommon.config.mapConfig then
        this.worldBounds = uiexpCommon.config.mapConfig
    else
        this.worldBounds = worldBounds
    end
end

---@class markerLib.menus
---@field menuMap tes3uiElement?
---@field localMap tes3uiElement?
---@field localPanel tes3uiElement?
---@field localPane tes3uiElement?
---@field localMapPane tes3uiElement?
---@field localPlayerMarker tes3uiElement?
---@field worldMap tes3uiElement?
---@field worldPane tes3uiElement?
---@field multiMap tes3uiElement?
---@field multiPanel tes3uiElement?
---@field multiPane tes3uiElement?
---@field multiPlayerMarker tes3uiElement?
---@field multiMapLayout tes3uiElement?
---@field multiMapPane tes3uiElement?
---@field uiExpZoomBar tes3uiElement?

---@type markerLib.menus
this.menu = {}
this.isMapMenuInitialized = false
this.isMultiMenuInitialized = false

---@param menu tes3uiElement
function this.initMapMenuInfo(menu)
    this.isMapMenuInitialized = false
    if not menu then return end

    local menuData = this.menu

    menuData.menuMap = menu

    menuData.localMap = menu:findChild("MenuMap_local")
    if not menuData.localMap then return end
    menuData.localPanel = menuData.localMap:findChild("MenuMap_panel")
    if not menuData.localPanel then return end
    menuData.localPane = menuData.localPanel:findChild("MenuMap_pane")
    if not menuData.localPane then return end
    menuData.localMapPane = menuData.localPanel:findChild("MenuMap_map_pane")
    if not menuData.localMapPane then return end
    menuData.localPlayerMarker = menuData.localPane:findChild("MenuMap_local_player")
    if not menuData.localPlayerMarker then return end

    menuData.worldMap = menu:findChild("MenuMap_world")
    if not menuData.worldMap then return end
    menuData.worldPane = menuData.worldMap:findChild("MenuMap_world_pane")
    if not menuData.worldPane then return end

    if menu.visible then
        if menuData.localMap.visible then
            this.activeMenu = "MenuMapLocal"
        elseif menuData.worldMap.visible then
            this.activeMenu = "MenuMapWorld"
        end
    end

    local uiExpBlock = menu:findChild("UIEXP:MapControls")
    if uiExpBlock then
        for _, child in pairs(uiExpBlock.children) do
            if child.type == tes3.uiElementType.scrollBar then
                menuData.uiExpZoomBar = child
                break
            end
        end
    end

    this.isMapMenuInitialized = true
    return this.isMapMenuInitialized
end

---@param menu tes3uiElement
function this.initMultiMenuInfo(menu)
    this.isMultiMenuInitialized = false
    if not menu then return end

    local menuData = this.menu

    menuData.multiMap = menu:findChild("MenuMap_panel")
    if not menuData.multiMap then return end
    menuData.multiPanel = menuData.multiMap:findChild("MenuMap_panel")
    if not menuData.multiPanel then return end
    menuData.multiPane = menuData.multiPanel:findChild("MenuMap_pane")
    if not menuData.multiPane then return end
    menuData.multiMapPane = menuData.multiPane:findChild("MenuMap_map_pane")
    if not menuData.multiMapPane then return end
    menuData.multiMapLayout = menuData.multiMap:findChild("MenuMap_layout")
    if not menuData.multiMapLayout then return end
    menuData.multiPlayerMarker = menuData.multiMap:findChild("MenuMap_local_player")
    if not menuData.multiPlayerMarker then return end

    if menuData.multiMap.visible then
        this.activeMenu = "MenuMulti"
    end

    this.isMultiMenuInitialized = true
    return this.isMultiMenuInitialized
end

function this.isReady()
    if not this.localMap or not this.records or not this.world then return false end
    return true
end

local function getCellEditorName(x, y)
    local cell = tes3.getCell{ x = x / 8192, y = y / 8192 }
    if not cell then return "" end
    return cell.editorName
end


---@class markerLib.addLocalMarker.params
---@field record string|markerLib.recordOOP
---@field position tes3vector3|{x : number, y : number, z : number}|nil
---@field cell string|tes3cell|nil should be nil if the cell is exterior
---@field objectId string|nil should be lowercase
---@field itemId string|nil should be lowercase
---@field conditionFunc (fun(data: markerLib.activeLocalMarkerElement):boolean)|nil
---@field temporary boolean|nil
---@field trackedRef tes3reference|nil
---@field trackOffscreen boolean|nil show the marker on the map menu border when it is offscreen
---@field shortTerm boolean|nil if true, the marker will be deleted after the interior flag for the player cell is changed, or after the interior cell is changed

---@param params markerLib.addLocalMarker.params
---@return string|nil, string|nil ret returns record id and cell id if added. Or nil if not
function this.addLocal(params)
    if not this.localMap or not params.record then return end

    local cellName
    local cellNameLabel

    if params.cell then
        local cell = params.cell
        if type(cell) == "string" then
            cellNameLabel = cell
            cellName = cell:lower()
        else
            cellNameLabel = cell.editorName ---@diagnostic disable-line: need-check-nil
            if cell.isInterior then ---@diagnostic disable-line: need-check-nil
                cellName = cell.editorName:lower() ---@diagnostic disable-line: need-check-nil
            end
        end
    elseif (params.position and params.position.x and params.position.y) then
        cellNameLabel = getCellEditorName(params.position.x, params.position.y)
    else
        cellNameLabel = allMapLabelName
    end

    cellNameLabel = cellNameLabel:lower() ---@diagnostic disable-line: need-check-nil

    if not this.localMap[cellNameLabel] then
        this.localMap[cellNameLabel] = {}
    end

    local position = params.position
    if position then
        position = {x = position.x, y = position.y, z = position.z}
    end

    local objectId = params.objectId
    local reference = params.trackedRef

    local recordId
    if type(params.record) == "string" then
        recordId = params.record
    else
        recordId = params.record.id
    end

    local id = getId()

    ---@type markerLib.markerData
    local data = {
        position = position,
        cellName = cellName,
        recordId = recordId,
        id = id,
        cellId = cellNameLabel,
        objectId = objectId,
        itemId = params.itemId,
        temporary = params.temporary,
        trackedRef = reference and tes3.makeSafeObjectHandle(reference),
        conditionFunc = params.conditionFunc,
        offscreen = params.trackOffscreen,
        shortTerm = params.shortTerm,
    }
    this.localMap[cellNameLabel][id] = data

    log("local marker added, id:", id, "cell:", cellNameLabel, "recId:", recordId, "object:", position or objectId or reference)

    this.addLocalMarkerFromMarkerData(data)

    return id, cellNameLabel
end

---@param id string marker id
---@param cellId string id of cell where marker was placed
---@return boolean ret returns true if the marker is found and removed. Or false if not found
function this.removeLocal(id, cellId)
    this.waitingToCreate_local[id] = nil
    local cellData = this.localMap[cellId] or {}
    local marker = cellData[id]
    if marker then
        this.markersToRemove[id] = true
        cellData[id] = nil
        return true
    end
    return false
end

---@return markerLib.markerData?
function this.getLocal(id, cellId)
    if not this.localMap or not this.localMap[cellId] then return end
    return this.localMap[cellId][id]
end

---@class markerLib.addWorldMarker.params
---@field record string|markerLib.worldMarkerOOP
---@field x number x coordinate of the marker
---@field y number y coordinate of the marker

---@param params markerLib.addWorldMarker.params
---@return string|nil ret returns marker id if added. Or nil if not
function this.addWorld(params)
    if not this.world or not params.record then return end

    local recordId
    if type(params.record) == "string" then
        recordId = params.record
    else
        recordId = params.record.id
    end

    local position = {x = params.x, y = params.y}

    local id = getId()

    local data = {
        position = position,
        recordId = recordId,
        id = id,
        markerId = id,
    }

    this.world[id] = data

    this.addWorldMarkerFromMarkerData(data)
    this.shouldUpdateWorld = true

    log("world marker added, id:", id, "recId:", recordId, "position", position)

    return id
end

---@param id string marker id
---@return boolean ret returns true if the marker is found and removed. Or false if not found
function this.removeWorld(id)
    this.waitingToCreate_world[id] = nil
    local marker = this.world[id]
    if marker then
        this.shouldUpdateWorld = true
        this.markersToRemove[id] = true
        this.world[id] = nil
        return true
    end
    return false
end

---@return markerLib.markerData?
function this.getWorld(id)
    if not this.world then return end
    return this.world[id]
end


---@param id string|nil
---@param params markerLib.markerRecord
---@return string|nil ret returns record id if added or updated. Or nil if not
function this.addRecord(id, params)
    if not params.path then return end

    local texturePath = "textures\\"..params.path
    local texture = tes3.loadSourceTexture(params.path)
    if not texture then return end

    ---@type markerLib.markerRecord
    local record = {path = texturePath}

    if params.pathAbove then
        texture = tes3.loadSourceTexture(params.pathAbove)
        if not texture then return end
        record.pathAbove = "textures\\"..params.pathAbove
    end
    if params.pathBelow then
        texture = tes3.loadSourceTexture(params.pathBelow)
        if not texture then return end
        record.pathBelow = "textures\\"..params.pathBelow
    end

    record.width = texture.width
    record.height = texture.height

    record.textureShiftX = params.textureShiftX or record.width / 2
    record.textureShiftY = params.textureShiftY or record.height / 2

    record.name = params.name
    record.description = params.description
    record.temporary = params.temporary
    record.color = params.color
    record.scale = params.scale
    record.priority = params.priority or 0

    if not id then
        id = getId()
    elseif not this.records[id] then
        return
    end

    record.id = id

    this.records[id] = record

    log("record added,", id)

    return id
end

---@param id string record id
---@return boolean ret returns true if the record is found and removed. Or false if not found
function this.removeRecord(id)
    if not id then return false end
    local rec = this.records[id]
    if rec then
        this.markersToRemove[id] = true
        this.records[id] = nil
        log("record removed,", id)
        return true
    end
    return false
end

---@param id string
---@return markerLib.markerRecord|nil
function this.getRecord(id)
    if not this.records or not id then return end
    return this.records[id]
end

---@return table<string, markerLib.markerData>
function this.getCellData(cellName)
    if cellName then
        return this.localMap[cellName:lower()]
    else
        return this.localMap[allMapLabelName]
    end
end


local tempRecordList = {}
---@param pane tes3uiElement
---@param record markerLib.markerRecord
---@param position {z : number}|tes3vector3|nil position of the tracked object
---@return tes3uiElement|nil
local function drawMarker(pane, x, y, record, position)
    if not pane or not record then return end

    local path
    if position and (record.pathBelow or record.pathAbove) then
        local playerPosZ = tes3.player.position.z
        local posDiff = position.z - playerPosZ
        local imageType = (posDiff > this.zDifference) and "pathAbove" or ((posDiff < -this.zDifference) and "pathBelow" or "path")
        path = record[imageType]
    end
    if not path then
        path = record.path
    end

    local image = pane:createImage{id = markerLabelId, path = path}

    image.autoHeight = true
    image.autoWidth = true
    image.absolutePosAlignX = -2
    image.absolutePosAlignY = -2
    image.imageScaleX = record.scale or 1
    image.imageScaleY = record.scale or 1
    image.positionX = x + (record.textureShiftX or -record.width / 2)
    image.positionY = y + (record.textureShiftY or record.height / 2)
    image.color = record.color or {1, 1, 1}

    image:setLuaData("imageRecordId", record)

    image:register(tes3.uiEvent.help, function (e)
        if not e.source then return end
        ---@type markerLib.markerContainer
        local luaData = e.source:getLuaData("data")
        if not luaData then return end

        table.clear(tempRecordList)
        for id, dt in pairs(luaData.items) do
            table.insert(tempRecordList, dt.record)
        end

        table.sort(tempRecordList, function (a, b)
            return (a.priority or 0) > (b.priority or 0)
        end)

        local tooltip = tes3ui.createTooltipMenu()
        tooltip.childAlignX = 0.5

        local blockCount = 0
        for i, rec in ipairs(tempRecordList) do
            if not rec.name and not rec.description then goto continue end

            local block = tooltip:createBlock{id = tooltipBlock}
            block.flowDirection = tes3.flowDirection.topToBottom
            block.autoHeight = true
            block.autoWidth = true
            block.maxWidth = 350
            block.borderBottom = 3

            blockCount = blockCount + 1

            if rec.name then
                local label = block:createLabel{id = tooltipName, text = rec.name}
                label.autoHeight = true
                label.autoWidth = true
                label.maxWidth = 350
                label.wrapText = true
                label.justifyText = tes3.justifyText.center
            end

            if rec.description then
                local label = block:createLabel{id = tooltipDescription, text = rec.description}
                label.autoHeight = true
                label.autoWidth = true
                label.maxWidth = 350
                label.wrapText = true
                label.justifyText = tes3.justifyText.left
            end

            ::continue::
        end

        if blockCount == 0 then
            tooltip:destroy()
        else
            tooltip:getTopLevelMenu():updateLayout()
        end
    end)

    return image
end

---@param element tes3uiElement
---@return markerLib.markerRecord|nil
local function getMaxPriorityRecord(element)
    if not element then return end

    ---@type markerLib.markerContainer
    local luaData = element:getLuaData("data")
    if not luaData then return end

    table.clear(tempRecordList)
    for id, dt in pairs(luaData.items) do
        table.insert(tempRecordList, dt.record)
    end

    table.sort(tempRecordList, function (a, b)
        return (a.priority or 0) > (b.priority or 0)
    end)

    if #tempRecordList == 0 then return end

    return tempRecordList[1]
end

---@param markerEl tes3uiElement
---@param updateImage boolean|nil update image
---@return boolean|nil
local function changeMarker(markerEl, x, y, updateImage)
    ---@type markerLib.markerRecord
    local rec = getMaxPriorityRecord(markerEl)

    if not rec then return end
    local ret = false

    ---@type markerLib.markerContainer
    local luaData = markerEl:getLuaData("data")
    if not luaData then return end

    local imageRecId = markerEl:getLuaData("imageRecordId")
    local position = luaData.position
    local imageType
    if position and position.z then
        local playerPosZ = tes3.player.position.z
        local posDiff = position.z - playerPosZ
        imageType = (posDiff > this.zDifference) and "pathAbove" or ((posDiff < -this.zDifference) and "pathBelow" or "path")
    else
        imageType = "path"
    end

    local path = rec[imageType]
    if not path then
        path = rec.path
    end

    local shouldUpdateImage = imageRecId ~= rec.id or (path and path ~= markerEl.contentPath)

    if updateImage or shouldUpdateImage then

        markerEl.contentPath = path

        markerEl:setLuaData("imageRecordId", rec.id)

        markerEl.imageScaleX = rec.scale or 1
        markerEl.imageScaleY = rec.scale or 1
        markerEl.color = rec.color or {1, 1, 1}
        ret = ret or true
    end

    if x and y then
        markerEl.positionX = math.round(x) + (rec.textureShiftX or -rec.width / 2)
        markerEl.positionY = math.round(y) + (rec.textureShiftY or rec.height / 2)
        ret = ret or true
    end

    return ret
end


---@param markerData markerLib.activeLocalMarkerElement
---@param container markerLib.markerContainer
---@return boolean|nil ret returns true if marker should to remove
local function checkConditionsToRemoveMarkerElement(markerData, container)

    if this.markersToRemove[markerData.id] or this.markersToRemove[markerData.record.id] then
        return true
    end

    if markerData.conditionFunc and not markerData.conditionFunc(markerData) then
        return true
    end


    if container.ref and markerData.itemId then
        local ref = container.ref:getObject()
        local inventory = ref.object.inventory
        if inventory and inventory:getItemCount(markerData.itemId) <= 0 then
            return true
        end
    end

    return false
end


local function getLocalMenuLayout()
    local menuData = this.menu

    if not this.isMapMenuInitialized and not this.isMultiMenuInitialized then return end

    local menuMap = menuData.menuMap
    local multiMenu = menuData.multiMap

    local localPane
    local playerMarker
    local localPanel
    local mapPane
    local layoutOffsetX = 0
    local layoutOffsetY = 0

    if this.isMapMenuInitialized and menuMap.visible then ---@diagnostic disable-line: need-check-nil
        localPane = menuData.localPane
        playerMarker = menuData.localPlayerMarker
        localPanel = menuData.localPanel
        mapPane = menuData.localMapPane
        layoutOffsetX = menuData.localPane.positionX
        layoutOffsetY = menuData.localPane.positionY
    elseif this.isMultiMenuInitialized and multiMenu.visible then ---@diagnostic disable-line: need-check-nil
        localPane = menuData.multiPane
        localPanel = menuData.multiPanel
        mapPane = menuData.multiMapPane
        local mapLayout = menuData.multiMapLayout
        local plM = menuData.multiPlayerMarker
        playerMarker = {
            positionX = -mapLayout.positionX + plM.positionX, ---@diagnostic disable-line: need-check-nil
            positionY = -mapLayout.positionY + plM.positionY, ---@diagnostic disable-line: need-check-nil
        }
        layoutOffsetX = menuData.multiMapLayout.positionX
        layoutOffsetY = menuData.multiMapLayout.positionY
    end

    return localPane, playerMarker, localPanel, mapPane, layoutOffsetX, layoutOffsetY
end


---@param data markerLib.markerData
---@return boolean
local function isMarkerValidToCreate(data)
    if data.cellName and not activeCells.isCellActiveByName(data.cellName) then
        return false
    elseif data.trackedRef and (not data.trackedRef:valid() or not activeCells.isCellActiveByName(data.trackedRef:getObject().cell.editorName:lower())) then
        return false
    elseif not data.cellName and data.position and not activeCells.isCellActiveByName(getCellEditorName(data.position.x, data.position.y):lower()) then
        return false
    end
    return true
end

---@param data markerLib.markerData
function this.addLocalMarkerFromMarkerData(data)
    if isMarkerValidToCreate(data) then
        this.waitingToCreate_local[data.id] = data
    end
end

-- Thank you, chatgpt
local function calculateOffscreenIndicator(targetX, targetY, screenWidth, screenHeight, screenOriginX, screenOriginY, border)
    local screenCenterX = screenOriginX + screenWidth / 2
    local screenCenterY = screenOriginY - screenHeight / 2

    local dirX = targetX - screenCenterX
    local dirY = targetY - screenCenterY

    local magnitude = math.sqrt(dirX^2 + dirY^2)
    local normX = dirX / magnitude
    local normY = dirY / magnitude

    local left = screenOriginX + border
    local right = screenOriginX + screenWidth - border
    local top = screenOriginY - border
    local bottom = screenOriginY - screenHeight + border

    local indicatorX, indicatorY

    if normX ~= 0 then
        local t1 = (left - screenCenterX) / normX
        local t2 = (right - screenCenterX) / normX
        if t1 > 0 then
            local y = screenCenterY + t1 * normY
            if y <= top and y >= bottom then
                indicatorX = left
                indicatorY = y
            end
        end
        if not indicatorX and t2 > 0 then
            local y = screenCenterY + t2 * normY
            if y <= top and y >= bottom then
                indicatorX = right
                indicatorY = y
            end
        end
    end

    if normY ~= 0 then
        local t3 = (top - screenCenterY) / normY
        local t4 = (bottom - screenCenterY) / normY
        if not indicatorX and t3 > 0 then
            local x = screenCenterX + t3 * normX
            if x >= left and x <= right then
                indicatorX = x
                indicatorY = top
            end
        end
        if not indicatorX and t4 > 0 then
            local x = screenCenterX + t4 * normX
            if x >= left and x <= right then
                indicatorX = x
                indicatorY = bottom
            end
        end
    end

    return indicatorX, indicatorY
end

---@param id string
---@param markerElement tes3uiElement
local function removeMarker(id, markerElement)
    this.deleteMarkerElement(markerElement)
    this.activeWorldMarkers[id] = nil
    this.activeLocalMarkers[id] = nil
    this.waitingToCreate_world[id] = nil
    this.waitingToCreate_local[id] = nil
    log("marker removed, id:", id)
end


---@param cell tes3cell
local function calcInterirAxisAngle(cell)
    for ref in cell:iterateReferences({tes3.objectType.static}) do
        if ref.baseObject.id == "NorthMarker" then
            axisAngle = ref.orientation.z
            break
        else
            axisAngle = 0
        end
    end
    axisAngleCos = math.cos(axisAngle)
    axisAngleSin = math.sin(axisAngle)
end

---@param localPane tes3uiElement
---@param playerMarker tes3uiElement
---@param playerPos tes3vector3
---@return boolean coordinatesHaveShanged
local function calcInterior00Coordinate(localPane, playerMarker, playerPos)
    local xShift = -playerPos.x
    local yShift = playerPos.y

    local posXNorm = xShift * axisAngleCos + yShift * axisAngleSin
    local posYNorm = yShift * axisAngleCos - xShift * axisAngleSin

    interior0PointPositionX = playerMarker.positionX + posXNorm / (8192 / localPane.width)
    interior0PointPositionY = playerMarker.positionY - posYNorm / (8192 / localPane.height)

    local ret = not (math.isclose(interior0PointPositionX, last0XCoord, 2) and math.isclose(interior0PointPositionY, last0YCoord, 2))
    last0XCoord = interior0PointPositionX
    last0YCoord = interior0PointPositionY
    return ret
end

---@param mapPane tes3uiElement
local function calcGridOffset(mapPane)
    local mapCell = mapPane:findChild("MenuMap_map_cell")
    if mapCell then
        local cell = mapCell:getPropertyObject("MenuMap_cell")
        if cell then
            last0GridX = cell.gridX - math.floor(mapCell.positionX / mapCell.width)
            last0GridY = cell.gridY + math.floor(mapCell.positionY / mapCell.height)
        end
    end
end

-- ################################################################################################

local function buildLocalMarkerPosMap()
    table.clear(localMarkerPositionMap)
    for id, data in pairs(this.activeLocalMarkers) do
        local pos = data.position
        if not data.ref and not data.objectId and pos then
            local mapId = tostring(math.floor(pos.x / 48))..","..tostring(math.floor(pos.y / 48))
            localMarkerPositionMap[mapId] = data
        end
    end
end

local function clearLocalMarkerPosMap()
    table.clear(localMarkerPositionMap)
end

---@param position tes3vector3
---@return markerLib.markerContainer?
local function getLocalMarkerPosData(position)
    local mapId = tostring(math.floor(position.x / 48))..","..tostring(math.floor(position.y / 48))
    return localMarkerPositionMap[mapId]
end

---@param position tes3vector3
---@param data markerLib.markerContainer
local function addLocalMarkerPosData(position, data)
    local mapId = tostring(math.floor(position.x / 48))..","..tostring(math.floor(position.y / 48))
    localMarkerPositionMap[mapId] = data
end

---@param position tes3vector3
local function removeLocalMarkerPosData(position)
    local mapId = tostring(math.floor(position.x / 48))..","..tostring(math.floor(position.y / 48))
    localMarkerPositionMap[mapId] = nil
end

local function buildWorldMarkerPosMap()
    table.clear(worldMarkerPositionMap)
    for id, data in pairs(this.activeWorldMarkers) do
        local pos = data.position
        if pos then
            local mapId = tostring(math.floor(pos.x / 2000))..","..tostring(math.floor(pos.y / 2000))
            worldMarkerPositionMap[mapId] = data
        end
    end
end

---@param position tes3vector3
---@return markerLib.markerContainer?
local function getWorldMarkerPosData(position)
    local mapId = tostring(math.floor(position.x / 2000))..","..tostring(math.floor(position.y / 2000))
    return worldMarkerPositionMap[mapId]
end

---@param position tes3vector3
---@param data markerLib.markerContainer
local function addWorldMarkerPosData(position, data)
    local mapId = tostring(math.floor(position.x / 2000))..","..tostring(math.floor(position.y / 2000))
    worldMarkerPositionMap[mapId] = data
end

---@param position tes3vector3
local function removeWorldMarkerPosData(position)
    local mapId = tostring(math.floor(position.x / 2000))..","..tostring(math.floor(position.y / 2000))
    worldMarkerPositionMap[mapId] = nil
end

-- ################################################################################################

function this.createLocalMarkers()
    local localPane, playerMarker, localPanel, mapPane = getLocalMenuLayout()

    if not localPane or not playerMarker or not mapPane then return end

    local player = tes3.player
    local playerPos = player.position
    local playerCell = player.cell

    lastCell = lastCell or {}

    if lastCell ~= playerCell then
        if playerCell.isInterior then
            calcInterirAxisAngle(playerCell)
            calcInterior00Coordinate(localPane, playerMarker, playerPos)
            is00CoordinateSteady = false
        else
            calcGridOffset(mapPane)
        end

        if lastCell.isInterior ~= playerCell.isInterior or playerCell.isInterior then

            for id, data in pairs(this.activeLocalMarkers) do
                if data.markerData and data.markerData.shortTerm then
                    this.removeLocal(data.markerData.id, data.markerData.cellId)
                    removeMarker(id, data.marker)
                end
            end
        end
    end

    if this.activeMenu ~= lastActiveMenu or lastCell ~= playerCell then
        lastActiveMenu = this.activeMenu
        this.reregisterLocal()
    end

    lastCell = playerCell

    if table.size(this.waitingToCreate_local) == 0 then return end

    local tileHeight
    local tileWidth
    if playerCell.isInterior then
        tileHeight = localPane.height
        tileWidth = localPane.width
    else
        tileHeight = localPane.height / 3
        tileWidth = localPane.width / 3
    end

    local widthPerPix = 8192 / tileWidth
    local heightPerPix = 8192 / tileHeight

    ---@return number, number
    local function calcInteriorPos(position)
        local posXNorm = position.x * axisAngleCos - position.y * axisAngleSin
        local posYNorm = -position.y * axisAngleCos - position.x * axisAngleSin

        local posX = interior0PointPositionX + posXNorm / widthPerPix
        local posY = interior0PointPositionY - posYNorm / heightPerPix

        return posX, posY
    end

    local function calcExteriorPos(position)
        local posX = (position.x / 8192 - last0GridX) * tileWidth
        local posY = -(1 + -position.y / 8192 + last0GridY) * tileHeight

        return posX, posY
    end

    for markerId, data in pairs(this.waitingToCreate_local) do
        local record = this.records[data.recordId]

        if not record then
            this.removeLocal(data.id, data.cellId)
            goto continue
        end

        local function createMarkerForRef(ref)
            local parentData = this.activeLocalMarkers[ref]

            if parentData and parentData.marker then
                if parentData.items[data.recordId] then
                    return
                else
                    parentData.items[data.recordId] = {
                        id = data.id,
                        record = record,
                        markerData = data,
                        conditionFunc = data.conditionFunc,
                        itemId = data.itemId
                    }
                    parentData.shouldUpdate = true
                    parentData.offscreen = parentData.offscreen or data.offscreen
                end

            else
                local position = ref.position

                local posX, posY
                if playerCell.isInterior then
                    posX, posY = calcInteriorPos(position)
                else
                    posX, posY = calcExteriorPos(position)
                end

                local marker = drawMarker(localPane, posX, posY, record, position)
                if marker then
                    local pos = ref.position:copy()
                    this.activeLocalMarkers[ref] = {
                        marker = marker,
                        items = {},
                        cell = ref.cell,
                        ref = data.trackedRef or tes3.makeSafeObjectHandle(ref),
                        objectId = data.objectId,
                        position = pos,
                        lastZDiff = math.abs(pos.z - playerPos.z),
                        offscreen = data.offscreen
                    }
                    local markerContainer = this.activeLocalMarkers[ref]
                    markerContainer.items[data.recordId] = {
                        id = data.id,
                        record = record,
                        markerData = data,
                        conditionFunc = data.conditionFunc,
                        itemId = data.itemId
                    }
                    marker:setLuaData("data", markerContainer)
                end
            end
        end

        if data.objectId then

            local object = tes3.getObject(data.objectId)
            if object then
                for ref, _ in pairs(objectCache.getRefTable(object.id)) do
                    createMarkerForRef(ref)
                end
            end

            this.activeLocalMarkers[data.objectId] = { markerData = data } ---@diagnostic disable-line: missing-fields

        elseif data.trackedRef then

            if data.trackedRef:valid() then
                local ref = data.trackedRef:getObject()
                createMarkerForRef(ref)
            end

        elseif data.position then -- for static markers

            local position = data.position
            local parentData = getLocalMarkerPosData(position)

            if parentData and parentData.marker then
                if parentData.items[data.recordId] then
                    goto continue
                else
                    parentData.items[data.recordId] = {
                        id = data.id,
                        record = record,
                        markerData = data,
                        conditionFunc = data.conditionFunc,
                        itemId = data.itemId
                    }
                    parentData.shouldUpdate = true
                    parentData.offscreen = parentData.offscreen or data.offscreen
                end

            else
                local posX, posY
                if playerCell.isInterior then
                    posX, posY = calcInteriorPos(position)
                else
                    posX, posY = calcExteriorPos(position)
                end

                local marker = drawMarker(localPane, posX, posY, record, position)
                if marker then
                    local id = getId()

                    local pos = tes3vector3.new(position.x, position.y, position.z)
                    this.activeLocalMarkers[id] = {
                        marker = marker,
                        items = {},
                        position = pos,
                        lastZDiff = math.abs(pos.z - playerPos.z),
                        cell = tes3.getCell{id = data.cellName, position = pos},
                        conditionFunc = data.conditionFunc,
                        itemId = data.itemId,
                        offscreen = data.offscreen
                    }
                    local markerContainer = this.activeLocalMarkers[id]
                    markerContainer.items[data.recordId] = {
                        id = data.id,
                        record = record,
                        markerData = data,
                        conditionFunc = data.conditionFunc,
                        itemId = data.itemId
                    }
                    marker:setLuaData("data", markerContainer)
                    addLocalMarkerPosData(position, markerContainer)
                end
            end
        end

        ::continue::
    end

    table.clear(this.waitingToCreate_local)
end


function this.updateLocalMarkers(force)

    this.lastLocalUpdate = os.clock()

    if table.size(this.activeLocalMarkers) == 0 then
        return
    end

    local player = tes3.player
    local playerPos = player.position
    local playerCell = player.cell

    local localPane, playerMarker, localPanel, mapPane, layoutOffsetX, layoutOffsetY = getLocalMenuLayout()

    if not localPane or not playerMarker or not localPanel or not mapPane then return end

    if lastLocalPaneWidth ~= localPane.width or lastLocalPaneHeight ~= localPane.height then
        force = true
        lastLocalPaneWidth = localPane.width
        lastLocalPaneHeight = localPane.height

        calcInterior00Coordinate(localPane, playerMarker, playerPos)
        is00CoordinateSteady = false

    elseif not is00CoordinateSteady then
        if calcInterior00Coordinate(localPane, playerMarker, playerPos) then
            menu00CoordinateSteadyCounter = 0
        else
            menu00CoordinateSteadyCounter = menu00CoordinateSteadyCounter + 1
        end

        if menu00CoordinateSteadyCounter >= 8 then
            menu00CoordinateSteadyCounter = 0
            is00CoordinateSteady = true
        end
    end

    if not playerCell.isInterior then
        local playerMarkerTileX = math.floor(3 * math.abs(playerMarker.positionX) / localPane.width)
        local playerMarkerTileY = math.floor(3 * math.abs(playerMarker.positionY) / localPane.height)

        if lastPlayerMarkerTileX ~= playerMarkerTileX or lastPlayerMarkerTileY ~= playerMarkerTileY then
            calcGridOffset(mapPane)
            lastPlayerMarkerTileX = playerMarkerTileX
            lastPlayerMarkerTileY = playerMarkerTileY
            force = true
        end
    end

    ---@type table<tes3uiElement, {pos : tes3vector3, containerData : markerLib.markerContainer}>
    local markersToUpdate = {}

    for id, data in pairs(this.activeLocalMarkers) do

        local markerData = data.markerData
        if not data.marker then
            if not markerData or this.markersToRemove[markerData.id] then
                this.activeLocalMarkers[id] = nil
            end
            goto continue
        end

        local function deleteMarker()
            removeMarker(id, data.marker)
        end

        local refObj = data.ref
        if refObj then
            if not refObj:valid() then
                deleteMarker()
                goto continue
            end

            local ref = refObj:getObject()
            local refPos = ref.position

            local shouldUpdate = data.shouldUpdate or data.offscreen or force
            data.shouldUpdate = false

            local offscreen = false
            for recordId, element in pairs(data.items) do
                if checkConditionsToRemoveMarkerElement(element, data) then
                    data.items[recordId] = nil
                    shouldUpdate = true
                else
                    offscreen = offscreen or (element.markerData and element.markerData.offscreen)
                end
            end

            if table.size(data.items) == 0 then
                deleteMarker()
                goto continue
            end

            data.offscreen = offscreen

            if shouldUpdate then goto action end

            if not math.isclose(data.position.x, refPos.x, positionDifferenceToUpdate) or
                    not math.isclose(data.position.y, refPos.y, positionDifferenceToUpdate) then
                shouldUpdate = true
            elseif not data.lastZDiff or math.floor(data.lastZDiff / this.zDifference) ~=
                    math.floor(math.abs(refPos.z - playerPos.z) / this.zDifference) then
                shouldUpdate = true
            end

            ::action::

            if not shouldUpdate then goto continue end

            data.position.x = refPos.x
            data.position.y = refPos.y
            data.position.z = refPos.z
            data.lastZDiff = math.abs(data.position.z - playerPos.z)

            markersToUpdate[data.marker] = {pos = data.position, containerData = data}

        elseif activeCells.isCellActive(data.cell) then

            local shouldUpdate = data.shouldUpdate or data.offscreen or force
            data.shouldUpdate = false
            if shouldUpdate then goto action end

            for recordId, element in pairs(data.items) do
                if checkConditionsToRemoveMarkerElement(element, data) then
                    data.items[recordId] = nil
                    shouldUpdate = true
                    break
                end
            end

            if shouldUpdate then goto action end

            if table.size(data.items) == 0 then
                removeLocalMarkerPosData(data.position)
                deleteMarker()
                goto continue
            end

            if not data.lastZDiff or math.floor(data.lastZDiff / this.zDifference) ~=
                    math.floor(math.abs(data.position.z - playerPos.z) / this.zDifference) then
                shouldUpdate = true
            end

            ::action::

            if not shouldUpdate then goto continue end

            data.lastZDiff = math.abs(data.position.z - playerPos.z)

            markersToUpdate[data.marker] = {pos = data.position, containerData = data}

        else
            removeLocalMarkerPosData(data.position)
            deleteMarker()
        end

        ::continue::
    end

    if table.size(markersToUpdate) == 0 then return end

    local tileHeight
    local tileWidth
    if playerCell.isInterior then
        tileHeight = localPane.height
        tileWidth = localPane.width
    else
        tileHeight = localPane.height / 3
        tileWidth = localPane.width / 3
    end

    local widthPerPix = 8192 / tileWidth
    local heightPerPix = 8192 / tileHeight

    local panelFrameX1 = -layoutOffsetX
    local panelFrameX2 = -layoutOffsetX + localPanel.width
    local panelFrameY1 = -layoutOffsetY
    local panelFrameY2 = -layoutOffsetY - localPanel.height

    for marker, data in pairs(markersToUpdate) do

        local pos = data.pos

        local posX
        local posY

        if playerCell.isInterior then
            local posXNorm = pos.x * axisAngleCos - pos.y * axisAngleSin
            local posYNorm = -pos.y * axisAngleCos - pos.x * axisAngleSin

            posX = interior0PointPositionX + posXNorm / widthPerPix
            posY = interior0PointPositionY - posYNorm / heightPerPix
        else
            posX = (pos.x / 8192 - last0GridX) * tileWidth
            posY = -(1 + -pos.y / 8192 + last0GridY) * tileHeight
        end

        if data.containerData.offscreen and (posX < panelFrameX1 or posX > panelFrameX2 or posY > panelFrameY1 or posY < panelFrameY2) then
            local border = this.activeMenu == "MenuMulti" and 4 or 6
            local nx, ny = calculateOffscreenIndicator(posX, posY, localPanel.width, localPanel.height, -layoutOffsetX, -layoutOffsetY, border)
            posX = nx or posX
            posY = ny or posY
        end

        changeMarker(marker, posX, posY, force)
    end
end

-- ################################################################################################

---@param pos tes3vector2|tes3vector3|{x : number, y : number}
---@return number x, number y
function this.convertObjectPosToWorldMapPaneCoordinates(pos)
    local zoomBar = this.menu.uiExpZoomBar
    local currentZoom = 2
    local xOffset = 4
    local yOffset = 4
    if zoomBar then
        currentZoom = zoomBar and zoomBar:getPropertyInt("PartScrollBar_current") / 100 + 1.0
        xOffset = 0
        yOffset = 0
    else
        currentZoom = this.menu.worldPane.width / 512
        if mcp_mapExpansion then
            xOffset = 1
            yOffset = 2
        end
    end

    local x = ((-this.worldBounds.minX + pos.x / 8192) * this.worldBounds.cellResolution + xOffset) * currentZoom
    local y = ((-this.worldBounds.maxY - 1 + pos.y / 8192) * this.worldBounds.cellResolution - yOffset) * currentZoom

    return x, y
end

-- ################################################################################################

function this.createWorldMarkers()
    lastActiveMenu = this.activeMenu
    if table.size(this.waitingToCreate_world) == 0 then return end

    local worldPane = this.menu.worldPane

    for markerId, data in pairs(this.waitingToCreate_world) do
        local record = this.records[data.recordId]

        if not record then
            this.removeWorld(data.id)
            if data.position then
                removeWorldMarkerPosData(data.position)
            end
            goto continue
        end

        local pos = data.position
        local parentData = getWorldMarkerPosData(pos)

        if parentData then
            if parentData.items[data.recordId] then
                goto continue
            else
                parentData.items[data.recordId] = {
                    id = data.id,
                    record = record,
                    markerData = data,
                }
                parentData.shouldUpdate = true
            end
        else
            local x, y = this.convertObjectPosToWorldMapPaneCoordinates(pos)

            local marker = drawMarker(worldPane, x, y, record)
            if marker then
                this.activeWorldMarkers[data.id] = {
                    id = data.id,
                    position = {x = data.position.x, y = data.position.y},
                    record = record,
                    marker = marker,
                    items = {},
                }
                local markerContainer = this.activeWorldMarkers[data.id]
                markerContainer.items[data.recordId] = {
                    id = data.id,
                    record = record,
                    markerData = data,
                }
                marker:setLuaData("data", markerContainer)
                addWorldMarkerPosData(pos, markerContainer)
            end
        end
        ::continue::
    end

    table.clear(this.waitingToCreate_world)
end

function this.updateWorldMarkers(forceRedraw)
    this.lastWorldUpdate = os.clock()

    if table.size(this.activeWorldMarkers) == 0 then
        return
    end

    local worldPane = this.menu.worldPane
    if not worldPane then return end

    if not this.shouldUpdateWorld and not forceRedraw and
            worldPane.width == lastWorldPaneWidth and worldPane.height == lastWorldPaneHeight then
        return
    end

    lastWorldPaneWidth = worldPane.width
    lastWorldPaneHeight = worldPane.height

    for id, data in pairs(this.activeWorldMarkers) do

        local function deleteMarker()
            if data.position then
                removeWorldMarkerPosData(data.position)
            end
            removeMarker(id, data.marker)
        end

        if this.markersToRemove[id] then
            deleteMarker()
            goto continue
        end

        for recordId, element in pairs(data.items) do
            if checkConditionsToRemoveMarkerElement(element, data) then
                data.items[recordId] = nil
                break
            end
        end

        if table.size(data.items) == 0 then
            deleteMarker()
            goto continue
        end

        local pos = data.position

        local x, y = this.convertObjectPosToWorldMapPaneCoordinates(pos)

        changeMarker(data.marker, x, y, forceRedraw)

        ::continue::
    end
    this.shouldUpdateWorld = false
end

-- ################################################################################################

---@param data markerLib.markerData
function this.addWorldMarkerFromMarkerData(data)
    this.waitingToCreate_world[data.id] = data
end


---@param marker tes3uiElement
function this.deleteMarkerElement(marker)
    if not marker then return end
    marker.visible = false
    this.markerElementsToDelete[marker] = true
end

function this.removeDeletedMarkers()
    for marker, _ in pairs(this.markerElementsToDelete) do
        marker:destroy()
    end
    table.clear(this.markerElementsToDelete)
end

---@param cell tes3cell|nil
function this.registerMarkersForCell(cell)
    if not this.localMap then return end
    local label
    if not cell then
        label = allMapLabelName
    else
        label = cell.editorName:lower()
    end

    for id, data in pairs(this.localMap[label] or {}) do
        log("marker registered, id:", data.id, "cell:", label)
        this.addLocalMarkerFromMarkerData(data)
    end
end

---@param ref tes3reference
function this.tryAddMarkersForRef(ref)
    local objectId = ref.baseObject.id
    local dataByObjId = this.activeLocalMarkers[objectId]
    if dataByObjId then
        local markerData = dataByObjId.markerData
        this.waitingToCreate_local[markerData.id] = dataByObjId.markerData ---@diagnostic disable-line: need-check-nil
    end
end

function this.reregisterLocal()
    for id, data in pairs(this.activeLocalMarkers) do
        if data.marker then
            this.deleteMarkerElement(data.marker)
        end
        if data.markerData then
            this.addLocalMarkerFromMarkerData(data.markerData)
        end
        if data.items then
            for recordId, markerElement in pairs(data.items) do
                this.addLocalMarkerFromMarkerData(markerElement.markerData)
            end
        end
    end
    clearLocalMarkerPosMap()
    table.clear(this.activeLocalMarkers)
end

function this.registerWorld()
    if not this.world then return end

    for id, data in pairs(this.world) do
        this.addWorldMarkerFromMarkerData(data)
    end
    this.shouldUpdateWorld = true
end

---@return boolean ret returns true if was successful
function this.updateMapMenu()
    local menu = this.menu.menuMap
    if not menu then return false end

    menu:updateLayout()
    return true
end


function this.reset()
    lastCell = nil
    lastActiveMenu = nil
    lastWorldPaneWidth = 0
    lastWorldPaneHeight = 0
    lastLocalPaneWidth = 0
    lastLocalPaneHeight = 0
    lastPlayerMarkerTileX = nil
    lastPlayerMarkerTileY = nil
    localMarkerPositionMap = {}
    worldMarkerPositionMap = {}
    last0XCoord = 0
    last0YCoord = 0
    last0GridX = 0
    last0GridY = 0
    menu00CoordinateSteadyCounter = 0
    is00CoordinateSteady = false

    storageData = nil
    this.activeMenu = nil

    this.shouldAddLocal = false
    this.shouldAddWorld = false
    this.shouldUpdateWorld = false

    this.updateInterval = 0.1
    this.lastLocalUpdate = 0
    this.lastWorldUpdate = 0
    this.zDifference = 256

    this.activeLocalMarkers = {}
    this.activeWorldMarkers = {}
    this.waitingToCreate_local = {}
    this.waitingToCreate_world = {}
    this.markersToRemove = {}
    this.markerElementsToDelete = {}
    this.menu = {}

    this.isMapMenuInitialized = false
    this.isMultiMenuInitialized = false

    this.localMap = nil
    this.records = nil
    this.world = nil
end


function this.save()
    if not storageData then return end

    storageData.map = {}

    for cellId, cellData in pairs(this.localMap) do
        storageData.map[cellId] = {}
        local plCellData = storageData.map[cellId]
        for id, data in pairs(cellData) do
            if data.temporary or data.trackedRef or data.conditionFunc then goto continue end
            plCellData[id] = data

            ::continue::
        end
    end
end

return this