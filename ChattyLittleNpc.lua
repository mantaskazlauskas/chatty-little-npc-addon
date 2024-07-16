---@class ChattyLittleNpc
local ChattyLittleNpc = LibStub("AceAddon-3.0"):NewAddon("ChattyLittleNpc", "AceConsole-3.0", "AceEvent-3.0")
ChattyLittleNpc.PlayButton = ChattyLittleNpc.PlayButton
ChattyLittleNpc.ReplayFrame = ChattyLittleNpc.ReplayFrame
ChattyLittleNpc.Options = ChattyLittleNpc.Options

local defaults = {
    profile = {
        useMaleVoice = true,
        useFemaleVoice = false,
        useBothVoices = false,
        playVoiceoversOnClose = true,
        printMissingFiles = false,
        framePos = { -- Default position
            point = "CENTER",
            relativeTo = nil,
            relativePoint = "CENTER",
            xOfs = 500,
            yOfs = 0
        }
    }
}

ChattyLittleNpc.lastSoundHandle = nil
ChattyLittleNpc.currentQuestId = nil
ChattyLittleNpc.currentPhase = nil
ChattyLittleNpc.currentQuestTitle = nil
ChattyLittleNpc.dialogState = nil
ChattyLittleNpc.expansions = { "Battle_for_Azeroth", "Cataclysm", "Classic", "Dragonflight", "Legion", "Mists_of_Pandaria", "Shadowlands", "The_Burning_Crusade", "The_War_Within", "Warlords_of_Draenor", "Wrath_of_the_Lich_King" }

function ChattyLittleNpc:OnInitialize()
    self.db = LibStub("AceDB-3.0"):New("ChattyLittleNpcDB", defaults, true)
    self:RegisterChatCommand("clnpc", "HandleSlashCommands")
    self.Options:SetupOptions()
end

function ChattyLittleNpc:OnEnable()
    self:RegisterEvent("QUEST_DETAIL")
    self:RegisterEvent("GOSSIP_CLOSED")
    self:RegisterEvent("QUEST_FINISHED")
    self:RegisterEvent("QUEST_PROGRESS")
    self:RegisterEvent("QUEST_COMPLETE")

    if self.ReplayFrame.displayFrame then
        self.ReplayFrame:LoadFramePosition()
    end

    local detailsFrame = QuestMapFrame and QuestMapFrame.DetailsFrame
    if detailsFrame then
        self.PlayButton:AttachPlayButton("TOPRIGHT", detailsFrame, "TOPRIGHT", 0, 30, "ChattyNPCPlayButton")
    end

    if QuestLogFrame then
        self.PlayButton:AttachPlayButton("TOPRIGHT", QuestLogFrame, "TOPRIGHT", -140, -40, "ChattyNPCQuestLogFramePlayButton")
    end

    if QuestLogDetailFrame then
        self.PlayButton:AttachPlayButton("TOPRIGHT", QuestLogDetailFrame, "TOPRIGHT", -140, -40, "ChattyNPCQuestLogDetailFramePlayButton")
    end

    hooksecurefunc("QuestMapFrame_UpdateAll", self.PlayButton.UpdatePlayButton)
    QuestMapFrame:HookScript("OnShow", self.PlayButton.UpdatePlayButton)
    QuestMapFrame.DetailsFrame:HookScript("OnHide", self.PlayButton.HidePlayButton)
end

function ChattyLittleNpc:OnDisable()
    self:UnregisterEvent("QUEST_DETAIL")
    self:UnregisterEvent("GOSSIP_CLOSED")
    self:UnregisterEvent("QUEST_FINISHED")
    self:UnregisterEvent("QUEST_PROGRESS")
    self:UnregisterEvent("QUEST_COMPLETE")
end

function ChattyLittleNpc:getNpcID(unit)
    local guid = UnitGUID(unit)
    if guid then
        local unitType, _, _, _, _, npcID = strsplit("-", guid)
        if unitType == "Creature" or unitType == "Vehicle" then
            return tonumber(npcID)
        end
    end
    return nil
end

function ChattyLittleNpc:getUnitInfo(unit)
    local name = UnitName(unit) or "Unknown"
    local sex = UnitSex(unit) -- 1 = neutral, 2 = male, 3 = female
    local sexStr = (sex == 1 and "Neutral") or (sex == 2 and "Male") or (sex == 3 and "Female") or "Unknown"
    local npcID = self:getNpcID(unit) or "Unknown"
    local race = UnitRace(unit) or "Unknown"

    return name, sexStr, race, npcID
end

function ChattyLittleNpc:IsDialogEnabled()
    local isDialogEnabled = GetCVar("Sound_EnableDialog");
    return isDialogEnabled
end

function ChattyLittleNpc:MuteDialogSound()
    SetCVar("Sound_EnableDialog", 0)
end

function ChattyLittleNpc:SaveDialogState()
    self.dialogState = nil
    self.dialogState = self:IsDialogEnabled()
end

function ChattyLittleNpc:ResetDialogToLastState()
    if (self.dialogState ~= nil) then
        SetCVar("Sound_EnableDialog", self.dialogState)
    end

    self.dialogState = nil
end

