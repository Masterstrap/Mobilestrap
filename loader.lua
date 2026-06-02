local RAW_URL = "https://raw.githubusercontent.com/Masterstrap/Mobilestrap/main/script.lua"
local CACHE_VERSION = "016" 
local CACHE_DIR = "Masterstrap/cache"
local CACHE_FILE = CACHE_DIR .. "/script.lua"
local CACHE_META = CACHE_DIR .. "/version.txt"
local MIN_BYTES = 1000
-- ==================================================

local function log(msg)
    warn("[Masterstrap] " .. tostring(msg))
end

local function wait_game()
    if not game:IsLoaded() then
        game.Loaded:Wait()
    end
end

local function http_get(url)
    local req = request or http_request or (syn and syn.request) or (http and http.request)
    if req then
        local ok, res = pcall(function()
            return req({
                Url = url,
                Method = "GET",
                Headers = { ["User-Agent"] = "Masterstrap-Loader" },
            })
        end)
        if ok and res and res.Body and #res.Body > 0 then
            return res.Body
        end
    end
    return game:HttpGet(url, true)
end

local function looks_like_html(body)
    if not body or #body < 20 then return true end
    local head = body:sub(1, 256):lower()
    return head:find("<!doctype", 1, true) ~= nil
        or head:find("<html", 1, true) ~= nil
        or head:find("404", 1, true) ~= nil and head:find("not found", 1, true) ~= nil
end

local function compile_and_run(source, chunkName)
    local fn, err = loadstring(source, chunkName or "MasterstrapScript")
    if not fn then
        error("loadstring failed: " .. tostring(err), 0)
    end
    return fn()
end

local function fallback_direct()
    log("No writefile — using direct HttpGet (slow every run).")
    wait_game()
    local src = http_get(RAW_URL)
    if looks_like_html(src) then
        error("GitHub returned HTML — check URL / branch / file name (script.lua)", 0)
    end
    if not src or #src < MIN_BYTES then
        error("Download failed or file too small (" .. tostring(src and #src or 0) .. " bytes)", 0)
    end
    return compile_and_run(src, "MasterstrapDirect")
end

if not (writefile and readfile and isfile and makefolder) then
    return fallback_direct()
end

pcall(function() makefolder("Masterstrap") end)
pcall(function() makefolder(CACHE_DIR) end)

local function cache_valid()
    if not isfile(CACHE_FILE) or not isfile(CACHE_META) then
        return false
    end
    local ok, ver = pcall(function()
        return readfile(CACHE_META)
    end)
    return ok and ver == CACHE_VERSION
end

local function clear_cache()
    pcall(function()
        if isfile(CACHE_FILE) then delfile(CACHE_FILE) end
        if isfile(CACHE_META) then delfile(CACHE_META) end
    end)
end

local function load_cached()
    log("Loading cached script (v" .. CACHE_VERSION .. ")...")
    local src = readfile(CACHE_FILE)
    if looks_like_html(src) then
        clear_cache()
        error("Cache corrupted (HTML). Cleared — run again.", 0)
    end
    return compile_and_run(src, "MasterstrapCached")
end

local function download_and_cache()
    log("Downloading script.lua from GitHub (obfuscated — may take a while)...")
    wait_game()
    local src = http_get(RAW_URL)
    if looks_like_html(src) then
        error("GitHub returned HTML — wrong URL or private repo.\n" .. RAW_URL, 0)
    end
    if not src or #src < MIN_BYTES then
        error("Download too small: " .. tostring(src and #src or 0) .. " bytes", 0)
    end
    writefile(CACHE_FILE, src)
    writefile(CACHE_META, CACHE_VERSION)
    log("Cached " .. tostring(#src) .. " bytes. Compiling...")
    return compile_and_run(src, "MasterstrapRemote")
end

if getgenv and getgenv().MasterstrapForceUpdate then
    clear_cache()
    log("Cache cleared (MasterstrapForceUpdate = true).")
end

local ok, result = xpcall(function()
    if cache_valid() then
        return load_cached()
    end
    return download_and_cache()
end, function(err)
    return debug.traceback(tostring(err), 2)
end)

if not ok then
    log("ERROR:\n" .. tostring(result))
    if cache_valid() then
        log("Retrying without cache...")
        clear_cache()
        local ok2, result2 = xpcall(download_and_cache, function(e)
            return debug.traceback(tostring(e), 2)
        end)
        if ok2 then
            return result2
        end
        error(tostring(result2), 0)
    end
    error(tostring(result), 0)
end

return result
