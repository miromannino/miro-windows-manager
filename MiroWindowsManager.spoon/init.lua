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
obj.version = "1.1"
obj.author = "Miro Mannino <miro.mannino@gmail.com>"
obj.homepage = "https://github.com/miromannino/miro-windows-management"
obj.license = "MIT - https://opensource.org/licenses/MIT"

obj._logger = hs.logger.new(obj.name)
local logger = obj._logger
logger.i("Loading ".. obj.name)


-- ### Utilities
function string.titleCase(str)
  return (str:gsub('^%l', string.upper))
end
local function expect_argument_to_be_in_table(argument, to_be_in)
  assert(
    hs.fnutils.contains(to_be_in, argument),
    'Expected "'.. hs.inspect(argument) ..'" to be one of '.. hs.inspect(to_be_in)
  )
end
local function expect_argument_to_be_in_table_or_nil(argument, to_be_in)
  assert(
    hs.fnutils.contains(to_be_in, argument) or argument == nil,
    'Expected "'.. hs.inspect(argument) ..'" to be one of '.. hs.inspect(to_be_in)
  )
end
local function expect_truthy(argument, expression)
  assert(
    argument,
    'Expected truthyness from '.. hs.inspect(expression)
  )
end


-- ## Public variables

--- MiroWindowsManager.sizes
--- Variable
--- The sizes that the window can have.  
--- The sizes are expressed as dividend of the entire screen's size.  
--- For example `{2, 3, 3/2}` means that it can be 1/2, 1/3 and 2/3 of the total
--- screen's size.
obj.sizes = {2, 3, 3/2}

--- MiroWindowsManager.fullScreenSizes
--- Variable
--- The sizes that the window can have in full-screen.  
--- The sizes are expressed as dividend of the entire screen's size.  
--- For example `{1, 4/3, 2}` means that it can be 1/1 (hence full screen), 3/4
--- and 1/2 of the total screen's size
obj.fullScreenSizes = {1, 4/3, 2}

-- Ensure changes to GRID update hs.grid
--   Prevent obj.GRID from being replaced
local _grid_store_yeeV5hiG = {}  -- we store the real GRID here
setmetatable(obj, {
  __index = function(t,k)
    if k == 'GRID' then return _grid_store_yeeV5hiG else return rawget(t,k) end end,
  __newindex =
    function(t,k,v)
      if k == 'GRID' then
        assert(type(v)=='table',rawget(obj,'name')..".GRID must be a table.")
        -- assign the assigned table's content to our real GRID table
        for kk,vv in pairs(v) do obj.GRID[kk] = vv end
      else
        rawset(t,k,v)
      end
    end,
})
--   Update hs.grid after relevant changes to obj.GRID
local _grid_value_store_Oocaeyim = {}  -- we store the real GRID values here
local m = {
  __newindex =
    function(t,k,v)
      rawset(_grid_value_store_Oocaeyim,k,v)
      if hs.fnutils.contains({'w','h'}, k) then
        hs.grid.setGrid(tostring(_grid_value_store_Oocaeyim.w or 0) ..  'x' ..
          tostring(_grid_value_store_Oocaeyim.h or 0))
      elseif k == 'margins' then
        hs.grid.setMargins(v)
      elseif hs.fnutils.contains({'MARGINX','MARGINY'}, k) then
        -- LEGACY
        if k == 'MARGINX' then
          obj.GRID.margins = hs.geometry(tostring(v) ..'x'..
            tostring(rawget(_grid_value_store_Oocaeyim, 'margins').h or 0))
        elseif k == 'MARGINY' then
          obj.GRID.margins =
            hs.geometry(tostring(rawget(_grid_value_store_Oocaeyim, 'margins').w or 0) ..'x'..
            tostring(v))
        end
      end
      logger.i("Updated hs.grid to ".. hs.inspect(_grid_value_store_Oocaeyim))
    end,
  __index =
    function(t,k) return rawget(_grid_value_store_Oocaeyim, k) end,
}
setmetatable(_grid_store_yeeV5hiG, m)

--- MiroWindowsManager.GRID
--- Variable
--- The screen's grid size.
obj.GRID = { w = 24, h = 24, margins = hs.geometry("0x0") }


--- MiroWindowsManager.pushToNextScreen
--- Variable
--- If `move`d past the screen edge, jump to next screen?
obj.pushToNextScreen = false


-- ## Internal

-- ### Internal configuration

