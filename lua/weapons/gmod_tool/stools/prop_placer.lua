TOOL.Category = "Construction"
TOOL.Name = "Prop Placer"
TOOL.Command = nil
TOOL.ConfigName = ""

if CLIENT then

    language.Add("tool.prop_placer.name", "Prop Placer")
    language.Add("tool.prop_placer.desc", "Places props")
    language.Add("tool.prop_placer.left", "Place prop")
    language.Add("tool.prop_placer.right", "Hold to rotate")
    language.Add("tool.prop_placer.reload", "Change axis")

    TOOL.Information = {
        { name = "left" },
        { name = "right" },
        { name = "reload" },
    }

    local msg_types = {
        ["Error"] = NOTIFY_ERROR,
        ["Other"] = NOTIFY_GENERIC,
        ["Info"] = NOTIFY_HINT,
        ["Scissor"] = NOTIFY_CLEANUP,
        ["Recycle"] = NOTIFY_UNDO
    }

    local msg_sounds = {
        ["Error"] = "buttons/button10.wav",
        ["Recycle"] = "buttons/button15.wav",
        ["Info"] = "buttons/button14.wav",
        ["Scissor"] = "buttons/button24.wav",
        ["Other"] = "buttons/blip1.wav",
    }

    net.Receive("PropPlacerNotify", function()
        local type = net.ReadString()
        local msg = net.ReadString()

        notification.AddLegacy(msg, msg_types[type], 2)
        surface.PlaySound(msg_sounds[type])

    end)

    net.Receive("PropPlacerSetGhostEntity", function()
        local tool = LocalPlayer():GetTool("prop_placer")
        local ent = net.ReadEntity()
        tool.SPGhostEntity = ent
    end)

end

if SERVER then
    util.AddNetworkString("PropPlacerNotify")
    util.AddNetworkString("PropPlacerSetGhostEntity")
end

local function calcPos(tr, ent, sink)
    local rbmins, rbmaxs = ent:GetRotatedAABB(ent:OBBMins(), ent:OBBMaxs())

    rbmins = rbmins - Vector(sink, sink, sink)
    return tr.HitPos - tr.HitNormal * rbmins
end



function TOOL:LeftClick(trace)

    if !self:GetOwner():CheckLimit("props") then
        return false
    end

    if CLIENT and !util.IsValidModel(GetConVar("prop_placer_prop_name"):GetString()) then
        return false
    end

    if SERVER then
        local ent = ents.Create("prop_physics")
        if (!IsValid(ent)) then return end

        if !hook.Run("PlayerSpawnProp", self:GetOwner(), self:GetClientInfo("prop_name")) then
            net.Start("PropPlacerNotify")
            net.WriteString("Error")
            net.WriteString("Cannot spawn this prop")
            net.Send(self:GetOwner())
            return false
        end

        ent:SetCreator(self:GetOwner())

        ent:SetAngles(Angle(
            self:GetClientInfo("pitch"),
            self:GetClientInfo("yaw"),
            self:GetClientInfo("roll")
        ))

        ent:SetModel(self:GetClientInfo("prop_name"))
        local sink = tonumber(self:GetClientInfo("sink"))
        ent:SetPos(calcPos(trace, ent, sink))

        ent:Spawn()

        -- Build custom collision when needed
        if !ent:GetPhysicsObject():IsValid() then
            local mins, maxs = ent:OBBMins(), ent:OBBMaxs()
            ent:PhysicsInitBox(mins, maxs)
            ent:EnableCustomCollisions(true)
        end

        ent:PhysWake()
        ent:GetPhysicsObject():EnableMotion(false)
        self:GetOwner():AddFrozenPhysicsObject(ent, ent:GetPhysicsObject())
        ent:Activate()
        undo.Create("prop")
            undo.AddEntity(ent)
            undo.SetPlayer(self:GetOwner())
        undo.Finish()
        cleanup.Add(self:GetOwner(), "props", ent)
        hook.Run("PlayerSpawnedProp", self:GetOwner(), self:GetClientInfo("prop_name"), ent)
        return true
    end

    return true
end

function TOOL:UpdatePropGhost(ent, ply)
    if !IsValid(ent) then return end
    local tr = ply:GetEyeTrace()
    local pitch = self:GetClientInfo("pitch")
    local yaw = self:GetClientInfo("yaw")
    local roll = self:GetClientInfo("roll")

    local sink = tonumber(self:GetClientInfo("sink"))

    ent:SetAngles( Angle(pitch, yaw, roll) )
    ent:SetPos(calcPos(tr, ent, sink))
    ent:SetNoDraw(false)

end



