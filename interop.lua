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

---@param updateImages boolean|nil if true, images on markers will be forced to update
function this.updateWorldMarkers(updateImages)
    markers.createWorldMarkers()
    markers.updateWorldMarkers(updateImages)
end

---@param updateImages boolean|nil if true, images on markers will be forced to update 
function this.updateLocalMarkers(updateImages)
    markers.createLocalMarkers()
    markers.updateLocalMarkers(updateImages)
end

function this.updateMapMenu()
    markers.updateMapMenu()
end

return this