-- Window moves and their relationships
local directions = { 'up', 'down', 'left', 'right' }
local directions_rel = {
  up =    { opp = 'down',  grow = 'taller', dim = 'h', pos = 'y', home = 0 },
  down =  { opp = 'up',    grow = 'taller', dim = 'h', pos = 'y', home = obj.GRID.h },
  left =  { opp = 'right', grow = 'wider',  dim = 'w', pos = 'x', home = 0 },
  right = { opp = 'left',  grow = 'wider',  dim = 'w', pos = 'x', home = obj.GRID.w },
}
-- Window growths and their relationships
local growths = { 'taller', 'shorter', 'wider', 'thinner' }
local growths_rel = {
  taller  = { opp = 'shorter', dim = 'h', pos = 'y', side = 'up',    sticky_bound_fix = false },
  shorter = { opp = 'taller',  dim = 'h', pos = 'y', side = 'down',  sticky_bound_fix = true  },
  wider   = { opp = 'thinner', dim = 'w', pos = 'x', side = 'left',  sticky_bound_fix = false },
  thinner = { opp = 'wider',   dim = 'w', pos = 'x', side = 'right', sticky_bound_fix = true  },
}

-- ### Internal state

obj._pressed = {}
obj._press_timers = {}
hs.fnutils.each(hs.fnutils.concat(directions, growths), function(move)
  obj._pressed[move] = false
  obj._press_timers[move] = hs.timer.doAfter(1, function() obj._pressed[move] = false end)
end)

local function register_press(direction)
  obj._pressed[direction] = true
  obj._press_timers[direction]:start()
end
local function cancel_press(direction)
  obj._pressed[direction] = false
  obj._press_timers[direction]:stop()
end
local function pressedQ(direction)
  return obj._pressed[direction]
end

-- ### Internal convenience functions

-- Accessor for functions on the frontmost window
obj._frontmost = {}
local frontmost = obj._frontmost

-- An hs.window for the frontmost window
function frontmost.window()
  return hs.window.frontmostWindow()
end
-- An hs.grid for the frontmost window
function frontmost.cell()
  local win = frontmost.window()
  return hs.grid.get(win, win:screen())
end

-- ## Public

--- MiroWindowsManager:move(side)
--- Method
--- Move the frontmost window up, down, left, right.  
--- Also:
---   * MiroWindowsManager:moveUp()
---   * MiroWindowsManager:moveDown()
---   * MiroWindowsManager:moveLeft()
---   * MiroWindowsManager:moveRight()
---
--- Parameters:
---  * side - up, down, left, right
---
--- Returns:
---  * The MiroWindowsManager object
function obj:move(side)
  expect_argument_to_be_in_table(side, directions)

  if self:boundQ(side) and not self.pushToNextScreen then
    logger.i("`self.pushToNextScreen` == false so not moving to ".. side .." screen.")
  else
    hs.grid['pushWindow'.. side:titleCase()](frontmost.window())
  end
  return self
end
hs.fnutils.each(directions,  -- up(), down, left, right
  function(move)
    obj['move'.. move:titleCase()] = function(self) return self:move(move) end
  end )


--- MiroWindowsManager:grow(growth)
--- Method
--- Grow the frontmost window taller, shorter, wider, thinner.
--- Also:
---   * MiroWindowsManager:taller()
---   * MiroWindowsManager:shorter()
---   * MiroWindowsManager:wider()
---   * MiroWindowsManager:thinner()
---
--- Parameters:
---  * growth - taller, shorter, wider, thinner
---
--- Returns:
---  * The MiroWindowsManager object
function obj:grow(growth)
  expect_argument_to_be_in_table(growth, growths)

  register_press(growth)
  if pressedQ(growths_rel[growth].opp) then 
    logger.i("Maximising ".. growths_rel[growth].dim .." since "..
      growths_rel[growth].opp .." still active.")
    return self:growFully(growth) -- full width/height
  else
    local sticky_bound_fix = growths_rel[growth].sticky_bound_fix and
      self:boundQ(growths_rel[growth].side) and
      not self:boundQ(directions_rel[growths_rel[growth].side].opp)
    local prev_window_ani
    if sticky_bound_fix then
      prev_window_ani = hs.window.animationDuration
      hs.window.animationDuration = 0
    end

    hs.grid['resizeWindow'.. growth:titleCase()](frontmost.window())

    if sticky_bound_fix then
      logger.i("Sticking to ".. growths_rel[growth].side ..
        " side since we're bound to it.")
      hs.window.animationDuration = prev_window_ani
      self:move(growths_rel[growth].side)
    end
  end
  return self
end
hs.fnutils.each(growths,  -- taller(), shorter, wider, thinner
  function(growth)
    obj[growth] = function(self) return self:grow(growth) end
  end )