hook.Add("InputMouseApply", "CaptureMousePropPlacer", function(cmd, x, y, ang)

    local ply = LocalPlayer()

    if
        IsValid(ply) and
        IsValid(ply:GetActiveWeapon()) and
        ply:GetActiveWeapon():GetClass() == "gmod_tool" and
        ply:GetTool() ~= nil and
        ply:GetTool().Name == "Prop Placer" and
        input.IsMouseDown(MOUSE_RIGHT)
        then

        local cvar = GetConVar("prop_placer_" .. ply:GetTool():GetClientInfo("axis"))
        local old_ang = cvar:GetInt()

        local result = 0

        if (old_ang + x) > 360 then
            result = (old_ang + x) - 360
        elseif (old_ang + x) < 0 then
            result = 360 - (old_ang + x)
        else
            result = old_ang + x
        end

        if x > 0 then
            cvar:SetInt(math.ceil(result))
        else
            cvar:SetInt(math.floor(result))
        end

        cmd:SetMouseX(0)
        cmd:SetMouseY(0)
        return true
    end
end)

local white = Color(255,255,255)
local red = Color(255,0,0)
local lply = nil

hook.Add("PostDrawTranslucentRenderables", "PropPlacerGUI", function()
    if lply == nil then
        lply = LocalPlayer() // Cache localplayer for performance
    end

    // If we're not holding the toolgun, don't draw the GUI
    // Performance reasons
    if !IsValid(lply) or ( IsValid(lply:GetActiveWeapon()) and lply:GetActiveWeapon():GetClass() ~= "gmod_tool" ) then return end
    local tool = lply:GetTool("prop_placer")
    if tool == nil or tool.Name != "Prop Placer" then return end
    local ghostEnt = tool.GhostEntity
    if game.SinglePlayer() then ghostEnt = tool.SPGhostEntity end
    if !IsValid(ghostEnt) then return end

    local tr = lply:GetEyeTrace()
    local ang = ghostEnt:GetAngles()
    local axis = tool:GetClientInfo("axis")

    local num = render.GetBlend()
    render.SetBlend(0.7)
    ghostEnt:DrawModel()
    render.SetBlend(num)

    -- Pitch
    cam.Start3D2D(ghostEnt:GetPos(), Angle(ang.p, ang.y, 90), 0.2)
        if axis == "pitch" then
            surface.DrawCircle(0, 0, 120, red)
            draw.DrawText("^ " .. math.Round(ang.p, 1), "GModNotify", 0, 120, red, TEXT_ALIGN_LEFT)
        else
            surface.DrawCircle(0, 0, 120, white)
            draw.DrawText("^ " .. math.Round(ang.p, 1), "GModNotify", 0, 120, white, TEXT_ALIGN_LEFT)
        end
    cam.End3D2D()

    -- Pitch Mirror
    cam.Start3D2D(ghostEnt:GetPos(), Angle(ang.p + 180, ang.y, 90 + 180), 0.2)
        if axis == "pitch" then
            draw.DrawText(math.Round(ang.p, 1) .. " ^", "GModNotify", 0, 120, red, TEXT_ALIGN_RIGHT)
        else
            draw.DrawText(math.Round(ang.p, 1) .. " ^", "GModNotify", 0, 120, white, TEXT_ALIGN_RIGHT)
        end
    cam.End3D2D()

    -- Yaw
    cam.Start3D2D(ghostEnt:GetPos(), Angle(0, ang.y, 0), 0.2)
        if axis == "yaw" then
            surface.DrawCircle(0, 0, 125, red)
            draw.DrawText("^ " .. math.Round(ang.y, 1), "GModNotify", 0, 125, red)
        else
            surface.DrawCircle(0, 0, 125, white)
            draw.DrawText("^ " .. math.Round(ang.y, 1), "GModNotify", 0, 125, white)
        end
    cam.End3D2D()

    -- Yaw Mirror
    cam.Start3D2D(ghostEnt:GetPos(), Angle(0, ang.y + 180, 180), 0.2)
        if axis == "yaw" then
            draw.DrawText(math.Round(ang.y, 1) .. " ^", "GModNotify", 0, 125, red, TEXT_ALIGN_RIGHT)
        else
            draw.DrawText(math.Round(ang.y, 1) .. " ^", "GModNotify", 0, 125, white, TEXT_ALIGN_RIGHT)
        end
    cam.End3D2D()

    -- Roll
    cam.Start3D2D(ghostEnt:GetPos(), ghostEnt:LocalToWorldAngles(Angle(90,0,0)), 0.2)
        if axis == "roll" then
            surface.DrawCircle(0, 0, 115, red)
            draw.DrawText("^ " .. math.Round(ang.r, 1), "GModNotify", 0, 115, red)
        else
            surface.DrawCircle(0, 0, 115, white)
            draw.DrawText("^ " .. math.Round(ang.r, 1), "GModNotify", 0, 115, white)
        end
    cam.End3D2D()

    local roll_ang = Angle(90,0,0)
    roll_ang:RotateAroundAxis(roll_ang:Right(), 180)
    roll_ang = ghostEnt:LocalToWorldAngles(roll_ang)

    -- Roll Mirror
    cam.Start3D2D(ghostEnt:GetPos(), roll_ang, 0.2)
        if axis == "roll" then
            draw.DrawText(math.Round(ang.r, 1) .. " ^", "GModNotify", 0, 115, red, TEXT_ALIGN_RIGHT)
        else
            draw.DrawText(math.Round(ang.r, 1) .. " ^", "GModNotify", 0, 115, white, TEXT_ALIGN_RIGHT)
        end
    cam.End3D2D()

end)

