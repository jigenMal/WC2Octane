# WC2Octane
One-click import of World Creator terrains into Octane Render Standalone.

This is a script for Octane Render Standalone (https://home.otoy.com/render/octane-render/). It will automatically import a terrain generated by World Creator 2 (https://www.world-creator.com).

# Prerequisites
This script works on Windows. I think it can be easily ported to other platforms, but for the time being it's Windows-only.

The script uses the Image Magick library (https://imagemagick.org) to edit textures. Download ImageMagick Windows binaries here: https://imagemagick.org/script/download.php#windows (the recommended 64bit version is OK), and install it. Take note of the path you installed it (you will need the full path to the "magick.exe" file).

You also need a LUA library called xml2lua (https://github.com/manoelcampos/Xml2Lua). Click the green "Clone or Download" button on the upper right of the page and choose "Download ZIP". Unzip the file in a folder of your preference and take note of it.

Download this script clicking the green "Clone or Download" button on the upper right of the page and choose "Download ZIP". Extract the file "WC2Octane.lua" (you can ignore the others) and copy it in your Octane LUA Scripts folder. 
The Octane script directory can be specified in the Octane preferences box, it's the first field in the Application tab.

Open the "WC2Octane.lua" file in a text editor (Notepad is ok) and in these two lines replace the paths with the corrects path on your system:
local imageMagickPath = [[C:\Program Files\ImageMagick-7.0.8-Q16\magick.exe]]  -- FULL PATH to the ImageMagick executable
local xml2luaPath = 	[[X:\Impostazioni\Octane\xml2lua\]]	-- FULL PATH to the folder of the xml2lua package (WITH trailing "\")

If Octane is already running, you can rescan the script folder through the Script menu -> Rescan Script folder.

# Usage
Open WordCreator and load or design a terrain. Save your project. Click on the Bridge Export button. Wait for completition. You will have a new folder, with the project name, usually in your Documents\WorldCreator\Bridge folder. There is a "bridge.xml" file in it.

In Octane, open the scripts menu, click on "WC2Octane" (or just type Alt-W as a shortcut). A file chooser dialog will open. Browse to the "bridge.xml" file created by Word Creator and open it. Wait for completition. Done. You will have a new subgraph with a geometry output pin to connect to your render target.

If you made changes in World Creator and want to reload the terrain, you can just repeat the export and import process. If you customized the nodes in Octane you will want to keep the existing nodes, so just rename them, import a new copy of the terrain and copy-paste the new parts you need to replace the old ones. Please keep in mind that the World Creator exporter deletes all the previous files, si it's better to save the scene as an ORBX package to avoid losing the textures.

