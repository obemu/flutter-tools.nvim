local lazy = require("flutter-tools.lazy")
local ui = lazy.require("flutter-tools.ui") ---@module "flutter-tools.ui"
local utils = lazy.require("flutter-tools.utils") ---@module "flutter-tools.utils"

---@class flutter.DevLogConfig
---
--- A filter function that determines with events should be written to the
--- logfile. If nil, then everything gets logged.
---@field filter? fun(data:string):boolean
---
---@field enabled boolean
---
---@field notify_errors boolean
---
--- Whether the windows that displays the logfile should be focused when it
--- gets opened.
---@field focus_on_open boolean
---
---@field create_file boolean
---
---@field filepath? string
---
---@field open_cmd string
---
--- The debug level
---@field debug integer

local api = vim.api
local fmt = string.format

local M = {}

---@type flutter.DevLogConfig|nil
local dev_log_config = nil

---@type string
local log_filename = "__FLUTTER_DEV_LOG__"

---@type integer|nil
local log_buf = nil

---@type integer|nil
local log_win = nil

---@type integer|nil
local autocmd_id = nil

--------------------------------
--      Private functions     --
--------------------------------

local function notify_setup_required()
  ui.notify(
    "The log module has not been setup yet",
    ui.ERROR
  )
end

local debug_log = function(_)
  notify_setup_required()
end

--- check if the buffer exists if does and we
--- lost track of it's buffer number re-assign it
local function exists()
  local is_valid = utils.buf_valid(log_buf, log_filename)
  if is_valid and not log_buf then
    log_buf = vim.fn.bufnr(log_filename)
  end
  return is_valid
end

local function on_log_buf_wipeout()
  log_buf = nil
  log_win = nil
end

--- Called whenever the log buffer is entered by the user.
local function on_log_buf_enter()
  vim.cmd("set filetype=log")
  vim.bo[log_buf].modifiable = false
  vim.bo[log_buf].modified = false
end

---Auto-scroll the log buffer to the end of the output
local function autoscroll()
  if not log_win then return end

  -- if the dev log is focused don't scroll it as it will block the
  -- user from persuing.
  if api.nvim_get_current_win() == log_win then return end

  -- Ensure that the log windows still exists in the current tab page.
  local log_win_exists = nil ~= utils.find(
    api.nvim_tabpage_list_wins(0),
    function(item) return log_win == item end
  )
  if not log_win_exists then return end

  local buf_length = api.nvim_buf_line_count(log_buf)
  local success, err = pcall(api.nvim_win_set_cursor, log_win, { buf_length, 0 })
  if not success then
    ui.notify(
      fmt("Failed to set cursor for log window %s: %s", log_win, err),
      ui.ERROR,
      {
        once = true,
      }
    )
  end
end

---Add lines to a buffer
---@param lines string[]
local function append(lines)
  vim.bo[log_buf].modifiable = true
  api.nvim_buf_set_lines(log_buf, -1, -1, true, lines)
  vim.bo[log_buf].modifiable = false
end

---@param on_created? fun():nil
local function create(on_created)
  if not dev_log_config then
    notify_setup_required()
    return
  end

  local cfg = dev_log_config
  local opts = {
    filename = log_filename,
    filetype = "log",
    buftype = "nowrite",
    open_cmd = cfg.open_cmd,
    focus_on_open = cfg.focus_on_open,
  }

  ui.open_win(opts, function(buf, win)
    debug_log("opening log windows")

    if not buf then
      ui.notify("Failed to open the dev log as the buffer could not be found", ui.ERROR)
      return
    end

    log_buf = buf
    log_win = win

    -- Delete old autocommand, in case buffer id changed.
    if nil ~= autocmd_id then
      api.nvim_del_autocmd(autocmd_id)
    end

    autocmd_id = api.nvim_create_autocmd(
      { "BufWipeout", "BufEnter" },
      {
        buffer = buf,
        callback = function(e)
          if "BufWipeout" == e.event then
            on_log_buf_wipeout()
          elseif "BufEnter" == e.event then
            on_log_buf_enter()
          end
        end,
      }
    )

    if on_created then on_created() end
  end)
end

--------------------------------
--      Public functions      --
--------------------------------

--- Check if the log window is open.
---
---@return boolean
function M.is_open()
  -- If the handles are nil, then the window cannot be open.
  if nil == log_win or nil == log_buf then
    return false
  end

  -- If the handles are invalid, then the windows cannot be open.
  if not api.nvim_win_is_valid(log_win) or
      not api.nvim_buf_is_valid(log_buf) then
    log_win = nil
    log_buf = nil
    return false
  end

  -- If the log window is not in the current list of windows, then it cannot
  -- be open.
  local found = nil ~= utils.find(
    api.nvim_list_wins(),
    function(item) return log_win == item end
  )
  if not found then return false end

  return true
end

---@return string[]|nil
function M.get_content()
  debug_log("get_content")

  if not log_buf or not api.nvim_buf_is_valid(log_buf) then
    return nil
  end

  return api.nvim_buf_get_lines(log_buf, 0, -1, false)
end

--- Append a line to the log buffer.
---
---@param data string
function M.log(data)
  local opts = dev_log_config

  -- Return if the log module has not been setup yet (opts is nil),
  -- or if it is disabled.
  if not opts or not opts.enabled then return end

  -- Check if data should be logged, if a filter has been provided.
  if opts.filter and not opts.filter(data) then return end

  local function do_log()
    append({ data })
    autoscroll()
  end

  -- Create the log buffer, if it does not exist already.
  if not exists() then create(do_log) end

  do_log()
end

--- Clear the contents of the log buffer.
function M.clear()
  if not log_buf or not api.nvim_buf_is_valid(log_buf) then
    return
  end

  vim.bo[log_buf].modifiable = true
  api.nvim_buf_set_lines(log_buf, 0, -1, false, {})
  vim.bo[log_buf].modifiable = false
end

--- Open the log window, if it is closed.
---
---@param scroll_to_bottom? boolean Defaults to true.
function M.open(scroll_to_bottom)
  if M.is_open() then return end

  scroll_to_bottom = nil ~= scroll_to_bottom and scroll_to_bottom or true

  create()

  if scroll_to_bottom then
    local buf_length = api.nvim_buf_line_count(log_buf)
    pcall(api.nvim_win_set_cursor, log_win, { buf_length, 0 })
  end
end

--- Close the log window, if it is open.
function M.close()
  if not M.is_open() then return end
  api.nvim_win_close(log_win, true)
end

--- Open the log window, if it is closed and close the window if it is
--- opened.
function M.toggle()
  if M.is_open() then
    M.close()
  else
    M.open()
  end
end

---@param config flutter.DevLogConfig
function M.setup(config)
  -- Setup has already been called.
  if dev_log_config then return end

  dev_log_config = config

  debug_log = utils.create_debug_log(dev_log_config.debug)
end

-----------------------------
--      Module export      --
-----------------------------

return setmetatable(M, {
  __index = function(_, k)
    if "filename" == k then return log_filename end
    return M[k]
  end
})
