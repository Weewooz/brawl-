--!strict

local AttributeUtilities = {}

function AttributeUtilities.BindToAttributeUpdate(instance: Instance, attributeName: string, callback: (any) -> (), doNotCallInstantly: boolean?): RBXScriptConnection
	local connection = instance:GetAttributeChangedSignal(attributeName):Connect(function()
		local newValue = instance:GetAttribute(attributeName)
		callback(newValue)
	end)

	if not doNotCallInstantly then
		local newValue = instance:GetAttribute(attributeName)
		callback(newValue)
	end
	
	return connection
end

return AttributeUtilities