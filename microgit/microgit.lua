VERSION = "1.0.1"

local micro = import("micro")
local config = import("micro/config")
local shell = import("micro/shell")
local buffer = import("micro/buffer")

local gitCache = {
    branch = nil,
    hasChanges = nil,
    gitRoot = nil,
    lastCheck = 0,
    cacheTimeout = 2000 -- 2 seconds
}

local diffCache = {}

local blameCache = {}

function getParentDir(path)

    if path:match("/$") and path ~= "/" then
        path = path:sub(1, -2)
    end

    if path == "/" or path == "" then
        return nil
    end

    local lastSlashPos = nil
    for i = #path, 1, -1 do
        if path:sub(i, i) == "/" then
            lastSlashPos = i
            break
        end
    end

    if lastSlashPos == nil then
        return nil
    end

    if lastSlashPos == 1 then
        return "/"
    end

    return path:sub(1, lastSlashPos - 1)
end


function findGitRoot(startPath)
    local path = startPath

    if path:match("/$") and path ~= "/" then
        path = path:sub(1, -2)
    end

    local maxDepth = 50
    local depth = 0

    while depth < maxDepth do
        local gitDir = path .. "/.git"
        local checkCmd = "sh -c 'test -d " .. shellescape(gitDir) .. " && echo yes || echo no'"
        local output, err = shell.RunCommand(checkCmd)

        if output and output:gsub("%s+", "") == "yes" then
            return path, nil
        end

        if path == "/" or path == "" then
            return nil, "Not a git repository (reached root)"
        end

        local parent = getParentDir(path)
        if parent == nil then
            return nil, "Not a git repository (no parent dir)"
        end

        if parent == path then
            return nil, "Not a git repository (parent same as current)"
        end

        path = parent
        depth = depth + 1
    end

    return nil, "Not a git repository (max depth reached)"
end


function isGitRepo(path)
    local gitRoot, err = findGitRoot(path)

    if gitRoot == nil then
        return false, err
    end

    return true, gitRoot
end

function shellescape(s)
    return "'" .. s:gsub("'", "'\\''") .. "'"
end


function getWorkingDir(buf)
    local pwd = os.getenv("PWD") or "."

    if buf.Path == "" then
        return pwd
    end

    local path = buf.Path

    if not path:match("^/") then
        path = pwd .. "/" .. path
    end

    local dir = path:match("^(.+)/[^/]+$")

    if dir == nil then
        return pwd
    end

    return dir
end

function getGitBranch(buf)
    local now = os.time() * 1000
    if gitCache.branch ~= nil and (now - gitCache.lastCheck) < gitCache.cacheTimeout then
        return gitCache.branch
    end

    local workDir = getWorkingDir(buf)
    local isRepo, gitRoot = isGitRepo(workDir)
    if not isRepo then
        gitCache.branch = nil
        gitCache.gitRoot = nil
        return nil
    end

    gitCache.gitRoot = gitRoot

    local cmd = "sh -c 'git -C " .. shellescape(gitRoot) .. " rev-parse --abbrev-ref HEAD 2>/dev/null'"
    local output, err = shell.RunCommand(cmd)
    if err ~= nil or output == "" or output == nil then
        gitCache.branch = nil
        return nil
    end

    gitCache.branch = output:gsub("%s+", "")
    gitCache.lastCheck = now
    return gitCache.branch
end

function hasGitChanges(buf)
    local now = os.time() * 1000
    if gitCache.hasChanges ~= nil and (now - gitCache.lastCheck) < gitCache.cacheTimeout then
        return gitCache.hasChanges
    end

    local gitRoot = gitCache.gitRoot
    if gitRoot == nil then
        local workDir = getWorkingDir(buf)
        local isRepo, root = isGitRepo(workDir)
        if not isRepo then
            gitCache.hasChanges = false
            return false
        end
        gitRoot = root
        gitCache.gitRoot = gitRoot
    end

    local cmd = "sh -c 'git -C " .. shellescape(gitRoot) .. " status --porcelain 2>/dev/null'"
    local output, err = shell.RunCommand(cmd)
    if err ~= nil or output == nil then
        gitCache.hasChanges = false
        return false
    end

    gitCache.hasChanges = output ~= ""
    return gitCache.hasChanges
