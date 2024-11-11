local objectCache = include("diject.map_markers.objectCache")
local activeCells = include("diject.map_markers.activeCells")
local log = include("diject.map_markers.utils.log")

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
local cellWidthMinPart = -minCellGridX * 8192
local cellHeightMaxPart = (maxCellGridY + 1) * 8192
local worldWidth = (-minCellGridX + maxCellGridX - 0.25) * 8192
local worldHeight = (-minCellGridY + maxCellGridY - 0.75) * 8192

local positionDifferenceToUpdate = 16


local allMapLabelName = "__all_map__"

local this = {}

this.activeMenu = nil

this.shouldAddLocal = false
this.shouldAddWorld = false

this.shouldUpdateWorld = false

this.updateInterval = 0.1
this.lastLocalUpdate = 0
this.lastWorldUpdate = 0

this.zDifference = 256

local storageData

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


---@class markerLib.markerData
---@field recordId string recordId
---@field position tes3vector3|{x : number, y : number, z : number}
---@field id string
---@field cellName string|nil should be nil if the cell is exterior
---@field objectId string|nil should be lowercase
---@field itemId string|nil should be lowercase
---@field conditionFunc (fun(data: markerLib.activeLocalMarkerElement):boolean)|nil
---@field temporary boolean|nil
---@field trackedRef mwseSafeObjectHandle|nil

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
end

function this.isReady()
    if not this.localMap or not this.records or not this.world then return false end
    return true
end

local function getExCellName(x, y)
    return string.format("%d, %d", math.floor(x / 8192), math.floor(y / 8192))
end



---@class markerLib.addLocalMarker.params
---@field recordId string
---@field position tes3vector3|{x : number, y : number, z : number}|nil
---@field cellName string|nil should be nil if the cell is exterior
---@field objectId string|nil should be lowercase
---@field itemId string|nil should be lowercase
---@field conditionFunc (fun(data: markerLib.activeLocalMarkerElement):boolean)|nil
---@field temporary boolean|nil
---@field trackedRef tes3reference|nil

---@param params markerLib.addLocalMarker.params
---@return string|nil, string|nil ret returns record id and cell id if added. Or nil if not
function this.addLocal(params)
    if not this.localMap then return end

    local cellName
    if (params.position and params.position.x and params.position.y) or params.cellName then
        cellName = params.cellName or getExCellName(params.position.x, params.position.y)
    else
        cellName = allMapLabelName
    end
    cellName = cellName:lower()

    if not this.localMap[cellName] then
        this.localMap[cellName] = {}
    end

    local position = params.position
    if position then
        position = {x = position.x, y = position.y, z = position.z}
    end

    local id = getId()

    ---@type markerLib.markerData
    local data = {
        position = position,
        recordId = params.recordId,
        id = id,
        objectId = params.objectId,
        itemId = params.itemId,
        temporary = params.temporary,
        trackedRef = params.trackedRef and tes3.makeSafeObjectHandle(params.trackedRef),
        conditionFunc = params.conditionFunc
    }
    this.localMap[cellName][id] = data

    log("added marker \"", id, "\" to \"", cellName, "\" cell", this.localMap[cellName][id])

    this.addLocalMarkerFromMarkerData(data)

    return id, cellName
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

---@class markerLib.addWorldMarker.params
---@field recordId string
---@field x number
---@field y number

---@param params markerLib.addWorldMarker.params
---@return string|nil ret returns marker id if added. Or nil if not
function this.addWorld(params)
    if not this.world then return end

    local id = getId()

    local data = {
        position = {x = params.x, y = params.y},
        recordId = params.recordId,
        id = id,
        markerId = id,
    }

    this.world[id] = data

    this.addWorldMarkerFromMarkerData(data)
    this.shouldUpdateWorld = true

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

    if pane.width < x or x < 0 or pane.height < -y or y > 0 then return end

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
        markerEl.positionX = x + (rec.textureShiftX or -rec.width / 2)
        markerEl.positionY = y + (rec.textureShiftY or rec.height / 2)
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


