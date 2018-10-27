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
--- For example `{2, 3, 3/2}` means that it can be 1/2, 1/3 and 2/3 of the total
--- screen's size.  
--- Ensuring that these numbers all divide both dimensions of
--- MiroWindowsManager.GRID to give integers makes everything work better.
obj.sizes = {2, 3, 3/2}

--- MiroWindowsManager.fullScreenSizes
--- Variable
--- The sizes that the window can have in full-screen.  
--- The sizes are expressed as dividend of the entire screen's size.  
--- For example `{1, 4/3, 2}` means that it can be 1/1 (hence full screen), 3/4
--- and 1/2 of the total screen's size.  
--- Ensuring that these numbers all divide both dimensions of
--- MiroWindowsManager.GRID to give integers makes everything work better.  
--- Special: Use 'c' for the original size and shape of the window before
--- starting to move it, but centered.
obj.fullScreenSizes = {1, 4/3, 2}

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
--- MiroWindowsManager.fullScreenSizes divide these numbers to give integers
--- makes everything work better.  
obj.GRID = { w = 24, h = 24, margins = hs.geometry.point(0,0) }
function obj.GRID.cell()
  return hs.geometry(obj.GRID.margins, hs.geometry.size(obj.GRID.w, obj.GRID.h))
end


--- MiroWindowsManager.moveToNextScreen
--- Variable
--- Boolean value to decide wether or not to move the window on the next screen
--- if the window is moved the screen edge.
obj.moveToNextScreen = false


-- ## Internal

-- ### Internal configuration

-- Window moves and their relationships
obj._directions = { 'up', 'down', 'left', 'right' }
obj._directions_rel = {
  up =    { opp = 'down',  grow = 'taller', dim = 'h', pos = 'y', home = function() return 0 end },
  down =  { opp = 'up',    grow = 'taller', dim = 'h', pos = 'y', home = function() return obj.GRID.h end },
  left =  { opp = 'right', grow = 'wider',  dim = 'w', pos = 'x', home = function() return 0 end },
  right = { opp = 'left',  grow = 'wider',  dim = 'w', pos = 'x', home = function() return obj.GRID.w end },
}

-- Window growths and their relationships
obj._growths = { 'taller', 'shorter', 'wider', 'thinner' }
obj._growths_rel = {
  taller  = { opp = 'shorter', dim = 'h', pos = 'y', side = 'up' },
  shorter = { opp = 'taller',  dim = 'h', pos = 'y', side = 'down' },
  wider   = { opp = 'thinner', dim = 'w', pos = 'x', side = 'left' },
  thinner = { opp = 'wider',   dim = 'w', pos = 'x', side = 'right' },
}

-- The keys used to move, generally the arrow keys, but they could also be WASD or something else
obj._movingKeys = { }
for _,move in ipairs(obj._directions) do
  obj._movingKeys[move] = move
end

-- ### Internal state

obj._pressed = {}
obj._press_timers = {}
obj._originalPositionStore = {}
obj._lastSeq = {}
obj._lastFullscreenSeq = nil
local function initPressed(move)
  obj._pressed[move] = false
  obj._press_timers[move] = hs.timer.doAfter(1, function() obj._pressed[move] = false end)
  obj._originalPositionStore[move] = {}
end
hs.fnutils.each(obj._growths, initPressed)
hs.fnutils.each(obj._directions, initPressed)
initPressed('fullscreen')

local function register_press(direction)
  obj._pressed[direction] = true
  obj._press_timers[direction]:start()
end
local function cancel_press(direction)
  obj._pressed[direction] = false
  obj._press_timers[direction]:stop()
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
hs.fnutils.each(obj._directions,  -- up(), down, left, right
  function(move)
    obj['move'.. titleCase(move)] = function(self) return self:move(move) end
  end )

obj._moveModeKeyWatcher = nil
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



--- MiroWindowsManager:growFully(growth)
--- Method
--- Grow the frontmost window to full width / height taller, wider.  
---
--- Parameters:
---  * growth - 'taller', or 'wider'
---
--- Returns:
---  * The MiroWindowsManager object
function obj:growFully(growth)
  local cell = frontmostCell()
  cell[self._growths_rel[growth].pos] = 0
  cell[self._growths_rel[growth].dim] = self.GRID[self._growths_rel[growth].dim]
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
  register_press(move)
  if currentlyPressed(self._directions_rel[move].opp) then
    -- if still keydown moving the in the opposite direction, go full width/height
    logger.i("Maximising ".. self._directions_rel[move].dim .." since "..
      self._directions_rel[move].opp .." still active.")
    self:growFully(self._directions_rel[move].grow) -- full width/height
  else
    local cell = frontmostCell()
    local seq = self:currentSeq(move)  -- current sequence index or 0 if out of sequence

    local log_info = "We're at ".. move .." sequence ".. tostring(seq) .." (".. cell.string .."), so"

    if hs.fnutils.contains(self.sizes, 'c') and seq == 0 then
      -- We're out of the sequence, so store the current window position
      obj._originalPositionStore[move][frontmostWindow():id()] = frontmostCell()
      log_info = log_info .." remembering position then"
    end

    seq = seq % #self.sizes  -- if at end of #self.sizes then wrap to 0
    log_info =
      log_info .. " moving to sequence " .. tostring(seq + 1) .." (size: ".. tostring(self.sizes[seq + 1]) ..")"
    logger.i(log_info)

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
  logger.i('WFT')

  local seq = self:currentFullscreenSeq()  -- current sequence index or 0 if out of sequence
  local log_info = "We're at fullscreen sequence ".. tostring(seq) .." (".. frontmostCell().string .."), so"

  if hs.fnutils.contains(self.fullScreenSizes, 'c') and seq == 0 then
    -- We're out of the sequence, so store the current window position
    obj._originalPositionStore['fullscreen'][frontmostWindow():id()] = frontmostCell()
    log_info = log_info .." remembering position then"
  end

  seq = seq % #self.fullScreenSizes  -- if #self.fullScreenSizes then 0
  log_info =
    log_info .. " moving to sequence " .. tostring(seq + 1) .." (size: ".. tostring(self.fullScreenSizes[seq + 1]) ..")"
  logger.i(log_info)

  self:setToFullscreenSeq(seq + 1)  -- next in sequence

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
    local dim = self._directions_rel[side].dim
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