end

function clearGitCache()
    gitCache.branch = nil
    gitCache.hasChanges = nil
    gitCache.gitRoot = nil
    gitCache.lastCheck = 0
end

function parseGitDiff(diffOutput)
    local changes = {
        added = {},   
        modified = {},
        deleted = {}
    }

    if not diffOutput or diffOutput == "" then
        return changes
    end

    local currentLine = 0
    for line in diffOutput:gmatch("[^\r\n]+") do
        local newStart, newCount = line:match("^@@%s+%-[%d,]+%s+%+(%d+),?(%d*)%s+@@")
        if newStart then
            currentLine = tonumber(newStart)
            if newCount == "" then
                newCount = 1
            else
                newCount = tonumber(newCount)
            end
        elseif line:sub(1, 1) == "+" and line:sub(2, 2) ~= "+" then
            table.insert(changes.added, currentLine)
            currentLine = currentLine + 1
        elseif line:sub(1, 1) == "-" and line:sub(2, 2) ~= "-" then
            table.insert(changes.deleted, currentLine > 0 and currentLine or 1)
        elseif line:sub(1, 1) == " " then
            currentLine = currentLine + 1
        end
    end

    return changes
end

function getFileDiff(filePath, gitRoot)
    if not filePath or filePath == "" then
        return nil
    end

    if diffCache[filePath] then
        local cached = diffCache[filePath]
        local now = os.time() * 1000
        if (now - cached.time) < 5000 then
            return cached.changes
        end
    end

    local cmd = "sh -c 'git -C " .. shellescape(gitRoot) .. " diff HEAD -- " .. shellescape(filePath) .. " 2>/dev/null'"
    local output, err = shell.RunCommand(cmd)

    if err ~= nil or not output then
        return nil
    end

    local changes = parseGitDiff(output)

    diffCache[filePath] = {
        changes = changes,
        time = os.time() * 1000
    }

    return changes
end

function updateGutterMarkers(buf)
    if buf.Path == "" or buf.Type.Kind ~= 0 then -- 0 = BTDefault (normal file buffer)
        return
    end

    local workDir = getWorkingDir(buf)
    local isRepo, gitRoot = isGitRepo(workDir)
    if not isRepo then
        return
    end

    local pwd = os.getenv("PWD") or "."
    local filePath = buf.Path
    if not filePath:match("^/") then
        filePath = pwd .. "/" .. filePath
    end

    local changes = getFileDiff(filePath, gitRoot)
    if not changes then
        return
    end

    clearGutterMarkers(buf)

    for _, lineNum in ipairs(changes.added) do
        if lineNum > 0 and lineNum <= buf:LinesNum() then
            local msg = buffer.NewMessageAtLine("microgit", "+", lineNum, buffer.MTInfo)
            buf:AddMessage(msg)
        end
    end

    for _, lineNum in ipairs(changes.deleted) do
        if lineNum > 0 and lineNum <= buf:LinesNum() then
            local msg = buffer.NewMessageAtLine("microgit", "-", lineNum, buffer.MTError)
            buf:AddMessage(msg)
        end
    end
end

function clearGutterMarkers(buf)
    buf:ClearMessages("microgit")
end

function parseBlameInfo(blameLine)
    if not blameLine or blameLine == "" then
        return nil
    end

    local hash = blameLine:match("^(%x+)")
    if not hash then
        return nil
    end

    local author = blameLine:match("%(([^%d]+)%d")
    if author then
        author = author:gsub("%s+$", "")
    end

    local date = blameLine:match("(%d%d%d%d%-%d%d%-%d%d)")

    local time = blameLine:match("(%d%d:%d%d:%d%d)")

    return {
        hash = hash:sub(1, 8),
        author = author or "Unknown",
        date = date or "",
        time = time or "",
        fullHash = hash
    }
end

