-- Decompiled using luadec 2.2 rev: 895d923 for Lua 5.1 from https://github.com/viruscamp/luadec
-- Command line: x86-64/regdecode.lua 

-- params : ...
-- function num : 0
-- DECOMPILER ERROR at PC5: Confused about usage of register: R0 in 'UnsetPending'

package.path = package.path .. ";.\\?.lhs;..\\?.lhs"
require("common_fun")
Reg_DECFun = function()
  -- function num : 0_0
  LoadC_Fun("./luadec.dll", "l_RegAllFun")
end

Reg_DECFun()

