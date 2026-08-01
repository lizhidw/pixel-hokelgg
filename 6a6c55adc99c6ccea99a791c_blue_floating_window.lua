--[[
    ============================================
    蓝色高端悬浮窗 v6.2
    整合「像火.lua」功能 + 网络/本地音乐 + 系统铃声
    偏移全部通过 dump.cs 验证（像素火影 v1.38）
    新增：启动选择背景模式（自选图片/默认）
    新增：悬浮球支持自选图片 + 加大到120dp
    新增：6套风格切换（深蓝/暗紫/暗绿/暗红/暗金/纯黑）
    新增：窗口加大（88%屏宽×75%屏高）
    新增：移速/伤害/暴击倍率/霸体/免伤/满血/满能量/须佐持续
    新增：自定义改值（实例地址+偏移量修改）
    新增：复制角色地址（Character实例地址）
    新增：开发者模式（密码保护，自定义改值+角色地址需解锁）
    修复：所有功能关闭时恢复原始值
    修复：改视角改用固定偏移链定位
    ============================================
]]

local windowManager = app.context:getSystemService('window')
local threadManager = luajava.threadManager
local runOnMainThread = threadManager.runOnMainThread

-- ========================================
-- 主题配色（6套风格可切换）
-- ========================================
local Themes = {
    { -- 1. 深蓝
        name = '深蓝',
        primary      = 0xFF1A73E8,
        primaryDark  = 0xFF0D47A1,
        primaryLight = 0xFF64B5F6,
        bgMain       = 0xFF0D1B2A,
        bgCard       = 0xFF1B2838,
        bgCardOn     = 0xFF1B3A5A,
        bgNav        = 0xFF162436,
        bgLog        = 0xFF0A1628,
        textPri      = 0xFFE3F2FD,
        textSec      = 0xFF90CAF9,
        textHint     = 0xFF5C8DB8,
    },
    { -- 2. 暗紫
        name = '暗紫',
        primary      = 0xFF8E24AA,
        primaryDark  = 0xFF4A148C,
        primaryLight = 0xFFCE93D8,
        bgMain       = 0xFF1A0A2E,
        bgCard       = 0xFF2D1B4E,
        bgCardOn     = 0xFF3D2A5E,
        bgNav        = 0xFF1F1035,
        bgLog        = 0xFF120620,
        textPri      = 0xFFF3E5F5,
        textSec      = 0xFFCE93D8,
        textHint     = 0xFF7B5BA6,
    },
    { -- 3. 暗绿
        name = '暗绿',
        primary      = 0xFF00897B,
        primaryDark  = 0xFF004D40,
        primaryLight = 0xFF80CBC4,
        bgMain       = 0xFF0A1F1C,
        bgCard       = 0xFF1B332E,
        bgCardOn     = 0xFF1B4A42,
        bgNav        = 0xFF0F2622,
        bgLog        = 0xFF061410,
        textPri      = 0xFFE0F2F1,
        textSec      = 0xFF80CBC4,
        textHint     = 0xFF4A8A82,
    },
    { -- 4. 暗红
        name = '暗红',
        primary      = 0xFFD32F2F,
        primaryDark  = 0xFF8B0000,
        primaryLight = 0xFFEF9A9A,
        bgMain       = 0xFF1F0A0A,
        bgCard       = 0xFF331B1B,
        bgCardOn     = 0xFF4A2020,
        bgNav        = 0xFF260F0F,
        bgLog        = 0xFF140606,
        textPri      = 0xFFFFEBEE,
        textSec      = 0xFFEF9A9A,
        textHint     = 0xFF8A4A4A,
    },
    { -- 5. 暗金
        name = '暗金',
        primary      = 0xFFFFA000,
        primaryDark  = 0xFFFF6F00,
        primaryLight = 0xFFFFD54F,
        bgMain       = 0xFF1A1400,
        bgCard       = 0xFF2D2410,
        bgCardOn     = 0xFF3D3215,
        bgNav        = 0xFF1F1808,
        bgLog        = 0xFF120E00,
        textPri      = 0xFFFFF8E1,
        textSec      = 0xFFFFD54F,
        textHint     = 0xFF8A7530,
    },
    { -- 6. 纯黑
        name = '纯黑',
        primary      = 0xFF424242,
        primaryDark  = 0xFF212121,
        primaryLight = 0xFF9E9E9E,
        bgMain       = 0xFF000000,
        bgCard       = 0xFF1A1A1A,
        bgCardOn     = 0xFF2A2A2A,
        bgNav        = 0xFF0A0A0A,
        bgLog        = 0xFF000000,
        textPri      = 0xFFE0E0E0,
        textSec      = 0xFF9E9E9E,
        textHint     = 0xFF616161,
    },
}

-- 当前主题表（运行时动态更新字段，所有闭包共享同一引用）
local T = {}

-- 语义色（所有主题共用）
local semanticColors = {
    success   = 0xFF4CAF50,
    warning   = 0xFFFFB300,
    error     = 0xFFE53935,
    toggleOff = 0xFF37474F,
}

-- 应用指定索引的主题（更新 T 的字段）
local function applyTheme(index)
    local theme = Themes[index]
    if not theme then return end
    for k in pairs(T) do T[k] = nil end
    for k, v in pairs(theme) do T[k] = v end
    for k, v in pairs(semanticColors) do T[k] = v end
end

-- 初始化为深蓝主题
applyTheme(1)

-- ========================================
-- 共享状态 (所有闭包通过此表访问)
-- ========================================
local S = {
    mainView = nil,
    mainParams = nil,
    ballView = nil,
    ballParams = nil,
    unpark = nil,
    exitFlag = false,
    logView = nil,
    contentContainer = nil,
    mediaPlayer = nil,
    musicPath = nil,
    customPatches = {},
    cameraAddr = nil,  -- 缓存搜索到的镜头地址
    devUnlocked = false,  -- 开发者模式解锁状态
    currentTheme = 1,     -- 当前风格索引
    bgDrawable = nil,     -- 自定义背景图片 Drawable
    bgImagePath = nil,    -- 自定义背景图片路径
    ballDrawable = nil,   -- 悬浮球图片 Drawable
    ballImagePath = nil,  -- 悬浮球图片路径
}

-- 拖动状态
local mainDrag = { sx=0, sy=0, srx=0, sry=0, moved=false }
local ballDrag = { sx=0, sy=0, srx=0, sry=0, moved=false }

-- ========================================
-- 工具函数
-- ========================================
local function newParams(w, h)
    local p = WindowManager.LayoutParams()
    p.type = (Build.VERSION.SDK_INT >= 26 and 2038 or 2002)
    p.format = PixelFormat.RGBA_8888
    p.flags = p.FLAG_NOT_FOCUSABLE
    p.width = w or p.WRAP_CONTENT
    p.height = h or p.WRAP_CONTENT
    p.gravity = Gravity.CENTER
    return p
end

local function gradient(colors, radius, orientation)
    local d = GradientDrawable()
    d:setOrientation(orientation or GradientDrawable.Orientation.LEFT_RIGHT)
    d:setColors(colors)
    if radius then d:setCornerRadius(radius) end
    return d
end

local function stateList(normalColor, pressedColor, radius)
    local sl = StateListDrawable()
    local function mkGrad(color)
        local g = GradientDrawable()
        g:setColor(color)
        if radius then g:setCornerRadius(radius) end
        return g
    end
    sl:addState({-android.R.attr.state_pressed}, mkGrad(normalColor))
    sl:addState({android.R.attr.state_pressed}, mkGrad(pressedColor))
    return sl
end

local function getView(id)
    local env = _ENV or _G
    local v = env[id]
    if v and type(v) == 'table' then
        return v.view or v
    end
    return v
end

-- ========================================
-- 背景图片加载
-- ========================================
local function loadBgDrawable(path)
    if not path or path == '' then return nil end
    local ok, drawable = pcall(function()
        local BitmapFactory = luajava.bindClass('android.graphics.BitmapFactory')
        local BitmapDrawable = luajava.bindClass('android.graphics.drawable.BitmapDrawable')
        local bitmap = BitmapFactory:decodeFile(path)
        if not bitmap then return nil end
        return BitmapDrawable(app.context:getResources(), bitmap)
    end)
    if ok and drawable then
        return drawable
    end
    return nil