if CLIENT then
    local released = true
end

local function MakeGhostEntityAnyway(self, model)
    -- copied from MakeGhostEntity
	util.PrecacheModel( model )

	-- We do ghosting serverside in single player
	-- It's done clientside in multiplayer
	if ( SERVER && !game.SinglePlayer() ) then return end
	if ( CLIENT && game.SinglePlayer() ) then return end

	-- The reason we need this is because in multiplayer, when you holster a tool serverside,
	-- either by using the spawnnmenu's Weapons tab or by simply entering a vehicle,
	-- the Think hook is called once after Holster is called on the client, recreating the ghost entity right after it was removed.
	if ( !IsFirstTimePredicted() ) then return end

	-- Release the old ghost entity
	self:ReleaseGhostEntity()

	if ( CLIENT ) then
		self.GhostEntity = ents.CreateClientProp( model )
	else
		self.GhostEntity = ents.Create( "prop_physics" )
	end

	-- If there's too many entities we might not spawn..
	if ( !IsValid( self.GhostEntity ) ) then
		self.GhostEntity = nil
		return
	end

	self.GhostEntity:SetModel( model )
	self.GhostEntity:SetPos( vector_origin )
	self.GhostEntity:SetAngles( angle_zero )
	self.GhostEntity:Spawn()

    if self.GhostEntity:GetPhysicsObject():IsValid() then
        -- We do not want physics at all
        self.GhostEntity:PhysicsDestroy()
    end

	-- SOLID_NONE causes issues with Entity.NearestPoint used by Wheel tool
	--self.GhostEntity:SetSolid( SOLID_NONE )
	self.GhostEntity:SetMoveType( MOVETYPE_NONE )
	self.GhostEntity:SetNotSolid( true )
	self.GhostEntity:SetRenderMode( RENDERMODE_TRANSCOLOR )
	self.GhostEntity:SetColor( Color( 255, 255, 255, 150 ) )
end

function TOOL:Think()
    local mdl = self:GetClientInfo("prop_name")
    if !IsValid(self.GhostEntity) or self.GhostEntity:GetModel() ~= mdl then
        self:MakeGhostEntity(mdl, vector_origin, angle_zero)

        if !util.IsValidRagdoll(mdl) and !util.IsValidProp(mdl) and util.IsValidModel(mdl) then
            MakeGhostEntityAnyway(self, mdl)
        end

        if SERVER and game.SinglePlayer() then
            net.Start("PropPlacerSetGhostEntity")
            net.WriteEntity(self.GhostEntity)
            net.Broadcast()
        end

        local ghostEnt = self.GhostEntity
        if CLIENT and game.SinglePlayer() then
            ghostEnt = self.SPGhostEntity
        end

        if CLIENT and IsValid(ghostEnt) then
            ghostEnt:SetNoDraw(true)
            ghostEnt:SetRenderMode(RENDERMODE_TRANSALPHADD)
        end

    end

    self:UpdatePropGhost(self.GhostEntity, self:GetOwner())

    if SERVER then return end

    local reload_down = input.IsKeyDown(input.GetKeyCode(input.LookupBinding("+reload")))

    if reload_down and released then
        released = false
        local cvar = GetConVar("prop_placer_axis")
        local axis = cvar:GetString()
        if axis == "pitch" then
            cvar:SetString("yaw")
        elseif axis == "yaw" then
            cvar:SetString("roll")
        elseif axis == "roll" then
            cvar:SetString("pitch")
        end
    end

    if !reload_down and !released then
        released = true
    end
end

