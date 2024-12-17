local function get_lib_extension()
  if jit.os:lower() == 'mac' or jit.os:lower() == 'osx' then return '.dylib' end
  if jit.os:lower() == 'windows' then return '.dll' end
  return '.so'
end

local root_dir = debug.getinfo(1).source:match('@?(.*/)')

local files = {
  get_lib_extension = get_lib_extension,
  root_dir = root_dir,
  lib_path = root_dir .. '../../../../target/release/libblink_cmp_fuzzy' .. get_lib_extension(),
  checksum_path = root_dir .. '../../../../target/release/libblink_cmp_fuzzy.sha256',
  version_path = root_dir .. '../../../../target/release/version.txt',
}

function files.read_file(path, cb)
  return vim.uv.fs_open(path, 'r', 438, function(open_err, fd)
    if open_err or fd == nil then return cb(open_err or 'Unknown error') end
    vim.uv.fs_read(fd, 8, 0, function(read_err, data)
      vim.uv.fs_close(fd, function() end)
      if read_err or data == nil then return cb(read_err or 'Unknown error') end
      return cb(nil, data)
    end)
  end)
end

function files.write_file(path, data, cb)
  return vim.uv.fs_open(path, 'w', 438, function(open_err, fd)
    if open_err or fd == nil then return cb(open_err or 'Unknown error') end
    vim.uv.fs_write(fd, data, 0, function(write_err)
      vim.uv.fs_close(fd, function() end)
      if write_err then return cb(write_err) end
      return cb()
    end)
  end)
end

--- @param cb fun(downloaded: boolean)
function files.is_prebuilt_downloaded(cb)
  vim.uv.fs_stat(files.lib_path, function(err)
    if not err then return cb(true) end

    -- If not found, check without 'lib' prefix
    vim.uv.fs_stat(
      string.gsub(files.lib_path, 'libblink_cmp_fuzzy', 'blink_cmp_fuzzy'),
      function(error) cb(not error) end
    )
  end)
end

--- @param cb fun(err: string | nil, checksum: string | nil)
function files.get_checksum(cb)
  return files.read_file(files.checksum_path, function(err, checksum)
    if err then return cb(err) end
    return cb(nil, vim.split(checksum, ' ')[1])
  end)
end

--- @param cb fun(err: string | nil)
function files.verify_checksum(cb)
  files.get_checksum(function(err, expected_checksum)
    if err then return cb('Failed to read expected checksum: ' .. err) end
    if not expected_checksum then return cb('Failed to read expected checksum for pre-built binary') end

    vim.system({ 'sha256sum', files.lib_path }, {}, function(out)
      if out.code ~= 0 then return cb('Failed to calculate checksum of pre-built binary: ' .. out.stderr) end

      local actual_checksum = vim.split(out.stdout, ' ')[1]
      vim.print(actual_checksum, expected_checksum)
      if actual_checksum == expected_checksum then return cb() end

      return cb(
        'Checksum of pre-built binary does not match. Expected "'
          .. expected_checksum
          .. '", got "'
          .. actual_checksum
          .. '"'
      )
    end)
  end)
end

--- @param cb fun(err: string | nil, last_version: string | nil)
function files.get_downloaded_version(cb) return files.read_file(files.version_path, cb) end

--- @param version string
--- @param cb fun(err: string | nil)
function files.set_downloaded_version(version, cb) return files.write_file(files.version_path, version, cb) end

return files
