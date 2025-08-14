processing OP_JMP to } else { 
 at line 2649 in file decompile.c
 for lua files: x86-64/imgdec_fun.lua
 at lua function 0_9 pc=239

-- Decompiled using luadec 2.2 rev: 895d923 for Lua 5.1 from https://github.com/viruscamp/luadec
-- Command line: x86-64/imgdec_fun.lua 

--[[
========================================================================
                    LiveSuite镜像解码模块 (imgdec_fun.lua)
========================================================================

功能概述:
本模块用于解析和提取全志(Allwinner)固件镜像文件(.img)中的数据。
支持多种镜像格式版本(32位/64位)，能够处理加密和非加密的镜像文件。

主要功能:
1. 镜像文件解析 - 读取和解析镜像头部信息
2. 项目表解析 - 解析镜像中包含的各个项目(分区/文件)
3. 数据解码 - 支持加密数据的解码
4. 数据提取 - 从镜像中提取指定项目的数据

支持的镜像版本:
- Version 256: 32位镜像格式
- Version 768+: 64位镜像格式，支持更大的文件和更多字段

核心数据结构:
- 镜像头部(ImageHead): 包含镜像基本信息、版本、项目数量等
- 项目表(ItemTable): 包含所有项目的元数据信息
- 项目句柄(ItemHandle): 用于跟踪项目读取状态

加密机制:
- 使用16字节块加密算法
- 支持头部、表格、数据三种不同的解码器
- 通过魔数"IMAGEWTY"识别是否为加密镜像

典型使用流程:
1. Img_Open() - 打开镜像文件
2. Img_OpenItem() - 打开指定项目
3. Img_ReadItemData() - 读取项目数据
4. Img_CloseItem() - 关闭项目
5. Img_Close() - 关闭镜像

========================================================================
--]]

--[[
LiveSuite镜像解码模块
用于解析和提取全志(Allwinner)固件镜像文件中的数据
支持加密和非加密的镜像格式
--]]

-- params : ...
-- function num : 0
require("regbasefun")    -- 基础寄存器操作函数
require("regdecode")     -- 解码相关函数

-- 调试和配置常量
DEBUG_FLAG = 0           -- 调试标志，0=关闭调试，1=开启调试

-- 解码接口ID定义
HEAD_ID = 1              -- 镜像头部解码接口ID
TABLE_ID = 2             -- 表格数据解码接口ID
DATA_ID = 3              -- 数据解码接口ID
IF_CNT = 3               -- 解码接口总数

-- 缓冲区大小常量
MAX_KEY_SIZE = 32        -- 最大密钥长度
IMAGE_HEAD_SIZE = 96     -- 镜像头部大小(字节)
IMAGE_HANDLE_SIZE = 136  -- 镜像句柄大小(字节)
IMAGE_ITEM_SIZE = 1024   -- 单个项目信息大小(字节)
ITEM_HANDLE_SIZE = 12    -- 项目句柄大小(字节)
ENCODE_LEN = 16          -- 加密块长度(字节)
SIZE_32K = 32768         -- 32KB缓冲区大小

-- 全局状态变量
g_bEncypt = 1            -- 加密标志，1=加密镜像，0=非加密镜像
Img_Version = 100        -- 镜像版本号
Item_OffList = nil       -- 项目偏移列表

-- 解码器句柄
g_hDecHead = nil         -- 头部解码器句柄
g_hDecTab = nil          -- 表格解码器句柄
g_hDecData = nil         -- 数据解码器句柄
g_DecIF = {g_hDecHead, g_hDecTab, g_hDecData}  -- 解码接口数组

-- 镜像句柄结构
g_hImageHandle = {
  fp = nil,              -- 文件指针
  ImageHead = nil,       -- 镜像头部数据
  ItemTab = nil,         -- 项目表数据
  rc_if_decode = g_DecIF -- 解码接口引用
}

ITEM_PHOENIX_TOOLS = "PXTOOLS "  -- Phoenix工具项目标识
--[[
调试输出函数
在DEBUG_FLAG为1时输出调试信息到控制台和调试跟踪
@param str 要输出的调试字符串
--]]
DebugPrint = function(str)
  -- function num : 0_0
  if DEBUG_FLAG == 1 then
    print(str)
    DebugTrace("IMGDec Debug:" .. str .. "\n")
  end
end

--[[
消息打印函数
与DebugPrint功能相同，提供另一个调试输出接口
@param str 要输出的消息字符串
--]]
mprint = function(str)
  -- function num : 0_1
  if DEBUG_FLAG == 1 then
    print(str)
    DebugTrace("IMGDec Debug:" .. str .. "\n")
  end
end

--[[
镜像头部结构定义(64位版本)
定义了镜像头部各个字段的偏移量
用于解析64位镜像格式的头部信息
--]]
Img_Head64 = {
  I_H_MAGIC = 0,           -- 魔数标识，用于识别文件格式
  I_H_VERSION = 8,         -- 镜像版本号
  I_H_SIZE = 12,           -- 头部大小
  I_H_ATTR = 16,           -- 头部属性
  I_H_IMG_VERSION = 20,    -- 镜像版本
  I_H_LELO = 24,           -- 长度低位
  I_H_LENHI = 28,          -- 长度高位
  I_H_ALIGN = 32,          -- 对齐方式
  I_H_PID = 36,            -- 产品ID
  I_H_VID = 40,            -- 厂商ID
  I_H_HARDAREID = 44,      -- 硬件ID
  I_H_FIRMWAREID = 48,     -- 固件ID
  I_H_ITEMATTR = 52,       -- 项目属性
  I_H_ITEMSIZE = 56,       -- 项目大小
  I_H_ITEMCNT = 60,        -- 项目数量
  I_H_ITEMOFFSET = 64,     -- 项目表偏移
  I_H_IMAGEATTR = 68,      -- 镜像属性
  I_H_APPENDISZE = 72,     -- 附加数据大小
  I_H_APPENDOFFSETLO = 76, -- 附加数据偏移低位
  I_H_APPENDOFFSETHI = 80, -- 附加数据偏移高位
  I_H_RESIVER = 84         -- 保留字段
}

--[[
镜像头部结构定义(32位版本)
定义了32位镜像格式头部各个字段的偏移量
与64位版本相比，某些字段位置和高位字段有所不同
--]]
Img_Head32 = {
  I_H_MAGIC = 0,           -- 魔数标识
  I_H_VERSION = 8,         -- 镜像版本号
  I_H_SIZE = 12,           -- 头部大小
  I_H_ATTR = 16,           -- 头部属性
  I_H_IMG_VERSION = 20,    -- 镜像版本
  I_H_LENLO = 24,          -- 长度低位
  I_H_LENHI = 0,           -- 长度高位(32位版本中为0)
  I_H_ALIGN = 28,          -- 对齐方式
  I_H_PID = 32,            -- 产品ID
  I_H_VID = 36,            -- 厂商ID
  I_H_HARDAREID = 40,      -- 硬件ID
  I_H_FIRMWAREID = 44,     -- 固件ID
  I_H_ITEMATTR = 48,       -- 项目属性
  I_H_ITEMSIZE = 52,       -- 项目大小
  I_H_ITEMCNT = 56,        -- 项目数量
  I_H_ITEMOFFSET = 60,     -- 项目表偏移
  I_H_IMAGEATTR = 64,      -- 镜像属性
  I_H_APPENDISZE = 68,     -- 附加数据大小
  I_H_APPENDOFFSETLO = 72, -- 附加数据偏移低位
  I_H_APPENDOFFSETHI = 0   -- 附加数据偏移高位(32位版本中为0)
}

--[[
镜像项目结构定义(32位版本)
定义了镜像中每个项目(文件/分区)的元数据结构
--]]
Img_Item32 = {
  I_T_VERSION = 0,         -- 项目版本
  I_T_SIZE = 4,            -- 项目结构大小
  I_T_MAINTYPE = 8,        -- 主类型(8字节字符串)
  I_T_SUBTYPE = 16,        -- 子类型(16字节字符串)
  I_T_ATTR = 32,           -- 项目属性
  I_T_DATALENLO = 36,      -- 数据长度低位
  I_T_FILELENLO = 40,      -- 文件长度低位
  I_T_OFFSETLO = 44,       -- 文件偏移低位
  I_T_CHECKSUM = 48,       -- 校验和
  I_T_NAME = 52,           -- 项目名称
  I_T_RES = 308            -- 保留字段
}

--[[
镜像项目结构定义(64位版本)
64位版本支持更大的文件和更多的字段
--]]
Img_Item64 = {
  I_T_SIZE = 4,            -- 项目结构大小
  I_T_MAINTYPE = 8,        -- 主类型
  I_T_SUBTYPE = 16,        -- 子类型
  I_T_ATTR = 32,           -- 项目属性
  I_T_NAME = 36,           -- 项目名称
  I_T_DATALENLO = 292,     -- 数据长度低位
  I_T_DATALENHI = 296,     -- 数据长度高位
  I_T_FILELENLO = 300,     -- 文件长度低位
  I_T_FILELENHI = 304,     -- 文件长度高位
  I_T_OFFSETLO = 308,      -- 文件偏移低位
  I_T_OFFSETHI = 312,      -- 文件偏移高位
  I_T_ENCYRPTID = 316,     -- 加密ID
  I_T_CHECKSUM = 380,      -- 校验和
  I_T_RES = 384            -- 保留字段
}

--[[
打开镜像文件
初始化解码器，读取并解析镜像头部和项目表
@param szImageFile 镜像文件路径
@return 成功返回镜像句柄，失败返回nil
--]]
Img_Open = function(szImageFile)
  -- function num : 0_2
  -- 分配镜像头部缓冲区
  local ImageHead = MallocBuffer(IMAGE_HEAD_SIZE)
  
  -- 解码器种子值，用于生成不同的解码密钥
  local seed = {"69", "6d", "67"}  -- 对应ASCII "img"
  local key_buff = "00000000000000000000000000000000"
  local key_len = MAX_KEY_SIZE
  local pTmpBuffer = MallocBuffer(key_len)
  
  -- 初始化三个解码器(头部、表格、数据)
  for i = 0, IF_CNT - 1 do
    Memset(pTmpBuffer, i, key_len)
    SetMemValue(pTmpBuffer, key_len - 1, tostring(seed[i + 1]))
    key_buff = pTmpBuffer
    -- DECOMPILER ERROR at PC38: Confused about usage of register: R10 in 'UnsetPending'

    -- 初始化解码器
    g_DecIF[i + 1] = Dec_Initial(key_buff, key_len)
    if g_DecIF[i + 1] == nil then
      free(pImage)
      return nil
    end
  end
  FreeBuffer(pTmpBuffer)
  
  -- 获取全局镜像句柄并打开文件
  local pImage = g_hImageHandle
  pImage.fp = LFopen(szImageFile, 0)
  DebugPrint(szImageFile)
  if pImage.fp == nil then
    return nil
  end
  
  -- 读取镜像头部
  local readRet = LFread(pImage.fp, ImageHead, IMAGE_HEAD_SIZE)
  DebugPrint("Read head return " .. readRet .. "\n")
  pImage.ImageHead = MallocBuffer(IMAGE_HEAD_SIZE)
  
  -- 检查魔数标识，判断是否为加密镜像
  local lMagicBuff = MallocBuffer(9)
  CharsToBuffer(lMagicBuff, "IMAGEWTY")  -- 非加密镜像的魔数
  TraceBuffer(ImageHead, 32)
  
  -- 比较魔数，确定加密状态
  if Memcmp(ImageHead, lMagicBuff, 8) == 0 then
    g_bEncypt = 0  -- 非加密镜像
  else
    g_bEncypt = 1  -- 加密镜像
  end
  DebugPrint("g_bEncypt = " .. g_bEncypt .. "\n")
  
  -- 根据加密状态处理镜像头部
  if g_bEncypt == 1 then
    -- 加密镜像：按16字节块解码头部数据
    for i = 0, IMAGE_HEAD_SIZE - ENCODE_LEN, ENCODE_LEN do
      DebugTrace("pIn pOut:")
      local pIn = GetBuffer(ImageHead, i)
      local pOut = GetBuffer(pImage.ImageHead, i)
      Dec_Decode((pImage.rc_if_decode)[HEAD_ID], pIn, pOut)
    end
  else
    -- 非加密镜像：直接拷贝头部数据
    Memcpy(pImage.ImageHead, ImageHead, IMAGE_HEAD_SIZE)
  end
  
  FreeBuffer(ImageHead)
  
  -- 验证解码后的魔数
  CharsToBuffer(lMagicBuff, "IMAGEWTY")
  local ncmpRet = Memcmp(pImage.ImageHead, lMagicBuff, 8)
  if ncmpRet ~= 0 then
    -- 魔数验证失败，文件格式错误
    LFclose(pImage.fp)
    FreeBuffer(lMagicBuff)
    return nil
  end
  
  -- 获取镜像版本和项目数量
  Img_Version = GetInt32FrmMem(pImage.ImageHead, Img_Head32.I_H_VERSION)
  local nIitemCnt = GetInt32FrmMem(pImage.ImageHead, Img_Head32.I_H_ITEMCNT)
  local ItemTableSize = nIitemCnt * IMAGE_ITEM_SIZE
  
  -- 分配项目表缓冲区
  pImage.ItemTable = MallocBuffer(ItemTableSize)
  if pImage.ItemTable == nil then
    LFclose(pImage.fp)
    return nil
  end
  
  -- 分配临时读取缓冲区
  ItemTableBuf = MallocBuffer(ItemTableSize)
  if ItemTableBuf == nil then
    FLclose(pImage.fp)
    return nil
  end
  
  -- 根据镜像版本定位项目表偏移
  if Img_Version == 256 then
    LFseek(pImage.fp, GetInt32FrmMem(pImage.ImageHead, Img_Head32.I_H_ITEMOFFSET), 0, 0)
  else
    if Img_Version >= 768 then
      LFseek(pImage.fp, GetInt32FrmMem(pImage.ImageHead, Img_Head64.I_H_ITEMOFFSET), 0, 0)
    else
      LFseek(pImage.fp, GetInt32FrmMem(pImage.ImageHead, Img_Head32.I_H_ITEMOFFSET), 0, 0)
    end
  end
  
  -- 读取项目表数据
  LFread(pImage.fp, ItemTableBuf, ItemTableSize)
  local pItemTableDecode = pImage.ItemTable
  DebugTrace("ItemTableSize = " .. ItemTableSize)
  
  -- 根据加密状态处理项目表数据
  if g_bEncypt == 1 then
    -- 加密镜像：按16字节块解码项目表
    for i = 0, ItemTableSize - ENCODE_LEN, ENCODE_LEN do
      local pin = GetBuffer(ItemTableBuf, i)
      local pout = GetBuffer(pItemTableDecode, i)
      Dec_Decode((pImage.rc_if_decode)[TABLE_ID], pin, pout)
    end
  else
    -- 非加密镜像：直接拷贝项目表
    Memcpy(pItemTableDecode, ItemTableBuf, ItemTableSize)
  end
  
  FreeBuffer(ItemTableBuf)
  FreeBuffer(lMagicBuff)
  return pImage
end

--[[
最小值函数
返回两个数值中的较小者
@param nValue1 第一个数值
@param nValue2 第二个数值  
@return 较小的数值
--]]
min = function(nValue1, nValue2)
  -- function num : 0_3
  if nValue1 < nValue2 then
    return nValue1
  else
    return nValue2
  end
end

--[[
打开镜像项目(32位版本)
在32位镜像格式中根据主类型和子类型查找并打开指定项目
@param hImage 镜像句柄
@param szMainType 主类型字符串(8字节)
@param szSubType 子类型字符串(16字节)
@return 成功返回项目句柄，失败返回nil
--]]
Img_OpenItem32 = function(hImage, szMainType, szSubType)
  -- function num : 0_4
  local pImage = hImage
  local pItem, dwLen = nil, nil
  
  -- 参数有效性检查
  if pImage == nil or szMainType == nil or szSubType == nil then
    DebugPrint("Img_OpenItem Error!")
    return nil
  end
  
  -- 初始化项目句柄
  pItem = {nIndex = 0, loPos = 0, hiPos = 0}
  pItem.index = INVALID_INDEX
  pItem.loPos = 0
  pItem.hiPos = 0
  DebugPrint("Img_OpenItem[" .. szMainType .. "][" .. szSubType .. "]\n")
  
  -- 遍历项目表查找匹配的项目
  local itemCnt = GetInt32FrmMem(pImage.ImageHead, Img_Head32.I_H_ITEMCNT)
  for i = 0, itemCnt - 1 do
    local tmpTab = GetBuffer(pImage.ItemTable, i * IMAGE_ITEM_SIZE)
    local szTmpMainType = BufferToChars(tmpTab, Img_Item32.I_T_MAINTYPE, 8)
    local szTmpSubType = BufferToChars(tmpTab, Img_Item32.I_T_SUBTYPE, 16)
    
    -- 检查主类型是否匹配
    if szMainType == szTmpMainType then
      -- Phoenix工具项目特殊处理(只需要主类型匹配)
      if ITEM_PHOENIX_TOOLS == szMainType then
        pItem.index = i
        return pItem
      else
        -- 普通项目需要主类型和子类型都匹配
        if szSubType == szTmpSubType then
          pItem.index = i
          return pItem
        end
      end
    end
  end
  
  -- 未找到匹配的项目
  DebugPrint("Img_OpenItem: cannot find item " .. szMainType .. szSubType)
  return nil
end

--[[
打开镜像项目(64位版本)
在64位镜像格式中根据主类型和子类型查找并打开指定项目
与32位版本的区别在于类型字符串会转换为大写进行比较
@param hImage 镜像句柄
@param szMainType 主类型字符串
@param szSubType 子类型字符串
@return 成功返回项目句柄，失败返回nil
--]]
Img_OpenItem64 = function(hImage, szMainType, szSubType)
  -- function num : 0_5
  local pImage = hImage
  local pItem = nil
  
  -- 将类型字符串转换为大写(64位版本特性)
  szMainType = (string.upper)(szMainType)
  szSubType = (string.upper)(szSubType)
  DebugPrint("Img_OpenItem now! \n" .. szMainType .. szSubType)
  local dwLen = nil
  
  -- 参数有效性检查
  if pImage == nil or szMainType == nil or szSubType == nil then
    DebugPrint("Img_OpenItem Error!")
    return nil
  end
  
  -- 初始化项目句柄
  pItem = {nIndex = 0, loPos = 0, hiPos = 0}
  pItem.index = INVALID_INDEX
  pItem.loPos = 0
  pItem.hiPos = 0
  
  -- 遍历项目表查找匹配的项目(使用64位头部结构)
  local itemCnt = GetInt32FrmMem(pImage.ImageHead, Img_Head64.I_H_ITEMCNT)
  for i = 0, itemCnt - 1 do
    local tmpTab = GetBuffer(pImage.ItemTable, i * IMAGE_ITEM_SIZE)
    local szTmpMainType = BufferToChars(tmpTab, Img_Item64.I_T_MAINTYPE, 8)
    local szTmpSubType = BufferToChars(tmpTab, Img_Item64.I_T_SUBTYPE, 16)
    
    -- 将项目表中的类型字符串也转换为大写进行比较
    szTmpMainType = (string.upper)(szTmpMainType)
    szTmpSubType = (string.upper)(szTmpSubType)
    
    -- 检查主类型是否匹配
    if szMainType == szTmpMainType then
      -- Phoenix工具项目特殊处理(只需要主类型匹配)
      if ITEM_PHOENIX_TOOLS == szMainType then
        pItem.index = i
        return pItem
      else
        -- 普通项目需要主类型和子类型都匹配
        if szSubType == szTmpSubType then
          pItem.index = i
          return pItem
        end
      end
    end
  end
  
  -- 未找到匹配的项目
  DebugPrint("Img_OpenItem: cannot find item " .. szMainType .. szSubType)
  return nil
end

--[[
打开镜像项目(自适应版本)
根据镜像版本自动选择32位或64位的项目打开方法
@param hImage 镜像句柄
@param szMainType 主类型字符串
@param szSubType 子类型字符串
@return 成功返回项目句柄，失败返回nil
--]]
Img_OpenItem = function(hImage, szMainType, szSubType)
  -- function num : 0_6
  local pImage = hImage
  local pItem = nil
  
  -- 根据镜像版本选择对应的打开方法
  if Img_Version >= 768 then
    -- 64位版本或更高版本
    pItem = Img_OpenItem64(pImage, szMainType, szSubType)
  else
    -- 32位版本
    pItem = Img_OpenItem32(pImage, szMainType, szSubType)
  end
  return pItem
end

--[[
获取镜像项目大小
根据镜像版本从项目表中读取指定项目的文件大小
@param hImage 镜像句柄
@param hItem 项目句柄
@return 成功返回文件大小(低位, 高位)，失败返回0
--]]
Img_GetItemSize = function(hImage, hItem)
  -- function num : 0_7
  local pImage = hImage
  local pItem = hItem
  
  -- 检查项目句柄有效性
  if pItem == nil then
    return 0
  end
  
  local nIndex = pItem.index
  local pTmpTab = GetBuffer(pImage.ItemTable, nIndex * IMAGE_ITEM_SIZE)
  local loPos = 0
  local hiPos = 0
  
  -- 根据镜像版本读取文件大小
  if Img_Version == 256 then
    -- 256版本只有低位文件大小
    loPos = GetInt32FrmMem(pTmpTab, Img_Item32.I_T_FILELENLO)
  else
    if Img_Version >= 768 then
      -- 768版本及以上支持64位文件大小
      loPos = GetInt32FrmMem(pTmpTab, Img_Item64.I_T_FILELENLO)
      hiPos = GetInt32FrmMem(pTmpTab, Img_Item64.I_T_FILELENHI)
    else
      -- 其他版本使用32位文件大小
      loPos = GetInt32FrmMem(pTmpTab, Img_Item32.I_T_FILELENLO)
    end
  end
  
  return loPos, hiPos
end

--[[
读取镜像项目数据(内部实现)
这是一个内部函数，处理复杂的加密解码和数据读取逻辑
支持按块读取加密数据并进行解码
@param hImage 镜像句柄
@param hItem 项目句柄  
@param buffer 数据缓冲区
@param Length 要读取的数据长度
@return 实际读取的数据长度
--]]
__Img_ReadItemData = function(hImage, hItem, buffer, Length)
  -- function num : 0_8
  local readlen = 0
  local pImage = hImage
  local pItem = hItem
  local buffer_encode = MallocBuffer(ENCODE_LEN)
  local pos = 0
  local posHi = 0
  local dwLen = nil
  local pTmpTable = GetBuffer(pImage.ItemTabale, pItem.index * IMAGE_ITEM_SIZE)
  if pImage == nil or pItem == nil or buffer == nil or Length == 0 then
    return 0
  end
  local fileLen = 0
  local dataLen = 0
  local nOffset = 0
  local hifileLen = 0
  local hidataLen = 0
  local hinOffset = 0
  if Img_Version == 256 then
    fileLen = GetInt32FrmMem(pTmpTable, Img_Item32.I_T_FILELENLO)
    dataLen = GetInt32FrmMem(pTmpTable, Img_Item32.I_T_DATALENLO)
    nOffset = GetInt32FrmMem(pTmpTable, Img_Item32.I_T_OFFSETLO)
  else
    if Img_Version >= 768 then
      fileLen = GetInt32FrmMem(pTmpTable, Img_Item64.I_T_FILELENLO)
      dataLen = GetInt32FrmMem(pTmpTable, Img_Item64.I_T_DATALENLO)
      nOffset = GetInt32FrmMem(pTmpTable, Img_Item64.I_T_OFFSETLO)
      hifileLen = GetInt32FrmMem(pTmpTable, Img_Item64.I_T_FILELENHI)
      hidataLen = GetInt32FrmMem(pTmpTable, Img_Item64.I_T_DATALENHI)
      hinOffset = GetInt32FrmMem(pTmpTable, Img_Item64.I_T_OFFSETHI)
    end
  end
  local nCmpRet = CompareInt64(pItem.loPos, pItem.hiPos, loItemLen, HiItemLen)
  if nCmpRet >= 1 then
    return 0
  end
  local nLen = Length
  nLen = min(Length, dataLen - pItem.loPos)
  if pItem.loPos % ENCODE_LEN == 0 then
    pos = Int64Add(nOffset, nOffsetHi, pItem.loPos, pItem.hiPos)
    LFseek(pImage.fp, pos, posHi)
    while readlen < nLen do
      Memset(buffer_encode, 0, ENCODE_LEN)
      LFread(pImage.fp, buffer_encode, ENCODE_LEN)
      pin = buffer_encode
      pout = buffer
      pout = GetBuffer(pout, readlen)
      if g_bEncypt == 1 then
        Dec_Decode((pImage.rc_if_decode)[DATA_ID], pin, pout)
      else
        Memcpy(pout, pin, ENCODE_LEN)
      end
      readlen = readlen + min(nLen - readlen, ENCODE_LEN)
    end
    pItem.loPos = Int64Add(pItem.loPos, pItem.hiPos, readlen, 0)
    return readlen
  else
    pl = pItem.loPos
    ph = pItem.hiPos
    pl = Int64Dec(pItem.loPos, pItem.hiPos, pItem.loPos % ENCODE_LEN, 0)
    -- DECOMPILER ERROR at PC198: Overwrote pending register: R9 in 'AssignReg'

    pos = Int64Add(nOffset, hinOffset, pl, ph)
    LFseek(pImage.fp, pos, posHi)
    if nLen > 0 and nLen < ENCODE_LEN then
      local read = ENCODE_LEN - pItem.pos % ENCODE_LEN
      if Length <= read then
        read = ENCODE_LEN - pItem.pos % ENCODE_LEN
        Memset(buffer_encode, 0, ENCODE_LEN)
        LFread(pImage.fp, buffer_encode, ENCODE_LEN)
        pin = buffer_encode
        pout = buffer
        pout = GetBuffer(pout, readlen)
        if g_bEncypt == 1 then
          Dec_Decode((pImage.rc_if_decode)[DATA_ID], pin, pout)
        else
          Memcpy(pout, pin, ENCODE_LEN)
        end
        readlen = nLen
        pItem.pos = pItem.pos + readlen
        return readlen
      else
        local read = ENCODE_LEN - pItem.pos % ENCODE_LEN
        Memset(buffer_encode, 0, ENCODE_LEN)
        LFread(pImage.fp, buffer_encode, ENCODE_LEN)
        pin = buffer_encode
        pout = buffer
        pout = GetBuffer(pout, readlen)
        if g_bEncypt == 1 then
          Dec_Decode((pImage.rc_if_decode)[DATA_ID], pin, pout)
        else
          Memcpy(pout, pin, ENCODE_LEN)
        end
        readlen = readlen + read
        local Left_Length = nLen - read
        Memset(buffer_encode, 0, ENCODE_LEN)
        LFread(pImage.fp, buffer_encode, ENCODE_LEN)
        pin = buffer_encode
        pout = buffer
        pout = GetBuffer(pout, readlen)
        if g_bEncypt == 1 then
          Dec_Decode((pImage.rc_if_decode)[DATA_ID], pin, pout)
        else
          Memcpy(pout, pin, ENCODE_LEN)
        end
        readlen = readlen + Left_Length
        pItem.loPos = Int64Add(pItem.loPos, pItem.hiPos, readlen, 0)
        return readlen
      end
    else
      do
        if ENCODE_LEN <= nLen then
          local read = ENCODE_LEN - pItem.loPos % ENCODE_LEN
          Memset(buffer_encode, 0, ENCODE_LEN)
          LFread(pImage.fp, buffer_encode, ENCODE_LEN)
          pin = buffer_encode
          pout = buffer
          pout = GetBuffer(pout + (readlen))
          if g_bEncypt == 1 then
            Dec_Decode((pImage.rc_if_decode)[DATA_ID], pin, pout)
          else
            Memcpy(pout, pin, ENCODE_LEN)
          end
          readlen = readlen + read
          local Left_Length = Length - read
          local Left_readlen = 0
          while Left_readlen < Left_Length do
            Memset(buffer_encode, 0, ENCODE_LEN)
            LFread(pImage.fp, buffer_encode, ENCODE_LEN)
            pin = buffer_encode
            pout = buffer
            pout = GetBuffer(pout, readlen)
            if g_bEncypt == 1 then
              Dec_Decode((pImage.rc_if_decode)[DATA_ID], pin, pout)
            else
              Memcpy(pout, pin, ENCODE_LEN)
            end
            Left_readlen = Left_readlen + min(Left_Length - Left_readlen, ENCODE_LEN)
          end
          readlen = readlen + (Left_readlen)
        end
        do
          pItem.loPos = Int64Add(pItem.loPos, pItem.hiPos, readlen, 0)
          do return readlen end
        end
      end
    end
  end
end

--[[
读取镜像项目数据(主函数)
高效读取镜像中指定项目的数据，支持加密解码和大块读取
相比__Img_ReadItemData，这个函数使用更大的缓冲区提高读取效率
@param hImage 镜像句柄
@param hItem 项目句柄
@param buffer 数据缓冲区
@param length 要读取的数据长度
@return 实际读取的数据长度
--]]
Img_ReadItemData = function(hImage, hItem, buffer, length)
  -- function num : 0_9
  local readlen = 0
  pImage = hImage
  pItem = hItem
  
  -- 分配32K缓冲区用于加密数据读取
  buffer_encode = MallocBuffer(SIZE_32K)
  local this_read = nil
  local pos = 0
  local posHi = 0
  local dwLen = nil
  
  -- 获取项目表中的当前项目信息
  local pTmpItemTab = GetBuffer(pImage.ItemTable, pItem.index * IMAGE_ITEM_SIZE)
  local loItemLen = 0    -- 项目数据长度低位
  local HiItemLen = 0    -- 项目数据长度高位
  local loDataLen = 0    -- 文件长度低位
  local HiDataLen = 0    -- 文件长度高位
  
  -- 根据镜像版本读取长度信息
  if Img_Version == 256 then
    loItemLen = GetInt32FrmMem(pTmpItemTab, Img_Item32.I_T_DATALENLO)
    loDataLen = GetInt32FrmMem(pTmpItemTab, Img_Item32.I_T_FILELENLO)
  else
    if Img_Version == 768 then
      loItemLen = GetInt32FrmMem(pTmpItemTab, Img_Item64.I_T_DATALENLO)
      loDataLen = GetInt32FrmMem(pTmpItemTab, Img_Item64.I_T_FILELENLO)
      HiItemLen = GetInt32FrmMem(pTmpItemTab, Img_Item64.I_T_DATALENHI)
      HiDataLen = GetInt32FrmMem(pTmpItemTab, Img_Item64.I_T_FILELENHI)
    end
  end
  
  -- 检查读取位置是否超出项目数据范围
  local nCmpRet = CompareInt64(pItem.loPos, pItem.hiPos, loItemLen, HiItemLen)
  if nCmpRet >= 1 then
    DebugTrace("Img_ReadItemData Error ")
    return nil
  end
  
  -- 计算剩余可读取的数据长度
  local nLeftLenLo = 0
  local nLeftLenHi = 0
  nLeftLenLo = Int64Dec(loDataLen, HiDataLen, pItem.loPos, pItem.hiPos)
  local nTmpLen = min(length, nLeftLenLo)
  if nLeftLenHi ~= 0 then
    nTmpLen = length
  end
  length = nTmpLen
  
  -- 获取项目在文件中的偏移位置
  local nOffsetLo = 0
  local nOffsetHi = 0
  if Img_Version == 256 then
    nOffsetLo = GetInt32FrmMem(pTmpItemTab, Img_Item32.I_T_OFFSETLO)
  else
    if Img_Version == 768 then
      nOffsetLo = GetInt32FrmMem(pTmpItemTab, Img_Item64.I_T_OFFSETLO)
      nOffsetHi = GetInt32FrmMem(pTmpItemTab, Img_Item64.I_T_OFFSETHI)
    end
  end
  
  -- 检查当前读取位置是否按加密块对齐
  if pItem.loPos % ENCODE_LEN == 0 then
    -- 位置对齐，可以直接读取
    pos = Int64Add(nOffsetLo, nOffsetHi, pItem.loPos, pItem.hiPos)
    LFseek(pImage.fp, pos, posHi)
    readlen = 0
    
    -- 循环读取数据
    while readlen < length do
      -- 计算本次读取大小(不超过32K)
      this_read = min(SIZE_32K, length - readlen)
      
      -- 计算需要读取的加密块数量(向上取整)
      local n = (this_read + ENCODE_LEN - 1) / ENCODE_LEN
      n = (math.floor)(n)
      
      -- 清零缓冲区并读取加密数据
      Memset(buffer_encode, 0, n * ENCODE_LEN)
      LFread(pImage.fp, buffer_encode, n * ENCODE_LEN)
      
      -- 设置输入输出缓冲区指针
      pin = buffer_encode
      pout = buffer
      pout = GetBuffer(pout, readlen)
      
      -- 按块解码数据
      for i = 0, n - 1 do
        if g_bEncypt == 1 then
          -- 加密镜像：解码数据块
          Dec_Decode((pImage.rc_if_decode)[DATA_ID], pin, pout)
        else
          -- 非加密镜像：直接拷贝数据块
          Memcpy(pout, pin, ENCODE_LEN)
        end
        -- 移动输入输出指针到下一个块
        pin = GetBuffer(pin, ENCODE_LEN)
        pout = GetBuffer(pout, ENCODE_LEN)
      end
      readlen = readlen + this_read
    end
    
    -- 更新项目读取位置
    -- DECOMPILER ERROR at PC233: Confused about usage of register: R21 in 'UnsetPending'
    -- DECOMPILER ERROR at PC234: Confused about usage of register: R20 in 'UnsetPending'
    pItem.loPos = Int64Add(pItem.loPos, pItem.hiPos, readlen, 0)
    FreeBuffer(buffer_encode)
    return readlen
  else
    -- 位置未对齐，使用复杂的读取方法
    FreeBuffer(buffer_encode)
    return __Img_ReadItemData(hImage, hItem, buffer, length)
  end
end

--[[
关闭镜像项目
释放项目句柄占用的内存资源
@param hImage 镜像句柄(未使用)
@param hItem 项目句柄
@return 成功返回0，失败返回nil
--]]
Img_CloseItem = function(hImage, hItem)
  -- function num : 0_10
  local pItem = hItem
  if pItem == nil then
    return nil
  end
  
  -- 释放项目句柄内存
  FreeBuffer(pItem)
  pItem = nil
  return 0
end

--[[
关闭镜像文件
释放镜像句柄和相关资源，关闭文件
@param hImage 镜像句柄
@return 无返回值
--]]
Img_Close = function(hImage)
  -- function num : 0_11
  pImage = hImage
  DebugTrace("Closing image now! \n")
  
  if pImage == nil then
    return nil
  end
  
  -- 关闭文件指针
  if pImage.fp ~= nil then
    LFclose(pImage.fp)
    -- DECOMPILER ERROR at PC18: Confused about usage of register: R1 in 'UnsetPending'
    pImage.fp = nil
  end
  
  -- 释放镜像头部缓冲区
  if pImage.ImageHead ~= nil then
    FreeBuffer(pImage.ImageHead)
  end
  
  -- 释放项目表缓冲区
  if pImage.ItemTable ~= nil then
    FreeBuffer(pImage.ItemTable)
    -- DECOMPILER ERROR at PC36: Confused about usage of register: R1 in 'UnsetPending'
    pImage.ItemTable = nil
  end
  
  pImage = nil
  DebugTrace("Clos image OK! \n")
  return 
end

--[[
下载镜像项目到本地文件
从镜像文件中提取指定的项目数据并保存为本地文件
这是一个高级封装函数，完成了完整的提取流程
@param szImageFile 镜像文件路径
@param szMainName 项目主类型
@param szSubName 项目子类型
@param szLocFileName 本地输出文件路径
@return 成功时无返回值，失败返回nil
--]]
Img_DownItemToLocal = function(szImageFile, szMainName, szSubName, szLocFileName)
  -- function num : 0_12
  
  -- 打开镜像文件
  local hImage = Img_Open(szImageFile)
  local nSize, nSizeHi = 0, nil
  mprint(szImageFile)
  
  if hImage == nil then
    mprint("Error")
    return nil
  end
  
  -- 打开指定项目
  local hItem = Img_OpenItem(hImage, szMainName, szSubName)
  if hItem ~= nil then
    -- 获取项目大小
    nSize = Img_GetItemSize(hImage, hItem)
    mprint("The Item Size is (" .. nSize .. ", " .. nSizeHi .. ")\n")
    
    -- 分配缓冲区并读取项目数据
    local lpBuffer = MallocBuffer(nSize)
    local nRet = Img_ReadItemData(hImage, hItem, lpBuffer, nSize)
    
    -- 关闭项目和镜像
    Img_CloseItem(hImage, hItem)
    Img_Close(hImage)
    
    -- 创建输出文件
    f = fopen(szLocFileName, "wb+")
    if f == nil then
      mprint("Open File " .. szImageFile .. " Error")
      return nil
    else
      mprint("Open File " .. szImageFile .. " OK")
    end
    
    -- 按256字节块写入文件
    local ptSize = nSize - 256
    for nPos = 0, nSize, 256 do
      local ptmp = GetBuffer(lpBuffer, nPos)
      if ptSize < nPos then
        -- 写入剩余的不足256字节的数据
        fwrite(f, ptmp, nSize - nPos)
      else
        -- 写入完整的256字节块
        fwrite(f, ptmp, 256)
      end
    end
    
    -- 关闭文件并释放缓冲区
    fclose(f)
    FreeBuffer(lpBuffer)
  else
    mprint("Error open the file" .. szImageFile)
  end
end


