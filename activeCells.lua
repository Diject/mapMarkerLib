local this = {}

---@type table<string, boolean> active cells. by cell editor name
this.validCellNames = {}

---@param cell tes3cell
---@return boolean
function this.isCellActive(cell)
    return this.validCellNames[cell.editorName] or false
end

---@param cellName string
---@return boolean
function this.isCellActiveByName(cellName)
    return this.validCellNames[cellName] or false
end

---@param cell tes3cell
function this.registerCell(cell)
    this.validCellNames[cell.editorName] = true
end

---@param cell tes3cell
function this.unregisterCell(cell)
    this.validCellNames[cell.editorName] = nil
end

return this