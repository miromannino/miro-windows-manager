-- Comment: Lots of work here to save users a little work. Previous versions
-- required users to call MiroWindowsManager:start() every time they changed
-- GRID. The metatable work here watches for those changes and does the work
-- :start() would have done.
--
-- usage:
--   require('extend_GRID').extend(obj, logger)

local M = {}

function M.extend(obj, logger)
  -- Ensure changes to GRID update hs.grid
  --   Prevent obj.GRID from being replaced
  local _grid_store = {}  -- we'll store the real GRID here
  setmetatable(obj, {
    __index = function(t,k)  -- if code reads obj, use this function (eg. `obj.sizes`)
      -- if code accesses obj.GRID, return the real GRID we created above,
      -- otherwise access obj as normal
      if k == 'GRID' then return _grid_store else return rawget(t,k) end end,
    __newindex =
      function(t,k,v)  -- if code writes to obj, use this function (eg. `obj.sizes = {2, 3}`)
        if k == 'GRID' then
        -- if code assigns to obj.GRID (`obj.GRID = ...`), don't overwrite our
        -- real GRID, otherwise access obj as normal
          assert(type(v)=='table', rawget(obj,'name')..".GRID must be a table.")
          -- assign the assigned table's content to our real GRID table
          for kk,vv in pairs(v) do obj.GRID[kk] = vv end
        else
          rawset(t,k,v)
        end
      end,
  })
  --   Update hs.grid after relevant changes to obj.GRID
  local _grid_value_store = {}  -- we store the real GRID *values* here
  setmetatable(_grid_store, {
    __newindex =
      function(_,k,v)  -- if code assigns to our real GRID…
        rawset(_grid_value_store,k,v) -- do the assignment, then…
        if hs.fnutils.contains({'w','h'}, k) then
          -- update hs.grid with hs.grid.setGrid, so the user doesn't have to
          hs.grid.setGrid(tostring(_grid_value_store.w or 0) ..  'x' ..
          tostring(_grid_value_store.h or 0))
          logger.i("Updated hs.grid to ".. hs.inspect(_grid_value_store))
        elseif k == 'margins' then
          -- update hs.grid with hs.grid.setMargins, so the user doesn't have to
          hs.grid.setMargins(v)
          logger.i("Updated hs.grid to ".. hs.inspect(_grid_value_store))
        elseif hs.fnutils.contains({'MARGINX','MARGINY'}, k) then
          -- LEGACY
          if k == 'MARGINX' then
            obj.GRID.margins = hs.geometry(tostring(v) ..'x'..
            tostring(rawget(_grid_value_store, 'margins').h or 0))
          elseif k == 'MARGINY' then
            obj.GRID.margins =
            hs.geometry(tostring(rawget(_grid_value_store, 'margins').w or 0) ..'x'..
            tostring(v))
          end
          logger.i("Updated hs.grid to ".. hs.inspect(_grid_value_store))
        end
      end,
    __index = function(_,k) return rawget(_grid_value_store, k) end,
  })
end

return M
