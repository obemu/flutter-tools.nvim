local lazy = require("flutter-tools.lazy")
local executable = lazy.require("flutter-tools.executable") ---@module "flutter-tools.executable"
local Job = require("plenary.job") ---@module "plenary.job"

---@class flutter.DetectedBanners
---
--- True, if the banner that matches `PATTERNS.FLUTTER_NEW_VERSION` has been
--- detected.
---
--- This banner will be detected if the file
--- `$FLUTTER_SDK/bin/cache/flutter_version_check.stamp` does not exist, or
--- reached a certain age. (Assuming `$FLUTTER_SDK` is the path to the directory
--- that contains your Flutter SDK).
---
--- See the [version.dart from the Flutter SDK](https://github.com/flutter/flutter/blob/3.35.7/packages/flutter_tools/lib/src/version.dart#L1303).
---@field has_flutter_new_version boolean
---
--- True, if the banner that matches `PATTERNS.FLUTTER_WELCOME` has been
--- detected.
---
--- This banner will be detected if the file `$HOME/.config/flutter/tool_state`
--- does not exist, or you changed your Flutter SDK to one with a different
--- welcome banner.
---
--- See the [first_run.dart from the Flutter SDK](https://github.com/flutter/flutter/blob/3.35.7/packages/flutter_tools/lib/src/reporting/first_run.dart#L13).
---@field has_flutter_welcome boolean

---@private
---@alias flutter.internal.OnBannersClearedListener fun(detect_banners: flutter.DetectedBanners):nil

---@type flutter.DetectedBanners?
local cached_banners = nil

---@type flutter.internal.OnBannersClearedListener[]
local on_cleared_listeners = {}

local has_started_cleansing = false

---@type uv.uv_timer_t?
local cache_clear_timer = nil

local M = {
  PATTERNS = {
    FLUTTER_NEW_VERSION = "A new version of Flutter is available!",
    FLUTTER_WELCOME = "Welcome to Flutter!",
  },
}

---@param lines string[]
---@return flutter.DetectedBanners
local function detect_banners(lines)
  ---@type flutter.DetectedBanners
  local banners = {
    has_flutter_new_version = false,
    has_flutter_welcome = false,
  }

  for _, line in ipairs(lines) do
    if nil ~= line:match(M.PATTERNS.FLUTTER_NEW_VERSION) then
      banners.has_flutter_new_version = true
    end

    if nil ~= line:match(M.PATTERNS.FLUTTER_WELCOME) then
      banners.has_flutter_welcome = true
    end
  end

  return banners
end

--- Calls every listener from `on_cleared_listeners`, once `do_clear_banners` is
--- done. Internally caches all listeners and then resets `on_cleared_listeners`
--- to an empty table.
---
---@param detected_banners flutter.DetectedBanners
local function on_cleared_banners(detected_banners)
  -- The cache needs to be cleaned after a certain time, otherwise the error
  -- from issue #495 (https://github.com/nvim-flutter/flutter-tools.nvim/pull/495)
  -- appears again.
  --
  -- This happens, because the Flutter CLI tool notifies the user again, if the
  -- last notification is at least `maxTimeSinceLastWarning` (https://github.com/flutter/flutter/blob/3.35.7/packages/flutter_tools/lib/src/version.dart#L1204)
  -- old. This can be seen in the `VersionFreshnessValidator.run` (https://github.com/flutter/flutter/blob/3.35.7/packages/flutter_tools/lib/src/version.dart#L1262).
  --
  -- To fix this problem, we clear the cache before `maxTimeSinceLastWarning`
  -- is reached.
  if cache_clear_timer == nil then
    cache_clear_timer = vim.defer_fn(
      function() M.reset_cache() end,
      20 * 3600 * 1000
    )
  end

  local listeners = vim.deepcopy(on_cleared_listeners)
  on_cleared_listeners = {}
  vim.schedule(function()
    for _, cb in ipairs(listeners) do
      cb(detected_banners)
    end
  end)
end

local function do_clear_banners(is_flutter_project)
  assert(nil == cached_banners)
  assert(not has_started_cleansing)

  has_started_cleansing = true

  executable.get(function(paths)
    if is_flutter_project then
      Job:new({
        command = paths.flutter_bin,
        args = { "--version" },
        enable_recording = true,
        on_exit = function(self, code, _)
          -- Exit code should always be 0.
          assert(0 == code)

          -- 'flutter --version' writes everything to STDOUT including the
          -- "Welcome" and "New Flutter Version" banner.
          ---@type string[]
          local lines = self:result()

          local banners = detect_banners(lines)
          cached_banners = banners

          on_cleared_banners(cached_banners)
        end,
      }):start()
    else
      -- Only flutter CLI shows startup banners that interfer with the
      -- Debug-/Jobrunner.
      --
      -- dart CLI does currently not show anything, maybe there will
      -- be a banner in the future.
      cached_banners = {
        has_flutter_welcome = false,
        has_flutter_new_version = false,
      }

      on_cleared_banners(cached_banners)
    end
  end)
end

--- Clear and detect any startup banners from the Flutter or Dart CLI tool.
--- `on_cleared` is called, after all banners have been cleared.
---
---@param is_flutter_project boolean
---@param on_cleared fun(detected_banners: flutter.DetectedBanners)
function M.clear_startup_banners(is_flutter_project, on_cleared)
  if nil ~= cached_banners then
    vim.schedule(function() on_cleared(cached_banners) end)
    return
  end

  table.insert(on_cleared_listeners, on_cleared)

  if not has_started_cleansing then do_clear_banners(is_flutter_project) end
end

--- Reset the internally cached banners.
function M.reset_cache()
  cached_banners = nil
  on_cleared_listeners = {}
  has_started_cleansing = false

  if cache_clear_timer ~= nil then
    cache_clear_timer:stop()
    cache_clear_timer:close()
    cache_clear_timer = nil
  end
end

return M
