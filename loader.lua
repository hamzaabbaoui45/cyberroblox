--==============================================================================
--  SMPWORK  ·  loader
--  ------------------------------------------------------------------
--  Paste THIS file into the Xeno executor. It downloads SMPWORK.lua from
--  GitHub and runs it.
--
--  Usage:
--    1. put your GitHub username in GITHUB_USER (line ~24)
--    2. open Roblox with Xeno, open the script tab, paste this, press Execute
--
--  Credits : Akram Abbaoui  &  Amjad Nejjari
--  Target  : Xeno (Luau) executor
--==============================================================================

local PROJECT = "SMPWORK"

--------------------------------------------------------------------------------
-- 1. WHERE TO DOWNLOAD THE HUB FROM
--------------------------------------------------------------------------------
-- >>> THE ONLY LINE YOU MAY NEED TO EDIT <<<
-- Put your GitHub username here (keep the quotes). The repository is expected
-- to be called "Fortoo" and the file to sit at its root, on branch "main".
-- If you renamed the repo or the branch, change the two lines below it too.
local GITHUB_USER   = "YOUR_USER"
local GITHUB_REPO   = "Fortoo"
local GITHUB_BRANCH = "main"

local FILE_NAME = "SMPWORK.lua"

-- Add more mirrors below if you want a fallback (the first one that answers
-- wins). A mirror is just another raw URL that serves the same file.
local SOURCES = {
    -- files uploaded straight to the repo root
    string.format("https://raw.githubusercontent.com/%s/%s/%s/%s",
        GITHUB_USER, GITHUB_REPO, GITHUB_BRANCH, FILE_NAME),
    -- files uploaded inside a "Fortoo" folder (drag & drop of the folder)
    string.format("https://raw.githubusercontent.com/%s/%s/%s/Fortoo/%s",
        GITHUB_USER, GITHUB_REPO, GITHUB_BRANCH, FILE_NAME),
}

--------------------------------------------------------------------------------
-- 2. DOWNLOAD HELPERS
--------------------------------------------------------------------------------

-- Fetch a URL as a string, trying every method the executor might expose.
-- Returns the body, or nil + a reason.
local function fetch(url)
    local lastError = "no HTTP method available"

    local function grab(res)
        if type(res) == "string" and #res > 0 then return res end
        if type(res) == "table" then
            local body = res.Body or res.body
            if type(body) == "string" and #body > 0 then return body end
        end
        return nil
    end

    local candidates = {}
    for _, name in ipairs({ "request", "http_request", "syn_request" }) do
        local fn = rawget(_G, name)
        if type(fn) == "function" then candidates[#candidates + 1] = fn end
    end
    if type(syn) == "table" and type(syn.request) == "function" then
        candidates[#candidates + 1] = syn.request
    end
    -- Roblox's own HttpGet (executors usually patch it back in).
    -- `game` is userdata in Roblox, so it cannot be type-checked as a table.
    candidates[#candidates + 1] = function(target) return game:HttpGet(target) end

    for _, fn in ipairs(candidates) do
        -- 1. table form, which is what most executors expect
        local ok, res = pcall(fn, { Url = url, Method = "GET" })
        if ok then
            local body = grab(res)
            if body then return body end
            lastError = "empty response"
        else
            lastError = tostring(res)
        end

        -- 2. bare URL form
        ok, res = pcall(fn, url)
        if ok then
            local body = grab(res)
            if body then return body end
            lastError = "empty response"
        else
            lastError = tostring(res)
        end
    end

    return nil, lastError
end

-- Compile a chunk of Luau source.
local function compile(source)
    if type(loadstring) == "function" then
        local ok, chunk = pcall(loadstring, source)
        if ok and type(chunk) == "function" then return chunk end
        return nil, chunk
    end
    if type(load) == "function" then
        local ok, chunk = pcall(load, source, "@" .. PROJECT .. ".lua")
        if ok and type(chunk) == "function" then return chunk end
        return nil, chunk
    end
    return nil, "this executor has no loadstring()/load()"
end

--------------------------------------------------------------------------------
-- 3. RUN
--------------------------------------------------------------------------------

local function report(msg)
    print("[" .. PROJECT .. "] " .. msg)
    -- some executors show a chat message, which is friendlier than a console line
    if type(warn) == "function" then pcall(warn, "[" .. PROJECT .. "] " .. msg) end
end

local function run()
    -- sanity check the URLs before we waste a request
    local usable = {}
    for _, url in ipairs(SOURCES) do
        if type(url) == "string" and #url > 0 and not url:find("YOUR_USER", 1, true) then
            usable[#usable + 1] = url
        end
    end

    if #usable == 0 then
        report("SOURCES is not configured yet.")
        report("Open loader.lua and replace YOUR_USER with your GitHub username.")
        return
    end

    local source, lastError, usedURL = nil, nil, nil

    for _, url in ipairs(usable) do
        local body, err = fetch(url)
        if type(body) == "string" and #body > 0 then
            source = body
            usedURL = url
            report("downloaded " .. #body .. " bytes from " .. url)
            break
        end
        lastError = err or "empty response"
        report("failed: " .. url .. " (" .. tostring(lastError) .. ")")
    end

    if not source then
        report("could not download the script. Check the URL and your internet.")
        return
    end

    -- basic sanity check so we do not run an HTML error page from GitHub
    if not source:find("SMPWORK", 1, true) and not source:find("MinimaHub", 1, true) then
        report("the downloaded file does not look like SMPWORK.lua - aborting.")
        return
    end

    -- Hand the working URL to the hub. Its "AUTO REATTACH", "CHECK FOR
    -- UPDATES" and "RELOAD FROM GITHUB" buttons use it, so SMPWORK.lua does
    -- not need to be edited at all.
    pcall(function()
        local env = (type(getgenv) == "function" and getgenv()) or _G
        if type(env) == "table" then
            env.SMPWORK_URL = usedURL
        end
    end)

    local chunk, compileError = compile(source)
    if not chunk then
        report("syntax error in the downloaded script: " .. tostring(compileError))
        return
    end

    local ok, err = pcall(chunk)
    if not ok then
        report("error while running: " .. tostring(err))
        return
    end

    report("loaded. RightControl toggles the overlay.")
end

run()
