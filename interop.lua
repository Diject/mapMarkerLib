local markers = include("diject.map_markers.marker")

local this = {}

---@param params markerLib.addLocalMarker.params
---@return string|nil, string|nil ret returns record id and cell id if added. Or nil if not
function this.addLocalMarker(params)
    local ret = markers.addLocal(params)
    return ret
end

---@param id string marker id
---@param cellId string id of cell where marker was placed
---@return boolean ret returns true if the marker is found and removed. Or false if not found
function this.removeLocalMarker(id, cellId)
    local ret = markers.removeLocal(id, cellId)
    return ret
end

---@param params markerLib.addWorldMarker.params
---@return string|nil ret returns marker id if added. Or nil if not
function this.addWorldMarker(params)
    return markers.addWorld(params)
end

---@param id string marker id
---@return boolean ret returns true if the marker is found and removed. Or false if not found
function this.removeWorldMarker(id)
    return markers.removeWorld(id)
end

---@param params markerLib.markerRecord
---@return string|nil ret returns record id if added. Or nil if not
function this.addRecord(params)
    return markers.addRecord(nil, params)
end

---@param id string record id
---@param params markerLib.markerRecord
---@return string|nil ret returns record id if found and updated. Or nil if not
function this.updateRecord(id, params)
    return markers.addRecord(id, params)
end

---Returns record data. You can change the data on the fly. Dangerous method!!!
---@param id string
---@return markerLib.markerRecord|nil
function this.getRecord(id)
    return markers.getRecord(id)
end

---@param id string record id
---@return boolean ret returns true if the record found and removed. Or false if unfound
function this.removeRecord(id)
    return markers.removeRecord(id)
end

---@class markerLib.interop.updateLocalMarkers.params
---@field recreate boolean|nil if true, markers will be removed and created again. Otherwise it will just update their positions
---@field updateMenu boolean|nil if true, the map menu will be updated after the markers are updated. Default: true

---@param params markerLib.interop.updateLocalMarkers.params|nil
function this.updateLocalMarkers(params)
    if not params then params = {} end
    params.updateMenu = params.updateMenu == true and true or false
    markers.updateCachedData()
    markers.createMarkersForAllTrackedRefs()
    markers.drawLocaLMarkers(true, params.updateMenu, params.recreate)
end

function this.updateWorldMarkers()
    markers.drawWorldMarkers(true)
end

return this