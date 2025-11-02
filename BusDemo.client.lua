local ReplicatedStorage = game:GetService 'ReplicatedStorage'
local Bus = require(ReplicatedStorage.Shared.EventBus)

Bus.on('Hello', function(msg)
  print('[Client] EventBus got:', msg)
end)

task.delay(2, function()
  Bus.emit('Hello', 'hi from client-side bus')
end)
