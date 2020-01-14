-- Imports WorldCreator scene thrugh Bridge Export data
-- works only on Windows (executes .bat batch files)
-- Requires ImageMagick installed (https://imagemagick.org/script/download.php) [install it anywhere and fill the correct path below]
-- Requires xml2lua XML parser (https://github.com/manoelcampos/Xml2Lua) [install it anywhere and fill the correct path below]
-- The code that creates the plane is extracted from the internal Octane primitives code by OTOY (version 1.2.1214)
--
-- 	@script-id 		WC2Octane
--  @description    Imports WorldCreator scene thrugh Bridge Export data
--  @author         Luca Malisan - www.malisan.it
--  @version        0.3
--  @shortcut       alt + w

------------------------------------------------------------------------------
-- CONFIGURATION: Fill these 2 lines with the absolute path to your imageMagick executable and xml2lua package istall folder
-- OPTIONAL: change the nodeNamePrefix variable to the name you prefer for the created subgraph
------------------------------------------------------------------------------
local imageMagickPath = [[C:\Program Files\ImageMagick-7.0.8-Q16\magick.exe]]  -- FULL PATH to the ImageMagick executable
local xml2luaPath = 	[[X:\Impostazioni\Octane\xml2lua\]]	-- FULL PATH to the folder of the xml2lua package (WITH trailing "\")
local nodeNamePrefix = "WC_Terrain"
------------------------------------------------------------------------------
-- END OF CONFIGURATION: Don't change below this line
------------------------------------------------------------------------------


package.path = xml2luaPath..'?.lua;' .. package.path
local xml2lua = require("xml2lua")
local tree = require("xmlhandler.tree")
local handler = tree:new()

-- Function to create material for each texture
local function populateMaterialData(tn,mi,st)
	materials[#materials+1] = {
		name = st.Name,
		splatFileName = tn,
		splatChannelIndex = mi-1,
		metallic=st.Metallic,
		roughness=1-st.Smoothness,
		textureFileName = st.FileName
	}
	materials[#materials]["scaleX"],materials[#materials]["scaleY"] = string.match(st.TileSize, "([%d.-]+),([%d.-]+)")
	materials[#materials]["ColorR"],materials[#materials]["ColorG"],materials[#materials]["ColorB"] = string.match(st.Color, "([%d.-]+), ([%d.-]+), ([%d.-]+)")
end

-- show the user a file chooser
result = octane.gui.showDialog
{
    type      = octane.gui.dialogType.FILE_DIALOG,
    title     = "Choose bridge.xml file",
    wildcards = "*.xml",
    save      = false ,
	path	  = octane.storage.project.syncToolXMLPath
}
if result.result == "" or not octane.file.exists(result.result) then 
    -- stop the script
    error("Missing bridge.xml")
end
octane.storage.project.syncToolXMLPath = octane.file.getParentDirectory(result.result)

-- Loads the choosen XML file in the XML parser
local xml = xml2lua.loadFile(result.result)
local parser = xml2lua.parser(handler)
parser:parse(xml)


-- definition of plane
plane = {
	name = handler.root.WorldCreator.Project._attr.Name,
	resolutionX = tonumber(handler.root.WorldCreator.Surface._attr.ResolutionX),
	resolutionY = tonumber(handler.root.WorldCreator.Surface._attr.ResolutionY),
	sizeX = tonumber(handler.root.WorldCreator.Surface._attr.Width),
	sizeY = tonumber(handler.root.WorldCreator.Surface._attr.Length),
	height = 100*(tonumber(handler.root.WorldCreator.Surface._attr.MaxHeight)-tonumber(handler.root.WorldCreator.Surface._attr.MinHeight)),
	zshift = tonumber(handler.root.WorldCreator.Surface._attr.MinHeight)
}
plane["subdiv"]= math.ceil(math.max(plane.resolutionX/plane.sizeX,plane.resolutionY/plane.sizeY))
-- definition of materials
materials = {}
-- Load textures splatmaps
textures = handler.root.WorldCreator.Texturing
if #textures.SplatTexture > 1 then
   textures = textures.SplatTexture
end
for i, t in pairs(textures) do
	if #t.TextureInfo > 1 then
		for k,ti in pairs(t.TextureInfo) do
			populateMaterialData(t._attr.Name,k,ti._attr)
		end
	else
		populateMaterialData(t._attr.Name,1,t.TextureInfo._attr)
	end
end

-- loads the displacement texture. If a tif file isn't found, it converts the raw in tif
heightMapFile = "\\heightmap.tif"
heightMapFile = octane.storage.project.syncToolXMLPath .. heightMapFile
if not octane.file.exists(heightMapFile) then
	local tmpScriptFile = os.tmpname()..".bat"
	local f = assert(io.open(tmpScriptFile, "w"))
	io.open(tmpScriptFile, "w")
	local tmpCommand = string.format([["%s" -depth 16 -size %ix%i GRAY:"%s" -flop "%s"]],imageMagickPath,plane.resolutionX,plane.resolutionY,string.gsub(heightMapFile,"heightmap.tif","heightmap.raw"),heightMapFile)
	f:write(tmpCommand)
    f:close()
	os.execute(tmpScriptFile)
	os.remove(tmpScriptFile)
end

--------------------------------------------
-- HELPER FUNCTIONS START -- code by OTOY (version 1.2.1214)-----------
--------------------------------------------
-- check if a file exists
function file_exists(name)
   local f=io.open(name,"r")
   if f~=nil then io.close(f) return true else return false end
end
-- Returns the number of segments in each dimensions for an homogenous tesselation.
-- Smallest dimension gets 2^level divisions.
-- The other dimension gets a number of segments such that the quads are as square as possible.
local function subdivideRectangle(width, height, level)

	-- Return the number of segments with `a` being the smallest dimension.
	local function getSegments(a, b)

		if a == 0 or b == 0 then
			return 1, 1
		end

		local ratio = math.max(0.01, math.min(100, b/a))

		local aSegments = math.pow(2, level)
		local bSegments = math.floor(aSegments * ratio + 0.5)

		return aSegments, bSegments
	end

	if width <= height then
		local a, b = getSegments(width, height)
		return a, b
	else
		local a, b = getSegments(height, width)
		return b, a
	end
end
	
-- Insert multiple values in a table
local function tableInsertVariadic(array, ...)
	for _, v in ipairs({...}) do
		table.insert(array, v)
	end
end
-- Append the content of t2 to t1
local function tableConcat(t1, t2)
	for i=1, #t2 do
		t1[#t1+1] = t2[i]
	end
	return t1
end
--------------------------------------------
-- Create triangles from a lattice of vertices.
-- The grid goes from bottom to top, left to right.
local function triangulateGrid(rows, cols, indices, wrapU, mergeTop, mergeBottom)

	local polyVertexIndices = {}
	local polyNormalIndices = {}
	local polyUVWIndices = {}
	local verticesPerPoly = {}

	for i=1, rows do

		local doMergeTop = (i==rows) and mergeTop
		local doMergeBottom = (i==1) and mergeBottom

		for j=1, cols do
			local p1 = indices[i][j] - 1
			local p2 = indices[i][j+1] - 1
			local p3 = indices[i+1][j] - 1
			local p4 = indices[i+1][j+1] - 1

			-- Deduplicate wrapped or merged vertices but keep their UVs.

			if doMergeTop then
				tableInsertVariadic(polyUVWIndices, p1, p2, p4)
			elseif doMergeBottom then
				tableInsertVariadic(polyUVWIndices, p1, p4, p3)
			else
				tableInsertVariadic(polyUVWIndices, p1, p2, p4)
				tableInsertVariadic(polyUVWIndices, p1, p4, p3)
			end

			if (j == cols) and wrapU then
				p2 = indices[i][1] - 1
				p4 = indices[i+1][1] - 1
			end

			if doMergeTop then
				p4 = indices[i+1][1] - 1
				tableInsertVariadic(polyVertexIndices, p1, p2, p4)
				tableInsertVariadic(polyNormalIndices, p1, p2, p4)
				table.insert(verticesPerPoly, 3)
			elseif doMergeBottom then
				p1 = indices[i][1] - 1
				tableInsertVariadic(polyVertexIndices, p1, p4, p3)
				tableInsertVariadic(polyNormalIndices, p1, p4, p3)
				table.insert(verticesPerPoly, 3)
			else
				tableInsertVariadic(polyVertexIndices, p1, p2, p4)
				tableInsertVariadic(polyNormalIndices, p1, p2, p4)
				table.insert(verticesPerPoly, 3)

				tableInsertVariadic(polyVertexIndices, p1, p4, p3)
				tableInsertVariadic(polyNormalIndices, p1, p4, p3)
				table.insert(verticesPerPoly, 3)
			end
		end
	end

	return
	{
		polyVertexIndices = polyVertexIndices,
		polyNormalIndices = polyNormalIndices,
		polyUVWIndices = polyUVWIndices,
		verticesPerPoly = verticesPerPoly
	}
end

----------------------
    -- Add one face of a box. Also used by the plane and quad.
    -- mesh: the current mesh being modified. Contains a collection of tables for indices and values.
    -- uDim: the size and sign in the face-local U direction.
    -- vDim: the size and sign in the face-local V direction.
    -- fDim: the distance and sign of the center of the face from origin.
    -- uIndex: the axis used for the face-local U direction. (1:x, 2:y, 3:z)
    -- vIndex: the axis used for the face-local V direction. (1:x, 2:y, 3:z)
    -- fIndex: the axis used for the distance of the face from origin.
    -- segments: a table of the number of segments to use, indexed by axes.
    -- normals: a table of normals, indexed by faces.
    -- face: a 0-based index in the collection of faces, used for UV.
    -- totalFaces: total number of faces.
local function addPlanarFace(mesh, uDim, vDim, fDim, uIndex, vIndex, fIndex, segments, normals, face, totalFaces)

	local faceIndices = {}

	for i=0, segments[vIndex] do

		local v = i / segments[vIndex]
		local rowIndices = {}

		for j=0, segments[uIndex] do

			local u = j / segments[uIndex]

			local vertex = {0, 0, 0}
			vertex[uIndex] = (u - 0.5) * uDim
			vertex[vIndex] = (v - 0.5) * vDim
			vertex[fIndex] = fDim / 2

			table.insert(mesh.vertices, vertex)
			table.insert(mesh.normals, normals[face + 1])
			table.insert(mesh.uvws, {(face/totalFaces) + (u/totalFaces), v, 0})

			table.insert(rowIndices, #mesh.vertices)
		end

		table.insert(faceIndices, rowIndices)
	end

	local wrapU = false
	local mergeTop = false
	local mergeBottom = false
	local tris = triangulateGrid(segments[vIndex], segments[uIndex], faceIndices, wrapU, mergeTop, mergeBottom)

	tableConcat(mesh.polyVertexIndices, tris.polyVertexIndices)
	tableConcat(mesh.polyNormalIndices, tris.polyNormalIndices)
	tableConcat(mesh.polyUVWIndices, tris.polyUVWIndices)
	tableConcat(mesh.verticesPerPoly, tris.verticesPerPoly)
end
	
		
----------------------
-- Plane or quad.
local function createPlaneMesh(params)

	local horizontalSize = math.max(0, params.width)
	local verticalSize = math.max(0, params.height)
	local plane = params.plane

	local mesh =
	{
		vertices = {},
		normals = {},
		uvws = {},
		polyVertexIndices = {},
		polyNormalIndices = {},
		polyUVWIndices = {},
		verticesPerPoly = {},
	}

	local a, b = subdivideRectangle(horizontalSize, verticalSize, params.subdivLevel)

	if plane == "xz" then
		local segments = {a, 0, b}
		local normals = { {0, 1, 0} }
		addPlanarFace(mesh, horizontalSize, -verticalSize, 0, 1, 3, 2, segments, normals, 0, 1)
	elseif plane == "xy" then
		local segments = {a, b, 0}
		local normals = { {0, 0, 1} }
		addPlanarFace(mesh, horizontalSize, verticalSize, 0, 1, 2, 3, segments, normals, 0, 1)
	end

	return mesh
end
--------------------------------------------
-- Mesh update
--------------------------------------------
local function updateNodeGeometry(mn,meshData)
	mn:setAttribute(octane.attributeId.A_VERTICES, meshData.vertices, false)
	mn:setAttribute(octane.attributeId.A_NORMALS, meshData.normals, false)
	mn:setAttribute(octane.attributeId.A_UVWS, meshData.uvws, false)
	mn:setAttribute(octane.attributeId.A_POLY_VERTEX_INDICES, meshData.polyVertexIndices, false)
	mn:setAttribute(octane.attributeId.A_POLY_NORMAL_INDICES, meshData.polyNormalIndices, false)
	mn:setAttribute(octane.attributeId.A_POLY_UVW_INDICES, meshData.polyUVWIndices, false)
	mn:setAttribute(octane.attributeId.A_VERTICES_PER_POLY, meshData.verticesPerPoly, false)
	mn:evaluate()
end
--------------------------------------------
-- HELPER FUNCTIONS END-----------
--------------------------------------------

---------------------------------------------------------
-- Create plane and displacement
---------------------------------------------------------
root = octane.nodegraph.create({type=octane.GT_STANDARD, name=nodeNamePrefix})

meshNode = octane.node.create{ type=octane.NT_GEO_MESH , name=nodeNamePrefix.." Plane", graphOwner=root }
params = {
	width = plane.sizeX,
	height = plane.sizeY,
	plane = "xz",
	subdivLevel = 8
} -- creates a mesh plane with 256x256 squares
updateNodeGeometry(meshNode,createPlaneMesh(params))

-- create a placement node and connect the mesh with it
local placeOb = octane.node.create {type=octane.NT_GEO_PLACEMENT, name= nodeNamePrefix.." Position",graphOwner  =root}
placeOb:connectTo(octane.P_GEOMETRY, meshNode)
-- size of the plane (as transform node)
local meshTransf = octane.node.create{type=octane.NT_TRANSFORM_VALUE,name=nodeNamePrefix.." Scale",graphOwner  =root}
meshTransf:setAttribute(octane.A_TRANSLATION,{0,plane.zshift,0})	
placeOb:connectTo(octane.P_TRANSFORM, meshTransf)
-- create a geometry output node and connect to the placement node
local meshOut = octane.node.create{type=octane.NT_OUT_GEOMETRY, name= nodeNamePrefix.." Geometry",graphOwner  =root}
meshOut:connectTo(octane.P_INPUT, placeOb)
-- create displacement node
planeResolution = math.max(plane.resolutionX,plane.resolutionY)
--------------------------------------------
-- Vector displacement node (not used, but ready) [only if the node is available - version 2019 and up)
if (octane.NT_VERTEX_DISPLACEMENT > 0) then 
	terrainVDisplNode = octane.node.create{type= octane.NT_VERTEX_DISPLACEMENT,name=nodeNamePrefix.." Vertex Displacement",graphOwner  =root}
	terrainVDisplNode:setPinValue(octane.P_AMOUNT,plane.height)
	if planeResolution >= 2048 then terrainVDisplNode:setPinValue(octane.P_SUBD_LEVEL,3)
	elseif planeResolution >= 1024 then terrainVDisplNode:setPinValue(octane.P_SUBD_LEVEL,2)
	else terrainVDisplNode:setPinValue(octane.P_SUBD_LEVEL,1) end
end
--------------------------------------------
-- Texture displacement node
terrainDisplNode = octane.node.create{type= octane.NT_DISPLACEMENT,name=nodeNamePrefix.." Texture Displacement",graphOwner  =root}
terrainDisplNode:setPinValue(octane.P_AMOUNT,plane.height)
-- create displacement texture
heightMapTexNode = octane.node.create{type=octane.NT_TEX_FLOATIMAGE ,name= nodeNamePrefix.." Heigthmap",graphOwner  =root}
terrainDisplTransform=octane.node.create{type=octane.NT_TRANSFORM_SCALE,name = nodeNamePrefix.." Heightmap Scale", graphOwner  =root}
terrainDisplTransform:setPinValue(octane.P_SCALE,{1.01,1.01,1.01}) -- scale a bit to avoid issues on border
heightMapTexNode:connectTo(octane.P_TRANSFORM,terrainDisplTransform)
terrainDisplNode:connectTo(octane.P_TEXTURE,heightMapTexNode)
if (octane.NT_VERTEX_DISPLACEMENT > 0) then terrainVDisplNode:connectTo(octane.P_TEXTURE,heightMapTexNode) end
terrainDisplNode:setPinValue(octane.P_FILTER_TYPE,2) --gaussian
terrainDisplNode:setPinValue(octane.P_FILTERSIZE,2) 
if planeResolution >= 4096 then terrainDisplNode:setPinValue(octane.P_LEVEL_OF_DETAIL,13) 
elseif planeResolution >= 2048 then terrainDisplNode:setPinValue(octane.P_LEVEL_OF_DETAIL,12) 
elseif planeResolution >= 1024 then terrainDisplNode:setPinValue(octane.P_LEVEL_OF_DETAIL,11) end
heightMapTexNode:setPinValue(octane.P_GAMMA, 1)
heightMapTexNode:setAttribute(octane.A_FILENAME, heightMapFile)
heightMapTexNode:setAttribute(octane.A_RELOAD, true)
heightMapTexNode:evaluate()
--create material for the base color
baseMaterial = octane.node.create{type=octane.NT_MAT_DIFFUSE,name=nodeNamePrefix.." Base Material",graphOwner  =root}
baseMaterialMultiplyNode = octane.node.create{type= octane.NT_TEX_MULTIPLY,graphOwner  =root}
baseColorTextPath = octane.storage.project.syncToolXMLPath.."\\colormap.png"
if file_exists(baseColorTextPath) then	
	local texNode = octane.node.create{type=octane.NT_TEX_IMAGE ,name= nodeNamePrefix.." Base Color",graphOwner  =root}
	texNode:setAttribute(octane.A_FILENAME, baseColorTextPath)
	texNode:setAttribute(octane.A_RELOAD, true)
	texNode:connectTo(octane.P_TRANSFORM,terrainDisplTransform)
	texNode:evaluate()
	-- the base color will be multiplied with the diffuse of the first texture (can't find a better way for now)	
	baseMaterialMultiplyNode:connectTo(octane.P_TEXTURE1,texNode)
end
baseMaterial:connectTo(octane.P_DIFFUSE,baseMaterialMultiplyNode)
-- create a composite material pin and connects
planeMaterial = octane.node.create {type= octane.NT_MAT_COMPOSITE, name= nodeNamePrefix.." Main Material",graphOwner  =root}
planeMaterial:setAttribute(octane.A_MATERIAL_COUNT,#materials+1, false)
planeMaterial:connectTo(octane.P_DISPLACEMENT, terrainDisplNode)
planeMaterial:connectToIx(2, baseMaterial)
meshNode:connectToIx(1, planeMaterial)

---------------------------------------------------------
-- Create materials
---------------------------------------------------------
-- read info from Texture XML Description
function getTexturesArray(strName)
	local texPath=octane.storage.project.syncToolXMLPath.."\\Assets\\"..strName.."\\"
	xmlTexPath=texPath.."Description.xml"
	local xmlHndTex = tree:new()
	local texParser = xml2lua.parser(xmlHndTex)
	texParser:parse(xml2lua.loadFile(xmlTexPath))
	return {
		texPath..xmlHndTex.root.WorldCreator.Textures.Diffuse._attr.File,
		texPath..xmlHndTex.root.WorldCreator.Textures.Normal._attr.File,
		texPath..xmlHndTex.root.WorldCreator.Textures.Displacement._attr.File
	}
end

-- iterate the materials lists and create the graphs
for i,m in pairs(materials) do
	splatFileName=octane.storage.project.syncToolXMLPath.."\\"..m.splatFileName
	if file_exists(splatFileName) then
		
		-- create universal material
		local mat = octane.node.create{type=octane.NT_MAT_UNIVERSAL,name=m.name,graphOwner  =root}
		mat:setPinValue(octane.P_ROUGHNESS,m.roughness)
		mat:setPinValue(octane.P_SPECULAR,m.metallic)
		planeMaterial:connectToIx(2*(i+1),mat) 
		
		-- load mask for material
		splatChannelFileName = string.format("%s__%i.tif",splatFileName,m.splatChannelIndex)
		if not file_exists(splatChannelFileName) then
			--extract channels from splatmap
			local tmpCommand = string.format([["%s" "%s" -colorspace RGB -flip -separate "%s__%%%%d.tif"]],imageMagickPath,splatFileName,splatFileName)
			local tmpScriptFile = os.tmpname()..".bat"
			local f = assert(io.open(tmpScriptFile, "w"))
			io.open(tmpScriptFile, "w")
			f:write(tmpCommand)
			f:close()
			os.execute(tmpScriptFile)
			os.remove(tmpScriptFile)
		end
		if file_exists(splatChannelFileName) then			
			-- link texture to material opacity
			local opaNode = octane.node.create{type=octane.NT_TEX_FLOATIMAGE ,name= m.name.." Mask",graphOwner  =root}
			opaNode:setAttribute(octane.A_FILENAME, splatChannelFileName)
			opaNode:setAttribute(octane.A_RELOAD, true)
			opaNode:evaluate()
			planeMaterial:connectToIx(2*(i+1)+1,opaNode)			
		end
				
		--load textures for material 
		difTexFiles = getTexturesArray(m.textureFileName)
		local matTransf = octane.node.create{type=octane.NT_TRANSFORM_SCALE,name=m.name.." tiling",graphOwner  =root}
		matTransf:setPinValue(octane.P_SCALE,{m.scaleX/plane.resolutionX,m.scaleY/plane.resolutionY,1})	
		if file_exists(difTexFiles[1]) then -- ALBEDO texture
			local texNode = octane.node.create{type=octane.NT_TEX_IMAGE ,name= m.name.." Diffuse",graphOwner  =root}
			if (tonumber(m.ColorR) < 1 or tonumber(m.ColorG) < 1 or tonumber(m.ColorB) < 1) then
				-- multiply the color
				local colorNode = octane.node.create{type= octane.NT_TEX_RGB,graphOwner  =root}
				colorNode:setAttribute(octane.A_VALUE, {m.ColorR,m.ColorG,m.ColorB})
				local multiplyNode = octane.node.create{type= octane.NT_TEX_MULTIPLY,graphOwner  =root}
				multiplyNode:connectTo(octane.P_TEXTURE2,colorNode)
				multiplyNode:connectTo(octane.P_TEXTURE1,texNode)
				mat:connectTo(octane.P_ALBEDO,multiplyNode)
			else
				mat:connectTo(octane.P_ALBEDO,texNode)
			end
			texNode:setAttribute(octane.A_FILENAME, difTexFiles[1])
			texNode:setAttribute(octane.A_RELOAD, true)
			texNode:evaluate()
			texNode:connectTo(octane.P_TRANSFORM,matTransf)
			if i == 1 then -- if this is the first material, its albedo will be also multiplied by the base texture in the base color
				baseMaterialMultiplyNode:connectTo(octane.P_TEXTURE2,texNode)
			end
		end
		if file_exists(difTexFiles[2]) then -- NORMAL texture
			local texNode = octane.node.create{type=octane.NT_TEX_IMAGE ,name= m.name.." Normal",graphOwner  =root}
			mat:connectTo(octane.P_NORMAL,texNode)
			texNode:setAttribute(octane.A_FILENAME, difTexFiles[2])
			texNode:setAttribute(octane.A_RELOAD, true)
			texNode:evaluate()
			texNode:connectTo(octane.P_TRANSFORM,matTransf)
		end
		if file_exists(difTexFiles[3]) then -- DISPLACEMENT texture
			local textDisplNode = octane.node.create{type= octane.NT_DISPLACEMENT,graphOwner  =root}
			-- fix displacement at 5cm
			textDisplNode:setPinValue(octane.P_AMOUNT,0.05)
			mat:connectTo(octane.P_DISPLACEMENT, textDisplNode)
			local texNode = octane.node.create{type=octane.NT_TEX_FLOATIMAGE ,name= m.name.." Displacement",graphOwner  =root}
			textDisplNode:connectTo(octane.P_TEXTURE,texNode)
			texNode:setAttribute(octane.A_FILENAME, difTexFiles[3])
			texNode:setAttribute(octane.A_RELOAD, true)
			texNode:evaluate()
			if texNode:getAttribute(octane.A_SIZE)[1] >= 8192 then textDisplNode:setPinValue(octane.P_LEVEL_OF_DETAIL,13) end
			if texNode:getAttribute(octane.A_SIZE)[1] >= 4096 then textDisplNode:setPinValue(octane.P_LEVEL_OF_DETAIL,12) end
			if texNode:getAttribute(octane.A_SIZE)[1] >= 2048 then textDisplNode:setPinValue(octane.P_LEVEL_OF_DETAIL,11) end
			texNode:connectTo(octane.P_TRANSFORM,matTransf)
		end
	end
end
root:unfold(true) -- tidy up everything
