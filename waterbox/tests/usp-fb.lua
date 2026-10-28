-- M5 frontend leg: boot the packaged core through the real frontend pipeline,
-- optionally with held input and per-frame savestate round-trips, screenshot.
-- Job description comes from the USP_JOB env var file (key=value lines):
--   frames=<N>          frames to advance after boot
--   input=<hexmask>     64-bit button mask held every frame (bit i = input.buttons[i])
--   extra=<N1,N2,...>   more buttons held every frame, by whole declared name
--                       (bits past 52 cannot ride the mask: a Lua number is a
--                       double, so the P5 keyboard comes through here)
--   rerecord=0|1        save+load the whole machine around every frame
--   shot=<path>         where to write the final screenshot (PNG)
--   meta=<path>         where to write status=OK and the frame count
-- Button order is waterbox.config input.buttons declaration order: P1
-- Kempston, P2 Sinclair, P3 Cursor, P4 QAOP, console Space/Enter, then the
-- P5 keyboard.
local function writeAll(path, data)
  local f = assert(io.open(path, "wb"))
  f:write(data)
  f:close()
end

local meta = {}
local function finish(status, detail)
  local lines = {
    "status=" .. status,
    "detail=" .. (detail or ""),
    "frames=" .. (meta.frames or 0),
    "ram=" .. (meta.ram or ""),
    "vram=" .. (meta.vram or ""),
    "lag=" .. (meta.lag or ""),
  }
  if meta.metaPath then writeAll(meta.metaPath, table.concat(lines, "\n") .. "\n") end
  client.exit()
end

local jobPath = os.getenv("USP_JOB")
if jobPath == nil then finish("ERROR", "no USP_JOB env var") end
local job = {}
for line in io.lines(jobPath) do
  local k, v = line:match("^([^=]+)=(.*)$")
  if k then job[k] = v end
end
meta.metaPath = job.meta

if emu.getsystemid() ~= "ZXS" then finish("ERROR", "wrong system id: " .. tostring(emu.getsystemid())) end
if emu.getsystemid() == nil then finish("ERROR", "no system id") end

local frames = tonumber(job.frames) or 600
local mask = tonumber(job.input or "0") or 0
local names = {
  "P1 Up", "P1 Down", "P1 Left", "P1 Right", "P1 Fire",
  "P2 Up", "P2 Down", "P2 Left", "P2 Right", "P2 Fire",
  "P3 Up", "P3 Down", "P3 Left", "P3 Right", "P3 Fire",
  "P4 Up", "P4 Down", "P4 Left", "P4 Right", "P4 Fire",
  "Key.Space", "Key.Enter",
}
local extra = {}
if job.extra then
  for name in (job.extra .. ","):gmatch("([^,]*),") do
    if name ~= "" then extra[#extra + 1] = name end
  end
end
local rerecord = (job.rerecord == "1")
local stateId = nil
if rerecord then stateId = memorysavestate.savecorestate() end
for i = 1, frames do
  if rerecord then memorysavestate.loadcorestate(stateId) end
  local buttons = {}
  for b = 0, #names - 1 do
    if math.floor(mask / (2 ^ b)) % 2 == 1 then buttons[names[b + 1]] = true end
  end
  for _, name in ipairs(extra) do buttons[name] = true end
  if next(buttons) ~= nil then joypad.set(buttons) end
  emu.frameadvance()
  if rerecord then
    memorysavestate.removestate(stateId)
    stateId = memorysavestate.savecorestate()
  end
end
meta.frames = emu.framecount()
meta.ram = memory.hash_region(0, 131072, "RAM")
meta.vram = memory.hash_region(0, 76800, "VRAM")
meta.lag = emu.lagcount()
client.screenshot(job.shot)
finish("OK", "")
