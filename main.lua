local discordia, json, fs, coroutine, timer = require("discordia"), require("json"), require("fs"), require("coroutine"), require("timer")
local Bot, Enum = discordia.Client({shardCount=2}), discordia.enums
local Guilds = {Default={Prefix="!", Party={Template="{USERNAME}'s Party", Category="0", Lobby="0"}}}
local TOKEN = process.env.TOKEN
function GetGuildInfo(Id) return Guilds[Id] or Guilds.Default end

local Parties = {}
local Members = {}

function Parties.get(Id) return Parties[Id] end
function Parties.new(Member, Category, Title)
  local Channel = Category:createVoiceChannel(Title)
  local Permissions = Channel:getPermissionOverwriteFor(Member)
  Permissions:clearAllPermissions()
  Permissions:allowPermissions(Enum.permission.connect, Enum.permission.speak, Enum.permission.connect)

  local self = {}
  self.Owner = Member.id
  self.Access = {}
  self.Title = Title
  self.Guild = Category.guild.id
  self.Id = Channel.id

  function self:GetChannel() return self.Id end
  function self:Remove()
    local Id = self.Id
    for Index, Value in pairs(self) do self[Index] = nil end
    Parties[Id] = nil
  end
  function self:HasAccess(Id)
    if #self.Access == 0 then return false end
    for int=1,#self.Access do
      if self.Access[int] == Id then
        return int
      end
    end
    return false
  end
  function self:Permit(Id)
    if self:HasAccess(Id) then return false, "0" end
    local Guild = Bot:getGuild(self.Guild)
    local Channel = Guild:getChannel(self.Id)
    if not Channel then return false, "1" end
    local Member = Guild:getMember(Id)
    if not Member then return false, "2" end
    local Permissions = Channel:getPermissionOverwriteFor(Member)
    Permissions:clearAllPermissions()
    Permissions:allowPermissions(Enum.permission.connect, Enum.permission.speak, Enum.permission.connect)
    table.insert(self.Access, Id)
    return true
  end
  function self:Revoke(Id)
    if #self.Access == 0 then return false, "1" end
    local Access = self:HasAccess(Id)
    print(Access)
    if not Access then return false, "2" end
    local Guild = Bot:getGuild(self.Guild)
    local Channel = Guild:getChannel(self.Id)
    if not Channel then return false, "3" end
    local Member = Guild:getMember(Id)
    if not Member then return false, "4" end
    local Permissions = Channel:getPermissionOverwriteFor(Member)
    Permissions:clearAllPermissions()
    Permissions:delete()
    table.remove(self.Access, Access)
    return true
  end
  function self:Lock()
    local Guild = Bot:getGuild(self.Guild)
    local Channel = Guild:getChannel(self.Id)
    if not Channel then return false, "1" end
    local Role = GetEveryoneRole(Guild)
    local Permissions = Channel:getPermissionOverwriteFor(Role)
    Permissions:clearAllPermissions()
    Permissions:denyPermissions(Enum.permission.connect, Enum.permission.speak, Enum.permission.connect)
    return true
  end
  function self:Unlock()
    local Guild = Bot:getGuild(self.Guild)
    local Channel = Guild:getChannel(self.Id)
    if not Channel then return false, "1" end
    local Role = GetEveryoneRole(Guild)
    local Permissions = Channel:getPermissionOverwriteFor(Role)
    Permissions:clearAllPermissions()
    return true
  end

  Parties[Channel.id] = self
  return self
end

function Members.get(Id) return Members[Id] end
function Members.new(Member)
  local self = {}
  self.Channel = ""

  function self:SetChannel(Id)
    self.Channel = Id
    return self
  end

  Members[Member.id] = self
  return self
end

function GetEveryoneRole(Guild)
  for _, Role in pairs(Guild.roles) do
    if Role.name == "@everyone" then
      return Role
    end
  end
end

function HasParty(Id)
  local _Member = Members.get(Id)
  if not _Member then return false end
  local Party = Parties.get(_Member.Channel)
  if not Party then return false end
  return true, _Member, Party
