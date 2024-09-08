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
--------------------------------------------------------------------------------

local mapping = {
  ["i"] = "cmdInsertMode",
  -- movements
  ["h"] = "cmdScrollLeft",
  ["j"] = "cmdScrollDown",
  ["k"] = "cmdScrollUp",
  ["l"] = "cmdScrollRight",
  ["d"] = "cmdScrollHalfPageDown",
  ["u"] = "cmdScrollHalfPageUp",
  ["gg"] = { "cmd", "up" },
  ["G"] = { "cmd", "down" },
  -- tabs
  ["q"] = { { "cmd", "shift" }, "[" }, -- tab left
  ["w"] = { { "cmd", "shift" }, "]" }, -- tab right
  ["r"] = { "cmd", "r" },              -- reload tab
  ["x"] = { "cmd", "w" },              -- close tab
  ["["] = { "cmd", "[" },              -- history back
  ["]"] = { "cmd", "]" },              -- history forward
  ["g1"] = { "cmd", "1" },
  ["g2"] = { "cmd", "2" },
  ["g3"] = { "cmd", "3" },
  ["g4"] = { "cmd", "4" },
  ["g5"] = { "cmd", "5" },
  ["g6"] = { "cmd", "6" },
  ["g7"] = { "cmd", "7" },
  ["g8"] = { "cmd", "8" },
  ["g9"] = { "cmd", "9" }, -- last tab
  ["g$"] = { "cmd", "9" }, -- last tab
  -- links
  ["f"] = "cmdGotoLink",
  ["F"] = "cmdGotoLinkNewTab",
  ["t"] = "cmdMoveMouseToLink",
  -- clipboard
  ["yy"] = "cmdCopyPageUrlToClipboard",
  ["yf"] = "cmdCopyLinkUrlToClipboard",
}

local config = {
  doublePressDelay = 0.2, -- seconds
  showLogs = false,
  axEditableRoles = { "AXTextField", "AXComboBox", "AXTextArea" },
  axJumpableRoles = { "AXLink", "AXButton", "AXPopUpButton", "AXComboBox", "AXTextField", "AXMenuItem", "AXTextArea" },
  mapping = mapping,
}

--------------------------------------------------------------------------------
-- helper functions
--------------------------------------------------------------------------------

local cached = {}
local current = {}
local action = {}

local safariFilter
local eventLoop

local function logWithTimestamp(message)
  if not config.showLogs then return end

  local timestamp = os.date("%Y-%m-%d %H:%M:%S")    -- Get current date and time
  local ms = math.floor(hs.timer.absoluteTime() / 1e6) % 1000
  hs.printf("[%s.%03d] %s", timestamp, ms, message) -- Print the message with the timestamp
end

local function tblContains(tbl, val)
  for _, v in ipairs(tbl) do
    if v == val then return true end
  end
  return false
end

function current.app()
  cached.app = cached.app or hs.application.get("Safari")
  return cached.app
end

function current.axApp()
  cached.axApp = cached.axApp or hs.axuielement.applicationElement(current.app())
  return cached.axApp
end

function current.window()
  cached.window = cached.window or current.app():mainWindow()
  return cached.window
end

function current.axWindow()
  cached.axWindow = cached.axWindow or hs.axuielement.windowElement(current.window())
  return cached.axWindow
end

function current.axFocusedElement()
  cached.axFocusedElement = cached.axFocusedElement or current.axApp():attributeValue("AXFocusedUIElement")
  return cached.axFocusedElement
end

local function findAXRole(rootElement, role)
  if rootElement:attributeValue("AXRole") == role then return rootElement end

  for _, child in ipairs(rootElement:attributeValue("AXChildren") or {}) do
    local result = findAXRole(child, role)
    if result then return result end
  end
end

function current.axScrollArea()
  cached.axScrollArea = cached.axScrollArea or findAXRole(current.axWindow(), "AXScrollArea")
  return cached.axScrollArea
end

-- webarea path from window: AXWindow>AXSplitGroup>AXTabGroup>AXGroup>AXGroup>AXScrollArea>AXWebArea
function current.axWebArea()
  cached.axWebArea = cached.axWebArea or findAXRole(current.axScrollArea(), "AXWebArea")
  return cached.axWebArea