function getFileBlame(filePath, gitRoot)
    if not filePath or filePath == "" then
        return nil
    end

    if blameCache[filePath] then
        local cached = blameCache[filePath]
        local now = os.time() * 1000
        if (now - cached.time) < 30000 then
            return cached.lines
        end
    end

    local cmd = "sh -c 'git -C " .. shellescape(gitRoot) .. " blame --line-porcelain " .. shellescape(filePath) .. " 2>/dev/null'"
    local output, err = shell.RunCommand(cmd)

    if err ~= nil or not output or output == "" then
        return nil
    end

    local lines = {}
    local currentLine = nil
    local lineNum = 0

    for line in output:gmatch("[^\r\n]+") do
        if line:match("^%x%x%x%x%x%x%x%x") then
            lineNum = lineNum + 1
            local hash = line:match("^(%x+)")
            currentLine = {
                hash = hash and hash:sub(1, 8) or "unknown",
                fullHash = hash,
                author = "Unknown",
                date = "",
                time = ""
            }
            lines[lineNum] = currentLine
        elseif currentLine then
            if line:match("^author ") then
                currentLine.author = line:match("^author (.+)") or "Unknown"
            elseif line:match("^author%-time ") then
                local timestamp = tonumber(line:match("^author%-time (%d+)"))
                if timestamp then
                    currentLine.date = os.date("%Y-%m-%d", timestamp)
                    currentLine.time = os.date("%H:%M:%S", timestamp)
                end
            elseif line:match("^summary ") then
                currentLine.summary = line:match("^summary (.+)") or ""
            end
        end
    end

    blameCache[filePath] = {
        lines = lines,
        time = os.time() * 1000
    }

    return lines
end

function getGitStatus(buf)
    local branch = getGitBranch(buf)
    if branch == nil then
        return ""
    end

    local status = " [" .. branch
    if hasGitChanges(buf) then
        status = status .. " ●"
    end
    status = status .. "]"

    return status
end

function gitStatus(bp)
    local workDir = getWorkingDir(bp.Buf)
    local isRepo, gitRoot = isGitRepo(workDir)
    if not isRepo then
        micro.InfoBar():Error("Not a git repository: " .. gitRoot)
        return
    end

    local output, err = shell.RunCommand("sh -c 'git -C " .. shellescape(gitRoot) .. " status'")
    if err ~= nil then
        micro.InfoBar():Error("Error running git status: " .. err)
        return
    end

    local buf = buffer.NewBuffer(output, "git-status")
    bp:OpenBuffer(buf)
end

function gitAdd(bp)
    local workDir = getWorkingDir(bp.Buf)
    local isRepo, gitRoot = isGitRepo(workDir)
    if not isRepo then
        micro.InfoBar():Error("Not a git repository: " .. gitRoot)
        return
    end

    if bp.Buf.Path == "" then
        micro.InfoBar():Error("Save the file before adding to git")
        return
    end

    local pwd = os.getenv("PWD") or "."
    local filePath = bp.Buf.Path

    if not filePath:match("^/") then
        filePath = pwd .. "/" .. filePath
    end

    local output, err = shell.RunCommand("sh -c 'git -C " .. shellescape(gitRoot) .. " add " .. shellescape(filePath) .. "'")
    if err ~= nil then
        micro.InfoBar():Error("Error adding file: " .. err)
        return
    end

    clearGitCache()
    micro.InfoBar():Message("File added to git")
end

function gitAddAll(bp)
    local workDir = getWorkingDir(bp.Buf)
    local isRepo, gitRoot = isGitRepo(workDir)
    if not isRepo then
        micro.InfoBar():Error("Not a git repository: " .. gitRoot)
        return
    end

    local output, err = shell.RunCommand("sh -c 'git -C " .. shellescape(gitRoot) .. " add .'")
    if err ~= nil then
        micro.InfoBar():Error("Error adding files: " .. err)
        return
    end

    clearGitCache()
    micro.InfoBar():Message("All files added to git")
end

function gitCommit(bp, args)
    local workDir = getWorkingDir(bp.Buf)
    local isRepo, gitRoot = isGitRepo(workDir)
    if not isRepo then
        micro.InfoBar():Error("Not a git repository: " .. gitRoot)
        return
    end

    if #args < 1 then
        micro.InfoBar():Error("Usage: commit <message>")
        return
    end

    local message = table.concat(args, " ")
    local output, err = shell.RunCommand("sh -c 'git -C " .. shellescape(gitRoot) .. " commit -m " .. shellescape(message) .. "'")
    if err ~= nil then
        micro.InfoBar():Error("Error committing: " .. err)
        return
    end

    clearGitCache()
    micro.InfoBar():Message("Commit successful")
