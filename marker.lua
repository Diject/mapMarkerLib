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


local allMapLabelName = "__all_map__"

local this = {}

this.lastLocalUpdate = 0

local storageData

---@type table<string, table<string, markerLib.addLocalMarker.params>>
this.localMap = nil
this.records = nil
this.world = nil

---@type table<string, table<string, markerLib.addLocalMarker.params>>
this.cachedFloatMarkerData = {}
---@type table<string, boolean>
this.cachedCells = {}
---@type table<tes3reference, markerLib.floatingMarker> by ObjectId
this.floatingMarkers = {}
this.hasFloatMarkers = false

---@class markerLib.floatingMarker
---@field id string
---@field markerId string
---@field x number|nil
---@field y number|nil
---@field z number|nil
---@field trackedRef tes3reference|nil
---@field marker tes3uiElement|nil

---@class markerLib.markerRecord
---@field path string texture path relative to Data Files\Textures
---@field width integer|nil texture width
---@field height integer|nil texture height
---@field textureShiftX integer|nil
---@field textureShiftY integer|nil
---@field scale number|nil
---@field name string|nil
---@field description string|nil
---@field color number[]|nil {r, g, b} [0, 1]
---@field isTemporary boolean|nil

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
    this.localMap = storageData.map
    this.records = storageData.records
    this.world = storageData.world

    this.cachedFloatMarkerData = {}
    this.cachedCells = {}
    this.floatingMarkers = {}

    for id, record in pairs(this.records) do
        if record.isTemporary then
            this.records[id] = nil
        end
    end

    for cellId, dt in pairs(this.localMap) do
        for mrkId, data in pairs(dt) do
            local record = this.records[data.id]
            if not record or data.temporary then
                dt[mrkId] = nil
                goto continue
            end

            ::continue::
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
---@field id string
---@field x number|nil
---@field y number|nil
---@field z number|nil
---@field cellName string|nil should be nil if the cell is exterior
---@field objectId string|nil should be lower
---@field temporary boolean|nil
---@field trackedRef tes3reference|nil

---@param params markerLib.addLocalMarker.params
---@return string|nil, string|nil ret returns record id and cell id if added. Or nil if not
function this.addLocal(params, temp)
    if not this.localMap then return end

    local cellName
    if params.x and params.y or params.cellName then
        cellName = params.cellName or getExCellName(params.x, params.y)
    else
        cellName = allMapLabelName
    end
    cellName = cellName:lower()

    if not this.localMap[cellName] then
        this.localMap[cellName] = {}
    end

    local id = getId()

    this.localMap[cellName][id] = {
        x = params.x,
        y = params.y,
        z = params.z,
        id = params.id,
        objectId = params.objectId,
        temporary = params.temporary,
        trackedRef = params.trackedRef,
        temp = temp
    }

    log("added marker \"", id, "\" to \"", cellName, "\" cell", this.localMap[cellName][id])

    return id, cellName
end

---@param id string marker id
---@param cellId string id of cell where marker was placed
---@return boolean ret returns true if the marker is found and removed. Or false if not found
function this.removeLocal(id, cellId)
    local cellData = this.localMap[cellId] or {}
    local marker = cellData[id]
    if marker then
        cellData[id] = nil
        return true
    end
    return false
end

---@class markerLib.addWorldMarker.params
---@field id string
---@field x number
---@field y number

---@param params markerLib.addWorldMarker.params
---@return string|nil ret returns marker id if added. Or nil if not
function this.addWorld(params)
    if not this.world then return end

    local id = getId()

    this.world[id] = {
        x = params.x,
        y = params.y,
        id = params.id,
    }

    return id
end

