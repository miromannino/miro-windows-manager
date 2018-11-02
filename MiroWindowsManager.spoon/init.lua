-- Copyright (c) 2018 Miro Mannino
-- Permission is hereby granted, free of charge, to any person obtaining a copy of this 
-- software and associated documentation files (the "Software"), to deal in the Software 
-- without restriction, including without limitation the rights to use, copy, modify, merge,
-- publish, distribute, sublicense, and/or sell copies of the Software, and to permit persons
-- to whom the Software is furnished to do so, subject to the following conditions:
--
-- The above copyright notice and this permission notice shall be included in all copies
-- or substantial portions of the Software.
--
-- THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, 
-- INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR 
-- PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE
-- FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR 
-- OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER 
-- DEALINGS IN THE SOFTWARE.

--- === MiroWindowsManager ===
---
--- With this Spoon you will be able to move the window in halves and in
--- corners using your keyboard and mainly using arrows. You would also be able
--- to resize them by thirds, quarters, or halves.  
--- Official homepage for more info and documentation:
--- [https://github.com/miromannino/miro-windows-manager](https://github.com/miromannino/miro-windows-manager)
--- 
--- NOTE: This Spoon sets `hs.grid` globals with `hs.grid.setGrid()`,
--- `hs.grid.MARGINX`, and `hs.grid.MARGINY`. Changing MiroWindowsManager.GRID
--- will change these globals.
---
--- Download:
--- https://github.com/miromannino/miro-windows-manager/raw/master/MiroWindowsManager.spoon.zip
---

-- ## TODO
-- different sizes lists for specific apps

local obj={}
obj.__index = obj

-- Metadata
obj.name = "MiroWindowsManager"
obj.version = "1.2"
obj.author = "Miro Mannino <miro.mannino@gmail.com>"
obj.homepage = "https://github.com/miromannino/miro-windows-management"
obj.license = "MIT - https://opensource.org/licenses/MIT"

local logger = hs.logger.new(obj.name)
obj._logger = logger  -- make logger available so users can turn up the volume!
logger.i("Loading ".. obj.name)


-- ## Public variables

--- MiroWindowsManager.sizes
--- Variable
--- The sizes that the window can have.  
--- The sizes are expressed as dividend of the entire screen's size.  
--- For example `{2, 3, 3/2}` means that it can be 1/2, 1/3 and 2/3 of the total screen's size.  
--- Make sure that these numbers divide both dimensions of MiroWindowsManager.GRID to give integers.
obj.sizes = {2, 3, 3/2}

--- MiroWindowsManager.fullScreenSizes
--- Variable
--- The sizes that the window can have in full-screen.  
--- The sizes are expressed as dividend of the entire screen's size.  
--- For example `{1, 4/3, 2}` means that it can be 1/1 (hence full screen), 3/4
--- and 1/2 of the total screen's size.  
--- Make sure that these numbers divide both dimensions of MiroWindowsManager.GRID to give integers.
--- Use 'c' for the original size and shape of the window before starting to move it.
obj.fullScreenSizes = {1, 2, 'c'}

-- Comment: Lots of work here to save users a little work. Previous versions
-- required users to call MiroWindowsManager:start() every time they changed
-- GRID. The metatable work here watches for those changes and does the work
-- :start() would have done.
package.path = package.path..";Spoons/".. ... ..".spoon/?.lua"
require('extend_GRID').extend(obj, logger)

--- MiroWindowsManager.GRID
--- Variable
--- The screen's grid size.  
--- Ensuring that the numbers in MiroWindowsManager.sizes and
--- Make sure that the numbers in MiroWindowsManager.fullScreenSizes divide h and w to give integers.
obj.GRID = { w = 24, h = 24, margins = hs.geometry.point(0,0) }
function obj.GRID.cell()
  return hs.geometry(obj.GRID.margins, hs.geometry.size(obj.GRID.w, obj.GRID.h))
end


--- MiroWindowsManager.pushToNextScreen
--- Variable
--- Boolean value to decide wether or not to move the window on the next screen
--- if the window is moved the screen edge.
obj.pushToNextScreen = false


--- MiroWindowsManager.resizeRate
--- Variable
--- Float value to decide the the rate to resize windows. With a value of 1.05 it means that 
--- everytime the window is made taller/wider by 5% more (or shorter/thinner by 5% less)
obj.resizeRate = 1.05

-- ## Internal

obj._directions = { 'up', 'down', 'left', 'right' }
obj._directionsRel = {
  up =    { opp = 'down',  dim = 'h', pos = 'y', home = function() return 0 end },
  down =  { opp = 'up',    dim = 'h', pos = 'y', home = function() return obj.GRID.h end },
  left =  { opp = 'right', dim = 'w', pos = 'x', home = function() return 0 end },
  right = { opp = 'left',  dim = 'w', pos = 'x', home = function() return obj.GRID.w end }
}
obj._growths = { 'taller', 'shorter', 'wider', 'thinner' }
obj._growthsRel = {
  taller  = { opp = 'shorter', dim = 'h', pos = 'y', growthSign = 1 },
  shorter = { opp = 'taller',  dim = 'h', pos = 'y', growthSign = -1 },
  wider   = { opp = 'thinner', dim = 'w', pos = 'x', growthSign = 1 },
  thinner = { opp = 'wider',   dim = 'w', pos = 'x', growthSign = -1 },
}

-- The keys used to move, generally the arrow keys, but they could also be WASD or something else
obj._movingKeys = { }
for _,move in ipairs(obj._directions) do
  obj._movingKeys[move] = move
end

obj._originalPositionStore = { fullscreen = {} }

obj._moveModeKeyWatcher = nil
obj._resizeModeKeyWatcher = nil

obj._pressed = {}
obj._pressTimers = {}
obj._lastSeq = {}
obj._lastFullscreenSeq = nil
local function initPressed(move)
  obj._pressed[move] = false
  obj._pressTimers[move] = hs.timer.doAfter(1, function() obj._pressed[move] = false end)
end
hs.fnutils.each(obj._directions, initPressed)
local function registerPress(direction)
  obj._pressed[direction] = true
  obj._pressTimers[direction]:start()
end
local function cancelPress(direction)
  obj._pressed[direction] = false
  obj._pressTimers[direction]:stop()
end
local function currentlyPressed(direction)
  return obj._pressed[direction]
end


-- ### Utilities

function titleCase(str)
  return (str:gsub('^%l', string.upper))
end

function round(num)
  if num >= 0 then
    return math.floor(num+.499999999)
  else
    return math.ceil(num-.499999999)
  end
end

-- Accessor for functions on the frontmost window
function frontmostWindow()
  return hs.window.frontmostWindow()
end

function frontmostScreen()
  return frontmostWindow():screen()
end

function frontmostCell()
  local win = frontmostWindow()
  return hs.grid.get(win, win:screen())
end

-- ## Public

--- MiroWindowsManager:move(side)
--- Method
--- Move the frontmost window up, down, left, right.  
---
--- Parameters:
---  * side - 'up', 'down', 'left', or 'right'
---
--- Returns:
---  * The MiroWindowsManager object
function obj:move(side)
  if self:currentlyBound(side) and not self.pushToNextScreen then
    logger.i("`self.pushToNextScreen` == false so not moving to ".. side .." screen.")
  else
    logger.i('Moving '.. side)
    hs.grid['pushWindow'.. titleCase(side)](frontmostWindow())
  end
  return self
end
function obj:_moveModeOn()
  logger.i("Move Mode on")
  self._moveModeKeyWatcher = hs.eventtap.new({ hs.eventtap.event.types.keyDown }, function(ev)
    local keyCode = ev:getKeyCode()

    if keyCode == hs.keycodes.map[self._movingKeys['left']] then
      self:move('left')
      return true
    elseif keyCode == hs.keycodes.map[self._movingKeys['right']] then
      self:move('right')
      return true
    elseif keyCode == hs.keycodes.map[self._movingKeys['down']] then
      self:move('down')
      return true
    elseif keyCode == hs.keycodes.map[self._movingKeys['up']] then
      self:move('up')
      return true
    else
      return false
    end
  end):start()
end
function obj:_moveModeOff()
  logger.i("Move Mode off");
  self._moveModeKeyWatcher:stop()
end

--- MiroWindowsManager:resize(growth)
--- Method
--- Resize the frontmost window taller, shorter, wider, thinner.
---
--- Parameters:
---  * growth - 'taller', 'shorter', 'wider', 'thinner'
---
--- Returns:
---  * The MiroWindowsManager object
function obj:resize(growth)
  logger.i('resize ' .. growth)

  local w = frontmostWindow()
  local fr = w:frame()

  local growthDiff = fr[self._growthsRel[growth].dim] * (self.resizeRate - 1) 
  fr[self._growthsRel[growth].pos] = fr[self._growthsRel[growth].pos] - (self._growthsRel[growth].growthSign * growthDiff / 2)
  fr[self._growthsRel[growth].dim] = fr[self._growthsRel[growth].dim] + (self._growthsRel[growth].growthSign * growthDiff)

  if fr['y'] < 0 then fr['y'] = 0 end
  if fr['x'] < 0 then fr['x'] = 0 end

  w:setFrame(fr)
  return self
end
function obj:_resizeModeOn()
  logger.i("Resize Mode on")
  self._resizeModeKeyWatcher = hs.eventtap.new({ hs.eventtap.event.types.keyDown }, function(ev)
    local keyCode = ev:getKeyCode()
    if keyCode == hs.keycodes.map[self._movingKeys['left']] then
      self:resize('thinner')
      return true
    elseif keyCode == hs.keycodes.map[self._movingKeys['right']] then
      self:resize('wider')
      return true
    elseif keyCode == hs.keycodes.map[self._movingKeys['down']] then
      self:resize('shorter')
      return true
    elseif keyCode == hs.keycodes.map[self._movingKeys['up']] then
      self:resize('taller')
      return true
    else
      return false
    end
  end):start()
end
function obj:_resizeModeOff()
  logger.i("Resize Mode off");
  self._resizeModeKeyWatcher:stop()
end

--- MiroWindowsManager:growFully(growth)
--- Method
--- Grow the frontmost window to full width / height.
---
--- Parameters:
---  * dimension - 'h', or 'w'
---
--- Returns:
---  * The MiroWindowsManager object
function obj:growFully(dimension)
  local cell = frontmostCell()
  cell[dimension == 'h' and 'y' or 'x'] = 0
  cell[dimension] = self.GRID[dimension]
  self._setPosition(cell)
  return self
end


--- MiroWindowsManager:go(move)
--- Method
--- Move to screen edge, or cycle to next horizontal or vertical size if already there.  
--- Tap both directions to go full width / height.  
---
--- Parameters:
---  * move - 'up', 'down', 'left', 'right'
---
--- Returns:
---  * The MiroWindowsManager object
function obj:go(move)
  registerPress(move)
  if currentlyPressed(self._directionsRel[move].opp) then
    -- if still keydown moving the in the opposite direction, go full width/height
    logger.i("Maximising " .. self._directionsRel[move].dim .. " since " 
      .. self._directionsRel[move].opp .." still active.")
    self:growFully(self._directionsRel[move].dim) -- full width/height
  else
    local cell = frontmostCell()
    local seq = self:currentSeq(move)  -- current sequence index or 0 if out of sequence

    logger.i("We're at ".. move .." sequence ".. tostring(seq) .." (".. cell.string ..")")

    seq = seq % #self.sizes  -- if at end of #self.sizes then wrap to 0
    logger.i("Updating seq to " .. tostring(seq + 1) .." (size: ".. tostring(self.sizes[seq + 1]) ..")")

    self:setToSeq(move, seq + 1)
  end
  return self
end

--- MiroWindowsManager:fullscreen()
--- Method
--- Fullscreen, or cycle to next fullscreen option
---
--- Parameters:
---  * None.
---
--- Returns:
---  * The MiroWindowsManager object
function obj:fullscreen()
  local seq = self:currentFullscreenSeq()  -- current sequence index or 0 if out of sequence
  logger.i("We're at fullscreen sequence ".. tostring(seq) .." (".. frontmostCell().string ..")")

  if seq == 0 then
    if hs.fnutils.contains(self.fullScreenSizes, 'c') then
      logger.i("Since we are at seq 0, storing current position to use it with 'c' for window " .. frontmostWindow():id())
      self._originalPositionStore['fullscreen'][frontmostWindow():id()] = frontmostCell()
    end
  end

  seq = seq % #self.fullScreenSizes + 1  -- if seq = #self.fullScreenSizes then 0 so next seq = 1 (we cycle through sizes)
  logger.i("Updating seq to " .. tostring(seq) .." (size: ".. tostring(self.fullScreenSizes[seq]) ..")")

  if self.fullScreenSizes[seq] == 'c' then
    logger.i("Seq is 'c' but we don't have a saved position, skip to the next one")
    if not self._originalPositionStore['fullscreen'][frontmostWindow():id()] then 
      seq = seq % #self.fullScreenSizes + 1
    end
  end

  self:setToFullscreenSeq(seq)  -- next in sequence

  return self
end

--- MiroWindowsManager:center()
--- Method
--- Center
---
--- Parameters:
---  * None.
---
--- Returns:
---  * The MiroWindowsManager object
function obj:center()
  local cell = frontmostCell()
  cell.center = self.GRID.cell().center
  self._setPosition(cell)
  return self
end

-- ### Side methods (up, down, left, right)
-- Query sequence for `side` - 0 means out of sequence
function obj:currentSeq(side)
  if self:currentlyBound(side) then
    local dim = self._directionsRel[side].dim
    local width = frontmostCell()[dim]
    local relative_size = self.GRID[dim] / width

    -- TODO
    local lastMatchedSeq =
      self._lastSeq[side] and  -- we've recorded a last seq, and
      self.sizes[self._lastSeq[side]] and  -- it's a valid index to sizes
      self._lastSeq[side]
      local lastMatchedSeqMatchesFrontmost =
      lastMatchedSeq and (self.sizes[lastMatchedSeq] == relative_size)

    -- cleanup
    if not lastMatchedSeqMatchesFrontmost then self._lastSeq[side] = nil end

    local seq =
      lastMatchedSeqMatchesFrontmost and lastMatchedSeq or  -- return it
      -- if another from sizes matches, return it
      hs.fnutils.indexOf(self.sizes, relative_size) or
      -- else 0
      0

      return seq
    else
      return 0
    end
  end

-- Set sequence for `move`
function obj:setToSeq(move, seq)
  local cell = frontmostCell()

  cell[self._directionsRel[move].dim] = self.GRID[self._directionsRel[move].dim] / self.sizes[seq]

  if move == 'left' or move == 'up' then
    cell[self._directionsRel[move].pos] = self._directionsRel[move].home()
  else
    cell[self._directionsRel[move].pos] = self._directionsRel[move].home() - cell[self._directionsRel[move].dim]
  end

  cell = self:snap_to_grid(cell)

  self._setPosition(cell)
  self._lastSeq[move] = seq
  return self
end

-- Query whether window is bound to `side` (is touching that side of the screen)
function obj:currentlyBound(side)
  local cell = frontmostCell()
  if side == 'up' then
    return cell.y == 0
    elseif side == 'down' then
      return cell.y + cell.h == self.GRID.h
      elseif side == 'left' then
        return cell.x == 0
        elseif side == 'right' then
          return cell.x + cell.w == self.GRID.w
        end
      end

-- ### Fullscreen methods

-- Query whether window is centered
function obj:currentlyCentered()
  local cell = frontmostCell()
  return cell.w + 2 * cell.x == self.GRID.w and
  cell.h + 2 * cell.y == self.GRID.h
end

function obj:snap_to_grid(cell)
  hs.fnutils.each({'w','h','x','y'}, function(d) cell[d] = round(cell[d]) end)
  return cell
end

-- Query fullscreen sequence - 0 means out of sequence
function obj:currentFullscreenSeq()
  local cell = frontmostCell()

  -- optimization, most likely the window is at the same place as the last fullscreen seq
  if self._lastFullscreenSeq and  -- if there is a saved last matched seq, and
      self.fullScreenSizes[self._lastFullscreenSeq] and -- it's (still) a valid index to fullScreenSizes
      cell == self:getFullscreenCell(self._lastFullscreenSeq) then -- last matched seq is same as the current fullscreen
    logger.i('last matched seq is same as current cell, so returning seq = ' .. tostring(self._lastFullscreenSeq))
    return self._lastFullscreenSeq 
  else 
    self._lastFullscreenSeq = nil -- cleanup if the last matched seq doesn't match the frontmost
  end

  -- trying to see which fullscreen size is the current window
  for i = 1,#self.fullScreenSizes do
    logger.i('analyze seq = ' .. tostring(i))
    if cell == self:getFullscreenCell(i) then
      logger.i('cell == self:getFullscreenCell(seq)')
      return i
    end
  end

  -- we cannot find any fullscreen size that match the current window state, so we start with 0
  return 0

end

-- Set fullscreen sequence
function obj:setToFullscreenSeq(seq)
  logger.i('lastMatchedSeq: ' .. tostring(lastMatchedSeq))

  self._setPosition(self:getFullscreenCell(seq))

  if self.fullScreenSizes[seq] == 'c' then
    -- we want to use the value only once and then discarge
    -- this is in case the window was in one of the full screen position/size
    self._originalPositionStore['fullscreen'][frontmostWindow():id()] = nil
  end

  self._lastFullscreenSeq = seq
  return self
end

-- hs.grid cell for fullscreen sequence `seq`
function obj:getFullscreenCell(seq)
  local seq_factor = self.fullScreenSizes[seq]
  local pnt, size

  if seq_factor == 'c' then
    return self._originalPositionStore['fullscreen'][frontmostWindow():id()]
  end

  logger.i('window id: ' .. tostring(frontmostWindow():id()))
  logger.i('windows: ' .. hs.inspect(self._originalPositionStore['fullscreen']))

  size = hs.geometry.size(
    self.GRID.w / seq_factor,
    self.GRID.h / seq_factor
    )
  pnt = hs.geometry.point(
    (self.GRID.w - size.w) / 2,
    (self.GRID.h - size.h) / 2
    )

  return self:snap_to_grid(hs.geometry(pnt, size))
end

-- Set window to cell
function obj._setPosition(cell)
  local win = frontmostWindow()
  hs.grid.set(win, cell, win:screen())
end


-- ## Spoon mechanics (`bind`, `init`)

obj.hotkeys = {}

--- MiroWindowsManager:bindHotkeys()
--- Method
--- Binds hotkeys for Miro's Windows Manager
---
--- Parameters:
---  * mapping - A table containing hotkey details for the following items:
---   * left: for the left action (usually `{hyper, "left"}`)
---   * right: for the right action (usually `{hyper, "right"}`)
---   * up: for the up action (usually {hyper, "up"})
---   * down: for the down action (usually `{hyper, "down"}`)
---   * fullscreen: for the full-screen action (e.g. `{hyper, "f"}`)
---   * center: for the center action (e.g. `{hyper, "c"}`)
---   * move: for the move action (e.g. `{hyper, "v"}`). The move action is
---           active as soon as the hotkey is pressed. While active the left, 
---           right, up or down keys can be used (these are configured by 
---           the actions above). 
---
--- A configuration example can be:
--- ``` lua
--- local hyper = {"ctrl", "alt", "cmd"}
--- spoon.MiroWindowsManager:bindHotkeys({
---   up          = {hyper, "up"},
---   down        = {hyper, "down"},
---   left        = {hyper, "left"},
---   right       = {hyper, "right"},
---   fullscreen  = {hyper, "f"},
---   center      = {hyper, "c"},
---   move        = {hyper, "v"}
--- })
---
--- In this example ctrl+alt+cmd+up will perform the 'up' action
--- Keeping ctrl+alt+cmd+v pressed you can move the window using the arrow keys up,down,left, and right
--- Pressing ctrl+alt+cmd+f the window will be maximized.
--- ```
function obj:bindHotkeys(mapping)
  logger.i("Bind Hotkeys for Miro's Windows Manager")

  for _,direction in ipairs(self._directions) do
    if mapping[direction] then
      self.hotkeys[#self.hotkeys + 1] = hs.hotkey.bind(
        mapping[direction][1], 
        mapping[direction][2],
        function() self:go(direction) end,
        function() cancelPress(direction) end)

        -- save the keys that the user decided to be for directions, 
        -- generally the arrows keys, but it could be also WASD.
        self._movingKeys[direction] = mapping[direction][2]
      end
    end

    if mapping.fullscreen then
      self.hotkeys[#self.hotkeys + 1] = hs.hotkey.bind(
        mapping.fullscreen[1], 
        mapping.fullscreen[2],
        function() self:fullscreen() end)
    end

    if mapping.center then
      self.hotkeys[#self.hotkeys + 1] = hs.hotkey.bind(
        mapping.center[1], 
        mapping.center[2],
        function() self:center() end)
    end

    if mapping.move then
      self.hotkeys[#self.hotkeys + 1] = hs.hotkey.bind(
        mapping.move[1], 
        mapping.move[2], 
        function() self:_moveModeOn() end, 
        function() self:_moveModeOff() end)
    end

    if mapping.resize then
      self.hotkeys[#self.hotkeys + 1] = hs.hotkey.bind(
        mapping.resize[1], 
        mapping.resize[2], 
        function() self:_resizeModeOn() end, 
        function() self:_resizeModeOff() end)
    end

    hs.hotkey.bind(
      {"ctrl", "alt", "cmd"},
      "l",
      function () 
        logger.i('window id: ' .. tostring(frontmostWindow():id()))
        logger.i('windows: ' .. hs.inspect(self._originalPositionStore['fullscreen']))
      end)

  end

--- MiroWindowsManager:init()
--- Method
function obj:init()
  -- void (but it could be used to initialize the module)
end

return obj