end

function current.visibleArea()
  if cached.visibleArea then return cached.visibleArea end

  local winFrame = current.axWindow():attributeValue("AXFrame")
  local webFrame = current.axWebArea():attributeValue("AXFrame")
  local scrollFrame = current.axScrollArea():attributeValue("AXFrame")

  -- TODO: sometimes it overlaps on scrollbars, need fixing logic on wide pages
  -- TDDO: doesn't work in fullscreen mode as well

  local visibleX = math.max(winFrame.x, webFrame.x)
  local visibleY = math.max(winFrame.y, scrollFrame.y)

  local visibleWidth = math.min(winFrame.x + winFrame.w, webFrame.x + webFrame.w) - visibleX
  local visibleHeight = math.min(winFrame.y + winFrame.h, webFrame.y + webFrame.h) - visibleY

  cached.visibleArea = {
    x = visibleX,
    y = visibleY,
    w = visibleWidth,
    h = visibleHeight
  }

  return cached.visibleArea
end

local function isEditableControlInFocus()
  if current.axFocusedElement() then
    return tblContains(config.axEditableRoles, current.axFocusedElement():attributeValue("AXRole"))
  else
    return false
  end
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

--------------------------------------------------------------------------------
-- menubar
--------------------------------------------------------------------------------

local menuBar = {}

function menuBar.new()
  if menuBar.item then menuBar.delete() end
  menuBar.item = hs.menubar.new()
end

function menuBar.delete()
  if menuBar.item then menuBar.item:delete() end
  menuBar.item = nil
end

local function setMode(mode)
  menuBar.item:setTitle(mode)
end

--------------------------------------------------------------------------------
-- actions
--------------------------------------------------------------------------------

function action.smoothScroll(x, y)
  local xstep = x / 5
  local ystep = y / 5
  hs.eventtap.event.newScrollEvent({ xstep, ystep }, {}, "pixel"):post()
  hs.timer.doAfter(0.01, function() hs.eventtap.event.newScrollEvent({ xstep * 3, ystep * 3 }, {}, "pixel"):post() end)
  hs.timer.doAfter(0.01, function() hs.eventtap.event.newScrollEvent({ xstep, ystep }, {}, "pixel"):post() end)
end

function action.openUrlInNewTab(url)
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
end

function action.setClipboardContents(contents)
  if contents and hs.pasteboard.setContents(contents) then
    hs.alert.show("Copied to clipboard: " .. contents, nil, nil, 4)
  else
    hs.alert.show("Failed to copy to clipboard", nil, nil, 4)
  end
end

function action.doForcedUnfocus()
  logWithTimestamp("forced unfocus on escape")
  if current.axWebArea() then
    current.axWebArea():setAttributeValue("AXFocused", true)
  end
end

--------------------------------------------------------------------------------
-- marks
--------------------------------------------------------------------------------

local marks = { data = {} }

function marks.clear()
  if marks.canvas then marks.canvas:delete() end
  marks.canvas = nil
  marks.data = {}
end

function marks.drawOne(markIndex)
  local mark = marks.data[markIndex]
  local visibleArea = current.visibleArea()
  local canvas = marks.canvas

  if not mark then return end
  if not marks.canvas then return end

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

  canvas:appendElements({
    type = "rectangle",
    fillColor = fillColor,
    strokeColor = { ["red"] = 0, ["green"] = 0, ["blue"] = 0, ["alpha"] = 1 },
    strokeWidth = 1,
    roundedRectRadii = { xRadius = 3, yRadius = 3 },
    frame = { x = bgRect.x - visibleArea.x, y = bgRect.y - visibleArea.y, w = bgRect.w, h = bgRect.h }
  })

  canvas:appendElements({
    type = "text",
    text = allCombinations[markIndex],
    textAlignment = "center",
    textColor = { ["red"] = 0, ["green"] = 0, ["blue"] = 0, ["alpha"] = 1 },
    textSize = fontSize,
    padding = padding,
    frame = { x = bgRect.x - visibleArea.x, y = bgRect.y - visibleArea.y, w = bgRect.w, h = bgRect.h }
  })