end

local function split(input, sep)
  if not sep then sep = "%s" end
  local rtn = {}
  for str in string.gmatch(input, "([^"..sep.."]+)") do table.insert(rtn, str) end
  return rtn
end

local function ShutdownBot()
  timer.clearTimer(SaveTimer)
  SaveFile("./guilds.json", Guilds)
  Bot:stop()
end

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
          return false, Result
        end
      else
        return true, Output
      end
    else
      return false, Result
    end
  else
    return false, Result
  end
end

function SaveFile(Path, Data)
  if type(Data) == "table" then Data = json.stringify(Data) end
  local Output, Result = fs.writeFileSync(Path, Data)
  return Output, Result
end

local Success, Result = LoadFile('./guilds.json')
if Success then Guilds = Result else print(string.format("[WARNING] Failed to load file: 'guilds.json' -- '%s'", Result)) end

--// Command Functions
function VoiceCommand(Member, Message, Args)
  if #Args == 0 then
    Message:reply(string.format("%s Subcommands: setup, template, name, claim, lock, unlock, permit, revoke", Message.author.mentionString))
    return
  end
  if string.lower(Args[1]) == "setup" then
    local HasChannelPerms = (Member:hasPermission(nil, Enum.permission.manageChannels) or Member:hasPermission(nil, Enum.permission.administrator))
    if not HasChannelPerms then
      Message:reply(string.format("%s You do not have the proper permissions to use that command.", Message.author.mentionString))
      return
    end
    local Info = GetGuildInfo(Message.guild.id)
    if Message.guild:getChannel(Info.Party.Category) or Message.guild:getChannel(Info.Party.Lobby) then
      Message:reply(string.format("%s Category or Voice Channel still exists. Delete them to restart the setup.", Message.author.mentionString))
      return
    end
    local Category = Message.guild:createCategory("Parties")
    Guilds[Member.guild.id].Party.Category = Category.id
    Category:moveUp(20)
    local Voice = Category:createVoiceChannel("Create a new voice party!")
    Guilds[Member.guild.id].Party.Lobby = Voice.id
    SaveFile("./guilds.json", Guilds)
    Message:reply(string.format("%s Setup complete, look for the category called \"Parties\"", Message.author.mentionString))
    return
  elseif Args[1] == "template" then
    table.remove(Args, 1)
    local Title = table.concat(Args, " ")
    if string.len(Title) == 0 then Message:reply(string.format("%s Your template string cannot be empty!", Message.author.mentionString)) return end
    Guilds[Member.guild.id].Party.Template = Title
    Message:reply(string.format("%s You changed the template to '%s'", Message.author.mentionString, string.gsub(Title, "{USERNAME}", Member.name)))
    return
  elseif (Args[1] == "name" or Args[1] == "rename" or Args[1] == "title") then
    table.remove(Args, 1)
    local Title = table.concat(Args, " ")
    local Exists, _Member, Party = HasParty(Member.id)
    if not Exists then
      Message:reply(string.format("%s You do not own a voice channel!", Message.author.mentionString))
      return
    end
    local Channel = Member.guild:getChannel(_Member.Channel)
    if not Channel then
      Message:reply(string.format("%s Error: Unknown Channel", Message.author.mentionString))
      return
    end
    Channel:setName(Title)
    Message:reply(string.format("Your channel was renamed to '%s'", Title))
  elseif Args[1] == "claim" then
    Message:reply("This sub-command is unfinished")
    return
  elseif Args[1] == "lock" then
    local Exists, _Member, Party = HasParty(Member.id)
    if not Exists then
      Message:reply(string.format("%s You do not own a voice channel!", Message.author.mentionString))
      return
    end
    local Success = Party:Lock()
    if Success then
      Message:reply("Your channel was locked!")
    else
      Message:reply("Error: unable to lock your channel!")
    end
    return
  elseif Args[1] == "unlock" then
    local Exists, _Member, Party = HasParty(Member.id)
    if not Exists then
      Message:reply(string.format("%s You do not own a voice channel!", Message.author.mentionString))
      return
    end
    local Success = Party:Unlock()
    if Success then
      Message:reply("Your channel was unlocked!")
    else
      Message:reply("Error: unable to unlock your channel!")
    end
    return
  elseif (Args[1] == "permit" or Args[1] == "allow") then
    local Exists, _Member, Party = HasParty(Member.id)
    if not Exists then
      Message:reply(string.format("%s You do not own a voice channel!", Message.author.mentionString))
      return
    end
    local Mentions = Message.mentionedUsers or {}
    if #Mentions == 0 then Message:reply(string.format("%s You didn't mention anybody!", Message.author.mentionString)) return end
    local Permitted = 0
    if #Mentions == 1 then
      local getMember = Message.guild:getMember(Mentions[1][1])
      if not getMember then
        Message:reply(string.format("%s That user isn't in this guild", Message.author.mentionString))
        return
      end
      local User = getMember.user
      if User.bot then
        Message:reply(string.format("%s You cannot give access to Discord Bots", Message.author.mentionString))
        return
      end
      if User.id == Member.id then
        Message:reply(string.format("%s You already have access to your own channel!", Message.author.mentionString))
        return
      end
      local Success, Output = Party:Permit(User.id)
      if Success then
        Message:reply(string.format("%s You gave access to '%s'", Message.author.mentionString, User.name))
      else
        Message:reply(string.format("%s Failed to give access. Error-Id %s", Message.author.mentionString, Output))
      end
      return
    else
      for _, Mention in pairs(Mentions) do
        local getMember = Message.guild:getMember(Mention.id)
        if getMember then
          local User = getMember.user
          if not User.bot and User.id ~= Member.id and not Party:HasAccess(User.id) then
            Party:Permit(User.id)
            Permitted = Permitted + 1
          end
        end
      end
      Message:reply(string.format("%s Permitted %s members.", Message.author.mentionString, Permitted))
      return
    end
  elseif (Args[1] == "revoke" or Args[1] == "remove") then
    local Exists, _Member, Party = HasParty(Member.id)
    if not Exists then
      Message:reply(string.format("%s You do not own a voice channel!", Message.author.mentionString))
      return
    end
    local Mentions = Message.mentionedUsers or {}
    if #Mentions == 0 then Message:reply(string.format("%s You didn't mention anybody!", Message.author.mentionString)) return end
    local Revoked = 0
    if #Mentions == 1 then
      local getMember = Message.guild:getMember(Mentions[1][1])
      if not getMember then
        Message:reply(string.format("%s That user isn't in this guild", Message.author.mentionString))
        return
      end
      local User = getMember.user
      if User.id == Member.id then
        Message:reply(string.format("%s You can't remove access to your own channel!", Message.author.mentionString))
        return
      end
      local Success, Output = Party:Revoke(User.id)
      if Success then
        Message:reply(string.format("%s You removed access from '%s'", Message.author.mentionString, User.name))
      else
        if Output == "1" or Output == "2" then
          Message:reply(string.format("%s That member doesn't have access to your channel.", Message.author.mentionString, Output))
        else
          Message:reply(string.format("%s Failed to remove access. Error-Id %s", Message.author.mentionString, Output))
        end
      end
      return
    else
      for _, Mention in pairs(Mentions) do
        local getMember = Message.guild:getMember(Mention.id)
        if getMember then
          local User = getMember.user
          if User.id ~= Member.id and Party:HasAccess(User.id) then
            Party:Revoke(User.id)
            Revoked = Revoked + 1
          end
        end
      end
      Message:reply(string.format("%s Removed %s members.", Message.author.mentionString, Permitted))
      return
    end
  end