-- Set sequence for `side`
function obj:setToSeq(side, seq)
  self._setPosition(self:seqCell(side, seq))
  self._lastSeq[side] = seq
  return self
end

-- hs.grid cell for sequence `seq`
function obj:seqCell(side, seq)
  local cell
  local seq_factor = self.sizes[seq]

  while seq_factor == 'c' and
    obj._originalPositionStore[side][frontmostWindow():id()] == nil do
    logger.i("... but nothing stored, so bouncing to the next position.")

    seq = seq + 1
    seq_factor = self.sizes[seq]
  end

  if seq_factor == 'c' then
    cell = obj._originalPositionStore[side][frontmostWindow():id()]
    logger.i('Restoring stored window size ('.. cell.string ..')')
  else
    cell = frontmostCell()
    cell[self._directions_rel[side].dim] = self.GRID[self._directions_rel[side].dim] / self.sizes[seq]
  end

  if hs.fnutils.contains({'left', 'up'}, side) then
    cell[self._directions_rel[side].pos] = self._directions_rel[side].home()
  else
    cell[self._directions_rel[side].pos] = self._directions_rel[side].home() - cell[self._directions_rel[side].dim]
  end

  return self:snap_to_grid(cell)
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

  local lastMatchedSeq = self._lastFullscreenSeq and  -- if there is a saved last matched seq, and
    self.fullScreenSizes[self._lastFullscreenSeq]  -- it's (still) a valid index to fullScreenSizes

  local lastMatchedSeqMatchesFrontmost = lastMatchedSeq and 
    (cell == self:getFullscreenCell(lastMatchedSeq))

  -- cleanup if the last matched seq doesn't matche the frontmost
  if not lastMatchedSeqMatchesFrontmost then self._lastFullscreenSeq = nil end

  local seq = lastMatchedSeqMatchesFrontmost and lastMatchedSeq or nil
  if seq then 
    logger.i('seq is true, value: ' .. tostring(seq))
    return seq 
  end

  for i = 1,#self.fullScreenSizes do
    logger.i('analyze i ' .. tostring(i))
    if cell == self:getFullscreenCell(i) then
      logger.i('cell == self:getFullscreenCell(i)')
      seq = i
      if obj._lastFullscreenSeq and i == obj._lastFullscreenSeq then 
        logger.i('returning loop ' .. tostring(seq))
        return i 
      end
    end
  end

  logger.i('returning ' .. tostring(seq))

  return seq or 0

end

-- Set fullscreen sequence
function obj:setToFullscreenSeq(seq)
  self._setPosition(self:getFullscreenCell(seq))
  self._lastFullscreenSeq = seq
  return self
end

-- hs.grid cell for fullscreen sequence `seq`
function obj:getFullscreenCell(seq)
  local seq_factor = self.fullScreenSizes[seq]
  local pnt, size

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
---
--- A configuration example can be:
--- ``` lua
--- local mods = {"ctrl", "alt", "cmd"}
--- spoon.MiroWindowsManager:bindHotkeys({
---   up          = {mods, "up"},
---   down        = {mods, "down"},
---   left        = {mods, "left"},
---   right       = {mods, "right"},
---   fullscreen  = {mods, "f"},
---   center      = {mods, "c"},
---   move        = {mods, "v"}
--- })
--- ```
function obj:bindHotkeys(mapping)
  logger.i("Bind Hotkeys for Miro's Windows Manager")

  for _,direction in ipairs(self._directions) do
    if mapping[direction] then
        self.hotkeys[#self.hotkeys + 1] =
          hs.hotkey.bind(mapping[direction][1], mapping[direction][2],
          function() self:go(direction) end,
          function() cancel_press(direction) end)

        -- save the keys that the user decided to be for directions, 
        -- generally the arrows keys, but it could be also WASD.
        self._movingKeys[direction] = mapping[direction][2]
      end
  end

  if mapping.fullscreen then
    self.hotkeys[#self.hotkeys + 1] =
      hs.hotkey.bind(mapping.fullscreen[1], mapping.fullscreen[2],
      function() self:fullscreen() end)
  end

  if mapping.center then
    self.hotkeys[#self.hotkeys + 1] =
      hs.hotkey.bind(mapping.center[1], mapping.center[2],
      function() self:center() end)
  end

  if mapping.move then
    self.hotkeys[#self.hotkeys + 1] =
      hs.hotkey.bind(mapping.move[1], mapping.move[2], 
        function() self:_moveModeOn() end, function() self:_moveModeOff() end)
  end

end

--- MiroWindowsManager:init()
--- Method
function obj:init()
  -- void (but it could be used to initialize the module)
end

return obj