end

function marks.draw()
  marks.canvas = hs.canvas.new(current.visibleArea())

  -- area testing
  -- marksCanvas:appendElements({
  --   type = "rectangle",
  --   fillColor = { ["red"] = 0, ["green"] = 1, ["blue"] = 0, ["alpha"] = 0.1 },
  --   strokeColor = { ["red"] = 1, ["green"] = 0, ["blue"] = 0, ["alpha"] = 1 },
  --   strokeWidth = 2,
  --   frame = { x = 0, y = 0, w = visibleArea.w, h = visibleArea.h }
  -- })

  for i, _ in ipairs(marks.data) do
    marks.drawOne(i)
  end

  -- marksCanvas:bringToFront(true)
  marks.canvas:show()
end

function marks.add(element)
  table.insert(marks.data, { element = element })
end

function marks.isElementPartiallyVisible(element)
  if element:attributeValue("AXHidden") then return false end

  local frame = element:attributeValue("AXFrame")
  if not frame then return false end

  local visibleArea = current.visibleArea()

  local xOverlap = (frame.x < visibleArea.x + visibleArea.w) and (frame.x + frame.w > visibleArea.x)
  local yOverlap = (frame.y < visibleArea.y + visibleArea.h) and (frame.y + frame.h > visibleArea.y)

  return xOverlap and yOverlap
end

function marks.findClickableElements(element, withUrls)
  if not element then return end

  local jumpable = tblContains(config.axJumpableRoles, element:attributeValue("AXRole"))
  local visible = marks.isElementPartiallyVisible(element)
  local showable = not withUrls or element:attributeValue("AXURL")

  if jumpable and visible and showable then marks.add(element) end

  local children = element:attributeValue("AXChildren")
  if children then
    for _, child in ipairs(children) do
      marks.findClickableElements(child, withUrls)
    end
  end
end

function marks.show(withUrls)
  marks.findClickableElements(current.axWebArea(), withUrls)
  marks.draw()
end

function marks.click(combination)
  logWithTimestamp("marks.click")
  for i, c in ipairs(allCombinations) do
    if c == combination and marks.data[i] and marks.onClickCallback then
      marks.onClickCallback(marks.data[i])
    end
  end
end

--------------------------------------------------------------------------------
-- commands
--------------------------------------------------------------------------------

local commands = {}

function commands.cmdScrollLeft()
  hs.eventtap.event.newScrollEvent({ 100, 0 }, {}, "pixel"):post()
end

function commands.cmdScrollRight()
  hs.eventtap.event.newScrollEvent({ -100, 0 }, {}, "pixel"):post()
end

function commands.cmdScrollUp()
  hs.eventtap.event.newScrollEvent({ 0, 100 }, {}, "pixel"):post()
end

function commands.cmdScrollDown()
  hs.eventtap.event.newScrollEvent({ 0, -100 }, {}, "pixel"):post()
end

function commands.cmdScrollHalfPageDown()
  hs.eventtap.event.newScrollEvent({ 0, -500 }, {}, "pixel"):post()
end

function commands.cmdScrollHalfPageUp()
  hs.eventtap.event.newScrollEvent({ 0, 500 }, {}, "pixel"):post()
end

function commands.cmdCopyPageUrlToClipboard()
  local axURL = current.axWebArea():attributeValue("AXURL")
  action.pasteUrl(axURL.url)
end

local multi
local inInsert = false
local inEscape = false
local captureLinkMark

local function setMulti(char)
  multi = char
  if multi then
    setMode(multi)
  else
    setMode("V")
  end
end

function commands.cmdInsertMode(char)
  setMulti(char)
  inInsert = true
end

function commands.cmdGotoLink(char)
  setMulti(char)
  captureLinkMark = ""
  marks.onClickCallback = function(mark)
    mark.element:performAction("AXPress")
  end
  hs.timer.doAfter(0, marks.show)
end

