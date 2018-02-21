-- This is an example of how the init.lua script in ~/.hammerspoon/init.lua could be in order to load Miro's Windows Management

local hyper = {"ctrl", "alt", "cmd"}

hs.loadSpoon("MiroWindowsManager")
hs.window.animationDuration = 0
spoon.MiroWindowsManager:bindHotkeys({
  up = {hyper, "up"},
  right = {hyper, "right"},
  down = {hyper, "down"},
  left = {hyper, "left"},
  fullscreen = {hyper, "f"}
})