end

function MessageCreated(Message)
  if Message.author.bot then return end
  if Message.type ~= 0 then return end
  local Content = Message.content:gsub("[\n\r]", "")
  local Guild = GetGuildInfo(Message.guild.id)
  if not Guilds[Message.guild.id] then Guilds[Message.guild.id] = Guild end
  local Args = split(Content, " ")
  local From, End = string.find((Args[1] or ""), string.format("<@!%s>", Bot.user.id))
  local Mentioned, UsedPrefix = (From==1), (string.sub((Args[1] or ""), 1, string.len(Guild.Prefix)) == Guild.Prefix)
  if Mentioned then Args[1] = string.sub(Args[1], End+1) end
  if string.len(Args[1]) == 0 then table.remove(Args, 1) end
  if Mentioned or UsedPrefix then
    if UsedPrefix then
      Args[1] = string.sub(Args[1], string.len(Guild.Prefix)+1)
      if string.len(Args[1]) == 0 then return end
    end
    local Member = Message.guild:getMember(Message.author.id)
    Command = string.lower(Args[1])
    if string.len(Command) == 0 then return end
    table.remove(Args, 1)

    if (Command == "voice") then
      VoiceCommand(Member, Message, Args)
    elseif (Command == "test") then
      Message:reply(string.format("%s Shard instance '%s'", Message.author.mentionString, Member.guild.shardId))
    elseif (Command == "reset" and Message.author.id == "180885949926998026") then
      if string.lower(Args[1]) == "all" then
        local defaultFile = {Default=Guilds.Default}
        SaveFile("./guilds.json", defaultFile)
        Message:reply(string.format("%s You reset the 'guilds.json' file.", Message.author.mentionString))
      else
        Guilds[Message.guild.id] = Guilds.Default
        Message:reply(string.format("%s You reset the settings for this server.", Message.author.mentionString))
      end
      return
    elseif (Command == "shutdown" and Message.author.id == "180885949926998026") then
      ShutdownBot()
    end
  end