function ChattyLittleNpc:StopCurrentSound()
    if self.lastSoundHandle and type(self.lastSoundHandle) == "number" then
        StopSound(self.lastSoundHandle)
        self.lastSoundHandle = nil
    end
end

function ChattyLittleNpc:GetTitleForQuestID(questID)
    if C_QuestLog and C_QuestLog.GetTitleForQuestID then
        return C_QuestLog.GetTitleForQuestID(questID)
    elseif QuestUtils_GetQuestName then
        return QuestUtils_GetQuestName(questID)
    end
end

function ChattyLittleNpc:PlayQuestSound(questId, phase, npcGender)
    self:StopCurrentSound()
    self.currentQuestId = questId
    self.currentPhase = phase

    local basePath = "Interface\\AddOns\\ChattyLittleNpc_"
    local fileName = questId .. "_" .. phase .. ".mp3"
    local soundPath, success, newSoundHandle

    success = false

    for _, folder in ipairs(self.expansions) do
        local corePathToVoiceovers = basePath .. folder .. "\\" .. "voiceovers" .. "\\"
        local soundPath = ChattyLittleNpc:GetVoiceoversPath(corePathToVoiceovers, fileName, npcGender)

        local retryCount = 0
        repeat
            success, newSoundHandle = PlaySoundFile(soundPath, "Master")
            if success == nil then
                if retryCount == 0 then
                    soundPath = ChattyLittleNpc:GetMaleVoiceoversPath(corePathToVoiceovers, fileName)
                elseif retryCount == 1 then
                    soundPath = ChattyLittleNpc:GetFemaleVoiceoversPath(corePathToVoiceovers, fileName)
                else
                    soundPath = ChattyLittleNpc:GetOldVoiceoversPath(corePathToVoiceovers, fileName)
                end
                retryCount = retryCount + 1
            end
        until success or retryCount > 2  -- Retry until success or tried all voiceover directories

        if success then
            self.lastSoundHandle = newSoundHandle
            local questTitle = self:GetTitleForQuestID(questId)
            ChattyLittleNpc.currentQuestTitle = questTitle
            local suffix = ""
            if phase == "Desc" then
                suffix = "(description)"
            elseif phase == "Prog" then
                suffix = "(progression)"
            elseif phase == "Comp" then
                suffix = "(completion)"
            end

            self.ReplayFrame:ShowDisplayFrame()
            break
        end
    end

    if not success and self.db.profile.printMissingFiles then
        print("Missing voiceover file: " .. soundPath)
    end
end

function ChattyLittleNpc:GetVoiceoversPath(corePathToVoiceovers, fileName, npcGender)
    if self.db.profile.useMaleVoice then
        return self:GetMaleVoiceoversPath(corePathToVoiceovers, fileName)
    elseif self.db.profile.useFemaleVoice then
        return self:GetFemaleVoiceoversPath(corePathToVoiceovers, fileName)
    elseif (self.db.profile.useBothVoices and (npcGender == "Male" or npcGender == "Female")) then
        if npcGender == "Male" then
            return self:GetMaleVoiceoversPath(corePathToVoiceovers, fileName)
        elseif npcGender == "Female" then
            return self:GetFemaleVoiceoversPath(corePathToVoiceovers, fileName)
        end
    else
        return self:GetOldVoiceoversPath(corePathToVoiceovers, fileName)
    end
end

function ChattyLittleNpc:GetFemaleVoiceoversPath(corePathToVoiceovers, fileName)
    return corePathToVoiceovers .. "female" .. "\\".. fileName
end

function ChattyLittleNpc:GetMaleVoiceoversPath(corePathToVoiceovers, fileName)
    return corePathToVoiceovers .. "male" .. "\\".. fileName
end

function ChattyLittleNpc:GetOldVoiceoversPath(corePathToVoiceovers, fileName)
    return corePathToVoiceovers .. fileName -- try the old directory if user didnt update voiceovers
end

function ChattyLittleNpc:QUEST_DETAIL()
    ChattyLittleNpc:HandlePlaybackStart("Desc")
end

function ChattyLittleNpc:QUEST_PROGRESS()
    ChattyLittleNpc:HandlePlaybackStart("Prog")
end

function ChattyLittleNpc:QUEST_COMPLETE()
    ChattyLittleNpc:HandlePlaybackStart("Comp")
end

function ChattyLittleNpc:GOSSIP_CLOSED()
    ChattyLittleNpc:HandlePlaybackStop()
end

function ChattyLittleNpc:QUEST_FINISHED()
    ChattyLittleNpc:HandlePlaybackStop()
end

function ChattyLittleNpc:HandlePlaybackStart(questPhase)
    self:SaveDialogState()
    if (self.dialogState) then
        self:MuteDialogSound()
    end

    local questId = GetQuestID()
    local name, sexStr, race, npcID = self:getUnitInfo("npc")
    self:PlayQuestSound(questId, questPhase, sexStr)
end

function ChattyLittleNpc:HandlePlaybackStop()
    self:ResetDialogToLastState()
    if not self.db.profile.playVoiceoversOnClose then
        self:StopCurrentSound()
        if self.ReplayFrame then self.ReplayFrame:Hide() end
    end
end

function ChattyLittleNpc:IsRetailVersion()
    -- This function checks if the game version is Retail by trying to access an API exclusive to Retail
    return C_QuestLog ~= nil
end