--- MiroWindowsManager:growFully(growth)
--- Method
--- Grow the frontmost window to full width / height taller, wider.  
--- Also:
---   * MiroWindowsManager:tallest()
---   * MiroWindowsManager:widest()
---
--- Parameters:
---  * growth - taller, wider
---
--- Returns:
---  * The MiroWindowsManager object
function obj:growFully(growth)
  expect_argument_to_be_in_table(growth, growths)

  local cell = frontmost.cell()
  cell[growths_rel[growth].pos] = 0
  cell[growths_rel[growth].dim] = self.GRID[growths_rel[growth].dim]
  self._setPosition(cell)
  return self
end
function obj:growTallest() return self:growFully('taller') end
function obj:growWidest() return self:growFully('wider') end


--- MiroWindowsManager:go(move)
--- Method
--- Move to screen edge, or cycle to next horizontal or vertical size if already there.  
--- Tap both directions to go full width / height.  
--- Also:  
---   * MiroWindowsManager:goUp()
---   * MiroWindowsManager:goDown()
---   * MiroWindowsManager:goLeft()
---   * MiroWindowsManager:goRight()
---
--- Parameters:
---  * move - up, down, left, right
---
--- Returns:
---  * The MiroWindowsManager object
function obj:go(move)
  if move == 'fullscreen' then return self:goFullscreen() end

  expect_argument_to_be_in_table(move, directions)

  register_press(move)
  if pressedQ(directions_rel[move].opp) then 
    -- if still keydown moving the in the opposite direction, go full width/height
    logger.i("Maximising ".. directions_rel[move].dim .." since "..
      directions_rel[move].opp .." still active.")
    self:growFully(directions_rel[move].grow) -- full width/height
  else
    local cell = frontmost.cell()
    local seq = self:seqQ(move)
    local log_info = "We're at ".. move .." sequence ".. tostring(seq) .."(".. hs.inspect(cell) ..")"
    seq = seq % #self.sizes  -- if #self.sizes then 0
    log_info = log_info .. ", so moving to sequence " .. tostring(seq + 1)
    logger.i(log_info)
    cell[directions_rel[move].dim] = self.GRID[directions_rel[move].dim] / self.sizes[seq + 1]
    if hs.fnutils.contains({'left', 'up'}, move) then
      cell[directions_rel[move].pos] = directions_rel[move].home
    else
      cell[directions_rel[move].pos] = directions_rel[move].home - cell[directions_rel[move].dim]
    end
    self._setPosition(cell)
  end
  return self
end
hs.fnutils.each(directions,  -- goUp(), goDown, goLeft, goRight
  function(move)
    obj['go'.. move:titleCase()] = function(self) return self:go(move) end
  end)

--- MiroWindowsManager:goFullscreen()
--- Method
--- Fullscreen, or cycle to next fullscreen option
---
--- Parameters:
---  * None.
---
--- Returns:
---  * The MiroWindowsManager object
function obj:goFullscreen()
  local cell
  if not self:centeredQ() then
    cell = frontmost.cell()
    cell.x = (self.GRID.w - cell.w) / 2
    cell.y = (self.GRID.h - cell.h) / 2
    self._setPosition(cell)
    if cell == frontmost.cell() then
      -- we didn't move, assume a rounding error
      self._setPosition(self:seqFullCell(1))
    else
      logger.i("Not centered, so centering (".. hs.inspect(cell) ..")")
    end
  else
    local seq = self:seqFullQ()
    local log_info = "We're at fullscreen sequence ".. tostring(seq) .."(".. hs.inspect(frontmost.cell()) ..")"
    seq = seq % #self.fullScreenSizes  -- if #self.fullScreenSizes then 0
    log_info = log_info .. ", so moving to sequence " .. tostring(seq + 1)
    logger.i(log_info)
    cell = self:seqFullCell(seq + 1)  -- next in sequence
    self._setPosition(cell)
  end
  return self
end


-- ## Public undocumented

-- Query fullscreen sequence - 0 means out of sequence
function obj:seqFullQ()
  local cell = frontmost.cell()
  for i = 1,#self.fullScreenSizes do
    if cell == self:seqFullCell(i) then
      return i
    end
  end
  return 0
end

-- Query whether window is centered
function obj:centeredQ()
  local cell = frontmost.cell()
  local h_center = cell.w + 2 * cell.x == self.GRID.w
  local v_center = cell.h + 2 * cell.y == self.GRID.h
  return h_center and v_center
end

