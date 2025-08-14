processing OP_JMP to } else { 
 at line 2649 in file decompile.c
 for lua files: x86-64/ini_fun.lua
 at lua function 0_7 pc=29

-- Decompiled using luadec 2.2 rev: 895d923 for Lua 5.1 from https://github.com/viruscamp/luadec
-- Command line: x86-64/ini_fun.lua 

-- params : ...
-- function num : 0
TrimLeft = function(szLine)
  -- function num : 0_0
  local szValid = szLine
  while 1 do
    while (string.sub)(szValid, 1, 1) == " " do
      szValid = (string.sub)(szValid, 2, -1)
    end
    break
  end
  if (string.sub)(szValid, 1, 1) == ";" then
    return nil
  end
  local nComm = (string.find)(szValid, ";")
  if nComm == 1 then
    szValid = nil
  else
    if nComm ~= nil then
      szValid = (string.sub)(szValid, 1, nComm - 1)
    end
  end
  return szValid
end

TrimRight = function(szLine)
  -- function num : 0_1
  local szValid = szLine
  if szLine == nil then
    return nil
  end
  while 1 do
    while (string.sub)(szValid, -1, -1) == " " do
      szValid = (string.sub)(szValid, 1, -2)
    end
    break
  end
  return szValid
end

IsSec = function(szLine)
  -- function num : 0_2
  local szValid = szLine
  if szValid == "" then
    return false
  end
  if (string.sub)(szValid, 1, 1) == "[" and (string.sub)(szValid, -1, -1) == "]" then
    return true
  else
    return false
  end
end

IsKey = function(szLine)
  -- function num : 0_3
  local szValid = szLine
  if szValid == "" then
    return false
  end
  local nEqu = (string.find)(szValid, "=")
  if nEqu == nil then
    return false
  end
  return true
end

GetSecName = function(szLine)
  -- function num : 0_4
  local szValid = TrimLeft(szLine)
  szValid = TrimRight(szValid)
  local szRet = (string.sub)(szValid, 2, -2)
  szRet = TrimLeft(szRet)
  szRet = TrimRight(szRet)
  return szRet
end

GetKeyName = function(szLine)
  -- function num : 0_5
  local nEqu = (string.find)(szLine, "=")
  if nEqu == nil then
    return nil
  end
  local szRet = (string.sub)(szLine, 1, nEqu - 1)
  szRet = TrimLeft(szRet)
  szRet = TrimRight(szRet)
  return szRet
end

GetKeyValue = function(szLine)
  -- function num : 0_6
  local nEqu = (string.find)(szLine, "=")
  if nEqu == nil then
    return nil
  end
  local szRet = (string.sub)(szLine, nEqu + 1, -1)
  szRet = TrimLeft(szRet)
  szRet = TrimRight(szRet)
  return szRet
end

GetIniString = function(szSecName, szKeyName, szFileName)
  -- function num : 0_7
  local bSecFind = false
  local bKeyFind = false
  for line in (io.lines)(szFileName) do
    local szValid = TrimLeft(line)
    szValid = TrimRight(szValid)
    do
      -- DECOMPILER ERROR at PC26: Unhandled construct in 'MakeBoolean' P1

      -- DECOMPILER ERROR at PC26: Unhandled construct in 'MakeBoolean' P1

      if szValid ~= nil and bSecFind == false and IsSec(szValid) == true then
        local szSecTmp = GetSecName(szValid)
        if szSecTmp == szSecName then
          bSecFind = true
        end
      end
      if IsSec(szValid) == true then
        return nil
      end
      if IsKey(szValid) == false then
        return nil
      end
      do
        local szKeyTmp = GetKeyName(szValid)
        if szKeyTmp == szKeyName then
          return GetKeyValue(szValid)
        end
        -- DECOMPILER ERROR at PC53: LeaveBlock: unexpected jumping out DO_STMT

      end
    end
  end
  return nil
end