local function getMenuLayout()
    local menu = tes3ui.findMenu("MenuMap")
    if not menu then return end

    local localPane
    local playerMarker

    if menu.visible then
        local localMap = menu:findChild("MenuMap_local")
        if not localMap then return end
        localPane = localMap:findChild("MenuMap_pane")
        if not localPane then return end
        playerMarker = localPane:findChild("MenuMap_local_player")
        if not playerMarker then return end
        if localMap.visible then
            this.activeMenu = "MenuMapLocal"
        else
            this.activeMenu = "MenuMapWorld"
        end
    else
        menu = tes3ui.findMenu("MenuMulti")
        if not menu then return end
        local localMap = menu:findChild("MenuMap_panel")
        if not localMap then return end
        localPane = localMap:findChild("MenuMap_pane")
        local mapLayout = localMap:findChild("MenuMap_layout")
        if not mapLayout then return end
        local plM = localMap:findChild("MenuMap_local_player")
        if not plM then return end
        playerMarker = {
            positionX = -mapLayout.positionX + plM.positionX,
            positionY = -mapLayout.positionY + plM.positionY,
        }
        this.activeMenu = "MenuMulti"
    end

    return localPane, playerMarker
end


---@param data markerLib.markerData
---@return boolean
local function isMarkerValidToCreate(data)
    if data.cellName and activeCells.isCellActiveByName(data.cellName) then
        return true
    elseif data.trackedRef and data.trackedRef:valid() and activeCells.isCellActiveByName(data.trackedRef:getObject().cell.editorName) then
        return true
    elseif data.position and activeCells.isCellActiveByName(getExCellName(data.position.x, data.position.y)) then
        return true
    end
    return true
end

---@param data markerLib.markerData
function this.addLocalMarkerFromMarkerData(data)
    if isMarkerValidToCreate(data) then
        this.waitingToCreate_local[data.id] = data
    end
end


local axisAngle = 0
local lastCell = nil
local lastActiveMenu = nil
---@type table<string, markerLib.markerContainer>
local localMarkerPositionMap = {}