-- hs.grid cell for fullscreen sequence `seq`
function obj:seqFullCell(seq)
  local size = {
    x = self.GRID.w / self.fullScreenSizes[seq],
    y = self.GRID.h / self.fullScreenSizes[seq],
  }
  local offset = {
    x = (self.GRID.w - size.x) / 2,
    y = (self.GRID.h - size.y) / 2,
  }
  local cell = hs.geometry({
    x = offset.x,
    y = offset.y,
    w = size.x,
    h = size.y,
  })
  return cell
end


-- Query sequence for `side` - 0 means out of sequence
function obj:seqQ(side)
  expect_argument_to_be_in_table(side, directions)

  if self:boundQ(side) then
    local dim = directions_rel[side].dim
    local width = frontmost.cell()[dim]
    local relative_size = self.GRID[dim] / width
    return hs.fnutils.indexOf(self.sizes, relative_size) or 0
  else
    return 0
  end
end
-- upSeqQ(seq), downSeqQ, leftSeqQ, rightSeqQ
hs.fnutils.each(directions,
  function(side)
    obj[side ..'SeqQ'] = function(self) return self:seqQ(side) end
  end )

-- Set sequence for `side`
function obj:setToSeq(side, seq)
  expect_argument_to_be_in_table(side, directions)
  expect_truthy(type(seq) == 'number', "type(seq) == 'number'")
  expect_truthy(seq ~= 0 and seq <= #self.sizes, "seq ~= 0 and seq <= #self.sizes")

  local cell = frontmost.cell()
  cell[directions_rel[side].pos] = directions_rel[side].home
  cell[directions_rel[side].dim] = self.sizes[seq]
  self._setPosition(cell)
  return self
end
hs.fnutils.each(directions,  -- setToUpSeq(seq), setToDownSeq, setToLeftSeq, setToRightSeq
  function(side)
    obj['setTo'.. side:titleCase() ..'Seq'] = function(self, seq) return self:seq(side, seq) end
  end )

-- Query whether window is bound to `side` (is touching that side of the screen)
function obj:boundQ(side)
  expect_argument_to_be_in_table(side, directions)

  local cell = frontmost.cell()
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
hs.fnutils.each(directions,  -- upBoundQ(), downBoundQ, leftBoundQ, rightBoundQ - on edge?
  function(side)
    obj[side ..'BoundQ'] = function(self) return  self:boundQ(side) end
  end )

-- Set window to cell
function obj._setPosition(cell)
  expect_truthy(
    type(cell) == 'table' and type(cell.type) == 'function' and cell:type() == 'rect',
    "type(cell) == 'table' and type(cell.type) == 'function' and cell:type() == 'rect'")

  local win = hs.window.frontmostWindow()
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
---   moveUp      = {{'⌃','⌥'}, "up"},
---   moveDown    = {{'⌃','⌥'}, "down"},
---   moveLeft    = {{'⌃','⌥'}, "left"},
---   moveRight   = {{'⌃','⌥'}, "right"},
---   taller      = {{'⌃','⌥','⇧'}, "down"},
---   shorter     = {{'⌃','⌥','⇧'}, "up"},
---   wider       = {{'⌃','⌥','⇧'}, "right"},
---   thinner     = {{'⌃','⌥','⇧'}, "left"},
--- })
--- ```
function obj:bindHotkeys(mapping)
  logger.i("Bind Hotkeys for Miro's Windows Manager")

  hs.fnutils.each(directions,  -- up, down, left, right
    function(direction)
      -- go
      if mapping[direction] then
        self.hotkeys[#self.hotkeys + 1] = hs.hotkey.bind(mapping[direction][1], mapping[direction][2],
          function() self:go(direction) end,
          function() cancel_press(direction) end)
      end

      -- move
      local move_command = 'move'.. direction:titleCase()
      if mapping[move_command] then
        self.hotkeys[#self.hotkeys + 1] = hs.hotkey.bind(mapping[move_command][1], mapping[move_command][2],
          function() self:move(direction) end)
      end
    end)

  hs.fnutils.each(growths,  -- taller, shorter, wider, thinner
    function(sense)
      -- grow
      if mapping[sense] then
        self.hotkeys[#self.hotkeys + 1] = hs.hotkey.bind(mapping[sense][1], mapping[sense][2],
          function() self:grow(sense) end,
          function() cancel_press(sense) end)
      end
    end)

  if mapping.fullscreen then
    self.hotkeys[#self.hotkeys + 1] = hs.hotkey.bind(mapping.fullscreen[1], mapping.fullscreen[2],
      function() self:goFullscreen() end)
  end

end

--- MiroWindowsManager:init()
--- Method
--- LEGACY: Calling this is not required.
function obj:init()
  -- Nothing to do here
end

return obj
