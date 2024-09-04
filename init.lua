local obj = {}
obj.__index = obj

--------------------------------------------------------------------------------
--- metadata
--------------------------------------------------------------------------------

obj.name = "vifari"
obj.version = "0.0.1"
obj.author = "Sergey Tarasov <dzirtusss@gmail.com>"
obj.homepage = "https://github.com/dzirtusss/vifari"
obj.license = "MIT - https://opensource.org/licenses/MIT"

--------------------------------------------------------------------------------
--- config

local safariFilter = nil
local eventLoop
local menuBarItem

--------------------------------------------------------------------------------
-- helper functions
--------------------------------------------------------------------------------

local showLogs = false

local function logWithTimestamp(message)
  if not showLogs then return end

  local timestamp = os.date("%Y-%m-%d %H:%M:%S")    -- Get current date and time
  local ms = math.floor(hs.timer.absoluteTime() / 1e6) % 1000
  hs.printf("[%s.%03d] %s", timestamp, ms, message) -- Print the message with the timestamp
end

local function isViModeActive()
  local app = hs.application.get("Safari")
  local appElement = hs.axuielement.applicationElement(app)
  local focusedElement = appElement:attributeValue("AXFocusedUIElement")
  if not focusedElement then return true end

  local role = focusedElement:attributeValue("AXRole")
  return role ~= "AXTextField" and role ~= "AXComboBox" and role ~= "AXTextArea"
end

local function isSpotlightActive()
  local app = hs.application.get("Spotlight")
  local appElement = hs.axuielement.applicationElement(app)
  local windows = appElement:attributeValue("AXWindows")
  return #windows > 0
end

-- TODO: do some better logic here
local function generateCombinations()
  local chars = "abcdefghijklmnopqrstuvwxyz"
  local combinations = {}
  for i = 1, #chars do
    for j = 1, #chars do
      table.insert(combinations, chars:sub(i, i) .. chars:sub(j, j))
    end
  end
  return combinations
end

local allCombinations = generateCombinations()

local function smoothScroll(x, y)
  local xstep = x / 5
  local ystep = y / 5
  hs.eventtap.event.newScrollEvent({ xstep, ystep }, {}, "pixel"):post()
  hs.timer.doAfter(0.01, function() hs.eventtap.event.newScrollEvent({ xstep * 3, ystep * 3 }, {}, "pixel"):post() end)
  hs.timer.doAfter(0.01, function() hs.eventtap.event.newScrollEvent({ xstep, ystep }, {}, "pixel"):post() end)
end

local function setMode(mode)
  menuBarItem:setTitle(mode)
end

--------------------------------------------------------------------------------
-- marks
--------------------------------------------------------------------------------

local marks = {}
local marksCanvas = nil

local function clearMarks()
  if marksCanvas then marksCanvas:delete() end
  marksCanvas = nil
  marks = {}
end

local function drawMark(markIndex, visibleArea)
  local mark = marks[markIndex]
  if not mark then return end
  if not marksCanvas then return end

  mark.position = mark.element:attributeValue("AXFrame")

  local padding = 2
  local fontSize = 14
  local bgRect = hs.geometry.rect(
    mark.position.x,
    mark.position.y,
    fontSize * 1.5 + 2 * padding,
    fontSize + 2 * padding
  )

  local fillColor
  if mark.element:attributeValue("AXRole") == "AXLink" then
    fillColor = { ["red"] = 1, ["green"] = 1, ["blue"] = 0, ["alpha"] = 1 }
  else
    fillColor = { ["red"] = 0.5, ["green"] = 1, ["blue"] = 0, ["alpha"] = 1 }
  end

  marksCanvas:appendElements({
    type = "rectangle",
    fillColor = fillColor,
    strokeColor = { ["red"] = 0, ["green"] = 0, ["blue"] = 0, ["alpha"] = 1 },
    strokeWidth = 1,
    roundedRectRadii = { xRadius = 3, yRadius = 3 },
    frame = { x = bgRect.x - visibleArea.x, y = bgRect.y - visibleArea.y, w = bgRect.w, h = bgRect.h }
  })

  marksCanvas:appendElements({
    type = "text",
    text = allCombinations[markIndex],
    textAlignment = "center",
    textColor = { ["red"] = 0, ["green"] = 0, ["blue"] = 0, ["alpha"] = 1 },
    textSize = fontSize,
    padding = padding,
    frame = { x = bgRect.x - visibleArea.x, y = bgRect.y - visibleArea.y, w = bgRect.w, h = bgRect.h }
  })