end

function gitDiff(bp)
    local workDir = getWorkingDir(bp.Buf)
    local isRepo, gitRoot = isGitRepo(workDir)
    if not isRepo then
        micro.InfoBar():Error("Not a git repository: " .. gitRoot)
        return
    end

    local output, err = shell.RunCommand("sh -c 'git -C " .. shellescape(gitRoot) .. " diff'")
    if err ~= nil then
        micro.InfoBar():Error("Error running git diff: " .. err)
        return
    end

    if output == "" then
        micro.InfoBar():Message("No changes to show")
        return
    end

    local buf = buffer.NewBuffer(output, "git-diff")
    bp:OpenBuffer(buf)
end

function gitLog(bp)
    local workDir = getWorkingDir(bp.Buf)
    local isRepo, gitRoot = isGitRepo(workDir)
    if not isRepo then
        micro.InfoBar():Error("Not a git repository: " .. gitRoot)
        return
    end

    local output, err = shell.RunCommand("sh -c 'git -C " .. shellescape(gitRoot) .. " log --oneline -n 20'")
    if err ~= nil then
        micro.InfoBar():Error("Error running git log: " .. err)
        return
    end

    local buf = buffer.NewBuffer(output, "git-log")
    bp:OpenBuffer(buf)
end

function gitBranch(bp)
    local workDir = getWorkingDir(bp.Buf)
    local isRepo, gitRoot = isGitRepo(workDir)
    if not isRepo then
        micro.InfoBar():Error("Not a git repository: " .. gitRoot)
        return
    end

    local output, err = shell.RunCommand("sh -c 'git -C " .. shellescape(gitRoot) .. " branch -a'")
    if err ~= nil then
        micro.InfoBar():Error("Error listing branches: " .. err)
        return
    end

    local buf = buffer.NewBuffer(output, "git-branch")
    bp:OpenBuffer(buf)
end

function gitRefresh(bp)
    if bp.Buf.Path == "" then
        micro.InfoBar():Error("No file open")
        return
    end

    local pwd = os.getenv("PWD") or "."
    local filePath = bp.Buf.Path
    if not filePath:match("^/") then
        filePath = pwd .. "/" .. filePath
    end
    diffCache[filePath] = nil

    updateGutterMarkers(bp.Buf)
    micro.InfoBar():Message("Git gutter refreshed")
end

function gitBlame(bp)
    if bp.Buf.Path == "" then
        micro.InfoBar():Error("No file open")
        return
    end

    local workDir = getWorkingDir(bp.Buf)
    local isRepo, gitRoot = isGitRepo(workDir)
    if not isRepo then
        micro.InfoBar():Error("Not a git repository")
        return
    end

    local pwd = os.getenv("PWD") or "."
    local filePath = bp.Buf.Path
    if not filePath:match("^/") then
        filePath = pwd .. "/" .. filePath
    end

    local currentLine = bp.Buf:GetActiveCursor().Y + 1

    local blameLines = getFileBlame(filePath, gitRoot)
    if not blameLines then
        micro.InfoBar():Error("Could not get git blame information")
        return
    end

    local blameInfo = blameLines[currentLine]
    if not blameInfo then
        micro.InfoBar():Error("No blame info for line " .. currentLine)
        return
    end

    local msg = string.format("[%s] %s (%s %s)",
        blameInfo.hash,
        blameInfo.author,
        blameInfo.date,
        blameInfo.time
    )

    if blameInfo.summary and blameInfo.summary ~= "" then
        msg = msg .. ": " .. blameInfo.summary
    end

    micro.InfoBar():Message(msg)
end

function gitBlameFile(bp)
    if bp.Buf.Path == "" then
        micro.InfoBar():Error("No file open")
        return
    end

    local workDir = getWorkingDir(bp.Buf)
    local isRepo, gitRoot = isGitRepo(workDir)
    if not isRepo then
        micro.InfoBar():Error("Not a git repository")
        return
    end

    local pwd = os.getenv("PWD") or "."
    local filePath = bp.Buf.Path
    if not filePath:match("^/") then
        filePath = pwd .. "/" .. filePath
    end

    local cmd = "sh -c 'git -C " .. shellescape(gitRoot) .. " blame " .. shellescape(filePath) .. " 2>/dev/null'"
    local output, err = shell.RunCommand(cmd)

    if err ~= nil or not output then
        micro.InfoBar():Error("Error running git blame")
        return
    end

    local buf = buffer.NewBuffer(output, "git-blame: " .. bp.Buf:GetName())
    bp:OpenBuffer(buf)
