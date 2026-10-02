--!strict

return function(Aim: typeof(require(script.Parent)), camera: Camera)
	local fixture = Instance.new("Folder")
	fixture.Name = "MouseAimSpec"
	fixture.Parent = workspace
	local floor = Instance.new("Part")
	floor.Size = Vector3.new(200, 1, 200)
	floor.Position = Vector3.new(0, -0.5, 0)
	floor.Anchored = true
	floor.Parent = fixture
	local platform = Instance.new("Part")
	platform.Size = Vector3.new(6, 4, 6)
	platform.Position = Vector3.new(-9, 2, -20)
	platform.Anchored = true
	platform.Parent = fixture
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Include
	params.FilterDescendantsInstances = { fixture }
	params.RespectCanCollide = true
	local ok, message = pcall(function()
		local origin = Vector3.new(0, 20, 0)
		for _, point in { Vector3.new(12, 0, -15), Vector3.new(-9, 4, -20), Vector3.new(7, 0, 8) } do
			local screen = camera:WorldToViewportPoint(point)
			local direction, position = Aim.Direction(camera, Vector2.new(screen.X, screen.Y), origin, params)
			assert(
				position and (position - point).Magnitude < 0.001,
				"The cursor must hit the actual surface independent of shooter height"
			)
			local expected = Vector3.new(point.X - origin.X, 0, point.Z - origin.Z).Unit
			assert(
				direction and direction:Dot(expected) > 0.99999,
				"Horizontal attacks must aim at the ground hit's X/Z position"
			)
			local projected = camera:WorldToViewportPoint(position)
			assert(math.abs(projected.Y - screen.Y) < 0.001, "The cursor ray must not subtract the top-bar inset")
		end
		params.FilterDescendantsInstances = {}
		local direction, position = Aim.Direction(camera, camera.ViewportSize * 0.5, origin, params)
		assert(direction == nil and position == nil, "A ray without ground must fail safely")
	end)
	fixture:Destroy()
	assert(ok, tostring(message))
	return "PC mouse aim: actual ground/raised surfaces, shooter height, viewport coordinates and missing ground passed"
end