end

local function drawMarks(visibleArea)
  marksCanvas = hs.canvas.new(visibleArea)

  -- area testing
  -- marksCanvas:appendElements({
  --   type = "rectangle",
  --   fillColor = { ["red"] = 0, ["green"] = 1, ["blue"] = 0, ["alpha"] = 0.1 },
  --   strokeColor = { ["red"] = 1, ["green"] = 0, ["blue"] = 0, ["alpha"] = 1 },
  --   strokeWidth = 2,
  --   frame = { x = 0, y = 0, w = visibleArea.w, h = visibleArea.h }
  -- })

  for i, _ in ipairs(marks) do
    drawMark(i, visibleArea)
  end

  -- marksCanvas:bringToFront(true)
  marksCanvas:show()
end

local function addMark(element)
  table.insert(marks, { element = element })
end

local axScrollArea = nil

-- webarea path from window: AXWindow>AXSplitGroup>AXTabGroup>AXGroup>AXGroup>AXScrollArea>AXWebArea
local function findAXWebArea(rootElement)
  -- Define a local recursive function to search for AXWebArea
  local function search(element)
    if not element then return nil end

    local role = element:attributeValue("AXRole")
    if role == "AXWebArea" then
      return element -- Return the AXWebArea element immediately
    elseif role == "AXScrollArea" then
      axScrollArea = element
    end

    local children = element:attributeValue("AXChildren")
    if children then
      for _, child in ipairs(children) do
        local result = search(child)
        if result then return result end -- Stop searching as soon as AXWebArea is found
      end
    end

    return nil -- Return nil if AXWebArea is not found
  end

  -- Start the search from the window element
  return search(rootElement)
end

local function isPartiallyVisible(element, visibleArea)
  local frame = element:attributeValue("AXFrame")
  if not frame then return false end

  local xOverlap = (frame.x < visibleArea.x + visibleArea.w) and (frame.x + frame.w > visibleArea.x)
  local yOverlap = (frame.y < visibleArea.y + visibleArea.h) and (frame.y + frame.h > visibleArea.y)

  return xOverlap and yOverlap
end

local function findClickableElements(element, visibleArea, withUrls)
  if not element then return end

  local role = element:attributeValue("AXRole")

  if role == "AXLink" or role == "AXButton" or role == "AXPopUpButton" or
      role == "AXComboBox" or role == "AXTextField" or role == "AXMenuItem" or
      role == "AXTextArea" then
    local hidden = element:attributeValue("AXHidden")

    if not hidden and isPartiallyVisible(element, visibleArea) then
      if not withUrls then
        addMark(element)
      elseif element:attributeValue("AXURL") then
        addMark(element)
      end
    end
  end

  local children = element:attributeValue("AXChildren")
  if children then
    for _, child in ipairs(children) do
      findClickableElements(child, visibleArea, withUrls)
    end
  end
end