---@param id string marker id
---@return boolean ret returns true if the marker is found and removed. Or false if not found
function this.removeWorld(id)
    local marker = this.world[id]
    if marker then
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
    ---@type markerLib.markerRecord
    local record = {path = texturePath}

    if not texture then return end
    record.width = texture.width
    record.height = texture.height

    record.textureShiftX = params.textureShiftX or record.width / 2
    record.textureShiftY = params.textureShiftY or record.height / 2

    record.name = params.name
    record.description = params.description
    record.isTemporary = params.isTemporary
    record.color = params.color
    record.scale = params.scale

    if not id then
        id = getId()
    elseif not this.records[id] then
        return
    end

    this.records[id] = record

    return id
end

---@param id string record id
---@return boolean ret returns true if the record is found and removed. Or false if not found
function this.removeRecord(id)
    local rec = this.records[id]
    if rec then
        this.records[id] = nil
        return true
    end
    return false
end

---@return table<string, markerLib.addLocalMarker.params>
function this.getCellData(cellName)
    if cellName then
        return this.localMap[cellName:lower()]
    else
        return this.localMap[allMapLabelName]
    end
end

---@param pane tes3uiElement
---@param record markerLib.markerRecord
---@return tes3uiElement|nil
local function drawMarker(pane, x, y, record)
    if not pane or not record then return end

    if pane.width < x or x < 0 or pane.height < -y or y > 0 then return end

    local image = pane:createImage{id = markerLabelId, path = record.path}

    image.autoHeight = true
    image.autoWidth = true
    image.absolutePosAlignX = -32668
    image.absolutePosAlignY = -32668
    image.imageScaleX = record.scale or 1
    image.imageScaleY = record.scale or 1
    image.positionX = x + (record.textureShiftX or -record.width / 2)
    image.positionY = y + (record.textureShiftY or record.height / 2)
    image.color = record.color or {1, 1, 1}

    image:setLuaData("records", {record})

    image:register(tes3.uiEvent.help, function (e)
        if not e.source then return end
        local luaData = e.source:getLuaData("records")
        if not luaData then return end

        local tooltip = tes3ui.createTooltipMenu()

        local blockCount = 0
        for i, rec in pairs(luaData) do
            if not rec.name and not rec.description then goto continue end

            local block = tooltip:createBlock{id = tooltipBlock}
            block.flowDirection = tes3.flowDirection.topToBottom
            block.autoHeight = true
            block.autoWidth = true
            block.maxWidth = 250
            block.borderBottom = 3

            blockCount = blockCount + 1

            if rec.name then
                local label = block:createLabel{id = tooltipName, text = rec.name}
                label.autoHeight = true
                label.autoWidth = true
                label.maxWidth = 250
                label.wrapText = true
                label.justifyText = tes3.justifyText.center
            end

            if rec.description then
                local label = block:createLabel{id = tooltipDescription, text = rec.description}
                label.autoHeight = true
                label.autoWidth = true
                label.maxWidth = 250
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

---@param markerEl tes3uiElement
---@param record markerLib.markerRecord
---@return tes3uiElement|nil
local function changeMarkerPosition(markerEl, x, y, record)
    markerEl.positionX = x - record.width / 2
    markerEl.positionY = y + record.height / 2
end

---@param markerElement tes3uiElement
---@param recordToAdd markerLib.markerRecord
local function addInfoToMarker(markerElement, recordToAdd)
    if not markerElement or not recordToAdd then return end

    local luaData = markerElement:getLuaData("records")
    if luaData then
        table.insert(luaData, recordToAdd)
        markerElement:setLuaData("records", luaData)
    end
end

local lastLocalMarkerPosX = 99999999
local lastLocalMarkerPosY = 99999999
local lastPosX = 99999999
local lastPosY = 99999999
local lastCellInteriorFlag = nil
local axisAngle = 0
local isSmallMenu

function this.drawLocaLMarkers(forceRedraw, updateMenu)
    local menu = tes3ui.findMenu("MenuMap")
    if not menu then return end

    local localPane
    local playerMarker

    local shouldUpdate = forceRedraw and true or false
    local removeOldMarkers = false

    if menu.visible then
        if isSmallMenu ~= false then
            removeOldMarkers = true
            shouldUpdate = true
        end
        isSmallMenu = false
        local localMap = menu:findChild("MenuMap_local")
        if not localMap then return end
        localPane = localMap:findChild("MenuMap_pane")
        if not localPane then return end
        playerMarker = localPane:findChild("MenuMap_local_player")
        if not playerMarker then return end
    else
        if isSmallMenu ~= true then
            removeOldMarkers = true
            shouldUpdate = true
        end
        isSmallMenu = true
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
    end

    local playerPos = tes3.player.position
    local playerCell = tes3.player.cell

    this.lastLocalUpdate = os.clock()

    if math.abs(playerMarker.positionX - lastLocalMarkerPosX) > 500 or math.abs(playerMarker.positionY - lastLocalMarkerPosY) > 500 then
        shouldUpdate = true
    end
    lastLocalMarkerPosX = playerMarker.positionX
    lastLocalMarkerPosY = playerMarker.positionY

    if lastCellInteriorFlag ~= playerCell.isInterior then
        removeOldMarkers = true
        axisAngle = 0
        if playerCell.isInterior then
            for ref in playerCell:iterateReferences(tes3.objectType.static) do
                if ref.id:lower() == "northmarker" then
                    axisAngle = ref.orientation.z
                end
            end
        end
        shouldUpdate = true
    end
    if not playerCell.isInterior then
        if math.abs(lastPosX - playerPos.x) > 8192 or math.abs(lastPosY - playerPos.y) > 8192 then
            shouldUpdate = true
        end
        lastPosX = playerPos.x
        lastPosY = playerPos.y
    else
        if math.abs(lastPosX - playerPos.x) > 512 or math.abs(lastPosY - playerPos.y) > 512 then
            shouldUpdate = true
            lastPosX = playerPos.x
            lastPosY = playerPos.y
        end
    end
    lastCellInteriorFlag = playerCell.isInterior

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

    if removeOldMarkers then
        this.removeFloatMarkersBindings()
    end

    local function updateDunamicMarkers()
        for ref, data in pairs(this.floatingMarkers) do
            if not data.marker then goto continue end

            local markerRecord = this.records[data.id]
            if not markerRecord then
                data.marker:destroy()
                this.floatingMarkers[ref] = nil
                goto continue
            end

            local position = ref.position
            data.x = position.x
            data.y = position.y
            data.z = position.z

            if playerCell.isInterior then
                    local xShift = (data.x - playerPos.x)
                    local yShift = (playerPos.y - data.y)

                    local posXNorm = xShift * math.cos(axisAngle) + yShift * math.sin(axisAngle)
                    local posYNorm = yShift * math.cos(axisAngle) - xShift * math.sin(axisAngle)

                    local posX = playerMarkerX + posXNorm / widthPerPix
                    local posY = playerMarkerY - posYNorm / heightPerPix

                    if math.abs(data.marker.positionX - posX) > 2 or math.abs(data.marker.positionY - posY) > 2 then
                        changeMarkerPosition(data.marker, posX, posY, markerRecord)
                    end
            else
                local posX = (offsetX + 1 + math.floor(data.x / 8192) - math.floor(playerPos.x / 8192) + (data.x % 8192) / 8192) * tileWidth
                local posY = -(-offsetY + 2 - (math.floor(data.y / 8192) - math.floor(playerPos.y / 8192) + (data.y % 8192) / 8192)) * tileHeight

                if math.abs(data.marker.positionX - posX) > 2 or math.abs(data.marker.positionY - posY) > 2 then
                    changeMarkerPosition(data.marker, posX, posY, markerRecord)
                end
            end

            ::continue::
        end
    end

    updateDunamicMarkers()

    if not shouldUpdate then
        if updateMenu then
            menu:updateLayout()
        end
        return
    end

    local markerMap = {}

    ---@type table<integer, tes3uiElement>
    local childrens = {}
    for _, child in pairs(localPane.children) do
        if child.name == markerLabelId then
            if removeOldMarkers then
                child:destroy()
            else
                local ids = child:getLuaData("ids")
                if ids then
                    for _, id in pairs(ids) do
                        childrens[id] = child
                    end
                else
                    child:destroy()
                end
            end
        end
    end

    if not playerCell.isInterior then
        local sX = -2
        local eX = 2
        local sY = -2
        local eY = 2

        local allowedError = 8

        local function placeMarker(markerRecord, markerId, markerData, combine)
            -- local posX = (offsetX + i + 1 + (markerData.x % 8192) / 8192) * tileWidth
            local posX = (offsetX + 1 + math.floor(markerData.x / 8192) - math.floor(playerPos.x / 8192) + (markerData.x % 8192) / 8192) * tileWidth
            -- local posY = -(-offsetY + 2 - (j + (markerData.y % 8192) / 8192)) * tileHeight
            local posY = -(-offsetY + 2 - (math.floor(markerData.y / 8192) - math.floor(playerPos.y / 8192) + (markerData.y % 8192) / 8192)) * tileHeight

            local markerMapId = tostring(math.floor(posX / 3))..","..tostring(math.floor(posY / 3))
            local marker = combine and markerMap[markerMapId] or nil

            local foundEl = childrens[markerId]
            childrens[markerId] = nil

            if foundEl then
                if math.abs(foundEl.positionX - posX) > allowedError or math.abs(foundEl.positionY - posY) > allowedError then
                    changeMarkerPosition(foundEl, posX, posY, markerRecord)
                end
                if combine then
                    markerMap[markerMapId] = foundEl
                end
                return
            end

            if marker then
                addInfoToMarker(marker, markerRecord)
                local ids = marker:getLuaData("ids")
                if not ids then
                    ids = {markerId}
                else
                    table.insert(ids, markerId)
                end
                marker:setLuaData("ids", ids)
            else
                marker = drawMarker(localPane, posX, posY, markerRecord)
                if marker then
                    marker:setLuaData("ids", {markerId})
                    markerMap[markerMapId] = marker
                end
            end

            markerData.marker = marker
        end

        for i = sX, eX do
            for j = sY, eY do
                local cellData = this.getCellData(getExCellName(playerPos.x + i * 8192, playerPos.y + j * 8192))

                for id, data in pairs(cellData or {}) do
                    local markerRecord = this.records[data.id]
                    if not markerRecord then
                        cellData[id] = nil
                        goto continue
                    end

                    if markerRecord.objectId or data.trackedRef then goto continue end

                    placeMarker(markerRecord, id, data, true)

                    ::continue::
                end
            end
        end

        for ref, data in pairs(this.floatingMarkers) do
            if data.marker then
                childrens[data.markerId] = nil
                goto continue
            end

            local markerRecord = this.records[data.id]
            if not markerRecord then
                this.floatingMarkers[ref] = nil
                goto continue
            end

            local position = ref.position
            data.x = position.x
            data.y = position.y
            data.z = position.z
            placeMarker(markerRecord, data.markerId, data, false)

            ::continue::
        end

        -- remove all unfound markers
        for id, child in pairs(childrens) do
            child:destroy()
        end

    else -- for interior cells

        local cellData = this.getCellData(playerCell.editorName)
        local allowedError = 8

        local function placeMarker(markerRecord, markerId, markerData, combine)
            local xShift = (markerData.x - playerPos.x)
            local yShift = (playerPos.y - markerData.y)

            local posXNorm = xShift * math.cos(axisAngle) + yShift * math.sin(axisAngle)
            local posYNorm = yShift * math.cos(axisAngle) - xShift * math.sin(axisAngle)

            local posX = playerMarkerX + posXNorm / widthPerPix
            local posY = playerMarkerY - posYNorm / heightPerPix

            local markerMapId = tostring(math.floor(markerData.x / 3))..","..tostring(math.floor(markerData.y / 3))
            local marker = combine and markerMap[markerMapId] or nil

            local foundEl = childrens[markerId]
            childrens[markerId] = nil

            if foundEl then
                if math.abs(foundEl.positionX - posX) > allowedError or math.abs(foundEl.positionY - posY) > allowedError then
                    changeMarkerPosition(foundEl, posX, posY, markerRecord)
                end
                if combine then
                    markerMap[markerMapId] = foundEl
                end
                return
            end

            if marker then
                addInfoToMarker(marker, markerRecord)
                local ids = marker:getLuaData("ids")
                if not ids then
                    ids = {markerId}
                else
                    table.insert(ids, markerId)
                end
                marker:setLuaData("ids", ids)
            else
                marker = drawMarker(localPane, posX, posY, markerRecord)
                if marker then
                    marker:setLuaData("ids", {markerId})
                    markerMap[markerMapId] = marker
                end
            end

            markerData.marker = marker
        end

        for id, data in pairs(cellData or {}) do
            local markerRecord = this.records[data.id]
            if not markerRecord then
                cellData[id] = nil
                goto continue
            end

            if markerRecord.objectId or data.trackedRef then goto continue end

            placeMarker(markerRecord, id, data, true)

            ::continue::
        end

        for ref, data in pairs(this.floatingMarkers) do
            if data.marker then
                childrens[data.markerId] = nil
                goto continue
            end

            local markerRecord = this.records[data.id]
            if not markerRecord then
                this.floatingMarkers[ref] = nil
                goto continue
            end

            local position = ref.position
            data.x = position.x
            data.y = position.y
            data.z = position.z
            placeMarker(markerRecord, data.markerId, data, false)

            ::continue::
        end

        -- remove all unfound markers
        for id, child in pairs(childrens) do
            child:destroy()
        end

    end

    if updateMenu then
        menu:updateLayout()
    end
end

local lastWorldPaneWidth = 0
local lastWorldPaneHeight = 0

function this.drawWorldMarkers(forceRedraw)
    local menu = tes3ui.findMenu("MenuMap")
    if not menu then return end
    local worldMap = menu:findChild("MenuMap_world")
    if not worldMap then return end
    local worldPane = worldMap:findChild("MenuMap_world_pane")
    if not worldPane then return end

    if not forceRedraw and worldPane.width == lastWorldPaneWidth and worldPane.height == lastWorldPaneHeight then
        return
    end
    lastWorldPaneWidth = worldPane.width
    lastWorldPaneHeight = worldPane.height

    for _, child in pairs(worldPane.children) do
        if child.name == markerLabelId then
            child:destroy()
        end
    end

    local widthPerPix = worldPane.width / worldWidth
    local heightPerPix = worldPane.height / worldHeight

    local markerMap = {}

    for id, markerData in pairs(this.world or {}) do
        local markerRecord = this.records[markerData.id]
        if not markerRecord then
            this.world[id] = nil
            goto continue
        end

        local x = (cellWidthMinPart + markerData.x) * widthPerPix
        local y = (-cellHeightMaxPart + markerData.y) * heightPerPix

        local markerMapId = tostring(math.floor(x / 3))..","..tostring(math.floor(y / 3))
        local marker = markerMap[markerMapId]

        if marker then
            addInfoToMarker(marker, markerRecord)
        else
            marker = drawMarker(worldPane, x, y, markerRecord)
            if marker then
                markerMap[markerMapId] = marker
            end
        end

        ::continue::
    end
end

---@class markerLib.addFloatingLocal.params
---@field ref tes3reference
---@field id string marker record id

---@param params markerLib.addFloatingLocal.params
function this.addFloatingLocal(params)
    local id = getId()

    this.floatingMarkers[params.ref] = {
        id = params.id,
        markerId = id,
        trackedRef = params.ref,
    }
end


---@param cellEditorName string|nil
function this.cacheDataOfTrackingObjects(cellEditorName)
    if not cellEditorName then cellEditorName = allMapLabelName end
    if this.cachedCells[cellEditorName] then return end

    local cellData = this.getCellData(cellEditorName)
    for id, data in pairs(cellData or {}) do
        local markerRecord = this.records[data.id]
        if not markerRecord then
            cellData[id] = nil
        elseif data.objectId then
            if not this.cachedFloatMarkerData[data.objectId] then
                this.cachedFloatMarkerData[data.objectId] = {}
            end
            this.cachedFloatMarkerData[data.objectId][id] = data
        elseif data.trackedRef then
            if not this.cachedFloatMarkerData[data.trackedRef] then
                this.cachedFloatMarkerData[data.trackedRef] = {}
            end
            this.cachedFloatMarkerData[data.trackedRef][id] = data
        end
    end

    this.cachedCells[cellEditorName] = true
    this.hasFloatMarkers = not (next(this.cachedFloatMarkerData) == nil)
end

function this.clearCache()
    this.cachedFloatMarkerData = {}
    this.hasFloatMarkers = false
    this.cachedCells = {}
end

function this.removeFloatMarkersBindings()
    for _, data in pairs(this.floatingMarkers) do
        data.marker = nil ---@diagnostic disable-line: inject-field
    end
end

---@param ref tes3reference
function this.checkRefForMarker(ref)
    if not ref then return end
    if not ref or ref.disabled or ref.object.objectType == tes3.objectType.static or not ref.cell then return end

    if not this.isReady() then
        this.init()
    end

    local cellName = ref.cell.editorName:lower()

    this.cacheDataOfTrackingObjects()
    this.cacheDataOfTrackingObjects(cellName)

    local function addMarker(objData)
        if not objData then return end
        for markerId, data in pairs(objData) do
            this.addFloatingLocal{ id = data.id, ref = ref }
        end
    end

    local objData = this.cachedFloatMarkerData[ref.baseObject.id:lower()]
    addMarker(objData)
    objData = this.cachedFloatMarkerData[ref]
    addMarker(objData)
end

---@param ref tes3reference
function this.removeRefFromCachedData(ref)
    if not ref then return end

    this.cachedFloatMarkerData[ref] = nil
    this.cachedFloatMarkerData[ref.baseObject.id:lower()] = nil

    this.hasFloatMarkers = not (next(this.cachedFloatMarkerData) == nil)
end

function this.updateCachedData()
    if not tes3.player then return end
    local playerCell = tes3.player.cell
    this.clearCache()
    if playerCell.isInterior then
        this.cacheDataOfTrackingObjects(playerCell.editorName:lower())
    else
        for _, cellData in pairs(tes3.dataHandler.exteriorCells) do
            this.cacheDataOfTrackingObjects(cellData.cell.editorName:lower())
        end
    end
end

function this.createMarkersForAllTrackedRefs()
    if not tes3.player then return end
    local playerCell = tes3.player.cell
    if playerCell.isInterior then
        for ref in playerCell:iterateReferences() do
            if ref.objectType == tes3.objectType.static then goto continue end

            this.checkRefForMarker(ref)

            ::continue::
        end
    else
        for _, cellData in pairs(tes3.dataHandler.exteriorCells) do
            for ref in cellData.cell:iterateReferences() do
                if ref.objectType == tes3.objectType.static then goto continue end

                this.checkRefForMarker(ref)

                ::continue::
            end
        end
    end
end

function this.reset()
    lastWorldPaneWidth = 0
    lastWorldPaneHeight = 0
    lastLocalMarkerPosX = 99999999
    lastLocalMarkerPosY = 99999999
    lastPosX = 99999999
    lastPosY = 99999999
    lastCellInteriorFlag = nil
    axisAngle = 0
    isSmallMenu = nil

    storageData = nil
    this.localMap = nil
    this.records = nil
    this.world = nil
    this.cachedFloatMarkerData = {}
    this.cachedCells = {}
    this.floatingMarkers = {}
    this.hasFloatMarkers = false
end

return this