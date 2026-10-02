--!strict
local Workspace = game:GetService("Workspace")
local MouseAim = {}
local DISTANCE = 2048

function MouseAim.Direction(
	camera: Camera,
	location: Vector2,
	origin: Vector3,
	params: RaycastParams
): (Vector3?, Vector3?)
	-- GetMouseLocation and ViewportPointToRay both include the top-bar area.
	local ray = camera:ViewportPointToRay(location.X, location.Y)
	local hit = Workspace:Raycast(ray.Origin, ray.Direction * DISTANCE, params)
	if not hit then
		return nil, nil
	end
	local point = hit.Position
	local offset = Vector3.new(point.X - origin.X, 0, point.Z - origin.Z)
	return if offset.Magnitude > 0.001 then offset.Unit else nil, point
end

return table.freeze(MouseAim)