end

function gitDebug(bp)
    local pwd = os.getenv("PWD") or "."
    local workDir = getWorkingDir(bp.Buf)

    local debugInfo = "=== MicroGit Debug Info ===\n\n"
    debugInfo = debugInfo .. "Current PWD: " .. pwd .. "\n"
    debugInfo = debugInfo .. "Buffer Path: " .. (bp.Buf.Path or "empty") .. "\n"
    debugInfo = debugInfo .. "Starting Search Directory: " .. workDir .. "\n\n"

    debugInfo = debugInfo .. "Search Path:\n"
    local path = workDir
    local depth = 0
    local maxDepth = 10
    local found = false
    local foundPath = nil

    while depth < maxDepth and path ~= nil do
        local gitDir = path .. "/.git"
        local checkCmd = "sh -c 'test -d " .. shellescape(gitDir) .. " && echo yes || echo no'"
        local output, err = shell.RunCommand(checkCmd)
        local exists = (output and output:gsub("%s+", "") == "yes")

        debugInfo = debugInfo .. "  " .. depth .. ". " .. path .. " - .git " .. (exists and "FOUND" or "not found")
        debugInfo = debugInfo .. " (output: '" .. (output or "nil") .. "')\n"

        if exists then
            found = true
            foundPath = path
            break
        end

        if path == "/" or path == "" then
            break
        end

        path = getParentDir(path)
        depth = depth + 1
    end

    debugInfo = debugInfo .. "\nResult:\n"
    debugInfo = debugInfo .. "Is Git Repo: " .. tostring(found) .. "\n"

    if found then
        debugInfo = debugInfo .. "Git Root: " .. foundPath .. "\n\n"
        local branch = getGitBranch(bp.Buf)
        local hasChanges = hasGitChanges(bp.Buf)
        debugInfo = debugInfo .. "Current Branch: " .. (branch or "unknown") .. "\n"
        debugInfo = debugInfo .. "Has Changes: " .. tostring(hasChanges) .. "\n"
    end

    local buf = buffer.NewBuffer(debugInfo, "git-debug")
    bp:OpenBuffer(buf)
end

function init()
    config.MakeCommand("gitstatus", gitStatus, config.NoComplete)
    config.MakeCommand("gitadd", gitAdd, config.NoComplete)
    config.MakeCommand("gitaddall", gitAddAll, config.NoComplete)
    config.MakeCommand("gitcommit", gitCommit, config.NoComplete)
    config.MakeCommand("gitdiff", gitDiff, config.NoComplete)
    config.MakeCommand("gitlog", gitLog, config.NoComplete)
    config.MakeCommand("gitbranch", gitBranch, config.NoComplete)
    config.MakeCommand("gitrefresh", gitRefresh, config.NoComplete)
    config.MakeCommand("gitblame", gitBlame, config.NoComplete)
    config.MakeCommand("gitblamefile", gitBlameFile, config.NoComplete)
    config.MakeCommand("gitdebug", gitDebug, config.NoComplete)

    micro.Log("MicroGit plugin loaded with git gutter and blame support!")
end

function onRenderStatusLine(statusline)
    local buf = statusline.Buf
    if buf ~= nil then
        local gitInfo = getGitStatus(buf)
        if gitInfo ~= "" then
            statusline:AddRight(gitInfo)
        end
    end
end

function onSave(bp)
    clearGitCache()
    if bp.Buf.Path ~= "" then
        local pwd = os.getenv("PWD") or "."
        local filePath = bp.Buf.Path
        if not filePath:match("^/") then
            filePath = pwd .. "/" .. filePath
        end
        diffCache[filePath] = nil
    end
    updateGutterMarkers(bp.Buf)
    return true
end

function onBufferOpen(buf)
    updateGutterMarkers(buf)
end
