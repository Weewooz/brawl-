local StarterGui=game:GetService("StarterGui")
local History=game:GetService("ChangeHistoryService")
local Selection=game:GetService("Selection")
local Charge=StarterGui.Controls:FindFirstChild("Charge")
assert(Charge and Charge:IsA("TextButton"),"Controls.Charge sample missing")
local Container=Charge:FindFirstChild("Container")
local Icon=Container and Container:FindFirstChild("Icon")
assert(Container and Icon and Icon:IsA("Frame"),"Charge Container/Icon frame missing")
History:SetWaypoint("Before Charge skill artwork")
local function ApplyImage(image,asset,zIndex)
 assert(image and image:IsA("ImageLabel"),"Expected existing image label")
 image.Image="rbxassetid://"..asset
 image.AnchorPoint=Vector2.new(0.5,0.5)
 image.Position=UDim2.fromScale(0.5,0.5)
 image.Size=UDim2.fromScale(1,1)
 image.Rotation=0
 image.BackgroundTransparency=1
 image.ImageTransparency=0
 image.ImageColor3=Color3.new(1,1,1)
 image.ScaleType=Enum.ScaleType.Fit
 image.ImageRectOffset=Vector2.zero
 image.ImageRectSize=Vector2.zero
 image.ZIndex=zIndex
 image.Visible=true
 image.Active=false
 image.Selectable=false
end
local function Layer(name,previous,asset,zIndex)
 local image=Icon:FindFirstChild(name) or (previous and Icon:FindFirstChild(previous))
 if not image then image=Instance.new("ImageLabel") image.Parent=Icon end
 image.Name=name
 ApplyImage(image,asset,zIndex)
 return image
end
ApplyImage(Container.Background,"139751609122567",1)
ApplyImage(Container.Decoration,"134142006452038",2)
Container.Decoration:SetAttribute("ArtworkLayer","BlackBrushTexture")
ApplyImage(Container.Foreground,"122399349451023",8)
Icon.AnchorPoint=Vector2.new(0.5,0.5)
Icon.Position=UDim2.fromScale(0.5,0.5)
Icon.Size=UDim2.fromScale(1,1)
Icon.BackgroundTransparency=1
Icon.Rotation=0
Icon.ZIndex=3
Icon.ClipsDescendants=false
Layer("WindScrolls","Background","122372029049248",3)
Layer("Dash",nil,"98932789717643",4)
Layer("Katana","Foreground","131162068996658",5)
Layer("Target",nil,"138890220933355",6)
local cooldown=Container:FindFirstChild("Cooldown")
if cooldown then cooldown.ZIndex=7 end
Charge.Title.Text="CHARGE"
Charge.Hint.Text="3"
Charge.Aim.Visible=false
local Overlap=Charge.Parent:FindFirstChild("T")
if Overlap and Overlap:IsA("GuiObject") and Overlap.Position==Charge.Position and Overlap.Size==Charge.Size then
	Overlap.Visible=false
	Charge.ZIndex=math.max(Charge.ZIndex,Overlap.ZIndex+1)
end
Selection:Set({Charge})
History:SetWaypoint("Assemble layered Charge skill")
return {Path=Charge:GetFullName(),LayerCount=7,IconChildren=#Icon:GetChildren(),Title=Charge.Title.Text,Hint=Charge.Hint.Text,AimVisible=Charge.Aim.Visible}