TOOL.ClientConVar[ "prop_name" ] = "models/error.mdl"
TOOL.ClientConVar[ "axis" ] = "yaw"
TOOL.ClientConVar[ "pitch" ] = 0
TOOL.ClientConVar[ "yaw" ] = 0
TOOL.ClientConVar[ "roll" ] = 0
TOOL.ClientConVar[ "sink" ] = 0.0

function TOOL.BuildCPanel(panel)
    local textentry, _ = panel:TextEntry("Model", "prop_placer_prop_name")

    panel:NumSlider("Pitch", "prop_placer_pitch", 0, 359, 1)
    panel:NumSlider("Yaw", "prop_placer_yaw", 0, 359, 1)
    panel:NumSlider("Roll", "prop_placer_roll", 0, 359, 1)

    local btn = vgui.Create("DButton", panel)
    btn:SetText("Reset")
    btn.DoClick = function()
        GetConVar("prop_placer_pitch"):SetFloat(0.0)
        GetConVar("prop_placer_yaw"):SetFloat(0.0)
        GetConVar("prop_placer_roll"):SetFloat(0.0)
    end

    panel:AddItem(btn)

    panel:NumSlider("Sink", "prop_placer_sink", -500, 500, 1)

    local btn2 = vgui.Create("DButton", panel)
    btn2:SetText("Reset")
    btn2.DoClick = function()
        GetConVar("prop_placer_sink"):SetFloat(0.0)
    end

    panel:AddItem(btn2)

    local modelpanel = vgui.Create("DModelPanel", panel)
    modelpanel:Dock(TOP)
    modelpanel:SetTall(400)
    modelpanel:SetModel("models/error.mdl")
    modelpanel:SetPaintBorderEnabled(true)

    local function updateModelPanel()

        if !util.IsValidModel(textentry:GetText()) then
            modelpanel:SetModel("models/error.mdl")
            return
        end

        modelpanel:SetModel(textentry:GetText())

        local ent = modelpanel:GetEntity()
        if !ent then return end
        local model_radius = ent:GetModelRadius()
        local rbmin, rbmax = ent:GetModelBounds()

        local center = math.abs(rbmax.z) - math.abs(rbmin.z)

        modelpanel:SetCamPos(Vector(model_radius * 2.5, 0, center))
        modelpanel:SetLookAt(Vector(0, 0, center))

        local pos = ent:GetPos()
        pos.z = pos.z * 1.2
        ent:SetPos(pos)
    end



    local textentry_oldupdate = textentry.Think
    textentry.Think = function(textentry)
        textentry_oldupdate(textentry)
        if modelpanel:GetModel():lower() ~= textentry:GetText():lower() then
            updateModelPanel()
        end

        if modelpanel:GetTall() ~= modelpanel:GetWide() then
            modelpanel:SetTall(modelpanel:GetWide())
        end
    end

end

local prop_name = ""

hook.Add("HUDPaint", "AddPropPlacerOptionsToSpawnMenu", function()
    local panel = vgui.GetHoveredPanel()
    if !panel or (panel:GetName() ~= "SpawnIcon" and panel:GetName() ~= "DMenuOption" and panel:GetName() ~= "ContentIcon") then return end
    if !LocalPlayer():HasWeapon("gmod_tool") then return end

    local parents = {}
    local parent = panel:GetParent()
    while parent do
        parents[parent:GetName()] = true
        parent = parent:GetParent()
    end

    if parents["SpawnmenuContentPanel"] and panel:GetName() == "ContentIcon" then
        local ent_table = scripted_ents.Get(panel:GetSpawnName())
        if ent_table and ent_table.Model then
            prop_name = ent_table.Model
        end
    end

    if panel:GetName() == "SpawnIcon" then
        prop_name = panel:GetModelName()
    end

    if panel:GetName() ~= "DMenuOption" then return end

    local menu = panel:GetParent()

    local child_names = {}
    for i,child in pairs(menu:GetChildren()) do
        if child:GetName() == "DMenuOption" then
            child_names[string.lower(child:GetText())] = true
        end
    end

    menu = menu:GetParent()

    if !child_names[string.lower(language.GetPhrase("spawnmenu.menu.spawn_with_toolgun"))] then return end
    if prop_name == "" then return end
    if menu.IsModifiedByPropPlacer then return end

    menu:AddSpacer()
    menu.PropPlacerPropName = prop_name

    local option = menu:AddOption("Use with Prop Placer", function()
        GetConVar("prop_placer_prop_name"):SetString(menu.PropPlacerPropName)
        input.SelectWeapon(LocalPlayer():GetWeapon("gmod_tool"))
        RunConsoleCommand("gmod_toolmode", "prop_placer")
    end)
    option:SetIcon("icon16/weather_sun.png")
    menu.IsModifiedByPropPlacer = true
    menu:InvalidateLayout()

end)