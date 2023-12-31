-- TODO: Add asserts
-- TODO: fs.parse

local compat = require("santoku.compat")
local inherit = require("santoku.inherit")
local str = require("santoku.string")
local err = require("santoku.err")
local gen = require("santoku.gen")
local tup = require("santoku.tuple")
local fun = require("santoku.fun")
local vec = require("santoku.vector")

local posix = require("santoku.fs.posix")

local M = {}

for k, v in pairs(posix) do
  M[k] = v
end

M.mkdirp = function (dir)
  local p0 = str.startswith(dir, M.pathdelim) and M.pathdelim or nil
  for p1 in dir:gmatch("([^" .. str.escape(M.pathdelim) .. "]+)/?") do
    if p0 then
      p1 = M.join(p0, p1)
    end
    p0 = p1
    local ok, err, code = M.mkdir(p1)
    if not ok and code ~= M.EEXIST then
      return ok, err, code
    end
  end
  return true
end

M.isdir = function (fp)
  local ok, mode, cd = M.mode(fp)
  if not ok and cd == M.ENOENT then
    return true, false
  elseif not ok then
    return false, mode, cd
  else
    return true, mode == "directory"
  end
end

M.isfile = function (fp)
  local ok, mode, cd = M.mode(fp)
  if not ok then
    return false, mode, cd
  else
    return true, mode == "file"
  end
end

M.exists = function (fp)
  local ok, mode, code = M.mode(fp)
  if not ok and code == M.ENOENT then
    return true, false
  elseif ok then
    return true, true, mode
  else
    return false, mode, code
  end
end

M.dir = function (dir)
  local ok, entries, cd = posix.dir(dir)
  if not ok then
    return false, entries, cd
  else
    return true, gen(function (yield)
      while true do
        local ok, name, mode = entries()
        if not ok then
          yield(false, name, mode)
          break
        elseif ok and name then
          yield(true, name, mode)
        else
          break
        end
      end
    end)
  end
end

-- TODO: Breadth vs depth, default to depth so
-- that directory contents are returned before
-- directories themselves
-- TODO: Reverse arg order, allow multiple dirs
M.walk = function (dir, opts)
  local prune = (opts or {}).prune or compat.const(false)
  local prunekeep = (opts or {}).prunekeep or false
  local leaves = (opts or {}).leaves or false
  return gen(function (each)
    local ok, entries, cd = M.dir(dir)
    if not ok then
      return each(false, entries, cd)
    else
      return entries:each(function (ok, name, mode)
        if not ok then
          return each(false, name, mode)
        end
        if name ~= M.dirparent and name ~= M.dirthis then
          name = M.join(dir, name)
          if mode == "directory" then
            if not prune(name, mode) then
              if not leaves then
                each(true, name, mode)
                return M.walk(name, opts):each(each)
              else
                M.walk(name, opts):each(each)
                return each(true, name, mode)
              end
            elseif prunekeep then
              return each(true, name, mode)
            end
          else
            return each(true, name, mode)
          end
        end
      end)
    end
  end)
end

-- TODO: Avoid pcall by using io.open/read
-- directly. Potentially use __gc on the
-- coroutine to ensure the file gets closed.
-- Provide binary t/f, chunk size, max line
-- size, max file size, how to handle overunning
-- max line size, etc.
-- TODO: Need a way to abort this iterator and close the file
M.lines = function (fp)
  local ok, iter, cd = pcall(io.lines, fp)
  if ok then
    return true, gen.iter(iter)
  else
    return false, iter, cd
  end
end

-- TODO: Reverse arg order, allow multiple dirs
M.files = function (dir, opts)
  local recurse = (opts or {}).recurse
  local walkopts = {}
  if not recurse then
    walkopts.prune = function (_, mode)
      return mode == "directory"
    end
  end
  return M.walk(dir, walkopts)
    :filter(function (ok, _, mode)
      return not ok or mode == "file"
    end)
end

-- TODO: Reverse arg order, allow multiple dirs
M.dirs = function (dir, opts)
  local recurse = (opts or {}).recurse
  local leaves = (opts or {}).leaves
  local walkopts = { prunekeep = true, leaves = leaves }
  if not recurse then
    walkopts.prune = function (_, mode)
      return mode == "directory"
    end
  end
  return M.walk(dir, walkopts)
    :filter(function (ok, _, mode)
      return not ok or mode == "directory"
    end)
end

-- TODO: Dynamically figure this out for each OS.
-- TODO: Does every OS have a singe-char path delim? If not,
-- some functions below will fail.
-- TODO: Does every OS use the same identifier as both
-- delimiter and root indicator?
M.pathdelim = "/"
M.pathroot = "/"
M.dirparent = ".."
M.dirthis = "."

M.basename = function (fp)
  if not fp:match(str.escape(M.pathdelim)) then
    return fp
  else
    local parts = str.split(fp, M.pathdelim)
    return parts[parts.n]
  end
end

M.dirname = function (fp)
  local parts = str.split(fp, M.pathdelim, { delim = "left" })
  local dir = table.concat(parts, "", 1, parts.n - 1):gsub("/$", "")
  if dir == "" then
    return "."
  else
    return dir
  end