end

function MessageCreatedSafe(Message)
  local Success, Result = pcall(MessageCreated, Message)
  if not Success then print("[MessageCreated]:",Result) end
end

function MemberJoinedVoice(Member, Channel)
  local Guild = GetGuildInfo(Member.guild.id)
  if Channel.id ~= Guild.Party.Lobby then return end
  local _Member = Members.get(Member.id)
  if not _Member then _Member = Members.new(Member) end
  local Party = Parties.get(_Member.Channel)
  if not Party then
    local Category = Member.guild:getChannel(Guild.Party.Category)
    if Category then
      print("New Party event")
      Party = Parties.new(Member, Category, string.gsub(Guild.Party.Template, "{USERNAME}", Member.name))
      local VoiceId = Party:GetChannel()
      _Member:SetChannel(VoiceId)
      Member:setVoiceChannel(VoiceId)
    end
  end
end

function MemberJoinedVoiceSafe(Member, Channel)
  local Success, Result = pcall(MemberJoinedVoice, Member, Channel)
  if not Success then print("[MemberJoinedVoice]:",Result) end
end

--// Fix this, doesn't always delete channel
function MemberLeftVoice(Member, Channel)
  local Party = Parties.get(Channel.id)
  if Party then
    if #Channel.connectedMembers == 0 then
      local Owner = Members.get(Party.Owner)
      if Owner then Owner.Channel = "" end
      Party:Remove()
      Channel:delete()
    end
  end
end

function MemberLeftVoiceSafe(Member, Channel)
  local Success, Result = pcall(MemberLeftVoice, Member, Channel)
  if not Success then print("[MemberLeftVoice]:",Result) end
end

function AutoSave()
  print("Auto-saving 'guilds.json'")
  SaveFile("./guilds.json", Guilds)
end

SaveTimer = timer.setInterval(120000, AutoSave)
Bot:on('messageCreate', MessageCreatedSafe)
Bot:on('voiceChannelJoin', MemberJoinedVoiceSafe)
Bot:on('voiceChannelLeave', MemberLeftVoiceSafe)
Bot:run(string.format("Bot %s", TOKEN))