end

-- 获取主背景 Drawable（图片优先，否则渐变）
local function getMainBgDrawable()
    if S.bgDrawable then
        return S.bgDrawable
    end
    return gradient({T.bgMain, T.bgNav}, 16, GradientDrawable.Orientation.TL_BR)
end

-- 获取悬浮球背景 Drawable（图片优先，否则渐变）
local function getBallBgDrawable()
    if S.ballDrawable then
        return S.ballDrawable
    end
    return gradient({T.primary, T.primaryDark}, 60)
end

-- ========================================
-- 日志系统
-- ========================================
local logs = {}

local function addLog(tag, msg, level)
    level = level or 'INFO'
    local time = os.date('%H:%M:%S')
    table.insert(logs, 1, string.format('[%s] [%s] %s', time, tag, msg))
    if #logs > 50 then table.remove(logs) end
    if S.logView then
        local text = ''
        for _, l in ipairs(logs) do text = text .. l .. '\n' end
        runOnMainThread(function()
            pcall(function() S.logView:setText(text) end)
        end)
    end
end

-- ========================================
-- 内存指针功能 (来自像火.lua)
-- ========================================
local function S_Pointer(t_So, t_Offset, _bit)
    local function getRanges()
        local ranges = {}
        local t = gg.getRangesList('^/data/*.so*$')
        for i, v in pairs(t) do
            if v.type:sub(2, 2) == 'w' then
                table.insert(ranges, v)
            end
        end
        return ranges
    end
    local function Get_Address(N_So, Offset, ti_bit)
        local ti = gg.getTargetInfo()
        local S_list = getRanges()
        local t = {}
        local _t
        local _S = nil
        if ti_bit then _t = 32 else _t = 4 end
        for i in pairs(S_list) do
            local _N = S_list[i].internalName:gsub('^.*/', '')
            if N_So[1] == _N and N_So[2] == S_list[i].state then
                _S = S_list[i]
                break
            end
        end
        if _S then
            t[#t + 1] = {}
            t[#t].address = _S.start + Offset[1]
            t[#t].flags = _t
            if #Offset ~= 1 then
                for i = 2, #Offset do
                    local S2 = gg.getValues(t)
                    t = {}
                    for _ in pairs(S2) do
                        if not ti.x64 then
                            S2[_].value = S2[_].value & 0xFFFFFFFF
                        end
                        t[#t + 1] = {}
                        t[#t].address = S2[_].value + Offset[i]
                        t[#t].flags = _t
                    end
                end
            end
            _S = t[#t].address
        end
        return _S
    end
    return Get_Address(t_So, t_Offset, _bit)
end

-- ========================================
-- 搜索战斗通用事件.原始镜头大小地址
-- dump.cs: 战斗通用事件 原始镜头大小(float,0xF8) 视角缩放倍数(float,0x100) 视角缩放计时(float,0x108)
-- 通过搜索特征值组合定位实例
-- ========================================
local function findCameraAddr()
    -- 使用缓存
    if S.cameraAddr and S.cameraAddr ~= 0 then
        -- 验证缓存地址是否仍然有效
        local ok, val = pcall(function()
            local r = gg.getValues({{address = S.cameraAddr, flags = 16}})
            return r and r[1] and r[1].value
        end)
        if ok and val and val > 0 and val < 100 then
            return S.cameraAddr
        end
        S.cameraAddr = nil
    end

    addLog('SEARCH', '正在搜索镜头地址...', 'INFO')

    -- 保存当前搜索状态
    local savedCount = gg.getResultsCount()

    gg.clearResults()

    -- 搜索浮点数 8 (原始镜头大小默认值)
    gg.searchNumber('8', gg.TYPE_FLOAT)

    local count = gg.getResultsCount()
    addLog('SEARCH', string.format('搜索到 %d 个结果', count), 'INFO')

    if count == 0 then
        addLog('SEARCH', '未找到原始镜头大小=8，请确保已进入战斗', 'ERROR')
        return nil
    end

    -- 逐个验证：+8 应为 1.0 (视角缩放倍数)，+16 应为 0.0 (视角缩放计时)
    local maxCheck = math.min(count, 2000)
    local results = gg.getResults(maxCheck)

    for i, r in ipairs(results) do
        local addr = r.address
        -- 检查 +8 (0x100 视角缩放倍数 = 1.0)
        local ok, checks = pcall(function()
            return gg.getValues({
                {address = addr + 8,  flags = 16},  -- 视角缩放倍数 = 1
                {address = addr + 16, flags = 16},  -- 视角缩放计时 = 0
                {address = addr - 4,  flags = 16},  -- 时缓尺度 = 0或1
            })
        end)

        if ok and checks then
            local zoomMul = checks[1].value
            local zoomTimer = checks[2].value
            local slowScale = checks[3].value

            -- 验证特征值
            if zoomMul == 1 and zoomTimer == 0
               and (slowScale == 0 or slowScale == 1) then
                S.cameraAddr = addr
                addLog('SEARCH', string.format('找到镜头地址: 0x%X', addr), 'SUCCESS')
                gg.clearResults()
                return addr
            end
        end
    end

    addLog('SEARCH', '特征验证失败，未找到匹配的镜头地址', 'ERROR')
    gg.clearResults()
    return nil
end

local function execPatch(patches, feat)
    feat.frozenItems = {}
    feat.savedValues = {}
    for _, p in ipairs(patches) do
        local addr = S_Pointer(p.so, p.offset, p.is32)
        if addr then
            -- 读取原始值保存
            local oldVal = nil
            pcall(function()
                local r = gg.getValues({{address = addr, flags = p.flags}})
                if r and r[1] then oldVal = r[1].value end
            end)
            table.insert(feat.savedValues, {address = addr, flags = p.flags, value = oldVal})

            -- 写入新值并冻结
            local item = {address = addr, flags = p.flags, value = p.value, freeze = true}
            gg.addListItems({item})
            table.insert(feat.frozenItems, item)
        end
    end
end

-- 关闭：根据功能配置恢复值
local function removePatch(feat)
    -- 1. 先移除冻结项 (停止锁定)
    if feat.frozenItems and #feat.frozenItems > 0 then
        pcall(function() gg.removeListItems(feat.frozenItems) end)
    end
    -- 2. 恢复值
    if feat.restoreType ~= 'unfreeze' then
        -- 需要写回值：如果定义了 restoreValue 用指定值，否则恢复原始值
        if feat.savedValues and #feat.savedValues > 0 then
            pcall(function()
                local restore = {}
                for _, sv in ipairs(feat.savedValues) do
                    local val = sv.value
                    if feat.restoreValue ~= nil then
                        val = feat.restoreValue
                    end
                    if val ~= nil then
                        table.insert(restore, {address = sv.address, flags = sv.flags, value = val})
                    end
                end
                if #restore > 0 then
                    gg.setValues(restore)
                end
            end)
        end
    end
    -- restoreType == 'unfreeze' 时只移除冻结，不写值
    feat.frozenItems = nil
    feat.savedValues = nil
end

-- ========================================
-- 功能定义
-- ========================================
-- ========================================
-- 功能定义（偏移全部通过 dump.cs 验证）
-- GG flags: 4=DWORD(int/bool), 16=FLOAT(float)
-- dump.cs Character 类字段偏移:
--   0x80 总血量(int)  0x84 当前血量(int)
--   0x88 当前能量(float)  0x8C 总能量(float)
--   0x90 当前奥义点数(int)  0x94 总奥义点数(int)  0x98 奥义解锁点数(int)
--   0xA0 一技能冷却  0xA4 二技能冷却  0xA8 奥义冷却
--   0xAC 秘卷冷却  0xB0 通灵冷却  0xB4 替身冷却 (以上float)
--   0x140 移动速度(float)  0x160 伤害加成(float)
--   0x164 暴击率(float)  0x168 暴击倍率(float)
--   0x1D8 是否时停(bool)  0x1E4 免伤率(float)
--   0x250 是否无敌(bool)  0x264 是否死亡(bool)
--   0x268 霸体等级(int)  0x26C 是否霸体(bool)
-- dump.cs 战斗通用事件类:
--   0xF8 原始镜头大小(float)
-- ========================================
local Features = {
    selectProcess = {
        name = '选择进程', desc = '选择目标游戏进程', icon = '◎',
        isButton = true,
        exec = function()
            pcall(function() gg.setProcessX() end)
            addLog('FUNC', '已打开进程选择', 'SUCCESS')
        end
    },

    -- ===== 改视角 (战斗通用事件.原始镜头大小 0xF8) =====
    viewAngle = {
        name = '改视角', desc = '修改镜头大小', icon = '◉',
        enabled = false,
        restoreValue = 8,
        patches = {
            { so = {"libil2cpp.so", "Cd"}, offset = {0xE0338, 0x530, 0x100, 0xF8}, is32 = true, flags = 16, value = 15 },
            { so = {"libil2cpp.so", "Cd"}, offset = {0xE0338, 0xB8, 0xF0, 0xF8}, is32 = true, flags = 16, value = 15 },
        }
    },

    -- ===== 无敌 (Character.是否无敌 0x250) =====
    invincible = {
        name = '无敌', desc = '免疫所有伤害', icon = '◈',
        enabled = false,
        restoreValue = 0,
        patches = {
            { so = {"libil2cpp.so:bss", "Cb"}, offset = {0x21DF88, 0x590, 0x250}, is32 = true, flags = 4, value = 1 },
            { so = {"libil2cpp.so:bss", "Cb"}, offset = {0x211990, 0x610, 0x590, 0x250}, is32 = true, flags = 4, value = 1 },
        }
    },

    -- ===== 暴击率 (Character.暴击率 0x164) =====
    crit = {
        name = '暴击率', desc = '暴击率 100%', icon = '★',
        enabled = false,
        restoreValue = 10,
        patches = {
            { so = {"libil2cpp.so:bss", "Cb"}, offset = {0x21DF88, 0x590, 0x164}, is32 = true, flags = 16, value = 100 },
            { so = {"libil2cpp.so:bss", "Cb"}, offset = {0x211990, 0x610, 0x590, 0x164}, is32 = true, flags = 16, value = 100 },
        }
    },

    -- ===== 暴击倍率 (Character.暴击倍率 0x168) 新增 =====
    critMulti = {
        name = '暴击倍率', desc = '暴击伤害 x50', icon = '✦',
        enabled = false,
        patches = {
            { so = {"libil2cpp.so:bss", "Cb"}, offset = {0x21DF88, 0x590, 0x168}, is32 = true, flags = 16, value = 50 },
            { so = {"libil2cpp.so:bss", "Cb"}, offset = {0x211990, 0x610, 0x590, 0x168}, is32 = true, flags = 16, value = 50 },
        }
    },

    -- ===== 无限火力 (6个冷却全归零) 扩展 =====
    infiniteFire = {
        name = '无限火力', desc = '全技能无冷却', icon = '⚡',
        enabled = false,
        restoreType = 'unfreeze',
        patches = {
            -- 一技能冷却 0xA0
            { so = {"libil2cpp.so:bss", "Cb"}, offset = {0x21DF88, 0x590, 0xA0}, is32 = true, flags = 16, value = 0 },
            { so = {"libil2cpp.so:bss", "Cb"}, offset = {0x211990, 0x610, 0x590, 0xA0}, is32 = true, flags = 16, value = 0 },
            -- 二技能冷却 0xA4
            { so = {"libil2cpp.so:bss", "Cb"}, offset = {0x21DF88, 0x590, 0xA4}, is32 = true, flags = 16, value = 0 },
            { so = {"libil2cpp.so:bss", "Cb"}, offset = {0x211990, 0x610, 0x590, 0xA4}, is32 = true, flags = 16, value = 0 },
            -- 奥义冷却 0xA8
            { so = {"libil2cpp.so:bss", "Cb"}, offset = {0x21DF88, 0x590, 0xA8}, is32 = true, flags = 16, value = 0 },
            { so = {"libil2cpp.so:bss", "Cb"}, offset = {0x211990, 0x610, 0x590, 0xA8}, is32 = true, flags = 16, value = 0 },
            -- 秘卷冷却 0xAC
            { so = {"libil2cpp.so:bss", "Cb"}, offset = {0x21DF88, 0x590, 0xAC}, is32 = true, flags = 16, value = 0 },
            { so = {"libil2cpp.so:bss", "Cb"}, offset = {0x211990, 0x610, 0x590, 0xAC}, is32 = true, flags = 16, value = 0 },
            -- 通灵冷却 0xB0
            { so = {"libil2cpp.so:bss", "Cb"}, offset = {0x21DF88, 0x590, 0xB0}, is32 = true, flags = 16, value = 0 },
            { so = {"libil2cpp.so:bss", "Cb"}, offset = {0x211990, 0x610, 0x590, 0xB0}, is32 = true, flags = 16, value = 0 },
            -- 替身冷却 0xB4
            { so = {"libil2cpp.so:bss", "Cb"}, offset = {0x21DF88, 0x590, 0xB4}, is32 = true, flags = 16, value = 0 },
            { so = {"libil2cpp.so:bss", "Cb"}, offset = {0x211990, 0x610, 0x590, 0xB4}, is32 = true, flags = 16, value = 0 },
        }
    },

    -- ===== 六豆 (3个奥义点数字段) 扩展 =====
    sixBean = {
        name = '六豆', desc = '奥义点数锁定 6', icon = '◆',
        enabled = false,
        restoreType = 'unfreeze',
        patches = {
            -- 当前奥义点数 0x90
            { so = {"libil2cpp.so:bss", "Cb"}, offset = {0x21DF88, 0x590, 0x90}, is32 = true, flags = 4, value = 6 },
            { so = {"libil2cpp.so:bss", "Cb"}, offset = {0x211990, 0x610, 0x590, 0x90}, is32 = true, flags = 4, value = 6 },
            -- 总奥义点数 0x94
            { so = {"libil2cpp.so:bss", "Cb"}, offset = {0x21DF88, 0x590, 0x94}, is32 = true, flags = 4, value = 6 },
            { so = {"libil2cpp.so:bss", "Cb"}, offset = {0x211990, 0x610, 0x590, 0x94}, is32 = true, flags = 4, value = 6 },
            -- 奥义解锁点数 0x98
            { so = {"libil2cpp.so:bss", "Cb"}, offset = {0x21DF88, 0x590, 0x98}, is32 = true, flags = 4, value = 6 },
            { so = {"libil2cpp.so:bss", "Cb"}, offset = {0x211990, 0x610, 0x590, 0x98}, is32 = true, flags = 4, value = 6 },
        }
    },

    -- ===== 移速加速 (Character.移动速度 0x140) 新增 =====
    moveSpeed = {
        name = '移速加速', desc = '移动速度大幅提升', icon = '➤',
        enabled = false,
        patches = {
            { so = {"libil2cpp.so:bss", "Cb"}, offset = {0x21DF88, 0x590, 0x140}, is32 = true, flags = 16, value = 20 },
            { so = {"libil2cpp.so:bss", "Cb"}, offset = {0x211990, 0x610, 0x590, 0x140}, is32 = true, flags = 16, value = 20 },
        }
    },

    -- ===== 伤害加成 (Character.伤害加成 0x160) 新增 =====
    damageBoost = {
        name = '伤害加成', desc = '所有伤害大幅提升', icon = '⚔',
        enabled = false,
        patches = {
            { so = {"libil2cpp.so:bss", "Cb"}, offset = {0x21DF88, 0x590, 0x160}, is32 = true, flags = 16, value = 10 },
            { so = {"libil2cpp.so:bss", "Cb"}, offset = {0x211990, 0x610, 0x590, 0x160}, is32 = true, flags = 16, value = 10 },
            -- 普攻伤害加成 0x16C
            { so = {"libil2cpp.so:bss", "Cb"}, offset = {0x21DF88, 0x590, 0x16C}, is32 = true, flags = 16, value = 10 },
            { so = {"libil2cpp.so:bss", "Cb"}, offset = {0x211990, 0x610, 0x590, 0x16C}, is32 = true, flags = 16, value = 10 },
            -- 一技能伤害加成 0x170
            { so = {"libil2cpp.so:bss", "Cb"}, offset = {0x21DF88, 0x590, 0x170}, is32 = true, flags = 16, value = 10 },
            { so = {"libil2cpp.so:bss", "Cb"}, offset = {0x211990, 0x610, 0x590, 0x170}, is32 = true, flags = 16, value = 10 },
            -- 二技能伤害加成 0x174
            { so = {"libil2cpp.so:bss", "Cb"}, offset = {0x21DF88, 0x590, 0x174}, is32 = true, flags = 16, value = 10 },
            { so = {"libil2cpp.so:bss", "Cb"}, offset = {0x211990, 0x610, 0x590, 0x174}, is32 = true, flags = 16, value = 10 },
            -- 奥义伤害加成 0x178
            { so = {"libil2cpp.so:bss", "Cb"}, offset = {0x21DF88, 0x590, 0x178}, is32 = true, flags = 16, value = 10 },
            { so = {"libil2cpp.so:bss", "Cb"}, offset = {0x211990, 0x610, 0x590, 0x178}, is32 = true, flags = 16, value = 10 },
        }
    },

    -- ===== 霸体 (Character.是否霸体 0x26C + 霸体等级 0x268) 新增 =====
    superArmor = {
        name = '霸体', desc = '免疫击退击飞', icon = '🛡',
        enabled = false,
        restoreValue = 0,
        patches = {
            -- 是否霸体 0x26C
            { so = {"libil2cpp.so:bss", "Cb"}, offset = {0x21DF88, 0x590, 0x26C}, is32 = true, flags = 4, value = 1 },
            { so = {"libil2cpp.so:bss", "Cb"}, offset = {0x211990, 0x610, 0x590, 0x26C}, is32 = true, flags = 4, value = 1 },
            -- 霸体等级 0x268
            { so = {"libil2cpp.so:bss", "Cb"}, offset = {0x21DF88, 0x590, 0x268}, is32 = true, flags = 4, value = 999 },
            { so = {"libil2cpp.so:bss", "Cb"}, offset = {0x211990, 0x610, 0x590, 0x268}, is32 = true, flags = 4, value = 999 },
        }
    },

    -- ===== 免伤 (Character.免伤率 0x1E4) 新增 =====
    damageReduce = {
        name = '免伤', desc = '受到伤害减少 100%', icon = '◍',
        enabled = false,
        patches = {
            { so = {"libil2cpp.so:bss", "Cb"}, offset = {0x21DF88, 0x590, 0x1E4}, is32 = true, flags = 16, value = 1 },
            { so = {"libil2cpp.so:bss", "Cb"}, offset = {0x211990, 0x610, 0x590, 0x1E4}, is32 = true, flags = 16, value = 1 },
        }
    },

    -- ===== 满血 (Character.当前血量 0x84 + 总血量 0x80) 新增 =====
    fullHP = {
        name = '锁血', desc = '血量锁定 99999', icon = '❤',
        enabled = false,
        patches = {
            -- 当前血量 0x84
            { so = {"libil2cpp.so:bss", "Cb"}, offset = {0x21DF88, 0x590, 0x84}, is32 = true, flags = 4, value = 99999 },
            { so = {"libil2cpp.so:bss", "Cb"}, offset = {0x211990, 0x610, 0x590, 0x84}, is32 = true, flags = 4, value = 99999 },
            -- 总血量 0x80
            { so = {"libil2cpp.so:bss", "Cb"}, offset = {0x21DF88, 0x590, 0x80}, is32 = true, flags = 4, value = 99999 },
            { so = {"libil2cpp.so:bss", "Cb"}, offset = {0x211990, 0x610, 0x590, 0x80}, is32 = true, flags = 4, value = 99999 },
        }
    },

    -- ===== 满能量 (Character.当前能量 0x88 + 总能量 0x8C) 新增 =====
    fullEnergy = {
        name = '满能量', desc = '能量锁定 100', icon = '⚡',
        enabled = false,
        patches = {
            -- 当前能量 0x88
            { so = {"libil2cpp.so:bss", "Cb"}, offset = {0x21DF88, 0x590, 0x88}, is32 = true, flags = 16, value = 100 },
            { so = {"libil2cpp.so:bss", "Cb"}, offset = {0x211990, 0x610, 0x590, 0x88}, is32 = true, flags = 16, value = 100 },
            -- 总能量 0x8C
            { so = {"libil2cpp.so:bss", "Cb"}, offset = {0x21DF88, 0x590, 0x8C}, is32 = true, flags = 16, value = 100 },
            { so = {"libil2cpp.so:bss", "Cb"}, offset = {0x211990, 0x610, 0x590, 0x8C}, is32 = true, flags = 16, value = 100 },
        }
    },

    -- ===== 解斑须佐持续 (解斑.奥义须佐持续计时 0x358) 新增 =====
    susanoo = {
        name = '须佐持续', desc = '解斑须佐持续时间改10', icon = '🌀',
        enabled = false,
        patches = {
            { so = {"libil2cpp.so:bss", "Cb"}, offset = {0x21DF88, 0x590, 0x358}, is32 = true, flags = 16, value = 10 },
            { so = {"libil2cpp.so:bss", "Cb"}, offset = {0x211990, 0x610, 0x590, 0x358}, is32 = true, flags = 16, value = 10 },
        }
    },

    -- ===== 自定义改值（实例地址+偏移）开发者功能 =====
    customMod = {
        name = '自定义改值', desc = '填实例地址+偏移修改', icon = '🔧',
        isButton = true,
        exec = function()
            if not S.devUnlocked then
                gg.toast('请先开启开发者模式')
                addLog('CUSTOM', '未解锁开发者模式，拒绝访问', 'WARN')
                return
            end
            local input = gg.prompt({
                '[1] 实例地址(如 0x12345678, 可从复制角色地址获取)',
                '[2] 偏移量(如 0x164, 十六进制)',
                '[3] 写入数值',
                '[4] 类型: 4=整数(DWORD) 16=浮点(FLOAT)',
                '[5] 是否冻结: 1=冻结 0=不冻结',
            }, {
                '0x0',
                '0x164',
                '100',
                '16',
                '1',
            }, {'text', 'text', 'text', 'text', 'text'})

            if not input then return end

            local baseStr = input[1] or '0'
            local offsetStr = input[2] or '0'
            local writeVal = input[3] or '0'
            local flagsNum = tonumber(input[4]) or 16
            local doFreeze = (input[5] == '1')

            -- 解析实例地址
            local baseAddr = tonumber(baseStr) or 0
            if baseAddr == 0 then
                addLog('CUSTOM', '实例地址无效', 'ERROR')
                gg.toast('实例地址无效')
                return
            end

            -- 解析偏移
            local offset = tonumber(offsetStr) or 0
            local addr = baseAddr + offset

            -- 转换数值
            local val = tonumber(writeVal) or 0

            -- 读取原始值
            local oldVal = nil
            pcall(function()
                local r = gg.getValues({{address = addr, flags = flagsNum}})
                if r and r[1] then oldVal = r[1].value end
            end)

            -- 写入
            if doFreeze then
                gg.addListItems({{address = addr, flags = flagsNum, value = val, freeze = true}})
            else
                gg.setValues({{address = addr, flags = flagsNum, value = val}})
            end

            -- 保存到自定义列表
            if not S.customPatches then S.customPatches = {} end
            table.insert(S.customPatches, {
                address = addr,
                flags = flagsNum,
                oldValue = oldVal,
                frozen = doFreeze,
                desc = string.format('0x%X+0x%X → %s (%s)', baseAddr, offset, writeVal,
                    doFreeze and '冻结' or '不冻结'),
            })

            local typeStr = (flagsNum == 16) and 'FLOAT' or 'DWORD'
            addLog('CUSTOM', string.format('[%s] 0x%X+0x%X=0x%X → %s %s',
                typeStr, baseAddr, offset, addr, writeVal, doFreeze and '(冻结)' or ''), 'SUCCESS')
            gg.toast(string.format('已写入 0x%X = %s', addr, writeVal))
        end
    },

    -- ===== 清除自定义（开发者功能） =====
    customClear = {
        name = '清除自定义', desc = '恢复所有自定义修改', icon = '🗑',
        isButton = true,
        exec = function()
            if not S.devUnlocked then
                gg.toast('请先开启开发者模式')
                return
            end
            if not S.customPatches or #S.customPatches == 0 then
                gg.toast('没有自定义修改')
                return
            end

            local frozenItems = {}
            local restoreVals = {}
            for _, cp in ipairs(S.customPatches) do
                if cp.frozen then
                    table.insert(frozenItems, {address = cp.address, flags = cp.flags})
                end
                if cp.oldValue ~= nil then
                    table.insert(restoreVals, {address = cp.address, flags = cp.flags, value = cp.oldValue})
                end
            end

            -- 移除冻结
            if #frozenItems > 0 then
                pcall(function() gg.removeListItems(frozenItems) end)
            end
            -- 恢复值
            if #restoreVals > 0 then
                pcall(function() gg.setValues(restoreVals) end)
            end

            local count = #S.customPatches
            S.customPatches = {}
            addLog('CUSTOM', string.format('已清除 %d 个自定义修改', count), 'WARN')
            gg.toast(string.format('已清除 %d 个自定义修改', count))
        end
    },

    -- ===== 一键全开 新增 =====
    allInOne = {
        name = '一键全开', desc = '开启所有战斗功能', icon = '☑',
        isButton = true,
        exec = function()
            local keys = {'viewAngle', 'invincible', 'crit', 'critMulti', 'infiniteFire', 'sixBean',
                         'moveSpeed', 'damageBoost', 'superArmor', 'damageReduce',
                         'fullHP', 'fullEnergy', 'susanoo'}
            for _, k in ipairs(keys) do
                local feat = Features[k]
                if feat and not feat.enabled then
                    feat.enabled = true
                    pcall(function() execPatch(feat.patches, feat) end)
                    -- 更新UI
                    runOnMainThread(function()
                        pcall(function()
                            local tv = getView(IDS['toggle_' .. k])
                            local cv = getView(IDS['card_' .. k])
                            if tv then
                                tv:setText('● ON')
                                tv:setTextColor(T.success)
                            end
                            if cv then
                                cv:setBackgroundDrawable(stateList(T.bgCardOn, 0xFF253547, 14))
                            end
                        end)
                    end)
                end
            end
            addLog('FUNC', '一键全开完成', 'SUCCESS')
            pcall(function() gg.toast('全部功能已开启') end)
        end
    },

    -- ===== 一键全关 新增 =====
    allOff = {
        name = '一键全关', desc = '关闭所有战斗功能', icon = '☒',
        isButton = true,
        exec = function()
            local keys = {'viewAngle', 'invincible', 'crit', 'critMulti', 'infiniteFire', 'sixBean',
                         'moveSpeed', 'damageBoost', 'superArmor', 'damageReduce',
                         'fullHP', 'fullEnergy', 'susanoo'}
            for _, k in ipairs(keys) do
                local feat = Features[k]
                if feat and feat.enabled then
                    feat.enabled = false
                    pcall(function() removePatch(feat) end)
                    -- 更新UI
                    runOnMainThread(function()
                        pcall(function()
                            local tv = getView(IDS['toggle_' .. k])
                            local cv = getView(IDS['card_' .. k])
                            if tv then
                                tv:setText('○ OFF')
                                tv:setTextColor(T.toggleOff)
                            end
                            if cv then
                                cv:setBackgroundDrawable(stateList(T.bgCard, 0xFF253547, 14))
                            end
                        end)
                    end)
                end
            end
            addLog('FUNC', '一键全关完成', 'WARN')
            pcall(function() gg.toast('全部功能已关闭') end)
        end
    },

    -- ===== 开发者模式入口（密码保护） =====
    devMode = {
        name = '开发者模式', desc = '需要密码解锁高级功能', icon = '🔐',
        isButton = true,
        exec = function()
            if S.devUnlocked then
                -- 已解锁，点击则关闭
                S.devUnlocked = false
                gg.toast('开发者模式已关闭')
                addLog('DEV', '开发者模式已关闭', 'WARN')
                -- 更新UI：恢复正常卡片样式
                runOnMainThread(function()
                    pcall(function()
                        local cv = getView(IDS['card_devMode'])
                        if cv then
                            cv:setBackgroundDrawable(stateList(T.bgCard, 0xFF253547, 14))
                        end
                    end)
                end)
            else
                -- 未解锁，需要密码
                local input = gg.prompt({'请输入开发者密码:'}, {'', }, {'text'})
                if not input then return end
                if input[1] == '085236qw' then
                    S.devUnlocked = true
                    gg.toast('密码正确，开发者模式已开启')
                    addLog('DEV', '密码正确，开发者模式已开启', 'SUCCESS')
                    -- 更新UI：高亮卡片样式
                    runOnMainThread(function()
                        pcall(function()
                            local cv = getView(IDS['card_devMode'])
                            if cv then
                                cv:setBackgroundDrawable(stateList(T.bgCardOn, 0xFF253547, 14))
                            end
                        end)
                    end)
                else
                    gg.toast('密码错误')
                    addLog('DEV', '密码错误', 'ERROR')
                end
            end
        end
    },

    -- ===== 复制角色地址（开发者功能） =====
    copyCharAddr = {
        name = '复制角色地址', desc = '获取并复制Character实例地址', icon = '📋',
        isButton = true,
        exec = function()
            if not S.devUnlocked then
                gg.toast('请先开启开发者模式')
                return
            end
            -- 无敌字段偏移 0x250
            local offsetInv = 0x250

            -- 玩家1: 0x21DF88 → 0x590 → 0x250
            local addrInvP1 = S_Pointer({"libil2cpp.so:bss", "Cb"}, {0x21DF88, 0x590, offsetInv}, true)
            -- 玩家2: 0x211990 → 0x610 → 0x590 → 0x250
            local addrInvP2 = S_Pointer({"libil2cpp.so:bss", "Cb"}, {0x211990, 0x610, 0x590, offsetInv}, true)

            addLog('ADDR', string.format('无敌字段地址 P1=%s P2=%s',
                tostring(addrInvP1), tostring(addrInvP2)), 'INFO')

            local addrP1 = nil
            local addrP2 = nil

            if addrInvP1 and addrInvP1 > 0x10000 then
                addrP1 = addrInvP1 - offsetInv
                addLog('ADDR', string.format('P1 Character=0x%X', addrP1), 'SUCCESS')
            end
            if addrInvP2 and addrInvP2 > 0x10000 then
                addrP2 = addrInvP2 - offsetInv
                addLog('ADDR', string.format('P2 Character=0x%X', addrP2), 'SUCCESS')
            end

            if not addrP1 and not addrP2 then
                gg.toast('未找到角色地址，请确保已进入战斗')
                return
            end

            local text = ''
            if addrP1 and addrP1 > 0x10000 then
                text = text .. string.format('P1: 0x%X', addrP1)
            end
            if addrP2 and addrP2 > 0x10000 then
                if text ~= '' then text = text .. '\n' end
                text = text .. string.format('P2: 0x%X', addrP2)
            end

            if text == '' then
                gg.toast('角色地址无效，请确保已进入战斗')
                return
            end

            pcall(function() gg.copyText(text) end)
            gg.toast('已复制到剪贴板:\n' .. text)
            addLog('ADDR', '地址已复制到剪贴板: ' .. text, 'SUCCESS')
        end
    },

    musicPlayer = {
        name = '播放音乐', desc = '网络URL或本地文件', icon = '♫',
        enabled = false,
    },
    systemRingtone = {
        name = '系统铃声', desc = '播放系统默认通知音', icon = '🔔',
        isButton = true,
        exec = function()
            pcall(function()
                local RingtoneManager = luajava.bindClass('android.media.RingtoneManager')
                local uri = RingtoneManager:getDefaultUri(RingtoneManager.TYPE_NOTIFICATION)
                local r = RingtoneManager:getRingtone(app.context, uri)
                if r then
                    r:play()
                    addLog('MUSIC', '播放系统铃声', 'SUCCESS')
                    pcall(function() gg.toast('播放系统铃声') end)
                end
            end)
        end
    },
}

local featureOrder = {
    'selectProcess',
    'viewAngle', 'invincible', 'crit', 'critMulti',
    'infiniteFire', 'sixBean',
    'moveSpeed', 'damageBoost', 'superArmor', 'damageReduce',
    'fullHP', 'fullEnergy', 'susanoo',
    'allInOne', 'allOff',
    'devMode',
    'customMod', 'customClear',
    'copyCharAddr',
    'musicPlayer', 'systemRingtone',
}

-- ========================================
-- 预生成 ID
-- ========================================
local IDS = {}
IDS.titleBar         = luajava.newId('title_bar')
IDS.pageTitle        = luajava.newId('page_title')
IDS.contentContainer = luajava.newId('content_container')
IDS.logView          = luajava.newId('log_view')
IDS.minimizeBtn      = luajava.newId('minimize_btn')
IDS.closeBtn         = luajava.newId('close_btn')
for _, key in ipairs(featureOrder) do
    IDS['card_' .. key] = luajava.newId('card_' .. key)
    IDS['toggle_' .. key] = luajava.newId('toggle_' .. key)
end

-- ========================================
-- 切换功能开关
-- ========================================
local function updateToggle(key)
    local feat = Features[key]
    if not feat or feat.isButton then return end

    feat.enabled = not feat.enabled

    if key == 'musicPlayer' then
        -- ========== 音乐播放逻辑 ==========
        if feat.enabled then
            -- 尝试继续播放
            local resumed = false
            pcall(function()
                if S.mediaPlayer then
                    S.mediaPlayer:start()
                    resumed = true
                end
            end)
            if resumed then
                addLog('MUSIC', '继续播放', 'SUCCESS')
                pcall(function() gg.toast('继续播放') end)
            else
                -- 需要创建新播放器
                local path = S.musicPath
                if not path or path == '' then
                    local input = gg.prompt({'请输入音乐链接或本地路径:'}, {'https://example.com/music.mp3'}, {'text'})
                    if input and input[1] and input[1] ~= '' then
                        path = input[1]
                        S.musicPath = path
                    else
                        addLog('MUSIC', '未输入音乐地址', 'WARN')
                        feat.enabled = false
                        return
                    end
                end
                -- 判断是网络还是本地
                local isNetwork = path:match('^https?://') ~= nil
                if not isNetwork then
                    -- 本地路径检查文件是否存在
                    local f = io.open(path, 'r')
                    if not f then
                        addLog('MUSIC', '文件不存在: ' .. path, 'ERROR')
                        pcall(function() gg.toast('音乐文件不存在') end)
                        feat.enabled = false
                        S.musicPath = nil
                        return
                    end
                    f:close()
                end
                -- 创建 MediaPlayer
                local ok, e = pcall(function()
                    S.mediaPlayer = luajava.newInstance('android.media.MediaPlayer')
                    S.mediaPlayer:setDataSource(path)
                    S.mediaPlayer:prepare()
                    S.mediaPlayer:start()
                end)
                if ok then
                    addLog('MUSIC', '开始播放: ' .. path, 'SUCCESS')
                    pcall(function() gg.toast('开始播放音乐') end)
                else
                    addLog('MUSIC', '播放失败: ' .. tostring(e), 'ERROR')
                    pcall(function() gg.toast('播放失败') end)
                    feat.enabled = false
                    S.mediaPlayer = nil
                    return
                end
            end
        else
            -- 暂停
            pcall(function()
                if S.mediaPlayer then
                    S.mediaPlayer:pause()
                end
            end)
            addLog('MUSIC', '音乐已暂停', 'WARN')
            pcall(function() gg.toast('音乐已暂停') end)
        end
    else
        -- ========== 原有内存补丁逻辑 ==========
        if feat.enabled then
            local ok, e = pcall(function() execPatch(feat.patches, feat) end)
            if ok then
                addLog('FUNC', feat.name .. ' 已开启', 'SUCCESS')
                pcall(function() gg.toast(feat.name .. ' 开启成功') end)
            else
                addLog('FUNC', feat.name .. ' 失败: ' .. tostring(e), 'ERROR')
                feat.enabled = false
                feat.frozenItems = nil
                return
            end
        else
            -- 只移除该功能的冻结项，不影响其他功能
            removePatch(feat)
            addLog('FUNC', feat.name .. ' 已关闭', 'WARN')
            pcall(function() gg.toast(feat.name .. ' 已关闭') end)
        end
    end

    -- 更新开关外观 (主线程)
    runOnMainThread(function()
        pcall(function()
            local tv = getView(IDS['toggle_' .. key])
            local cv = getView(IDS['card_' .. key])
            if tv then
                tv:setText(feat.enabled and '● ON' or '○ OFF')
                tv:setTextColor(feat.enabled and T.success or T.toggleOff)
            end
            if cv then
                cv:setBackgroundDrawable(stateList(
                    feat.enabled and T.bgCardOn or T.bgCard,
                    0xFF253547, 12
                ))
            end
        end)
    end)
end

-- ========================================
-- 构建功能卡片
-- ========================================
local function buildCard(key)
    local feat = Features[key]
    if not feat then return end

    local rightElem
    if feat.isButton then
        rightElem = {
            TextView, text = '›', textSize = '26sp',
            textColor = T.primaryLight, layout_width = '36dp', gravity = 'center',
        }
    else
        rightElem = {
            TextView, id = IDS['toggle_' .. key],
            text = '○ OFF', textSize = '14sp',
            textColor = T.toggleOff, textStyle = 'bold',
            layout_width = 'wrap_content', gravity = 'center',
        }
    end

    return {
        LinearLayout,
        id = IDS['card_' .. key],
        layout_width = 'match_parent',
        layout_height = 'wrap_content',
        layout_margin = '6dp',
        padding = '16dp',
        orientation = 'horizontal',
        gravity = 'center_vertical',
        background = stateList(T.bgCard, 0xFF253547, 14),
        onClick = function()
            if feat.isButton then
                pcall(feat.exec)
            else
                pcall(function() updateToggle(key) end)
            end
        end,
        {
            TextView, text = feat.icon, textSize = '26sp',
            textColor = T.textSec,
            layout_width = '42dp', layout_height = '42dp', gravity = 'center',
        },
        {
            LinearLayout,
            layout_width = '0dp', layout_weight = 1,
            layout_height = 'wrap_content', orientation = 'vertical',
            layout_marginLeft = '14dp',
            {
                TextView, text = feat.name, textSize = '17sp',
                textColor = T.textPri, textStyle = 'bold',
            },
            {
                TextView, text = feat.desc, textSize = '13sp',
                textColor = T.textHint, layout_marginTop = '3dp',
            }
        },
        rightElem
    }
end

-- ========================================
-- 最小化 / 恢复
-- ========================================
local function minimize()
    runOnMainThread(function()
        pcall(function() windowManager:removeView(S.mainView) end)
        pcall(function() windowManager:addView(S.ballView, S.ballParams) end)
    end)
    addLog('UI', '已最小化为悬浮球')
end

local function restore()
    runOnMainThread(function()
        pcall(function() windowManager:removeView(S.ballView) end)
        pcall(function() windowManager:addView(S.mainView, S.mainParams) end)
    end)
    addLog('UI', '已恢复主窗口')
end

-- ========================================
-- 前向声明（switchTheme 在 buildBallLayout 之后定义）
-- ========================================
local switchTheme

-- ========================================
-- 构建风格选项栏
-- ========================================
local function buildStyleBar()
    local inner = {
        LinearLayout,
        layout_width = 'wrap_content',
        layout_height = 'wrap_content',
        orientation = 'horizontal',
        padding = '6dp',
    }

    for i, theme in ipairs(Themes) do
        local isActive = (i == S.currentTheme)
        local tab = {
            TextView,
            text = theme.name,
            textSize = '14sp',
            textColor = isActive and 0xFFFFFFFF or T.textSec,
            padding = '12dp',
            layout_margin = '4dp',
            gravity = 'center',
            onClick = function()
                if i ~= S.currentTheme then
                    switchTheme(i)
                end
            end,
        }
        if isActive then
            tab.textStyle = 'bold'
            tab.background = gradient({T.primary, T.primaryDark}, 12)
        else
            tab.background = stateList(T.bgCard, 0xFF253547, 12)
        end
        inner[#inner + 1] = tab
    end

    return {
        HorizontalScrollView,
        layout_width = 'match_parent',
        layout_height = 'wrap_content',
        scrollbars = 'none',
        inner
    }
end

-- ========================================
-- 构建主窗口布局 (使用原生 onTouch)
-- ========================================
local function buildMainLayout()
    return {
        LinearLayout,
        layout_width = 'match_parent',
        layout_height = 'match_parent',
        orientation = 'vertical',
        background = getMainBgDrawable(),
        {
            -- 标题栏 (onTouch 拖动)
            LinearLayout,
            id = IDS.titleBar,
            layout_width = 'match_parent',
            layout_height = 'wrap_content',
            orientation = 'horizontal',
            gravity = 'center_vertical',
            padding = '16dp',
            background = gradient({T.primary, T.primaryDark}, 0),
            onTouch = function(view, event)
                local action = event:getAction() & 0xff
                if action == 0 then
                    mainDrag.sx = S.mainParams.x
                    mainDrag.sy = S.mainParams.y
                    mainDrag.srx = event:getRawX()
                    mainDrag.sry = event:getRawY()
                    mainDrag.moved = false
                elseif action == 2 then
                    local dx = event:getRawX() - mainDrag.srx
                    local dy = event:getRawY() - mainDrag.sry
                    if math.abs(dx) > 10 or math.abs(dy) > 10 then
                        mainDrag.moved = true
                    end
                    if mainDrag.moved then
                        S.mainParams.x = mainDrag.sx + dx
                        S.mainParams.y = mainDrag.sy + dy
                        pcall(function()
                            windowManager:updateViewLayout(S.mainView, S.mainParams)
                        end)
                    end
                end
                return true
            end,
            {
                LinearLayout,
                layout_width = '42dp', layout_height = '42dp',
                gravity = 'center',
                background = gradient({0xFFFFFFFF, 0xFFB3D9FF}, 21),
                {
                    TextView, text = 'B', textSize = '20sp',
                    textColor = T.primaryDark, textStyle = 'bold',
                }
            },
            {
                TextView, id = IDS.pageTitle, text = '小志助手',
                layout_width = '0dp', layout_weight = 1,
                textSize = '19sp', textColor = 0xFFFFFFFF, textStyle = 'bold',
                layout_marginLeft = '12dp',
            },
            {
                TextView, id = IDS.minimizeBtn, text = '—',
                textSize = '20sp', textColor = 0xCCFFFFFF,
                layout_width = '38dp', layout_height = '38dp', gravity = 'center',
                background = stateList(0x20FFFFFF, 0x40FFFFFF, 19),
                onClick = function() pcall(minimize) end,
            },
            {
                TextView, id = IDS.closeBtn, text = '✕',
                layout_marginLeft = '8dp',
                textSize = '18sp', textColor = 0xFFFFCDD2,
                layout_width = '38dp', layout_height = '38dp', gravity = 'center',
                background = stateList(0x20FF0000, 0x40FF0000, 19),
                onClick = function()
                    addLog('UI', '正在退出...', 'WARN')
                    S.exitFlag = true
                    pcall(function() if S.unpark then S.unpark() end end)
                end,
            },
        },
        -- 风格选项栏
        buildStyleBar(),
        {
            ScrollView,
            layout_width = 'match_parent',
            layout_height = '0dp',
            layout_weight = 1,
            {
                LinearLayout,
                id = IDS.contentContainer,
                layout_width = 'match_parent',
                layout_height = 'wrap_content',
                orientation = 'vertical',
                padding = '10dp',
            }
        },
        {
            View, layout_width = 'match_parent', layout_height = '1dp',
            backgroundColor = 0x20FFFFFF,
        },
        {
            LinearLayout,
            layout_width = 'match_parent',
            layout_height = '120dp',
            orientation = 'vertical',
            padding = '10dp',
            background = gradient({T.bgLog, T.bgMain}, 0),
            {
                TextView, text = '运行日志', textSize = '12sp',
                textColor = T.textHint, layout_marginBottom = '4dp',
            },
            {
                ScrollView,
                layout_width = 'match_parent',
                layout_height = 'match_parent',
                {
                    TextView, id = IDS.logView,
                    layout_width = 'match_parent',
                    layout_height = 'wrap_content',
                    textSize = '11sp',
                    textColor = T.textSec,
                    textIsSelectable = true,
                }
            }
        }
    }
end

-- ========================================
-- 构建悬浮球 (120dp, onTouch 拖动 + 点击恢复)
-- ========================================
local function buildBallLayout()
    if S.ballDrawable then
        -- 有图片背景，不显示文字
        return {
            FrameLayout,
            layout_width = '120dp',
            layout_height = '120dp',
            background = getBallBgDrawable(),
            onTouch = function(view, event)
                local action = event:getAction() & 0xff
                if action == 0 then
                    ballDrag.sx = S.ballParams.x
                    ballDrag.sy = S.ballParams.y
                    ballDrag.srx = event:getRawX()
                    ballDrag.sry = event:getRawY()
                    ballDrag.moved = false
                elseif action == 2 then
                    local dx = event:getRawX() - ballDrag.srx
                    local dy = event:getRawY() - ballDrag.sry
                    if math.abs(dx) > 10 or math.abs(dy) > 10 then
                        ballDrag.moved = true
                    end
                    if ballDrag.moved then
                        S.ballParams.x = ballDrag.sx + dx
                        S.ballParams.y = ballDrag.sy + dy
                        pcall(function()
                            windowManager:updateViewLayout(S.ballView, S.ballParams)
                        end)
                    end
                elseif action == 1 then
                    if not ballDrag.moved then
                        pcall(restore)
                    end
                end
                return true
            end,
        }
    else
        -- 默认渐变背景，显示 "B" 文字
        return {
            FrameLayout,
            layout_width = '120dp',
            layout_height = '120dp',
            background = getBallBgDrawable(),
            onTouch = function(view, event)
                local action = event:getAction() & 0xff
                if action == 0 then
                    ballDrag.sx = S.ballParams.x
                    ballDrag.sy = S.ballParams.y
                    ballDrag.srx = event:getRawX()
                    ballDrag.sry = event:getRawY()
                    ballDrag.moved = false
                elseif action == 2 then
                    local dx = event:getRawX() - ballDrag.srx
                    local dy = event:getRawY() - ballDrag.sry
                    if math.abs(dx) > 10 or math.abs(dy) > 10 then
                        ballDrag.moved = true
                    end
                    if ballDrag.moved then
                        S.ballParams.x = ballDrag.sx + dx
                        S.ballParams.y = ballDrag.sy + dy
                        pcall(function()
                            windowManager:updateViewLayout(S.ballView, S.ballParams)
                        end)
                    end
                elseif action == 1 then
                    if not ballDrag.moved then
                        pcall(restore)
                    end
                end
                return true
            end,
            {
                TextView, text = 'B', textSize = '40sp',
                textColor = 0xFFFFFFFF, textStyle = 'bold',
                layout_gravity = 'center',
            }
        }
    end
end

-- ========================================
-- 切换风格（重建整个主窗口）
-- ========================================
switchTheme = function(index)
    if index == S.currentTheme then return end
    if not Themes[index] then return end

    -- 更新主题
    applyTheme(index)
    S.currentTheme = index

    runOnMainThread(function()
        pcall(function()
            -- 移除旧主窗口
            windowManager:removeView(S.mainView)

            -- 重建主窗口
            S.mainView = luajava.loadlayout(buildMainLayout())
            S.logView = getView(IDS.logView)
            S.contentContainer = getView(IDS.contentContainer)

            -- 重新填充功能卡片
            if S.contentContainer then
                for _, key in ipairs(featureOrder) do
                    pcall(function()
                        luajava.loadlayout(buildCard(key), nil, S.contentContainer)
                    end)
                end
            end

            -- 恢复开关状态
            for _, key in ipairs(featureOrder) do
                local feat = Features[key]
                if feat and not feat.isButton and feat.enabled then
                    local tv = getView(IDS['toggle_' .. key])
                    local cv = getView(IDS['card_' .. key])
                    if tv then
                        tv:setText('● ON')
                        tv:setTextColor(T.success)
                    end
                    if cv then
                        cv:setBackgroundDrawable(stateList(T.bgCardOn, 0xFF253547, 14))
                    end
                end
            end

            -- 恢复开发者模式高亮
            if S.devUnlocked then
                local cv = getView(IDS['card_devMode'])
                if cv then
                    cv:setBackgroundDrawable(stateList(T.bgCardOn, 0xFF253547, 14))
                end
            end

            -- 恢复日志文本
            if S.logView then
                local text = ''
                for _, l in ipairs(logs) do text = text .. l .. '\n' end
                S.logView:setText(text)
            end

            -- 重新添加主窗口
            windowManager:addView(S.mainView, S.mainParams)

            -- 重建悬浮球
            S.ballView = luajava.loadlayout(buildBallLayout())
        end)
    end)

    addLog('UI', '切换风格: ' .. Themes[index].name, 'INFO')
    pcall(function() gg.toast('风格: ' .. Themes[index].name) end)
end

-- ========================================
-- 主程序
-- ========================================
local ok, err = pcall(function()

    -- === 0. 启动前选择模式：自选图片 / 默认 ===
    local modeChoice = gg.choice({
        '🖼  自选图片（自定义背景）',
        '🎨  默认（纯色渐变背景）',
    }, 1, '请选择悬浮窗背景模式')

    if modeChoice == 1 then
        -- 自选图片模式
        local imgInput = gg.prompt({
            '请输入图片路径:',
        }, {
            '/storage/emulated/0/mmexport1784642808708.jpg',
        }, {'text'})

        if imgInput and imgInput[1] and imgInput[1] ~= '' then
            S.bgImagePath = imgInput[1]
            S.bgDrawable = loadBgDrawable(S.bgImagePath)
            if S.bgDrawable then
                addLog('SYSTEM', '背景图片加载成功: ' .. S.bgImagePath, 'SUCCESS')
            else
                addLog('SYSTEM', '背景图片加载失败，使用默认背景: ' .. S.bgImagePath, 'ERROR')
                gg.toast('图片加载失败，使用默认背景')
            end
        end
    else
        -- 默认模式，不设置背景图片
        S.bgDrawable = nil
        S.bgImagePath = nil
    end

    -- === 0.5 悬浮球图片选择 ===
    local ballChoice = gg.choice({
        '🖼  自选悬浮球图片',
        '🔵  默认悬浮球（蓝色渐变）',
    }, 1, '请选择悬浮球样式')

    if ballChoice == 1 then
        local ballInput = gg.prompt({
            '请输入悬浮球图片路径:',
        }, {
            '/storage/emulated/0/1964024d4a551ac660179c4ab5e06b78.jpg',
        }, {'text'})

        if ballInput and ballInput[1] and ballInput[1] ~= '' then
            S.ballImagePath = ballInput[1]
            S.ballDrawable = loadBgDrawable(S.ballImagePath)
            if S.ballDrawable then
                addLog('SYSTEM', '悬浮球图片加载成功: ' .. S.ballImagePath, 'SUCCESS')
            else
                addLog('SYSTEM', '悬浮球图片加载失败，使用默认样式: ' .. S.ballImagePath, 'ERROR')
                gg.toast('悬浮球图片加载失败，使用默认样式')
            end
        end
    else
        S.ballDrawable = nil
        S.ballImagePath = nil
    end

    -- === 1. 主线程创建窗口 ===
    runOnMainThread(function()
        -- 获取屏幕尺寸，设置大窗口
        local dm = app.context:getResources():getDisplayMetrics()
        local winW = math.floor(dm.widthPixels * 0.88)   -- 屏幕宽度 88%
        local winH = math.floor(dm.heightPixels * 0.75)  -- 屏幕高度 75%

        S.mainParams = newParams(winW, winH)
        S.mainView = luajava.loadlayout(buildMainLayout())

        -- 视图引用
        S.logView = getView(IDS.logView)
        S.contentContainer = getView(IDS.contentContainer)

        -- 填充功能卡片
        if S.contentContainer then
            for _, key in ipairs(featureOrder) do
                pcall(function()
                    luajava.loadlayout(buildCard(key), nil, S.contentContainer)
                end)
            end
        end

        -- 创建悬浮球（加大到 120dp）
        S.ballParams = newParams(120, 120)
        S.ballView = luajava.loadlayout(buildBallLayout())

        -- 显示主窗口
        windowManager:addView(S.mainView, S.mainParams)
    end)

    -- 等待主线程完成
    gg.sleep(500)

    -- 初始日志
    addLog('SYSTEM', '蓝色助手已启动 v6.2', 'SUCCESS')
    addLog('SYSTEM', '偏移已通过 dump.cs 验证')
    addLog('SYSTEM', '6套风格可切换: 深蓝/暗紫/暗绿/暗红/暗金/纯黑')
    if S.bgDrawable then
        addLog('SYSTEM', '背景模式: 自选图片')
    else
        addLog('SYSTEM', '背景模式: 默认渐变')
    end
    if S.ballDrawable then
        addLog('SYSTEM', '悬浮球: 自选图片 (120dp)')
    else
        addLog('SYSTEM', '悬浮球: 默认渐变 (120dp)')
    end
    addLog('SYSTEM', '点击卡片切换 开/关')
    addLog('SYSTEM', '一键全开/全关 快捷操作')
    addLog('SYSTEM', '开发者模式: 自定义改值+角色地址需密码解锁')

    pcall(function() gg.setVisible(false) end)
    pcall(function() luajava.setFloatingWindowHide(true) end)

    -- === 2. park/unpark 保持运行 ===
    local park, unpark = luajava.getLockSupport()
    S.unpark = unpark

    if setExitEvent then
        setExitEvent(function()
            S.exitFlag = true
            pcall(function() if S.unpark then S.unpark() end end)
        end)
    end

    -- 主循环
    while not S.exitFlag do
        park()
    end

    -- === 3. 清理 ===
    runOnMainThread(function()
        pcall(function() windowManager:removeView(S.mainView) end)
        pcall(function() windowManager:removeView(S.ballView) end)
    end)
    -- 清理所有功能冻结项并恢复原始值
    pcall(function()
        for _, key in ipairs(featureOrder) do
            local feat = Features[key]
            if feat and (feat.frozenItems or feat.savedValues) then
                removePatch(feat)
            end
        end
    end)
    pcall(function()
        if S.mediaPlayer then
            S.mediaPlayer:stop()
            S.mediaPlayer:release()
            S.mediaPlayer = nil
        end
    end)
    gg.sleep(300)
end)

-- ========================================
-- 兜底清理
-- ========================================
pcall(function()
    runOnMainThread(function()
        if S.mainView then pcall(function() windowManager:removeView(S.mainView) end) end
        if S.ballView then pcall(function() windowManager:removeView(S.ballView) end) end
    end)
    -- 兜底：清理所有冻结项并恢复原始值
    pcall(function()
        for _, key in ipairs(featureOrder) do
            local feat = Features[key]
            if feat and (feat.frozenItems or feat.savedValues) then
                removePatch(feat)
            end
        end
    end)
    if S.mediaPlayer then
        S.mediaPlayer:stop()
        S.mediaPlayer:release()
        S.mediaPlayer = nil
    end
end)

pcall(function() gg.setVisible(true) end)
pcall(function() luajava.setFloatingWindowHide(false) end)

if not ok then
    pcall(function()
        gg.alert('悬浮窗错误:\n' .. tostring(err))
    end)
end
