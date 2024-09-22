local ffi = require("ffi")
ffi.cdef [[
    typedef struct {
        void* vtable;
        int refCount;
        unsigned int format;
        unsigned int channelMasks[4];
        unsigned int bitsPerPixel;
        unsigned int compareBits[2];
        void* palette;
        unsigned char* pixels;
        unsigned int* widths;
        unsigned int* heights;
        unsigned int* offsets;
        unsigned int mipMapLevels;
        unsigned int bytesPerPixel;
        unsigned int revisionID;
    } NiPixelData;
]]

local mcp_mapExpansion = tes3.hasCodePatchFeature(tes3.codePatchFeature.mapExpansionForTamrielRebuilt)

local this = {}

-- local widthPerCell = mcp_mapExpansion and 512 / (51 + 51 + 1) or 512 / (28 + 28 + 1)
-- local heightPerCell = mcp_mapExpansion and 512 / (64 + 38 + 1) or 512 / (64 + 38 + 1)
this.cellWidth = mcp_mapExpansion and 5 or 9
this.cellHeight = mcp_mapExpansion and 5 or 9
this.minCellGridX = mcp_mapExpansion and -51 or -28
this.minCellGridY = mcp_mapExpansion and -64 or -28
this.maxCellGridX = mcp_mapExpansion and 51 or 28
this.maxCellGridY = mcp_mapExpansion and 38 or 28
this.mapGridWidth = mcp_mapExpansion and 103 or 57
this.mapGridHeight = mcp_mapExpansion and 103 or 57

local leftOffset = 1
local topOffset = 2

---@class world_map_marker.drawMarker.params
---@field pixelData niPixelData
---@field gridX integer
---@field gridY integer
---@field markerHeight integer
---@field markerWidth integer
---@field markerPixels table<integer>
---@field withAlpha boolean|nil
---@field centered boolean|nil

---@param params world_map_marker.drawMarker.params
---@return boolean
function this.drawMarker(params)
    local pixelData = params.pixelData
    local bytesPerPixel = params.pixelData.bytesPerPixel
    local ptr = mwse.memory.convertFrom.niObject(pixelData) ---@diagnostic disable-line
    local pixelDataFFI = ffi.cast("NiPixelData*", ptr)[0]

    local offsetX = params.centered and math.floor(params.markerWidth / 2) or 0
    local offsetY = params.centered and math.floor(params.markerHeight / 2) or 0

    local sX = math.floor(leftOffset + (-1 * this.minCellGridX + params.gridX - offsetX) * this.cellWidth + 0.5)
    if sX < 0 then sX = 0 end
    local eX = sX + params.markerWidth
    local sY = math.floor(topOffset + (this.maxCellGridY + -1 * params.gridY - offsetY) * this.cellHeight + 0.5)
    if sY < 0 then sY = 0 end
    local eY = sY + params.markerHeight
    local pixelPtr = 1

    for y = sY, eY - 1 do
        for x = sX, eX - 1 do
            local i = (y * 512 + x) * bytesPerPixel
            local r = params.markerPixels[pixelPtr]
            local g = params.markerPixels[pixelPtr + 1]
            local b = params.markerPixels[pixelPtr + 2]
            pixelPtr = pixelPtr + 3
            if params.withAlpha then
                local a = params.markerPixels[pixelPtr]
                pixelPtr = pixelPtr + 1
                pixelDataFFI.pixels[i] = pixelDataFFI.pixels[i] * (1 - a) + r * a
                pixelDataFFI.pixels[i + 1] = pixelDataFFI.pixels[i + 1] * (1 - a) + g * a
                pixelDataFFI.pixels[i + 2] = pixelDataFFI.pixels[i + 2] * (1 - a) + b * a
            else
                pixelDataFFI.pixels[i] = r
                pixelDataFFI.pixels[i + 1] = g
                pixelDataFFI.pixels[i + 2] = b
            end
        end
    end

    return true
end

---@param pixelData niPixelData
---@return niPixelData
function this.newPixelData(pixelData, width, height)
    local oldPtr = mwse.memory.convertFrom.niObject(pixelData) ---@diagnostic disable-line
    local pixelDataFFI = ffi.cast("NiPixelData*", oldPtr)[0]
    local new = niPixelData.new(width, height, pixelData.mipMapLevels)
    local newPtr = mwse.memory.convertFrom.niObject(new) ---@diagnostic disable-line
    local newPixelDataFFI = ffi.cast("NiPixelData*", newPtr)[0]
    if pixelData.bytesPerPixel == 3 then
        for i = 0, width * height - 1 do
            newPixelDataFFI.pixels[i * 4] = pixelDataFFI.pixels[i * 3 + 0]
            newPixelDataFFI.pixels[i * 4 + 1] = pixelDataFFI.pixels[i * 3 + 1]
            newPixelDataFFI.pixels[i * 4 + 2] = pixelDataFFI.pixels[i * 3 + 2]
            newPixelDataFFI.pixels[i * 4 + 3] = 255
        end
    else
        ffi.copy(newPixelDataFFI.pixels, pixelDataFFI.pixels, ffi.sizeof("char") * width * height * pixelData.bytesPerPixel)
    end
    return new
end

return this