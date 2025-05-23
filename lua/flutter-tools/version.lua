local lazy = require("flutter-tools.lazy")
local utils = lazy.require("flutter-tools.utils") ---@module "flutter-tools.utils"
local ui = lazy.require("flutter-tools.ui") ---@module "flutter-tools.ui"
local executable = lazy.require("flutter-tools.executable") ---@module "flutter-tools.executable"
local Job = require("plenary.job")

---@class flutter.SemVer
---@field major integer
---@field minor integer
---@field patch integer

---@private
---@class flutter.FlutterVersion
---
--- The version of the Flutter SDK.
---@field frameworkVersion string
---
---@field channel string
---
---@field repositoryUrl string
---
---@field frameworkRevision string
---
---@field frameworkCommitDate string
---
---@field engineRevision string
---
--- The version of the Dart SDK used by the Flutter SDK.
---@field dartSdkVersion string
---
--- The version of devtools included in the Dart SDK. May be nil for Flutter
--- SDKs that use versions of the Dart SDK that do not include the 'devtools'
--- command (Every Dart SDK < 2.15.x).
---@field devToolsVersion string?
---
--- The version of the Flutter SDK. This is the same as frameworkVersion.
--- May be nil for older SDK versions.
---@field flutterVersion string?
---
--- Path to the root directory of the Flutter SDK.
---@field flutterRoot string

local M = {}

---@param callback fun(version:flutter.FlutterVersion):nil
local function _get_version(callback)
  executable.flutter(function(flutter_exe)
    Job:new({
      command = flutter_exe,
      args = { "--version", "--machine" },
      enable_recording = true,
      on_exit = function(job, code, _)
        if 0 ~= code then
          ui.notify(
            "Failed to retrieve the version of the Flutter SDK:\n" ..
            utils.join(job:stderr_result()),
            ui.ERROR
          )
          return
        end

        local raw_json = utils.join(job:result())
        local version = vim.json.decode(raw_json)
        callback(version)
      end
    }):start()
  end)
end

--- Converts version_str into a flutter.SemVer.
--- Returns nil if version_str is malformed.
---
---@param version_str string
---@return flutter.SemVer?
local function _parse_semver(version_str)
  local major, minor, patch = string.match(version_str, "(%d+)%.(%d+)%.(%d+)")
  if nil == major or nil == minor or nil == patch then
    return nil
  end

  return {
    major = tonumber(major),
    minor = tonumber(minor),
    patch = tonumber(patch)
  }
end

--- Retrieves the version of the currently used Flutter and Dart SDK.
---@param callback fun(flutter_version: flutter.SemVer, dart_version:flutter.SemVer):nil
function M.version(callback)
  _get_version(function(version)
    local dart_version = _parse_semver(version.dartSdkVersion)
    if nil == dart_version then
      ui.notify(
        "Failed to parse the Dart SDK version: " ..
        vim.inspect(version.dartSdkVersion),
        ui.ERROR
      )
      return
    end

    local flutter_version = _parse_semver(version.frameworkVersion)
    if nil == flutter_version then
      ui.notify(
        "Failed to parse the Flutter SDK version: " ..
        vim.inspect(version.frameworkVersion),
        ui.ERROR
      )
      return
    end

    callback(flutter_version, dart_version)
  end)
end

--- Retrieves the version of the currently used Flutter SDK.
---@param callback fun(version: flutter.SemVer):nil
function M.flutter_version(callback)
  M.version(function(flutter_version, _)
    callback(flutter_version)
  end)
end

--- Retrieves the version of the currently used Dart SDK.
---@param callback fun(version: flutter.SemVer):nil
function M.dart_version(callback)
  M.version(function(_, dart_version)
    callback(dart_version)
  end)
end

return M
