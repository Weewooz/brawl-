local Http = game:GetService("HttpService")
local Starter = game:GetService("StarterGui")
local Storage = game:GetService("ServerStorage")
local History = game:GetService("ChangeHistoryService")
local Preview = Starter:WaitForChild("Controls")
local Template = Preview:WaitForChild("Template")
local Original = Preview:WaitForChild("Controls")
assert(Template:IsA("TextButton") and Template.Container.Icon:IsA("Frame"), "Controls.Template requires Container.Icon frame")
local Names = {"Attack","Block","Dash","RisingCrash","Spin","Charge","Sprint","GroundShock"}
local Backgrounds = {Attack="99134915816391",Block="81487382219486",Dash="85601907082374",RisingCrash="99134915816391",Spin="106801642554970",Charge="139751609122567",Sprint="104345496505935",GroundShock="73592488866229"}
local Skills = {
 RisingCrash = {Patterns="rbxassetid://106912137358351",Effects="rbxassetid://72452549973821",Katana="rbxassetid://128426923445328"},
 Spin = {Patterns="rbxassetid://128803305506693",Effects="rbxassetid://134094950640514",Katana="rbxassetid://138990562851709"},
 GroundShock = {Patterns="rbxassetid://106814492288646",Effects="rbxassetid://136783138955530",Katana="rbxassetid://133582933091394"}
}
local function ApplyImage(image, content, z, scale)
 image.Image = if content:find("rbxassetid://",1,true) then content else "rbxassetid://"..content
 image.AnchorPoint=Vector2.new(0.5,0.5)
 image.Position=UDim2.fromScale(0.5,0.5)
 image.Size=UDim2.fromScale(scale or 1,scale or 1)
 image.BackgroundTransparency=1
 image.ImageColor3=Color3.new(1,1,1)
 image.ImageTransparency=0
 image.ScaleType=Enum.ScaleType.Fit
 image.ImageRectOffset=Vector2.zero
 image.ImageRectSize=Vector2.zero
 image.Rotation=0
 image.ZIndex=z
 image.Visible=true
 image.Active=false
 image.Selectable=false
end
local function Layer(parent,name,content,z,scale)
 local image=Instance.new("ImageLabel")
 image.Name=name
 ApplyImage(image,content,z,scale)
 image.Parent=parent
 return image
end
local Built=Instance.new("Frame")
Built.Name="Controls"
Built.Size=Original.Size
Built.Position=Original.Position
Built.AnchorPoint=Original.AnchorPoint
Built.BackgroundTransparency=1
Built.BorderSizePixel=0
Built.Visible=true
Built.ClipsDescendants=false
local scale=Instance.new("UIScale")
scale.Name="UIScale"
scale.Scale=1
scale.Parent=Built
for _,name in Names do
 local old=Original:WaitForChild(name)
 assert(old:IsA("TextButton") and old:FindFirstChild("CooldownRing") and old:FindFirstChild("Cooldown"),name.." input feedback is missing")
 local button=Template:Clone()
 button.Name=name
 button.Size=old.Size
 button.Position=old.Position
 button.AnchorPoint=old.AnchorPoint
 button.Rotation=0
 button.Visible=true
 button.Text=""
 button.AutoButtonColor=false
 button.BackgroundTransparency=1
 button.ZIndex=2
 button.Active=true
 button:SetAttribute("InputAction",name)
 button:SetAttribute("ArtworkTemplate","Controls.Template")
 local container=button.Container
 container.ZIndex=1
 container.ClipsDescendants=false
 ApplyImage(container.Background,Backgrounds[name],1)
 ApplyImage(container.Decoration,"134142006452038",2)
 ApplyImage(container.Foreground,"122399349451023",8)
 ApplyImage(container.Cooldown,"106673974330758",7)
 container.Cooldown.ImageTransparency=0.45
 container.Cooldown.Visible=false
 local oldIcon=container.Icon
 local icon=Instance.new("Frame")
 icon.Name="Icon"
 icon.AnchorPoint=Vector2.new(0.5,0.5)
 icon.Position=UDim2.fromScale(0.5,0.5)
 icon.Size=UDim2.fromScale(1,1)
 icon.BackgroundTransparency=1
 icon.BorderSizePixel=0
 icon.ZIndex=3
 oldIcon.Name="TemplateArtwork"
 oldIcon.Parent=nil
 icon.Parent=container
 if name=="Charge" then
  for _,child in oldIcon:GetChildren() do child.Parent=icon end
 elseif Skills[name] then
  Layer(icon,"Patterns",Skills[name].Patterns,3,0.8)
  Layer(icon,"Effects",Skills[name].Effects,4)
  Layer(icon,"Katana",Skills[name].Katana,5)
 else
  local artwork=old:FindFirstChild("Icon") or (old:FindFirstChild("Container") and old.Container.Icon:FindFirstChild("Artwork"))
  assert(artwork and artwork:IsA("ImageLabel"),name.." existing artwork is missing")
  Layer(icon,"Artwork",artwork.Image,4,0.88)
  button:SetAttribute("ArtworkMode","ExistingComposedArtwork")
 end
 local cooldown=old.Cooldown:Clone()
 cooldown.Name="Cooldown"
 cooldown.ZIndex=13
 cooldown.Visible=false
 cooldown.Text=""
 cooldown.Parent=button
 local ring=old.CooldownRing:Clone()
 for _,segment in ring:GetChildren() do if segment:IsA("Frame") then segment.Visible=false segment.ZIndex=12 end end
 ring.Parent=button
 local title=button.Title
 title.Text=old.Title.Text
 title.AnchorPoint=Vector2.new(0.5,0)
 title.Position=UDim2.fromScale(0.5,0.94)
 title.Size=UDim2.fromScale(1.5,0.24)
 title.TextScaled=false
 title.TextSize=if old.Size.X.Offset>85 then 12 else 9
 title.TextColor3=Color3.fromRGB(232,205,150)
 title.TextStrokeTransparency=0.3
 title.TextWrapped=false
 title.ZIndex=15
 local hint=button.Hint
 hint.Text=old.Hint.Text
 hint.AnchorPoint=Vector2.new(0.5,0)
 hint.Position=UDim2.fromScale(0.5,1.2)
 hint.Size=UDim2.fromScale(1.6,0.2)
 hint.TextScaled=false
 hint.TextSize=9
 hint.ZIndex=15
 button.Cost.ZIndex=15
 button.Cost.Text=""
 button.Aim.Visible=false
 button.Aim.ZIndex=14
 button.Parent=Built
end
History:SetWaypoint("Before template input UI")
local backup=Instance.new("Folder")
backup.Name="InputUiBeforeTemplate"
local existing=Storage:FindFirstChild(backup.Name)
if existing then backup.Name=backup.Name..tostring(#Storage:GetChildren()) end
backup.Parent=Storage
Original.Parent=backup
Built.Parent=Preview
local runtime=Starter:WaitForChild("CombatControls")
local previous=runtime:FindFirstChild("Controls")
if previous then previous.Name="RuntimeControls" previous.Parent=backup end
local playable=Built:Clone()
playable.Parent=runtime
Preview:SetAttribute("EditorPreview",true)
Preview.Enabled=true
Template.Visible=false
runtime.Enabled=false
game:GetService("Selection"):Set({Built})
History:SetWaypoint("Rebuilt template input UI")
return Http:JSONEncode({Preview=Built:GetFullName(),Runtime=playable:GetFullName(),Backup=backup:GetFullName(),Count=#Names,TemplatePreserved=Template.Parent==Preview})

