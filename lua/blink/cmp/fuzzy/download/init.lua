local download_config = require('blink.cmp.config').fuzzy.prebuilt_binaries
local files = require('blink.cmp.fuzzy.download.files')
local system = require('blink.cmp.fuzzy.download.system')

local download = {}

--- @param callback fun(err: string | nil)
function download.ensure_downloaded(callback)
  callback = vim.schedule_wrap(callback)

  if not download_config.download then return callback() end

  download.get_git_tag(function(git_version_err, git_version)
    if git_version_err then return callback(git_version_err) end

    files.get_downloaded_version(function(version_err, version)
      files.is_prebuilt_downloaded(function(downloaded)
        local target_version = download_config.force_version or git_version

        -- not built locally, not a git tag, error
        if not downloaded and not target_version then
          return callback(
            "Can't download from github due to not being on a git tag and no fuzzy.prebuilt_binaries.force_version set, but found no built version of the library. "
              .. 'Either run `cargo build --release` via your package manager, switch to a git tag, or set `fuzzy.prebuilt_binaries.force_version` in config. '
              .. 'See the README for more info.'
          )
        end
        -- built locally, ignore
        if downloaded and (version_err or version == nil) then return callback() end
        -- already downloaded and the correct version
        if version == target_version and downloaded then return callback() end
        -- unknown state
        if not target_version then
          return callback('Unknown error while getting pre-built binary. Consider re-installing')
        end

        -- download from github and set version
        download.from_github(target_version, function(download_err)
          if download_err then return callback(download_err) end
          files.set_downloaded_version(target_version, function(set_err)
            if set_err then return callback(set_err) end
            callback()
          end)
        end)
      end)
    end)
  end)
end

--- @param cb fun(downloaded: boolean)
function download.is_downloaded(cb)
  vim.uv.fs_stat(download.lib_path, function(err)
    if not err then return cb(true) end

    -- If not found, check without 'lib' prefix
    vim.uv.fs_stat(
      string.gsub(download.lib_path, 'libblink_cmp_fuzzy', 'blink_cmp_fuzzy'),
      function(error) cb(not error) end
    )
  end)
end

--- @param cb fun(err: string | nil, tag: string | nil)
function download.get_git_tag(cb)
  -- If repo_dir is nil, no git reposiory is found, similar to `out.code == 128`
  local repo_dir = vim.fs.root(files.root_dir, '.git')
  if not repo_dir then
    return vim.schedule(function() return cb() end)
  end

  vim.system({
    'git',
    '--git-dir',
    vim.fs.joinpath(repo_dir, '.git'),
    '--work-tree',
    repo_dir,
    'describe',
    '--tags',
    '--exact-match',
  }, { cwd = files.root_dir }, function(out)
    if out.code == 128 then return cb() end
    if out.code ~= 0 then
      return cb('While getting git tag, git exited with code ' .. out.code .. ': ' .. out.stderr)
    end
    local lines = vim.split(out.stdout, '\n')
    if not lines[1] then return cb('Expected atleast 1 line of output from git describe') end
    return cb(nil, lines[1])
  end)
end

--- @param tag string
--- @param cb fun(err: string | nil)
function download.from_github(tag, cb)
  system.get_triple(function(system_triple)
    if not system_triple then
      return cb(
        'Your system is not supported by pre-built binaries. You must run cargo build --release via your package manager with rust nightly. See the README for more info.'
      )
    end

    local base_url = 'https://github.com/saghen/blink.cmp/releases/download/' .. tag .. '/'
    local library_filename = system_triple .. files.get_lib_extension()
    local checksum_filename = system_triple .. '.sha256'

    local function download_file(url, cb)
      local args = { 'curl' }
      vim.list_extend(args, download_config.extra_curl_args)
      vim.list_extend(args, {
        '--fail', -- Fail on 4xx/5xx
        '--location', -- Follow redirects
        '--silent', -- Don't show progress
        '--show-error', -- Show errors, even though we're using --silent
        '--create-dirs',
        '--output',
        download.lib_path,
        url,
      })

      vim.system(args, {}, function(out)
        if out.code ~= 0 then return cb('Failed to download pre-build binaries: ' .. out.stderr) end
        cb()
      end)
    end

    download_file(base_url .. library_filename, function(err)
      if err then return cb(err) end

      download_file(base_url .. checksum_filename, function(err)
        if err then return cb(err) end
        files.verify_checksum(function(err)
          if err then return cb(err) end
          cb()
        end)
      end)
    end)
  end)
end

return download
