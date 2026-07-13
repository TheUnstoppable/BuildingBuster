--    BuildingBuster, W3D Lightmap Spot Burning Script
--    Copyright (C) 2026 Unstoppable
--
--    This program is free software: you can redistribute it and/or modify it under the terms of the GNU Lesser General Public License as
--    published by the Free Software Foundation, either version 3 of the License, or (at your option) any later version.
--    This program is distributed in the hope that it will be useful, but WITHOUT ANY WARRANTY; without even the implied warranty of
--    MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU Lesser General Public License for more details.
--    You should have received a copy of the GNU Lesser General Public License along with this program.
--    If not, see <https://www.gnu.org/licenses/>.

rollout BuildingBusterRollout "Building Buster" width:700 height:700
(
    label lblTaskLabel "Task:" pos:[20,20] width:100 height:20
    label lblTask "Ready" pos:[120,20] width:560 height:20
    progressBar pbTask pos:[20,45] width:660 height:20
    
    label lblProgressLabel "Current Progress:" pos:[20,75] width:100 height:20
    progressBar pbProgress pos:[20,100] width:660 height:20
    
    label lblObjectLabel "Current Object:" pos:[20,130] width:100 height:20
    label lblObject " " pos:[120,130] width:560 height:20
    
    button btnStart "Start" pos:[20,220] width:320 height:40
    button btnCancel "Cancel" pos:[360,220] width:320 height:40 enabled:false
    
    dropdownList ddlLightmapSize "Lightmap Size:" items:#("256x256", "512x512", "1024x1024", "2048x2048") selection:2 pos:[20,170] width:150 height:20
    
    editText edtOutput "" pos:[20,270] width:660 height:410 readonly:true
    
    local exportFolder = ""
    local cancelRequested = false
    local objectList = #()
    local rootList = #()
    local oldAmbientColor = undefined
    
    -- ============================================
    -- HELPERS
    -- ============================================
    
    fn isMeshObject obj =
    (
        local baseClass = classof obj.baseObject
        baseClass == Editable_mesh or baseClass == Editable_Poly or classof obj == Editable_mesh or classof obj == Editable_Poly
    )
    
    fn getStringInput =
    (
        global gStringInputResult = ""
        rollout inputRollout "Input" width:200 height:90
        (
            label lblPrompt "Enter export name:" pos:[10,10] width:190
            editText edtInput "" pos:[4,30] width:190
            button btnOK "OK" pos:[10,60] width:85 height:25
            button btnCancel "Cancel" pos:[105,60] width:85 height:25
            
            on btnOK pressed do
            (
                gStringInputResult = edtInput.text
                DestroyDialog inputRollout
            )
            
            on btnCancel pressed do
            (
                gStringInputResult = ""
                DestroyDialog inputRollout
            )
        )
        createDialog inputRollout modal:true
        gStringInputResult
    )
    
    fn log msg =
    (
        edtOutput.text = edtOutput.text + msg + "\n"
        windows.processPostedMessages()
    )
    
    fn getObjectsToRender obj =
    (
        if isGroupHead obj then
        (
            local objs = #()
            for child in obj do
            (
                if isMeshObject child then
                    append objs child
            )
            objs
        )
        else if isMeshObject obj then
            #(obj)
        else
            #()
    )
    
    fn blendPixels sourcePixelArray destColor =
    (
        local sourcePixel = if (classof sourcePixelArray) == Array then sourcePixelArray[1] else sourcePixelArray
        
        local r = (sourcePixel.red * destColor.red) / 255.0
        local g = (sourcePixel.green * destColor.green) / 255.0
        local b = (sourcePixel.blue * destColor.blue) / 255.0
        local a = (sourcePixel.alpha * destColor.alpha) / 255.0
        
        r = (r + 0.5) as integer
        g = (g + 0.5) as integer
        b = (b + 0.5) as integer
        a = (a + 0.5) as integer
        
        r = amax 0 (amin 255 r)
        g = amax 0 (amin 255 g)
        b = amax 0 (amin 255 b)
        a = amax 0 (amin 255 a)
        
        color r g b a
    )
    
    -- ============================================
    -- STAGE 0: SCENE COLLECTION & VALIDATION
    -- ============================================
    
    fn validateAndCollect obj =
    (
        if isGroupHead obj then
        (
            if obj.parent == undefined then
                append rootList obj
            
            for child in obj do
            (
                if obj == child then continue
                validateAndCollect child
            )
        )
        else if isMeshObject obj then
        (
            if obj.parent == undefined then
                append rootList obj
            
            append objectList obj
        )
    )
    
    fn stageValidation =
    (
        lblTask.text = "Validating scene..."
        pbTask.value = 0
        pbProgress.value = 0
        
        objectList = #()
        rootList = #()
        local currentIndex = 0
        local totalObjects = objects.count
        
        for obj in objects do
        (
            currentIndex += 1
            if obj.isHidden then continue
            
            if obj.parent == undefined then
                validateAndCollect obj
            
            pbProgress.value = ((currentIndex / totalObjects as float) * 100) as integer
        )
        
        if rootList.count == 0 then
        (
            log "Error: No suitable root objects found in the scene"
            return false
        )
        
        pbProgress.value = 100
        pbTask.value = 0
        windows.processPostedMessages()
        
        log "=== SCENE ANALYSIS ==="
        log ("  Root objects: " + (rootList.count as string))
        log ("  Total child objects: " + (objectList.count as string))
        
        return true
    )
    
    -- ============================================
    -- STAGE 1: UVW MAP CREATION (Channel 1)
    -- ============================================
    
    fn stageUVWMapCreation =
    (
        lblTask.text = "Creating UVW maps on channel 1..."
        pbTask.value = 15
        pbProgress.value = 0
        
        if rootList.count == 0 then
        (
            log "No objects found"
            return false
        )
        
        local processCount = 0
        local createdCount = 0
        
        max modify mode
        
        for idx = 1 to rootList.count do
        (
            if cancelRequested then exit
            
            local obj = rootList[idx]
            lblObject.text = obj.name + " (" + (idx as string) + "/" + (rootList.count as string) + ")"

            if validModifier obj (UVWMap()) then
            (
                clearSelection()
                select obj
                
                for i = obj.modifiers.count to 1 do
                (
                    if classof obj.modifiers[i] == Uvwmap then
                        deleteModifier obj i
                )
                
                local uvwMod = Uvwmap()
                uvwMod.channel = 1
                uvwMod.maptype = 4
                modPanel.addModToSelection uvwMod
                modPanel.setCurrentObject uvwMod
                
                local bbox = (nodeGetBoundingBox obj (matrix3 1))
                local bboxMin = bbox[1]
                local bboxMax = bbox[2]
                local bboxCenter = (bboxMin + bboxMax) / 2.0
                
                uvwMod.gizmo.transform = (translate (matrix3 1) bboxCenter)
                uvwMod.gizmo.scale = [64.0, 64.0, 64.0]
                
                maxops.CollapseNodeTo obj 1 true

                createdCount += 1
            )
            
            processCount += 1
            pbProgress.value = ((processCount / rootList.count as float) * 100) as integer
            windows.processPostedMessages()
        )
        
        clearSelection()
        pbTask.value = 15
        pbProgress.value = 100
        log ("UVW Map Creation: Processed " + (processCount as string) + " | Created: " + (createdCount as string))
        return true
    )
    
    -- ============================================
    -- STAGE 2: LOAD EXISTING LIGHTMAPS
    -- ============================================
    
    fn stageLoadLightmaps =
    (
        lblTask.text = "Loading existing lightmaps..."
        pbTask.value = 30
        pbProgress.value = 0
        
        local lightmapsLoaded = #()
        
        for idx = 1 to rootList.count do
        (
            if cancelRequested then exit
            
            local lightmapFile = exportFolder + "\\" + exportName + "+" + (idx as string) + ".tga"
            
            lblObject.text = (idx as string) + "/" + (rootList.count as string) + " - " + (getFilenameFile lightmapFile)
            
            if doesFileExist lightmapFile then
            (
                local bmp = openBitmap lightmapFile
                if bmp != undefined then
                (
                    append lightmapsLoaded bmp
                )
                else
                (
                    log ("Warning: Could not load " + lightmapFile)
                    append lightmapsLoaded undefined
                )
            )
            else
            (
                log ("Warning: Lightmap not found: " + lightmapFile)
                append lightmapsLoaded undefined
            )
            
            pbProgress.value = ((idx / rootList.count as float) * 100) as integer
            windows.processPostedMessages()
        )
        
        pbTask.value = 30
        pbProgress.value = 100
        log ("Lightmaps loaded: " + (lightmapsLoaded.count as string))
        return lightmapsLoaded
    )
    
    -- ============================================
    -- STAGE 3: CREATE CELLULAR MATERIAL
    -- ============================================
    
    fn createCellularMaterial =
    (
        local mat = Standard()
        mat.name = "CellularSpotBurn"
        
        local cellularMap = Cellular()
        cellularMap.cellColor = (color 36 36 36)  -- #242424
        cellularMap.divisionColor1 = (color 111 102 96)  -- #6F6660
        cellularMap.divisionColor2 = (color 149 149 149)  -- #959595
        cellularMap.size = 3.1
        cellularMap.spread = 0.75
        cellularMap.smooth = 0.1
        
        mat.diffuseMap = cellularMap
        mat.diffuseMapAmount = 100.0
        
        mat
    )
    
    fn stageCreateMaterial =
    (
        lblTask.text = "Creating cellular material..."
        pbTask.value = 45
        pbProgress.value = 0
        
        local mat = createCellularMaterial()
        
        pbTask.value = 45
        pbProgress.value = 100
        windows.processPostedMessages()
        
        return mat
    )
    
    -- ============================================
    -- STAGE 4: APPLY MATERIAL AND BAKE
    -- ============================================
    
    fn bakeLightmapSpots obj index lightmapSize cellularMat bakedExportFolder origTexturePath =
    (
        if cancelRequested then
            return undefined
        
        local objectsToRender = getObjectsToRender obj
        if objectsToRender.count == 0 then
            return undefined
        
        local blendedBmp = openBitmap origTexturePath
        if blendedBmp == undefined then
            return undefined
            
        local tempFiles = #()
        
        local originalMaterials = #()
        for i = 1 to objectsToRender.count do
        (
            originalMaterials[i] = objectsToRender[i].material
            objectsToRender[i].material = cellularMat
            objectsToRender[i].wireColor = color 255 255 255
        )
        
        for i = 1 to objectsToRender.count do
        (
            local o = objectsToRender[i]
            lblObject.text = obj.name + "(" + (index as string) + "/" + (rootList.count as string) + ") -> " + o.name + " (" + (i as string) + "/" + (objectsToRender.count as string) + ")"
            
            local tempFile = bakedExportFolder + "\\temp_" + (index as string) + "_" + (i as string) + ".tga"
            append tempFiles tempFile
            
            o.INodeBakeProperties.removeAllBakeElements()
            local bakeElem = CompleteMap()
            bakeElem.outputSzX = lightmapSize
            bakeElem.outputSzY = lightmapSize
            bakeElem.fileType = tempFile
            bakeElem.fileName = filenameFromPath tempFile
            bakeElem.filterOn = true
            bakeElem.shadowsOn = false
            bakeElem.enabled = true
            
            o.INodeBakeProperties.addBakeElement bakeElem
            o.INodeBakeProperties.bakeEnabled = true
            o.INodeBakeProperties.bakeChannel = 2
            o.INodeBakeProperties.nDilations = 2
            
            clearSelection()
            o.isSelected = true
            
            windows.processPostedMessages()
            render rendertype:#bakeSelected vfb:off progressBar:false outputSize:[lightmapSize, lightmapSize]
            
            if doesFileExist tempFile then
            (
                local objBmp = openBitmap tempFile
                if objBmp != undefined then
                (
                    for y = 0 to lightmapSize-1 do
                    (
                        for x = 0 to lightmapSize-1 do
                        (
                            local bakedPixel = getPixels objBmp [x,y] 1
                            if bakedPixel[1].alpha > 0 then
                            (
                                local destPixel = getPixels blendedBmp [x,y] 1
                                local r = ((bakedPixel[1].red as float) * (destPixel[1].red as float)) / 255.0
                                local g = ((bakedPixel[1].green as float) * (destPixel[1].green as float)) / 255.0
                                local b = ((bakedPixel[1].blue as float) * (destPixel[1].blue as float)) / 255.0
                                local a = ((bakedPixel[1].alpha as float) * (destPixel[1].alpha as float)) / 255.0
                                r = (r + 0.5) as integer
                                g = (g + 0.5) as integer
                                b = (b + 0.5) as integer
                                a = (a + 0.5) as integer
                                r = amax 0 (amin 255 r)
                                g = amax 0 (amin 255 g)
                                b = amax 0 (amin 255 b)
                                a = amax 0 (amin 255 a)
                                local blended = color r g b a
                                setPixels blendedBmp [x,y] #(blended)
                            )
                        )
                    )
                    close objBmp
                    free objBmp
                )
            )
            
            windows.processPostedMessages()
        )
        
        for i = 1 to objectsToRender.count do
        (
            objectsToRender[i].material = originalMaterials[i]
        )
        
        for tempFile in tempFiles do
        (
            if doesFileExist tempFile then
            (
                deleteFile tempFile
                windows.processPostedMessages()
            )
        )
        
        clearSelection()
        return blendedBmp
    )
    
    fn processW3DMaterial mat matIndex obj objIdx lightmapSize cellularMat processedTextures materialToBlendedTex =
    (
        local texName = undefined
        local passes = wwGetPassCount mat
        if passes > 0 then
        (
            texName = wwGetTexture mat 1
        )
        
        local matDesc = if matIndex > 0 then ("submaterial " + (matIndex as string)) else "material"
        if texName == undefined or texName == "" then
        (
            log ("Warning: No W3D texture found for " + matDesc)
            return undefined
        )
        else if not (doesFileExist texName) then
        (
            log ("Warning: Texture file not found at: " + texName)
            return undefined
        )
        
        local alreadyProcessed = false
        local processedIdx = 0
        
        for pIdx = 1 to processedTextures.count do
        (
            if processedTextures[pIdx][1] == texName then
            (
                alreadyProcessed = true
                processedIdx = pIdx
                exit
            )
        )
        
        if not alreadyProcessed then
        (
            local blendedBmp = bakeLightmapSpots obj objIdx lightmapSize cellularMat exportFolder texName
            
            if blendedBmp != undefined then
            (
                local texDir = getFilenamePath texName
                local texFile = getFilenameFile texName
                local texExt = getFilenameType texName
                local outputFile = texDir + texFile + "a" + texExt

                local saveBmp = bitmap blendedBmp.width blendedBmp.height
                copy blendedBmp saveBmp
                
                saveBmp.filename = outputFile
                save saveBmp
                close blendedBmp
                free blendedBmp
                free saveBmp
                
                append processedTextures #(texName, outputFile, outputFile)
                processedIdx = processedTextures.count
            )
        )
        
        if processedIdx > 0 then
        (
            append materialToBlendedTex #(mat, processedIdx)
        )
        
        return processedIdx
    )
    
    fn stageProcessMaterials cellularMat =
    (
        lblTask.text = "Processing materials and baking unique textures..."
        pbTask.value = 60
        pbProgress.value = 0
        
        local lightmapSizes = #(256, 512, 1024, 2048)
        local lightmapSize = lightmapSizes[ddlLightmapSize.selection]
        
        local processedTextures = #()
        local materialToBlendedTex = #()
        
        local sceneSkylight = Skylight()
        sceneSkylight.pos = [0, 0, 0]
        sceneSkylight.color = color 255 255 255
        sceneSkylight.castShadows = false
        
        for objIdx = 1 to rootList.count do
        (
            if cancelRequested then exit
            
            local obj = rootList[objIdx]
            lblObject.text = obj.name + " (" + (objIdx as string) + "/" + (rootList.count as string) + ")"
            
            local objectsToRender = getObjectsToRender obj
            
            if objectsToRender.count > 0 then
            (
                for childIdx = 1 to objectsToRender.count do
                (
                    local child = objectsToRender[childIdx]
                    if child.material != undefined then
                    (
                        local mat = child.material
                        
                        if classof mat == Multimaterial then
                        (
                            for subIdx = 1 to mat.numsubs do
                            (
                                local subMat = mat[subIdx]
                                if subMat != undefined and subMat != mat then
                                (
                                    processW3DMaterial subMat subIdx obj objIdx lightmapSize cellularMat processedTextures materialToBlendedTex
                                )
                            )
                        )
                        else
                        (
                            processW3DMaterial mat 0 obj objIdx lightmapSize cellularMat processedTextures materialToBlendedTex
                        )
                    )
                )
            )
            
            pbProgress.value = ((objIdx / rootList.count as float) * 100) as integer
            windows.processPostedMessages()
        )
        
        pbTask.value = 60
        pbProgress.value = 100
        log ("Material Scanning: Processed " + (processedTextures.count as string) + " unique textures")
        
        return #(processedTextures, materialToBlendedTex)
    )
    
    -- ============================================
    -- STAGE 5: APPLY BLENDED TEXTURES TO MATERIALS
    -- ============================================
    
    fn stageApplyBlendedTextures materialData =
    (
        lblTask.text = "Applying blended textures to materials..."
        pbTask.value = 85
        pbProgress.value = 0
        
        local processedTextures = materialData[1]
        local materialToBlendedTex = materialData[2]
        
        local appliedCount = 0
        
        for matDataIdx = 1 to materialToBlendedTex.count do
        (
            if cancelRequested then exit
            
            local matData = materialToBlendedTex[matDataIdx]
            local mat = matData[1]
            local texIdx = matData[2]
            
            if texIdx > 0 and texIdx <= processedTextures.count then
            (
                local texData = processedTextures[texIdx]
                local outputFile = texData[2]
                
                lblObject.text = (matDataIdx as string) + "/" + (materialToBlendedTex.count as string)
                
                wwSetTexture mat outputFile 1
                appliedCount += 1
            )
            
            pbProgress.value = ((matDataIdx / materialToBlendedTex.count as float) * 100) as integer
            windows.processPostedMessages()
        )
        
        pbTask.value = 85
        pbProgress.value = 100
        log ("Texture Application: Applied " + (appliedCount as string) + " textures")
        return true
    )
    
    -- ============================================
    -- MAIN PIPELINE EXECUTION
    -- ============================================
    
    fn executePipeline =
    (
        edtOutput.text = ""
        cancelRequested = false
        
        if not stageValidation() then
        (
            log "Error: Scene validation failed -- operation aborted"
            return false
        )
        
        if cancelRequested then
        (
            log "Pipeline cancelled -- operation aborted"
            return false
        )
        
        local exportDir = getSavePath caption:"Select export directory (where existing lightmaps are)"
        if exportDir == undefined or exportDir == "" then
        (
            messageBox "Export directory required"
            return false
        )
        exportFolder = exportDir
        
        log "Starting spot burn operation..."
        log ""
        
        if not stageUVWMapCreation() then
        (
            log "Error: UVW map creation failed -- operation aborted"
            return false
        )
        
        if cancelRequested then
        (
            log "Pipeline cancelled -- operation aborted"
            return false
        )
        
        log ""
        local cellularMat = stageCreateMaterial()
        
        if cancelRequested then
        (
            log "Pipeline cancelled -- operation aborted"
            return false
        )
        
        log ""
        local materialData = stageProcessMaterials cellularMat
        
        if cancelRequested then
        (
            log "Pipeline cancelled -- operation aborted"
            return false
        )
        
        log ""
        if not stageApplyBlendedTextures materialData then
        (
            log "Warning: Texture application encountered issues"
        )
        
        log ""
        log "=== SPOT BURN OPERATION COMPLETED SUCCESSFULLY ==="
        
        pbTask.value = 100
        pbProgress.value = 0
        lblTask.text = "Completed"
        lblObject.text = ""
        
        return true
    )
    
    on btnStart pressed do
    (
        btnStart.enabled = false
        btnCancel.enabled = true
        ddlLightmapSize.enabled = false
        pbTask.value = 0
        pbProgress.value = 0

        oldAmbientColor = ambientColor
        ambientColor = color 255 255 255
        
        if (executePipeline()) then
        (
            lblTask.text = "Ready"
        )
        else
        (
            lblTask.text = "Aborted"
        )
        
        ambientColor = oldAmbientColor
        lblObject.text = ""
        
        btnStart.enabled = true
        btnCancel.enabled = false
        ddlLightmapSize.enabled = true
        pbTask.value = 100
        pbProgress.value = 0
    )
    
    on btnCancel pressed do
    (
        cancelRequested = true
        btnCancel.enabled = false
        lblTask.text = "Cancelling..."
    )
)

createDialog BuildingBusterRollout