function this.createLocalMarkers()
    local localPane, playerMarker = getMenuLayout()

    local player = tes3.player
    local playerPos = player.position
    local playerCell = player.cell

    if this.activeMenu ~= lastActiveMenu or ((lastCell or {}).isInterior ~= playerCell.isInterior) then
        lastActiveMenu = this.activeMenu
        this.reregisterLocal()
    end

    if table.size(this.waitingToCreate_local) == 0 then return end

    if not localPane or not playerMarker then return end

    if lastCell ~= playerCell then
        if playerCell.isInterior then
            local nMarker = tes3.getReference("NorthMarker")
            if nMarker then
                axisAngle = nMarker.orientation.z
            end
        end
        lastCell = playerCell
    end

    table.clear(localMarkerPositionMap)
    for id, data in pairs(this.activeLocalMarkers) do
        local pos = data.position
        if pos then
            local mapId = tostring(math.floor(pos.x / 48))..","..tostring(math.floor(pos.y / 48))
            localMarkerPositionMap[mapId] = data
        end
    end

    local tileHeight
    local tileWidth
    if playerCell.isInterior then
        tileHeight = localPane.height
        tileWidth = localPane.width
    else
        tileHeight = localPane.height / 3
        tileWidth = localPane.width / 3
    end
    local playerMarkerX = playerMarker.positionX
    local playerMarkerY = playerMarker.positionY
    local widthPerPix = 8192 / tileWidth
    local heightPerPix = 8192 / tileHeight

    local playerMarkerTileX = math.floor(math.abs(playerMarker.positionX) / tileWidth)
    local playerMarkerTileY = math.floor(math.abs(playerMarker.positionY) / tileHeight)

    local offsetX = 1 - playerMarkerTileX
    local offsetY = 1 - playerMarkerTileY

    ---@return number, number
    local function calcInteriorPos(position)
        local xShift = (position.x - playerPos.x)
        local yShift = (playerPos.y - position.y)

        local posXNorm = xShift * math.cos(axisAngle) + yShift * math.sin(axisAngle)
        local posYNorm = yShift * math.cos(axisAngle) - xShift * math.sin(axisAngle)

        local posX = playerMarkerX + posXNorm / widthPerPix
        local posY = playerMarkerY - posYNorm / heightPerPix

        return posX, posY
    end

    local function calcExteriorPos(position)
        local posX = (offsetX + 1 + math.floor(position.x / 8192) - math.floor(playerPos.x / 8192) + (position.x % 8192) / 8192) * tileWidth
        local posY = -(-offsetY + 2 - (math.floor(position.y / 8192) - math.floor(playerPos.y / 8192) + (position.y % 8192) / 8192)) * tileHeight

        return posX, posY
    end

    for markerId, data in pairs(this.waitingToCreate_local) do
        local record = this.records[data.recordId]

        if not record then
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
            local parentData = localMarkerPositionMap[tostring(math.floor(position.x / 48))..","..tostring(math.floor(position.y / 48))]

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
                    local pos = tes3vector3.new(data.position.x, data.position.y, data.position.z)
                    this.activeLocalMarkers[id] = {
                        marker = marker,
                        items = {},
                        position = pos,
                        lastZDiff = math.abs(pos.z - playerPos.z),
                        cell = tes3.getCell{id = data.cellName, position = pos},
                        conditionFunc = data.conditionFunc,
                        itemId = data.itemId,
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
                end
            end
        end

        ::continue::
    end

    table.clear(this.waitingToCreate_local)
end


function this.updateLocalMarkers(force)

    this.lastLocalUpdate = os.clock()

    local player = tes3.player
    local playerPos = player.position
    local playerCell = player.cell

    ---@type table<tes3uiElement, tes3vector3>
    local markersToUpdate = {}

    for id, data in pairs(this.activeLocalMarkers) do

        if not data.marker then
            if not data.markerData or this.markersToRemove[data.markerData.id] then
                this.activeLocalMarkers[id] = nil
            end
            goto continue
        end

        local function deleteMarker()
            this.deleteMarkerElement(data.marker)
            this.activeLocalMarkers[id] = nil
        end

        local refObj = data.ref
        if refObj then
            if not refObj:valid() then
                deleteMarker()
                goto continue
            end

            local ref = refObj:getObject()
            local refPos = ref.position

            local shouldUpdate = data.shouldUpdate or force
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
                deleteMarker()
                goto continue
            end

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

            markersToUpdate[data.marker] = data.position

        elseif activeCells.isCellActive(data.cell) then

            local shouldUpdate = data.shouldUpdate or force
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

            markersToUpdate[data.marker] = data.position

        else
            deleteMarker()
        end

        ::continue::
    end

    if table.size(markersToUpdate) == 0 then return end

    local localPane, playerMarker = getMenuLayout()

    if not localPane or not playerMarker then return end

    local tileHeight
    local tileWidth
    if playerCell.isInterior then
        tileHeight = localPane.height
        tileWidth = localPane.width
    else
        tileHeight = localPane.height / 3
        tileWidth = localPane.width / 3
    end
    local playerMarkerX = playerMarker.positionX
    local playerMarkerY = playerMarker.positionY
    local widthPerPix = 8192 / tileWidth
    local heightPerPix = 8192 / tileHeight

    local playerMarkerTileX = math.floor(math.abs(playerMarker.positionX) / tileWidth)
    local playerMarkerTileY = math.floor(math.abs(playerMarker.positionY) / tileHeight)

    local offsetX = 1 - playerMarkerTileX
    local offsetY = 1 - playerMarkerTileY

    for marker, pos in pairs(markersToUpdate) do

        local posX
        local posY

        if playerCell.isInterior then
            local xShift = (pos.x - playerPos.x)
            local yShift = (playerPos.y - pos.y)

            local posXNorm = xShift * math.cos(axisAngle) + yShift * math.sin(axisAngle)
            local posYNorm = yShift * math.cos(axisAngle) - xShift * math.sin(axisAngle)

            posX = playerMarkerX + posXNorm / widthPerPix
            posY = playerMarkerY - posYNorm / heightPerPix
        else
            posX = (offsetX + 1 + math.floor(pos.x / 8192) - math.floor(playerPos.x / 8192) + (pos.x % 8192) / 8192) * tileWidth
            posY = -(-offsetY + 2 - (math.floor(pos.y / 8192) - math.floor(playerPos.y / 8192) + (pos.y % 8192) / 8192)) * tileHeight
        end

        changeMarker(marker, posX, posY, force)
    end
end


local lastWorldPaneWidth = 0
local lastWorldPaneHeight = 0
---@type table<string, markerLib.markerContainer>
local worldMarkerPositionMap = {}

function this.createWorldMarkers()
    lastActiveMenu = this.activeMenu
    if table.size(this.waitingToCreate_world) == 0 then return end

    local menu = tes3ui.findMenu("MenuMap")
    if not menu then return end
    local worldMap = menu:findChild("MenuMap_world")
    if not worldMap then return end
    local worldPane = worldMap:findChild("MenuMap_world_pane")
    if not worldPane then return end

    local widthPerPix = worldPane.width / worldWidth
    local heightPerPix = worldPane.height / worldHeight

    table.clear(worldMarkerPositionMap)
    for id, data in pairs(this.activeWorldMarkers) do
        local pos = data.position
        if pos then
            local mapId = tostring(math.floor(pos.x / 48))..","..tostring(math.floor(pos.y / 48))
            worldMarkerPositionMap[mapId] = data
        end
    end

    for markerId, data in pairs(this.waitingToCreate_world) do
        local record = this.records[data.recordId]

        if not record then goto continue end

        local pos = data.position
        local parentData = worldMarkerPositionMap[tostring(math.floor(pos.x / 48))..","..tostring(math.floor(pos.y / 48))]

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
            local x = (cellWidthMinPart + pos.x) * widthPerPix
            local y = (-cellHeightMaxPart + pos.y) * heightPerPix

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
            end
        end
        ::continue::
    end

    table.clear(this.waitingToCreate_world)
end

function this.updateWorldMarkers(forceRedraw)
    this.lastWorldUpdate = os.clock()

    local menu = tes3ui.findMenu("MenuMap")
    if not menu then return end
    local worldMap = menu:findChild("MenuMap_world")
    if not worldMap then return end
    local worldPane = worldMap:findChild("MenuMap_world_pane")
    if not worldPane then return end

    if not this.shouldUpdateWorld and not forceRedraw and
            worldPane.width == lastWorldPaneWidth and worldPane.height == lastWorldPaneHeight then
        return
    end

    local widthPerPix = worldPane.width / worldWidth
    local heightPerPix = worldPane.height / worldHeight

    local function removeMarker(id, marker)
        this.deleteMarkerElement(marker)
        this.activeWorldMarkers[id] = nil
    end

    for id, data in pairs(this.activeWorldMarkers) do
        if this.markersToRemove[id] then
            removeMarker(id, data.marker)
            goto continue
        end

        for recordId, element in pairs(data.items) do
            if checkConditionsToRemoveMarkerElement(element, data) then
                data.items[recordId] = nil
                break
            end
        end

        if table.size(data.items) == 0 then
            removeMarker(id, data.marker)
            goto continue
        end

        local pos = data.position

        local x = (cellWidthMinPart + pos.x) * widthPerPix
        local y = (-cellHeightMaxPart + pos.y) * heightPerPix

        changeMarker(data.marker, x, y, forceRedraw)

        ::continue::
    end
    this.shouldUpdateWorld = false
end

---@param data markerLib.markerData
function this.addWorldMarkerFromMarkerData(data)
    this.waitingToCreate_world[data.id] = data
end


---@param marker tes3uiElement
function this.deleteMarkerElement(marker)
    marker.visible = false
    this.markerElementsToDelete[marker] = true
end

function this.removeDeletedMarkers()
    for marker, _ in pairs(this.markerElementsToDelete) do
        marker:destroy()
    end
    table.clear(this.markerElementsToDelete)
end

---@param cellEditorName string|nil
function this.registerMarkersForCell(cellEditorName)
    if not this.localMap then return end

    if not cellEditorName then cellEditorName = allMapLabelName end

    for id, data in pairs(this.localMap[cellEditorName] or {}) do
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
    local menu = tes3ui.findMenu("MenuMap")
    if not menu then return false end

    menu:updateLayout()
    return true
end


function this.reset()
    lastCell = nil
    lastActiveMenu = nil
    lastWorldPaneWidth = 0
    lastWorldPaneHeight = 0
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