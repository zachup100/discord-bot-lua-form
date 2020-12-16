local discordia, json, fs = require("discordia"), require("json"), require("fs")
local client = discordia.Client()
local guilds = {}

local defaultGuild = {prefix="!", party={category="0", lobby="0"}}
local parties = {} --// {owner=""}
local users = {} --// {voice="", guild=""}

--// string.split isn't a global function?
local function split(input, sep)
  if not sep then sep = "%s" end
  local rtn = {}
  for str in string.gmatch(input, "([^"..sep.."]+)") do table.insert(rtn, str) end
  return rtn
end

local function combine(tbl)
  local rtn = ""
  for _,str in pairs(tbl) do rtn = rtn.." "..str end
  return rtn
end

function Shutdown()
  SaveFile("./guilds.json", (guilds or {}))
  client:stop()
end

--// Easier way to load file without CopyPasta
function LoadFile(Path)
  local Output, Result = fs.existsSync(Path)
  if Output then
    local Output, Result = fs.readFileSync(Path)
    if Output then
      if (string.lower(string.sub(Path, string.len(Path)-4)) == ".json") then --// If it's a .json file
        local Result = json.parse(Output)
        if Result then
          return true, Result
        else
          --print(string.format("[WARNING] Failed to parse json file: '%s'", Result))
          return false, Result
        end
      else
        return true, Output
      end
    else
      --print(string.format("[WARNING] Failed to read file: '%s' -- '%s'", Path, Result))
      return false, Result
    end
  else
    --print(string.format("[WARNING] Failed to locate file: '%s' -- '%s'", Path, Result))
    return false, Result
  end
end

function SaveFile(Path, Data)
  if type(Data) == "table" then Data = json.stringify(Data) end
  local Output, Result = fs.writeFileSync(Path, Data)
  return Output, Result
end

local Success, Result = LoadFile('./guilds.json')
if Success then guilds = Result else print(string.format("[WARNING] Failed to load file: 'guilds.json' -- '%s'", Result)) end

--// Command Functions
function VoiceCommand(message, args)
  if args[1] == "setup" then
    local info = (type(guilds[message.guild._id].party)=="table" and guilds[message.guild._id].party) or {} --// {prefix="!", party={category="", lobby=""}}
    local category = message.guild:getChannel(info.category)
    if not category then
      category = message.guild:createCategory("Test Category")
      category:moveUp(20)
      if type(guilds[message.guild._id].party) ~= "table" then guilds[message.guild._id].party = {} end
      guilds[message.guild._id].party.category = category.id
      SaveFile("./guilds.json", (guilds or {}))
    end
    local voice = message.guild:getChannel(info.lobby)
    if not voice then
      voice = category:createVoiceChannel("Create a new voice party!")
      if type(guilds[message.guild._id].party) ~= "table" then guilds[message.guild._id].party = {} end
      guilds[message.guild._id].party.lobby = voice.id
      SaveFile("./guilds.json", (guilds or {}))
    end
  end
end

function TestCommand(message, args)
  print(message.author.mentionString) --// -> <@180885949926998026>
  print(message.author.id)
  message:reply(message.author.mentionString.." You ran a test command!")
end

--// Listen for Commands
--// Get Guild Id -> message.guild._id
--// Get Bot Client Id -> client.user.id
function MessageCreated(message)
	if message.author.bot then return end
  if message.type ~= 0 then return end
	local content = message.content:gsub("[\n\r]", "")
  local info = ((type(guilds[message.guild._id])=="table" and guilds[message.guild._id]) or defaultGuild)
  if not guilds[message.guild._id] then guilds[message.guild._id] = info end
  local args = split(content, " ")
  local From, End = string.find((args[1] or ""), string.format("<@!%s>", client.user.id))
  local Mentioned, UsedPrefix = (From==1), (string.sub((args[1] or ""), 1, string.len(info.prefix)) == info.prefix)
  if Mentioned then args[1] = string.sub(args[1], End+1) end --// Adjust arguments for Mentioned command
  if string.len(args[1]) == 0 then table.remove(args, 1) end --// Removes if first argument is just a mention

  if Mentioned or UsedPrefix then
    if UsedPrefix then
      args[1] = string.sub(args[1], string.len(info.prefix)+1)
      if string.len(args[1]) == 0 then return end --// If they message only contains the prefix
    end

    for i=1,#args do args[i] = string.lower(args[i]) end
    command = args[1]
    table.remove(args, 1)
    if string.len(command) == 0 then return end

    if command == "test" then
      TestCommand(message, args)
    elseif command == "voice" then
      VoiceCommand(message, args)
    elseif (command == "shutdown" and message.author.id == "180885949926998026") then
      Shutdown()
    else
      message:reply(message.author.mentionString.." Unknown Command!")
    end
  end
end

function MemberJoinedVoice(member, channel)
  local info = ((type(guilds[member.guild._id])=="table" and guilds[member.guild._id]) or defaultGuild)
  local category = channel.guild:getChannel(info.party.category)
  if not category then return end --// Guild didn't run 'voice setup'
  if type(users[member.id]) ~= "table" then users[member.id] = {voice=""} end
  if channel.id == info.party.lobby then
    local voice = channel.guild:getChannel(users[member.id].voice)
    if voice then
      member:setVoiceChannel(voice)
    else
      local voice = category:createVoiceChannel(member.name.."'s party")
      parties[voice.id] = {owner=member.id}
      users[member.id] = {voice=voice.id}
      member:setVoiceChannel(voice)
    end
  end
end

function MemberLeftVoice(member, channel)
  if parties[channel.id] then
    if #channel.connectedMembers == 0 then
      users[parties[channel.id].owner].voice = nil
      parties[channel.id] = nil
      channel:delete()
    end
  end
end

--// Discordia Listeners
print("Starting Client")
client:on('messageCreate', MessageCreated)
client:on('voiceChannelJoin', MemberJoinedVoice)
client:on('voiceChannelLeave', MemberLeftVoice)
client:run(string.format('Bot %s', process.env.TOKEN))