local calculateVisibleArea = function(windowElement, webArea, scrollArea)
  local winFrame = windowElement:attributeValue("AXFrame")
  local webFrame = webArea:attributeValue("AXFrame")
  local scrollFrame = scrollArea:attributeValue("AXFrame")

  -- TODO: sometimes it overlaps on scrollbars, need fixing logic on wide pages
  -- TDDO: doesn't work in fullscreen mode as well

  local visibleX = math.max(winFrame.x, webFrame.x)
  local visibleY = math.max(winFrame.y, scrollFrame.y)

  local visibleWidth = math.min(winFrame.x + winFrame.w, webFrame.x + webFrame.w) - visibleX
  local visibleHeight = math.min(winFrame.y + winFrame.h, webFrame.y + webFrame.h) - visibleY

  local visibleArea = {
    x = visibleX,
    y = visibleY,
    w = visibleWidth,
    h = visibleHeight
  }
  return visibleArea
end

local function showMarks(withUrls)
  local app = hs.application.get("Safari")
  local window = app:mainWindow()
  if not window then return end

  local windowElement = hs.axuielement.windowElement(window)
  local webAreaElement = findAXWebArea(windowElement)
  local visibleArea = calculateVisibleArea(windowElement, webAreaElement, axScrollArea)

  findClickableElements(webAreaElement, visibleArea, withUrls)
  -- logWithTimestamp("Found " .. #marks .. " marks")
  -- hs.alert.show("Found " .. #marks .. " marks")
  drawMarks(visibleArea)
end

local function clickMark(mark, mode)
  logWithTimestamp("clickMark")
  if not mark then return end

  if mode == "f" then
    mark.element:performAction("AXPress")
  elseif mode == "F" then
    local axURL = mark.element:attributeValue("AXURL")
    local url = axURL.url
    -- hs.alert.show(url)
    local script = [[
      tell application "Safari"
        activate
        tell window 1
          set current tab to (make new tab with properties {URL:"%s"})
        end tell
      end tell
    ]]
    script = string.format(script, url)
    hs.osascript.applescript(script)
  elseif mode == "t" then
    local frame = mark.element:attributeValue("AXFrame")
    hs.mouse.absolutePosition({ x = frame.x + frame.w / 2, y = frame.y + frame.h / 2 })
  end
end

--------------------------------------------------------------------------------
--- vifari
--------------------------------------------------------------------------------

local simpleMapping = {
  ["q"] = { { "cmd", "shift" }, "[" },
  ["w"] = { { "cmd", "shift" }, "]" },
  ["J"] = { { "cmd", "shift" }, "[" },
  ["K"] = { { "cmd", "shift" }, "]" },
  ["["] = { { "cmd", }, "[" },
  ["]"] = { { "cmd", }, "]" },
  ["H"] = { { "cmd", }, "[" },
  ["L"] = { { "cmd", }, "]" },
  ["r"] = { { "cmd" }, "r" },
  ["x"] = { { "cmd" }, "w" },
}

local multi = nil
local modeFChars = ""
local inEscape = false

local function setMulti(char)
  multi = char
  if multi then
    setMode(multi)
  else
    setMode("V")
  end
end

local function vimLoop(char)
  logWithTimestamp("vimLoop " .. char)

  local mapping = simpleMapping[char]

  if char == "escape" then
    if multi == "f" or multi == "F" or multi == "t" then
      setMulti(nil)
      hs.timer.doAfter(0, clearMarks)
    elseif multi then
      setMulti(nil)
    end
    inEscape = true
    return
  else
    inEscape = false
  end

  if multi == "f" or multi == "F" or multi == "t" then
    modeFChars = modeFChars .. char:lower()
    if #modeFChars == 2 then
      -- hs.alert.show("Selected " .. modeFChars)
      local idx = nil
      for i, combination in ipairs(allCombinations) do
        if combination == modeFChars then
          idx = i
          break
        end
      end
      if idx then
        local mark = marks[idx]
        clickMark(mark, multi)
      end
      setMulti(nil)
      hs.timer.doAfter(0, clearMarks)
    end
    return
  end

  if multi == "g" then
    setMulti(nil)
    if char == "g" then
      hs.eventtap.keyStroke({ "cmd" }, "up")
    elseif char:match("%d") then
      hs.eventtap.keyStroke({ "cmd" }, char)
    elseif char == "$" then
      hs.eventtap.keyStroke({ "cmd" }, "9")
    end
    return
  end

  if multi == "y" then
    setMulti(nil)
    if char == "y" then
      local script = [[
        tell application "Safari"
          set currentURL to URL of front document
          return currentURL
        end tell
      ]]
      local ok, result = hs.osascript.applescript(script)
      if ok then
        hs.pasteboard.setContents(result)
        hs.alert.show("Copied URL: " .. result, nil, nil, 4)
      else
        hs.alert.show("Failed to get URL", nil, nil, 4)
      end
    end
    return
  end

  if char == "f" then
    setMulti("f")
    modeFChars = ""
    hs.timer.doAfter(0, showMarks)
  elseif char == "F" then
    setMulti("F")
    modeFChars = ""
    hs.timer.doAfter(0, function() showMarks(true) end)
  elseif char == "t" then
    setMulti("t")
    modeFChars = ""
    hs.timer.doAfter(0, showMarks)
  elseif char == "g" then
    setMulti("g")
  elseif char == "G" then
    hs.eventtap.keyStroke({ "cmd" }, "down")
  elseif char == "y" then
    setMulti("y")
  elseif char == "i" then
    setMulti("i")
  elseif char == "j" then
    hs.eventtap.event.newScrollEvent({ 0, -100 }, {}, "pixel"):post()
  elseif char == "k" then
    hs.eventtap.event.newScrollEvent({ 0, 100 }, {}, "pixel"):post()
  elseif char == "h" then
    hs.eventtap.event.newScrollEvent({ 100, 0 }, {}, "pixel"):post()
  elseif char == "l" then
    hs.eventtap.event.newScrollEvent({ -100, 0 }, {}, "pixel"):post()
  elseif char == "d" then
    smoothScroll(0, -500)
  elseif char == "u" then
    smoothScroll(0, 500)
  elseif mapping then
    hs.eventtap.keyStroke(mapping[1], mapping[2])
    return
  end
end

local function eventHandler(event)
  local modifiers = event:getFlags()
  if modifiers["cmd"] or modifiers["ctrl"] or modifiers["alt"] or modifiers["fn"] then
    return false
  end

  local char = event:getCharacters()
  if event:getKeyCode() == hs.keycodes.map["escape"] then
    char = "escape"
  elseif not char:match("[%a%d%[%]%$]") then
    return false
  end

  if not isViModeActive() or isSpotlightActive() then return false end
  if multi == "i" and char ~= "escape" then return false end

  if event:getType() == hs.eventtap.event.types.keyUp then return false end

  if char == "escape" and inEscape then return false end

  -- hs.alert.show(char)
  logWithTimestamp("eventhandler " .. char)
  hs.timer.doAfter(0, function() vimLoop(char) end)
  return true
end

local function onWindowFocused()
  logWithTimestamp("onWindowFocused")
  if not eventLoop then
    eventLoop = hs.eventtap.new({ hs.eventtap.event.types.keyDown, hs.eventtap.event.types.keyUp }, eventHandler):start()
  end
  setMode("V")
end

local function onWindowUnfocused()
  logWithTimestamp("onWindowUnfocused")
  if eventLoop then
    eventLoop:stop()
    eventLoop = nil
  end
  setMulti(nil)
  if #marks > 0 then clearMarks() end
  setMode("X")
end

function obj:start()
  menuBarItem = hs.menubar.new()
  safariFilter = hs.window.filter.new("Safari")
  safariFilter:subscribe(hs.window.filter.windowFocused, onWindowFocused)
  safariFilter:subscribe(hs.window.filter.windowUnfocused, onWindowUnfocused)
end

function obj:stop()
  if safariFilter then
    safariFilter:unsubscribe(onWindowFocused)
    safariFilter:unsubscribe(onWindowUnfocused)
    safariFilter = nil
  end
  if menuBarItem then
    menuBarItem:delete()
  end
end

return obj