end

M.join = function (...)
  return M.joinwith(M.pathdelim, ...)
end

M.joinwith = function (d, ...)
  local de = str.escape(d)
  -- TODO: Does this pattern work with
  -- delimiters longer than 1 char?
  local pat = string.format("%s*$", de)
  local clean = fun.bindl(tup.map, fun.bindr(string.gsub, pat, ""))
  local filter = fun.bindl(tup.filter, compat.id)
  local interleave = fun.bindl(tup.interleave, d)
  return tup.concat(interleave(clean(filter(...))))
end

M.splitparts = function (fp, opts)
  return str.split(fp, M.pathdelim, opts)
end

M.stripextension = function (fp)
  local parts = M.splitparts(fp)
  local last = parts[parts.n]
  last = string.match(last, "(.*)%..*") or last
  parts[parts.n] = last
  return table.concat(parts, M.pathdelim)
end

M.stripextensions = function (fp)
  local parts = M.splitparts(fp)
  local last = parts[parts.n]
  local idot = string.find(last, "%.")
  if idot then
    last = last:sub(1, idot - 1)
  end
  parts[parts.n] = last
  return table.concat(parts, M.pathdelim)
end

M.extension = function (fp)
  fp = M.basename(fp)
  return (string.match(fp, ".*%.(.*)"))
end

M.extensions = function (fp)
  fp = M.basename(fp)
  local idot = string.find(fp, "%.")
  if idot then
    return fp:sub(idot + 1, fp:len())
  end
end

-- TODO: Can probably improve performance by not
-- splitting so much. Perhaps we need an isplit
-- function that just returns indices?
M.splitexts = function (fp)
  local parts = M.splitparts(fp, { delim = "left" })
  local last = str.split(parts[parts.n], "%.", { delim = "right" })
  local lasti = 1
  if last[1] == "" then
    lasti = 2
  end
  return {
    exts = last:slice(lasti + 1),
    name = table.concat(parts, "", 1, parts.n - 1)
        .. table.concat(last, "", lasti, 1)
  }
end

-- TODO: Can we leverage a generalized function
-- for this?
M.writefile = function (fp, str, flag)
  flag = flag or "w"
  assert(type(flag) == "string")
  local fh, err
  if fp == io.stdout then
    fh = io.stdout
  else
    fh, err = io.open(fp, flag)
  end
  if not fh then
    return false, err
  else
    fh:write(str)
    fh:flush()
    if fh ~= io.stdout then
      fh:close()
    end
    return true
  end
end

-- TODO: Leverage fs.chunks or fs.parse
M.readfile = function (fp, flag)
  flag = flag or "r"
  assert(type(flag) == "string")
  local fh, err
  if fp == io.stdin then
    fh = io.stdin
  else
    fh, err = io.open(fp, flag)
  end
  if not fh then
    return false, err
  else
    local content = fh:read("*all")
    if fh ~= io.stdin then
      fh:close()
    end
    return true, content
  end
end

M.rm = function (fp, allow_noexist)
  local ok, err, cd = os.remove(fp)
  if not ok and (not allow_noexist and cd == M.ENOENT) then
    return false, err, cd
  else
    return true
  end
end

M.mv = function (old, new)
  local ok, err, cd = os.rename(old, new)
  if not ok then
    return false, err, cd
  else
    return true
  end
end

M.rmdirs = function (dir)
  return err.pwrap(function (check)
    M.dirs(dir, { recurse = true, leaves = true })
      :map(check)
      :map(M.rmdir)
      :each(check)
  end)
end

M.absolute = function (fp)
  if fp:sub(1, 1) == M.pathroot then
    return M.normalize(fp)
  elseif fp:sub(1, 2) == "~/" then
    local home = os.getenv("HOME")
    if not home then
      return false, "No home directory"
    else
      fp = M.join(home, fp:sub(2))
    end
  else
    local ok, dir, cd = M.cwd()
    if not ok then
      return false, dir, cd
    else
      fp = M.join(dir, fp)
    end
  end
  return M.normalize(fp)
end

M.normalize = function (fp)
  assert(type(fp) == "string")
  fp = fp:match("^/*(.*)$")
  local parts = str.split(fp, M.pathdelim)
  local parts0 = vec()
  for i = 1, parts.n do
    if parts0.n == 0 and parts[i] == ".." then
      return false, "Can't move past root with '..'"
    elseif parts[i] == ".." then
      parts0:pop()
    elseif parts[i] ~= "." and parts[i] ~= "" then
      parts0:append(parts[i])
    end
  end
  fp = M.join(parts0:unpack())
  if fp == "" then
    return true, "."
  else
    return true, M.pathroot .. fp
  end
end

M.loadfile = function (fp, env)
  local ok, data, cd = M.readfile(fp)
  if not ok then
    return false, data, cd
  else
    return compat.load(data, env)
  end
end

M.runfile = function (fp, env)
  local lenv = inherit.pushindex(env or {}, _G)
  local ok, fn, cd = M.loadfile(fp, lenv)
  if not ok then
    return false, fn, cd
  else
    return pcall(fn)
  end
end

return M
