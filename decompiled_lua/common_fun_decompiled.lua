-- Decompiled using luadec 2.2 rev: 895d923 for Lua 5.1 from https://github.com/viruscamp/luadec
-- Command line: x86-64/common_fun.lua 

-- params : ...
-- function num : 0
require("ini_fun")
LoadC_Fun = function(modelpath, funcName)
  -- function num : 0_0
  local Reg = (package.loadlib)(modelpath, funcName)
  if Reg then
    print("Register" .. modelpath .. " " .. funcName .. " Sucess!")
    Reg()
  else
    print("Register" .. modelpath .. " " .. funcName .. " Failed!")
  end
end


