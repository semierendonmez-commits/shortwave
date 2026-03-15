-- lib/names.lua
-- procedural radio station name generator
-- inspired by namesizer but self-contained

local Names = {}

-- syllable pools for different "cultures"
local PREFIXES = {
  "Radio ", "FM ", "WKRP-", "VOA-", "RTL-", "NHK-",
  "BBC-", "KBS-", "RFI-", "RAI-", "",  "", "", "", "",
}

local SYLLABLES_A = {
  "ka","mi","to","ru","na","shi","ko","ha","yu","sa",
  "no","te","ri","wa","su","chi","ki","mo","fu","ne",
  "ze","vo","ax","el","on","ar","is","um","ox","en",
}

local SYLLABLES_B = {
  "la","ra","da","ma","pa","ba","ta","ga","za","va",
  "lon","ran","dan","man","pan","ber","ter","ger","zan","ver",
  "nia","sia","dia","lia","ria","tia","gia","bia","via","zia",
}

local SUFFIXES = {
  " FM", " AM", " SW", " HF", "", "", "", "",
  " Int'l", " World", " Wave",
}

local WORD_POOL = {
  "Echo", "Nova", "Pulsar", "Drift", "Static", "Ghost",
  "Signal", "Beacon", "Orbit", "Void", "Nebula", "Haze",
  "Murmur", "Flux", "Aether", "Ether", "Cosmo", "Lunar",
  "Cipher", "Zenith", "Nadir", "Phase", "Quantum",
  "Aurora", "Vertex", "Prism", "Nexus", "Helix",
}

function Names.generate()
  local style = math.random(1, 5)

  if style == 1 then
    -- call sign: WXYZ-123
    local letters = ""
    for i = 1, math.random(3, 4) do
      letters = letters .. string.char(math.random(65, 90))
    end
    return letters .. "-" .. math.random(10, 99)

  elseif style == 2 then
    -- syllable name: Karumi FM
    local name = SYLLABLES_A[math.random(#SYLLABLES_A)]
      .. SYLLABLES_B[math.random(#SYLLABLES_B)]
    name = name:sub(1,1):upper() .. name:sub(2)
    return name .. SUFFIXES[math.random(#SUFFIXES)]

  elseif style == 3 then
    -- word name: Echo Wave
    return WORD_POOL[math.random(#WORD_POOL)]

  elseif style == 4 then
    -- prefix + number
    return PREFIXES[math.random(#PREFIXES)] .. math.random(1, 999)

  else
    -- two syllables
    local s1 = SYLLABLES_A[math.random(#SYLLABLES_A)]
    local s2 = SYLLABLES_A[math.random(#SYLLABLES_A)]
    local name = (s1 .. s2)
    return name:sub(1,1):upper() .. name:sub(2)
  end
end

return Names