function commands.cmdGotoLinkNewTab(char)
  setMulti(char)
  captureLinkMark = ""
  marks.onClickCallback = function(mark)
    local axURL = mark.element:attributeValue("AXURL")
    action.openUrlInNewTab(axURL.url)
  end
  hs.timer.doAfter(0, function() marks.show(true) end)
end

function commands.cmdMoveMouseToLink(char)
  setMulti(char)
  captureLinkMark = ""
  marks.onClickCallback = function(mark)
    local frame = mark.element:attributeValue("AXFrame")
    hs.mouse.absolutePosition({ x = frame.x + frame.w / 2, y = frame.y + frame.h / 2 })
  end
  hs.timer.doAfter(0, marks.show)
end

function commands.cmdCopyLinkUrlToClipboard(char)
  setMulti(char)
  captureLinkMark = ""
  marks.onClickCallback = function(mark)
    local axURL = mark.element:attributeValue("AXURL")
    action.pasteUrl(axURL.url)
  end
  hs.timer.doAfter(0, function() marks.show(true) end)
end

--------------------------------------------------------------------------------
--- vifari
--------------------------------------------------------------------------------

local mappingPrefixes

local function fetchMappingPrefixes()
  mappingPrefixes = {}
  for k, _ in pairs(config.mapping) do
    if #k == 2 then
      mappingPrefixes[string.sub(k, 1, 1)] = true
    end
  end
  logWithTimestamp("mappingPrefixes: " .. hs.inspect(mappingPrefixes))
end

local function vimLoop(char)
  logWithTimestamp("vimLoop " .. char)

  if char == "escape" then
    if multi then
      setMulti(nil)
      captureLinkMark = nil
      hs.timer.doAfter(0, marks.clear)
    end
    inEscape = true
    inInsert = false
    return
  else
    inEscape = false
  end

  if captureLinkMark then
    captureLinkMark = captureLinkMark .. char:lower()
    if #captureLinkMark == 2 then
      marks.click(captureLinkMark)
      setMulti(nil)
      captureLinkMark = nil
      hs.timer.doAfter(0, marks.clear)
    end
    return
  end

  local foundMapping = config.mapping[char]
  if multi then foundMapping = config.mapping[multi .. char] end

  if foundMapping then
    setMulti(nil)
    if type(foundMapping) == "string" then
      commands[foundMapping](char)
    elseif type(foundMapping) == "table" then
      hs.eventtap.keyStroke(foundMapping[1], foundMapping[2])
    else
      logWithTimestamp("Unknown mapping for " .. char .. " " .. hs.inspect(foundMapping))
    end
  elseif mappingPrefixes[char] then
    setMulti(char)
  else
    logWithTimestamp("Unknown char " .. char)
  end
end

local lastEscape = hs.timer.absoluteTime()

local function eventHandler(event)
  cached = {}

  local modifiers = event:getFlags()
  if modifiers["cmd"] or modifiers["ctrl"] or modifiers["alt"] or modifiers["fn"] then
    return false
  end

  if isSpotlightActive() then return false end

  local char = event:getCharacters()
  if event:getKeyCode() == hs.keycodes.map["escape"] then
    char = "escape"
  elseif not char:match("[%a%d%[%]%$]") then
    return false
  end

  if isEditableControlInFocus() then
    if char == "escape" and event:getType() == hs.eventtap.event.types.keyDown then
      local delaySinceLastEscape = (hs.timer.absoluteTime() - lastEscape) / 1e9 -- nanoseconds to seconds
      lastEscape = hs.timer.absoluteTime()

      if delaySinceLastEscape < config.doublePressDelay then
        inInsert = false
        inEscape = false
        setMulti(nil)
        action.doForcedUnfocus()
        return true
      end
    end
    return false
  end

  if inInsert and char ~= "escape" then return false end

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
  marks.clear()
end

local function onWindowUnfocused()
  logWithTimestamp("onWindowUnfocused")
  if eventLoop then
    eventLoop:stop()
    eventLoop = nil
  end
  setMulti(nil)
  setMode("X")
  marks.clear()
end

function obj:start()
  fetchMappingPrefixes()
  menuBar.new()
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
  menuBar.delete()
end

return obj
