--[[
    ============================================
    小志助手 v8.0  —  科技指挥中心 UI
    整合「像火.lua」功能
    偏移全部通过 dump.cs 验证（像素火影 v1.38）
    新 UI：赛博朋克风格 / 青色辉光边框 / 玻璃拟态卡片
          分类分组 + 药丸开关 + 彩色日志级别
          图标容器按分类着色（蓝/青/绿/橙）
    功能不变：视角/无敌/暴击/暴击倍率/无限火力/六豆
             移速/伤害/霸体/免伤/锁血/满能量/须佐持续
             自定义改值/清除自定义/复制角色地址
             一键全开/全关、6套风格、开发者密码模式
    ============================================
]]

local windowManager = app.context:getSystemService('window')
local threadManager = luajava.threadManager
local runOnMainThread = threadManager.runOnMainThread

-- ========================================
-- 主题配色（6套风格可切换）
-- ========================================
local Themes = {
    { -- 1. 科技蓝（默认，赛博朋克风）
        name = '科技蓝',
        primary      = 0xFF00D4FF,
        primaryDark  = 0xFF1890FF,
        primaryLight = 0xFF66E5FF,
        bgMain       = 0xFF0A0F1A,
        bgCard       = 0xFF111D2E,
        bgCardOn     = 0xFF1A2D44,
        bgNav        = 0xFF0F1923,
        bgLog        = 0xFF080D17,
        textPri      = 0xFFFFFFFF,
        textSec      = 0xFF8B9DC3,
        textHint     = 0xFF5A7A9A,
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
        primary      = 0xFF00C853,
        primaryDark  = 0xFF00695C,
        primaryLight = 0xFF69F0AE,
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
        primary      = 0xFFFF5252,
        primaryDark  = 0xFFC62828,
        primaryLight = 0xFFFF8A80,
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
        primary      = 0xFFFFD600,
        primaryDark  = 0xFFFF8F00,
        primaryLight = 0xFFFFE57F,
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
        primary      = 0xFF9E9E9E,
        primaryDark  = 0xFF616161,
        primaryLight = 0xFFE0E0E0,
        bgMain       = 0xFF000000,
        bgCard       = 0xFF141414,
        bgCardOn     = 0xFF222222,
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
    success   = 0xFF52C41A,
    warning   = 0xFFFAAD14,
    error     = 0xFFFF4D4F,
    toggleOff = 0xFF1A2D44,
}

-- 应用指定索引的主题（更新 T 的字段）
local function applyTheme(index)
    local theme = Themes[index]
    if not theme then return end
    for k in pairs(T) do T[k] = nil end
    for k, v in pairs(theme) do T[k] = v end
    for k, v in pairs(semanticColors) do T[k] = v end
end

-- 初始化为科技蓝主题
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
    customPatches = {},
    cameraAddr = nil,
    devUnlocked = false,
    currentTheme = 1,
    bgDrawable = nil,
    bgImagePath = nil,
    ballDrawable = nil,
    ballImagePath = nil,
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

-- 替换颜色的 Alpha 通道（alpha: 0x00~0xFF）
local function withAlpha(color, alpha)
    return (alpha * 0x1000000) + (color % 0x1000000)
end

-- 科技卡片 Drawable：渐变背景 + 辉光描边
local function techCard(bgColor1, bgColor2, strokeColor, radius)
    local g = GradientDrawable()
    g:setOrientation(GradientDrawable.Orientation.TL_BR)
    g:setColors({bgColor1, bgColor2})
    if strokeColor then
        g:setStroke(2, strokeColor)
    end
    if radius then g:setCornerRadius(radius) end
    return g
end

-- 科技卡片 StateList（普通 / 按压）
local function techCardState(n1, n2, ns, p1, p2, ps, radius)
    local sl = StateListDrawable()
    sl:addState({-android.R.attr.state_pressed}, techCard(n1, n2, ns, radius))
    sl:addState({android.R.attr.state_pressed}, techCard(p1, p2, ps, radius))
    return sl
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

-- 获取主背景 Drawable（图片优先，否则科技渐变 + 辉光边框）
local function getMainBgDrawable()
    if S.bgDrawable then
        return S.bgDrawable
    end
    local g = gradient({T.bgMain, T.bgNav}, 18, GradientDrawable.Orientation.TL_BR)
    g:setStroke(2, withAlpha(T.primary, 0x44))
    return g
end

-- 获取悬浮球背景 Drawable（图片优先，否则渐变）
local function getBallBgDrawable()
    if S.ballDrawable then
        return S.ballDrawable
    end
    return gradient({T.primary, T.primaryDark}, 60)
end

-- ========================================
-- 日志系统（彩色级别 HTML 渲染）
-- ========================================
local levelColors = {
    INFO    = '#00d4ff',
    SUCCESS = '#52c41a',
    WARN    = '#faad14',
    ERROR   = '#ff4d4f',
}

local logs = {}

local function renderLogs()
    if not S.logView then return end
    runOnMainThread(function()
        local ok, html = pcall(function()
            local Html = luajava.bindClass('android.text.Html')
            local h = ''
            local timeColor = string.format('#%06X', T.textHint % 0x1000000)
            local tagColor = string.format('#%06X', T.textSec % 0x1000000)
            local msgColor = string.format('#%06X', T.textPri % 0x1000000)
            for _, l in ipairs(logs) do
                local msg = l.msg:gsub('&', '&amp;'):gsub('<', '&lt;'):gsub('>', '&gt;')
                h = h .. string.format(
                    '<font color="%s">%s</font> <font color="%s"><b>[%s]</b></font> <font color="%s">[%s]</font> <font color="%s">%s</font><br>',
                    timeColor, l.time, l.color, l.level, tagColor, l.tag, msgColor, msg
                )
            end
            return Html:fromHtml(h)
        end)
        if ok and html then
            pcall(function() S.logView:setText(html) end)
        else
            -- 降级为纯文本
            pcall(function()
                local text = ''
                for _, l in ipairs(logs) do
                    text = text .. string.format('[%s] [%s] [%s] %s\n', l.time, l.level, l.tag, l.msg)
                end
                S.logView:setText(text)
            end)
        end
    end)
end

local function addLog(tag, msg, level)
    level = level or 'INFO'
    local time = os.date('%H:%M:%S')
    local color = levelColors[level] or '#00d4ff'
    table.insert(logs, 1, {time=time, tag=tag, msg=msg, level=level, color=color})
    if #logs > 50 then table.remove(logs) end
    renderLogs()
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
-- 前向声明
-- ========================================
local showMainPanel, showDevPanel
local setToggleVisual

-- ========================================
-- 搜索镜头地址
-- ========================================
local function findCameraAddr()
    if S.cameraAddr and S.cameraAddr ~= 0 then
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
    local savedCount = gg.getResultsCount()
    gg.clearResults()
    gg.searchNumber('8', gg.TYPE_FLOAT)
    local count = gg.getResultsCount()
    addLog('SEARCH', string.format('搜索到 %d 个结果', count), 'INFO')

    if count == 0 then
        addLog('SEARCH', '未找到原始镜头大小=8，请确保已进入战斗', 'ERROR')
        return nil
    end

    local maxCheck = math.min(count, 2000)
    local results = gg.getResults(maxCheck)

    for i, r in ipairs(results) do
        local addr = r.address
        local ok, checks = pcall(function()
            return gg.getValues({
                {address = addr + 8,  flags = 16},
                {address = addr + 16, flags = 16},
                {address = addr - 4,  flags = 16},
            })
        end)
        if ok and checks then
            local zoomMul = checks[1].value
            local zoomTimer = checks[2].value
            local slowScale = checks[3].value
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
            local oldVal = nil
            pcall(function()
                local r = gg.getValues({{address = addr, flags = p.flags}})
                if r and r[1] then oldVal = r[1].value end
            end)
            table.insert(feat.savedValues, {address = addr, flags = p.flags, value = oldVal})
            local item = {address = addr, flags = p.flags, value = p.value, freeze = true}
            gg.addListItems({item})
            table.insert(feat.frozenItems, item)
        end
    end
end

local function removePatch(feat)
    if feat.frozenItems and #feat.frozenItems > 0 then
        pcall(function() gg.removeListItems(feat.frozenItems) end)
    end
    if feat.restoreType ~= 'unfreeze' then
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
    feat.frozenItems = nil
    feat.savedValues = nil
end

-- ========================================
-- 功能定义（偏移全部通过 dump.cs 验证）
-- GG flags: 4=DWORD(int/bool), 16=FLOAT(float)
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

    viewAngle = {
        name = '改视角', desc = '修改镜头大小', icon = '◉',
        enabled = false,
        restoreValue = 8,
        patches = {
            { so = {"libil2cpp.so", "Cd"}, offset = {0xE0338, 0x530, 0x100, 0xF8}, is32 = true, flags = 16, value = 15 },
            { so = {"libil2cpp.so", "Cd"}, offset = {0xE0338, 0xB8, 0xF0, 0xF8}, is32 = true, flags = 16, value = 15 },
        }
    },

    invincible = {
        name = '无敌', desc = '免疫所有伤害', icon = '◈',
        enabled = false,
        restoreValue = 0,
        patches = {
            { so = {"libil2cpp.so:bss", "Cb"}, offset = {0x21DF88, 0x590, 0x250}, is32 = true, flags = 4, value = 1 },
            { so = {"libil2cpp.so:bss", "Cb"}, offset = {0x211990, 0x610, 0x590, 0x250}, is32 = true, flags = 4, value = 1 },
        }
    },

    crit = {
        name = '暴击率', desc = '暴击率 100%', icon = '★',
        enabled = false,
        restoreValue = 10,
        patches = {
            { so = {"libil2cpp.so:bss", "Cb"}, offset = {0x21DF88, 0x590, 0x164}, is32 = true, flags = 16, value = 100 },
            { so = {"libil2cpp.so:bss", "Cb"}, offset = {0x211990, 0x610, 0x590, 0x164}, is32 = true, flags = 16, value = 100 },
        }
    },

    critMulti = {
        name = '暴击倍率', desc = '暴击伤害 x50', icon = '✦',
        enabled = false,
        patches = {
            { so = {"libil2cpp.so:bss", "Cb"}, offset = {0x21DF88, 0x590, 0x168}, is32 = true, flags = 16, value = 50 },
            { so = {"libil2cpp.so:bss", "Cb"}, offset = {0x211990, 0x610, 0x590, 0x168}, is32 = true, flags = 16, value = 50 },
        }
    },

    infiniteFire = {
        name = '无限火力', desc = '全技能无冷却', icon = '⚡',
        enabled = false,
        restoreType = 'unfreeze',
        patches = {
            { so = {"libil2cpp.so:bss", "Cb"}, offset = {0x21DF88, 0x590, 0xA0}, is32 = true, flags = 16, value = 0 },
            { so = {"libil2cpp.so:bss", "Cb"}, offset = {0x211990, 0x610, 0x590, 0xA0}, is32 = true, flags = 16, value = 0 },
            { so = {"libil2cpp.so:bss", "Cb"}, offset = {0x21DF88, 0x590, 0xA4}, is32 = true, flags = 16, value = 0 },
            { so = {"libil2cpp.so:bss", "Cb"}, offset = {0x211990, 0x610, 0x590, 0xA4}, is32 = true, flags = 16, value = 0 },
            { so = {"libil2cpp.so:bss", "Cb"}, offset = {0x21DF88, 0x590, 0xA8}, is32 = true, flags = 16, value = 0 },
            { so = {"libil2cpp.so:bss", "Cb"}, offset = {0x211990, 0x610, 0x590, 0xA8}, is32 = true, flags = 16, value = 0 },
            { so = {"libil2cpp.so:bss", "Cb"}, offset = {0x21DF88, 0x590, 0xAC}, is32 = true, flags = 16, value = 0 },
            { so = {"libil2cpp.so:bss", "Cb"}, offset = {0x211990, 0x610, 0x590, 0xAC}, is32 = true, flags = 16, value = 0 },
            { so = {"libil2cpp.so:bss", "Cb"}, offset = {0x21DF88, 0x590, 0xB0}, is32 = true, flags = 16, value = 0 },
            { so = {"libil2cpp.so:bss", "Cb"}, offset = {0x211990, 0x610, 0x590, 0xB0}, is32 = true, flags = 16, value = 0 },
            { so = {"libil2cpp.so:bss", "Cb"}, offset = {0x21DF88, 0x590, 0xB4}, is32 = true, flags = 16, value = 0 },
            { so = {"libil2cpp.so:bss", "Cb"}, offset = {0x211990, 0x610, 0x590, 0xB4}, is32 = true, flags = 16, value = 0 },
        }
    },

    sixBean = {
        name = '六豆', desc = '奥义点数锁定 6', icon = '◆',
        enabled = false,
        restoreType = 'unfreeze',
        patches = {
            { so = {"libil2cpp.so:bss", "Cb"}, offset = {0x21DF88, 0x590, 0x90}, is32 = true, flags = 4, value = 6 },
            { so = {"libil2cpp.so:bss", "Cb"}, offset = {0x211990, 0x610, 0x590, 0x90}, is32 = true, flags = 4, value = 6 },
            { so = {"libil2cpp.so:bss", "Cb"}, offset = {0x21DF88, 0x590, 0x94}, is32 = true, flags = 4, value = 6 },
            { so = {"libil2cpp.so:bss", "Cb"}, offset = {0x211990, 0x610, 0x590, 0x94}, is32 = true, flags = 4, value = 6 },
            { so = {"libil2cpp.so:bss", "Cb"}, offset = {0x21DF88, 0x590, 0x98}, is32 = true, flags = 4, value = 6 },
            { so = {"libil2cpp.so:bss", "Cb"}, offset = {0x211990, 0x610, 0x590, 0x98}, is32 = true, flags = 4, value = 6 },
        }
    },

    moveSpeed = {
        name = '移速加速', desc = '移动速度大幅提升', icon = '➤',
        enabled = false,
        patches = {
            { so = {"libil2cpp.so:bss", "Cb"}, offset = {0x21DF88, 0x590, 0x140}, is32 = true, flags = 16, value = 20 },
            { so = {"libil2cpp.so:bss", "Cb"}, offset = {0x211990, 0x610, 0x590, 0x140}, is32 = true, flags = 16, value = 20 },
        }
    },

    damageBoost = {
        name = '伤害加成', desc = '所有伤害大幅提升', icon = '⚔',
        enabled = false,
        patches = {
            { so = {"libil2cpp.so:bss", "Cb"}, offset = {0x21DF88, 0x590, 0x160}, is32 = true, flags = 16, value = 10 },
            { so = {"libil2cpp.so:bss", "Cb"}, offset = {0x211990, 0x610, 0x590, 0x160}, is32 = true, flags = 16, value = 10 },
            { so = {"libil2cpp.so:bss", "Cb"}, offset = {0x21DF88, 0x590, 0x16C}, is32 = true, flags = 16, value = 10 },
            { so = {"libil2cpp.so:bss", "Cb"}, offset = {0x211990, 0x610, 0x590, 0x16C}, is32 = true, flags = 16, value = 10 },
            { so = {"libil2cpp.so:bss", "Cb"}, offset = {0x21DF88, 0x590, 0x170}, is32 = true, flags = 16, value = 10 },
            { so = {"libil2cpp.so:bss", "Cb"}, offset = {0x211990, 0x610, 0x590, 0x170}, is32 = true, flags = 16, value = 10 },
            { so = {"libil2cpp.so:bss", "Cb"}, offset = {0x21DF88, 0x590, 0x174}, is32 = true, flags = 16, value = 10 },
            { so = {"libil2cpp.so:bss", "Cb"}, offset = {0x211990, 0x610, 0x590, 0x174}, is32 = true, flags = 16, value = 10 },
            { so = {"libil2cpp.so:bss", "Cb"}, offset = {0x21DF88, 0x590, 0x178}, is32 = true, flags = 16, value = 10 },
            { so = {"libil2cpp.so:bss", "Cb"}, offset = {0x211990, 0x610, 0x590, 0x178}, is32 = true, flags = 16, value = 10 },
        }
    },

    superArmor = {
        name = '霸体', desc = '免疫击退击飞', icon = '🛡',
        enabled = false,
        restoreValue = 0,
        patches = {
            { so = {"libil2cpp.so:bss", "Cb"}, offset = {0x21DF88, 0x590, 0x26C}, is32 = true, flags = 4, value = 1 },
            { so = {"libil2cpp.so:bss", "Cb"}, offset = {0x211990, 0x610, 0x590, 0x26C}, is32 = true, flags = 4, value = 1 },
            { so = {"libil2cpp.so:bss", "Cb"}, offset = {0x21DF88, 0x590, 0x268}, is32 = true, flags = 4, value = 999 },
            { so = {"libil2cpp.so:bss", "Cb"}, offset = {0x211990, 0x610, 0x590, 0x268}, is32 = true, flags = 4, value = 999 },
        }
    },

    damageReduce = {
        name = '免伤', desc = '受到伤害减少 100%', icon = '◍',
        enabled = false,
        patches = {
            { so = {"libil2cpp.so:bss", "Cb"}, offset = {0x21DF88, 0x590, 0x1E4}, is32 = true, flags = 16, value = 1 },
            { so = {"libil2cpp.so:bss", "Cb"}, offset = {0x211990, 0x610, 0x590, 0x1E4}, is32 = true, flags = 16, value = 1 },
        }
    },

    fullHP = {
        name = '锁血', desc = '血量锁定 99999', icon = '❤',
        enabled = false,
        patches = {
            { so = {"libil2cpp.so:bss", "Cb"}, offset = {0x21DF88, 0x590, 0x84}, is32 = true, flags = 4, value = 99999 },
            { so = {"libil2cpp.so:bss", "Cb"}, offset = {0x211990, 0x610, 0x590, 0x84}, is32 = true, flags = 4, value = 99999 },
            { so = {"libil2cpp.so:bss", "Cb"}, offset = {0x21DF88, 0x590, 0x80}, is32 = true, flags = 4, value = 99999 },
            { so = {"libil2cpp.so:bss", "Cb"}, offset = {0x211990, 0x610, 0x590, 0x80}, is32 = true, flags = 4, value = 99999 },
        }
    },

    fullEnergy = {
        name = '满能量', desc = '能量锁定 100', icon = '⚡',
        enabled = false,
        patches = {
            { so = {"libil2cpp.so:bss", "Cb"}, offset = {0x21DF88, 0x590, 0x88}, is32 = true, flags = 16, value = 100 },
            { so = {"libil2cpp.so:bss", "Cb"}, offset = {0x211990, 0x610, 0x590, 0x88}, is32 = true, flags = 16, value = 100 },
            { so = {"libil2cpp.so:bss", "Cb"}, offset = {0x21DF88, 0x590, 0x8C}, is32 = true, flags = 16, value = 100 },
            { so = {"libil2cpp.so:bss", "Cb"}, offset = {0x211990, 0x610, 0x590, 0x8C}, is32 = true, flags = 16, value = 100 },
        }
    },

    susanoo = {
        name = '须佐持续', desc = '解斑须佐持续时间改10', icon = '🌀',
        enabled = false,
        patches = {
            { so = {"libil2cpp.so:bss", "Cb"}, offset = {0x21DF88, 0x590, 0x358}, is32 = true, flags = 16, value = 10 },
            { so = {"libil2cpp.so:bss", "Cb"}, offset = {0x211990, 0x610, 0x590, 0x358}, is32 = true, flags = 16, value = 10 },
        }
    },

    customMod = {
        name = '自定义改值', desc = '填实例地址+偏移修改', icon = '🔧',
        isButton = true,
        exec = function()
            local input = gg.prompt({
                '[1] 实例地址(如 0x12345678, 可从复制角色地址获取)',
                '[2] 偏移量(如 0x164, 十六进制)',
                '[3] 写入数值',
                '[4] 类型: 4=整数(DWORD) 16=浮点(FLOAT)',
                '[5] 是否冻结: 1=冻结 0=不冻结',
            }, {
                '0x0', '0x164', '100', '16', '1',
            }, {'text', 'text', 'text', 'text', 'text'})
            if not input then return end
            local baseAddr = tonumber(input[1]) or 0
            if baseAddr == 0 then
                addLog('CUSTOM', '实例地址无效', 'ERROR')
                gg.toast('实例地址无效')
                return
            end
            local offset = tonumber(input[2]) or 0
            local addr = baseAddr + offset
            local val = tonumber(input[3]) or 0
            local flagsNum = tonumber(input[4]) or 16
            local doFreeze = (input[5] == '1')
            local oldVal = nil
            pcall(function()
                local r = gg.getValues({{address = addr, flags = flagsNum}})
                if r and r[1] then oldVal = r[1].value end
            end)
            if doFreeze then
                gg.addListItems({{address = addr, flags = flagsNum, value = val, freeze = true}})
            else
                gg.setValues({{address = addr, flags = flagsNum, value = val}})
            end
            if not S.customPatches then S.customPatches = {} end
            table.insert(S.customPatches, {
                address = addr, flags = flagsNum, oldValue = oldVal, frozen = doFreeze,
                desc = string.format('0x%X+0x%X → %s (%s)', baseAddr, offset, input[3],
                    doFreeze and '冻结' or '不冻结'),
            })
            local typeStr = (flagsNum == 16) and 'FLOAT' or 'DWORD'
            addLog('CUSTOM', string.format('[%s] 0x%X+0x%X=0x%X → %s %s',
                typeStr, baseAddr, offset, addr, input[3], doFreeze and '(冻结)' or ''), 'SUCCESS')
            gg.toast(string.format('已写入 0x%X = %s', addr, input[3]))
        end
    },

    customClear = {
        name = '清除自定义', desc = '恢复所有自定义修改', icon = '🗑',
        isButton = true,
        exec = function()
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
            if #frozenItems > 0 then
                pcall(function() gg.removeListItems(frozenItems) end)
            end
            if #restoreVals > 0 then
                pcall(function() gg.setValues(restoreVals) end)
            end
            local count = #S.customPatches
            S.customPatches = {}
            addLog('CUSTOM', string.format('已清除 %d 个自定义修改', count), 'WARN')
            gg.toast(string.format('已清除 %d 个自定义修改', count))
        end
    },

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
                    runOnMainThread(function()
                        pcall(function() setToggleVisual(k, true) end)
                    end)
                end
            end
            addLog('FUNC', '一键全开完成', 'SUCCESS')
            pcall(function() gg.toast('全部功能已开启') end)
        end
    },

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
                    runOnMainThread(function()
                        pcall(function() setToggleVisual(k, false) end)
                    end)
                end
            end
            addLog('FUNC', '一键全关完成', 'WARN')
            pcall(function() gg.toast('全部功能已关闭') end)
        end
    },

    devMode = {
        name = '开发者模式', desc = '需要密码解锁高级功能', icon = '🔐',
        isButton = true,
        exec = function()
            if S.devUnlocked then
                S.devUnlocked = false
                gg.toast('开发者模式已关闭')
                addLog('DEV', '开发者模式已关闭', 'WARN')
                if showMainPanel then showMainPanel() end
            else
                local input = gg.prompt({'请输入开发者密码:'}, {'', }, {'text'})
                if not input then return end
                if input[1] == '085236qw' then
                    S.devUnlocked = true
                    gg.toast('密码正确，开发者模式已开启')
                    addLog('DEV', '密码正确，开发者模式已开启', 'SUCCESS')
                    if showDevPanel then showDevPanel() end
                else
                    gg.toast('密码错误')
                    addLog('DEV', '密码错误', 'ERROR')
                end
            end
        end
    },

    copyCharAddr = {
        name = '复制角色地址', desc = '获取并复制Character实例地址', icon = '📋',
        isButton = true,
        exec = function()
            local offsetInv = 0x250
            local addrInvP1 = S_Pointer({"libil2cpp.so:bss", "Cb"}, {0x21DF88, 0x590, offsetInv}, true)
            local addrInvP2 = S_Pointer({"libil2cpp.so:bss", "Cb"}, {0x211990, 0x610, 0x590, offsetInv}, true)
            addLog('ADDR', string.format('无敌字段地址 P1=%s P2=%s',
                tostring(addrInvP1), tostring(addrInvP2)), 'INFO')
            local addrP1, addrP2 = nil, nil
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

    devBack = {
        name = '返回主界面', desc = '退出开发者界面', icon = '←',
        isButton = true,
        exec = function()
            S.devUnlocked = false
            if showMainPanel then showMainPanel() end
            addLog('DEV', '已退出开发者界面', 'WARN')
            pcall(function() gg.toast('已返回主界面') end)
        end
    },
}

-- ========================================
-- 面板分组定义（新 UI：分类分区 + 分类着色）
-- glowKey 指定该分区图标容器的发光色（取自主题表）
-- ========================================
local mainPanelSections = {
    { title = '系 统',     glowKey = 'primaryDark', keys = {'selectProcess'} },
    { title = '战 斗 增 强', glowKey = 'primary',     keys = {'viewAngle','invincible','crit','critMulti','infiniteFire','sixBean',
                                    'moveSpeed','damageBoost','superArmor','damageReduce','fullHP','fullEnergy','susanoo'} },
    { title = '快 捷 操 作', glowKey = 'success',     keys = {'allInOne','allOff'} },
    { title = '高 级',     glowKey = 'warning',      keys = {'devMode'} },
}

local devPanelSections = {
    { title = '开 发 者 工 具', glowKey = 'primary',     keys = {'customMod','customClear','copyCharAddr'} },
    { title = '导 航',          glowKey = 'primaryDark', keys = {'devBack'} },
}

-- 兼容旧引用
local featureOrder = {
    'selectProcess',
    'viewAngle', 'invincible', 'crit', 'critMulti',
    'infiniteFire', 'sixBean',
    'moveSpeed', 'damageBoost', 'superArmor', 'damageReduce',
    'fullHP', 'fullEnergy', 'susanoo',
    'allInOne', 'allOff',
    'devMode',
}
local devFeatureOrder = {
    'customMod', 'customClear',
    'copyCharAddr',
    'devBack',
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
for _, key in ipairs(devFeatureOrder) do
    if not IDS['card_' .. key] then
        IDS['card_' .. key] = luajava.newId('card_' .. key)
        IDS['toggle_' .. key] = luajava.newId('toggle_' .. key)
    end
end

-- ========================================
-- 统一设置开关视觉效果（科技药丸开关）
-- ========================================
setToggleVisual = function(key, enabled)
    local tv = getView(IDS['toggle_' .. key])
    local cv = getView(IDS['card_' .. key])
    if tv then
        tv:setText(enabled and 'ON' or 'OFF')
        tv:setTextColor(enabled and 0xFFFFFFFF or T.textHint)
        if enabled then
            -- 开启：青色渐变药丸 + 辉光
            tv:setBackgroundDrawable(gradient({T.primary, T.primaryDark}, 24))
        else
            -- 关闭：暗色药丸 + 微弱描边
            tv:setBackgroundDrawable(techCard(T.toggleOff, T.bgCard, withAlpha(T.primary, 0x22), 24))
        end
    end
    if cv then
        if enabled then
            -- 开启：更亮背景 + 强辉光描边
            cv:setBackgroundDrawable(techCardState(
                T.bgCardOn, T.bgCard, withAlpha(T.primary, 0x66),
                T.bgCardOn, T.bgCardOn, withAlpha(T.primary, 0x99),
                16
            ))
        else
            -- 关闭：正常背景 + 微弱描边
            cv:setBackgroundDrawable(techCardState(
                T.bgCard, T.bgNav, withAlpha(T.primary, 0x22),
                T.bgCardOn, T.bgCard, withAlpha(T.primary, 0x44),
                16
            ))
        end
    end
end

-- ========================================
-- 切换功能开关
-- ========================================
local function updateToggle(key)
    local feat = Features[key]
    if not feat or feat.isButton then return end

    feat.enabled = not feat.enabled

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
        removePatch(feat)
        addLog('FUNC', feat.name .. ' 已关闭', 'WARN')
        pcall(function() gg.toast(feat.name .. ' 已关闭') end)
    end

    runOnMainThread(function()
        pcall(function() setToggleVisual(key, feat.enabled) end)
    end)
end

-- ========================================
-- 构建分类小标题（科技风：装饰条 + 渐变线）
-- ========================================
local function buildSectionHeader(title)
    return {
        LinearLayout,
        layout_width = 'match_parent',
        layout_height = 'wrap_content',
        orientation = 'horizontal',
        gravity = 'center_vertical',
        layout_marginTop = '14dp',
        layout_marginBottom = '4dp',
        layout_marginLeft = '4dp',
        {
            View, layout_width = '3dp', layout_height = '16dp',
            background = gradient({T.primaryLight, T.primary}, 2, GradientDrawable.Orientation.TOP_BOTTOM),
            layout_marginRight = '8dp',
        },
        {
            TextView, text = title, textSize = '13sp',
            textColor = T.primary, textStyle = 'bold',
        },
        {
            View, layout_width = 'match_parent', layout_height = '1dp',
            background = gradient({withAlpha(T.primary, 0x33), withAlpha(T.primary, 0x08)}, 0, GradientDrawable.Orientation.LEFT_RIGHT),
            layout_marginLeft = '10dp',
        }
    }
end

-- ========================================
-- 构建功能卡片（科技风：辉光描边 + 发光图标容器）
-- ========================================
local function buildCard(key, glowColor)
    local feat = Features[key]
    if not feat then return end

    local rightElem
    if feat.isButton then
        rightElem = {
            TextView, text = '›', textSize = '24sp',
            textColor = T.textHint,
            layout_width = '30dp', layout_height = '30dp', gravity = 'center',
        }
    else
        rightElem = {
            TextView, id = IDS['toggle_' .. key],
            text = 'OFF', textSize = '12sp',
            textColor = T.textHint, textStyle = 'bold',
            gravity = 'center',
            padding = '8dp',
            minWidth = '52dp',
            background = techCard(T.toggleOff, T.bgCard, withAlpha(T.primary, 0x22), 24),
        }
    end

    local gc = glowColor or T.primary

    return {
        LinearLayout,
        id = IDS['card_' .. key],
        layout_width = 'match_parent',
        layout_height = 'wrap_content',
        layout_margin = '5dp',
        orientation = 'horizontal',
        gravity = 'center_vertical',
        padding = '13dp',
        background = techCardState(
            T.bgCard, T.bgNav, withAlpha(T.primary, 0x22),
            T.bgCardOn, T.bgCard, withAlpha(T.primary, 0x44),
            16
        ),
        onClick = function()
            if feat.isButton then
                pcall(feat.exec)
            else
                pcall(function() updateToggle(key) end)
            end
        end,
        -- 左侧装饰条（分类色渐变）
        {
            View, layout_width = '3dp', layout_height = '34dp',
            background = gradient({gc, withAlpha(gc, 0x44)}, 2, GradientDrawable.Orientation.TOP_BOTTOM),
            layout_marginRight = '11dp',
        },
        -- 图标容器（发光效果：半透明分类色背景 + 描边）
        {
            LinearLayout,
            layout_width = '38dp', layout_height = '38dp',
            gravity = 'center',
            background = techCard(withAlpha(gc, 0x26), withAlpha(gc, 0x11), withAlpha(gc, 0x33), 10),
            layout_marginRight = '11dp',
            {
                TextView, text = feat.icon, textSize = '19sp',
                textColor = gc,
            }
        },
        -- 文字
        {
            LinearLayout,
            layout_width = '0dp', layout_weight = 1,
            layout_height = 'wrap_content', orientation = 'vertical',
            {
                TextView, text = feat.name, textSize = '16sp',
                textColor = T.textPri, textStyle = 'bold',
            },
            {
                TextView, text = feat.desc, textSize = '12sp',
                textColor = T.textHint, layout_marginTop = '2dp',
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
-- 面板切换：主界面 / 开发者界面
-- ========================================
local function clearContentContainer()
    if S.contentContainer then
        pcall(function() S.contentContainer:removeAllViews() end)
    end
end

-- 按分区填充功能卡片（传入分类发光色）
local function fillPanel(sections)
    if not S.contentContainer then return end
    for _, sec in ipairs(sections) do
        local glow = T[sec.glowKey] or T.primary
        pcall(function()
            luajava.loadlayout(buildSectionHeader(sec.title), nil, S.contentContainer)
        end)
        for _, key in ipairs(sec.keys) do
            pcall(function()
                luajava.loadlayout(buildCard(key, glow), nil, S.contentContainer)
            end)
        end
    end
end

-- 恢复主界面所有开关状态
local function restoreMainToggles()
    for _, key in ipairs(featureOrder) do
        local feat = Features[key]
        if feat and not feat.isButton and feat.enabled then
            pcall(function() setToggleVisual(key, true) end)
        end
    end
end

-- 显示主界面
showMainPanel = function()
    runOnMainThread(function()
        pcall(function()
            clearContentContainer()
            fillPanel(mainPanelSections)
            restoreMainToggles()
            local pt = getView(IDS.pageTitle)
            if pt then pt:setText('小志助手') end
        end)
    end)
    addLog('UI', '已切换到主界面', 'INFO')
end

-- 显示开发者界面
showDevPanel = function()
    runOnMainThread(function()
        pcall(function()
            clearContentContainer()
            fillPanel(devPanelSections)
            local pt = getView(IDS.pageTitle)
            if pt then pt:setText('开发者工具') end
        end)
    end)
    addLog('UI', '已切换到开发者界面', 'INFO')
end

-- ========================================
-- 前向声明
-- ========================================
local switchTheme

-- ========================================
-- 构建风格选项栏（科技药丸）
-- ========================================
local function buildStyleBar()
    local inner = {
        LinearLayout,
        layout_width = 'wrap_content',
        layout_height = 'wrap_content',
        orientation = 'horizontal',
        padding = '4dp',
    }
    for i, theme in ipairs(Themes) do
        local isActive = (i == S.currentTheme)
        local tab = {
            TextView,
            text = theme.name,
            textSize = '13sp',
            textColor = isActive and 0xFFFFFFFF or T.textHint,
            padding = '10dp',
            layout_margin = '3dp',
            gravity = 'center',
            onClick = function()
                if i ~= S.currentTheme then
                    switchTheme(i)
                end
            end,
        }
        if isActive then
            tab.textStyle = 'bold'
            tab.background = gradient({T.primary, T.primaryDark}, 20)
        else
            tab.background = techCard(T.bgCard, T.bgNav, withAlpha(T.primary, 0x22), 20)
        end
        inner[#inner + 1] = tab
    end
    return {
        HorizontalScrollView,
        layout_width = 'match_parent',
        layout_height = 'wrap_content',
        scrollbars = 'none',
        layout_marginTop = '2dp',
        inner
    }
end

-- ========================================
-- 构建主窗口布局（科技指挥中心风格）
-- ========================================
local function buildMainLayout()
    return {
        LinearLayout,
        layout_width = 'match_parent',
        layout_height = 'match_parent',
        orientation = 'vertical',
        background = getMainBgDrawable(),
        {
            -- 标题栏（渐变 + 底部辉光线）
            LinearLayout,
            id = IDS.titleBar,
            layout_width = 'match_parent',
            layout_height = 'wrap_content',
            orientation = 'vertical',
            {
                LinearLayout,
                layout_width = 'match_parent',
                layout_height = 'wrap_content',
                orientation = 'horizontal',
                gravity = 'center_vertical',
                padding = '14dp',
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
                    layout_width = '40dp', layout_height = '40dp',
                    gravity = 'center',
                    background = gradient({0xFFFFFFFF, 0xFFB3E5FF}, 12),
                    {
                        TextView, text = '志', textSize = '19sp',
                        textColor = T.primaryDark, textStyle = 'bold',
                    }
                },
                {
                    LinearLayout,
                    layout_width = '0dp', layout_weight = 1,
                    layout_height = 'wrap_content', orientation = 'vertical',
                    layout_marginLeft = '12dp',
                    {
                        TextView, id = IDS.pageTitle, text = '小志助手',
                        textSize = '18sp', textColor = 0xFFFFFFFF, textStyle = 'bold',
                    },
                    {
                        TextView, text = 'v8.0 · 科技指挥中心', textSize = '11sp',
                        textColor = 0xCCFFFFFF, layout_marginTop = '1dp',
                    }
                },
                {
                    TextView, id = IDS.minimizeBtn, text = '—',
                    textSize = '18sp', textColor = 0xCCFFFFFF,
                    layout_width = '36dp', layout_height = '36dp', gravity = 'center',
                    background = stateList(0x20FFFFFF, 0x40FFFFFF, 10),
                    onClick = function() pcall(minimize) end,
                },
                {
                    TextView, id = IDS.closeBtn, text = '✕',
                    layout_marginLeft = '8dp',
                    textSize = '17sp', textColor = 0xFFFFCDD2,
                    layout_width = '36dp', layout_height = '36dp', gravity = 'center',
                    background = stateList(0x20FF0000, 0x40FF0000, 10),
                    onClick = function()
                        local confirm = gg.alert('是否退出小志助手？', '确定退出', '取消')
                        if confirm == 1 then
                            addLog('UI', '正在退出...', 'WARN')
                            S.exitFlag = true
                            pcall(function() if S.unpark then S.unpark() end end)
                        end
                    end,
                },
            },
            -- 底部辉光分割线
            {
                View, layout_width = 'match_parent', layout_height = '2dp',
                background = gradient({withAlpha(T.primary, 0x66), withAlpha(T.primary, 0x11)}, 0, GradientDrawable.Orientation.LEFT_RIGHT),
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
                padding = '8dp',
            }
        },
        -- 分隔线
        {
            View, layout_width = 'match_parent', layout_height = '1dp',
            backgroundColor = 0x18FFFFFF,
        },
        -- 日志面板（科技风：状态点 + 彩色级别）
        {
            LinearLayout,
            layout_width = 'match_parent',
            layout_height = '110dp',
            orientation = 'vertical',
            padding = '8dp',
            background = gradient({T.bgLog, T.bgMain}, 0),
            {
                LinearLayout,
                layout_width = 'match_parent',
                layout_height = 'wrap_content',
                orientation = 'horizontal',
                gravity = 'center_vertical',
                layout_marginBottom = '3dp',
                {
                    View, layout_width = '7dp', layout_height = '7dp',
                    background = gradient({T.success, T.success}, 4),
                    layout_marginRight = '6dp',
                },
                {
                    TextView, text = '运行日志', textSize = '12sp',
                    textColor = T.textSec, textStyle = 'bold',
                },
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
-- 构建悬浮球 (120dp)
-- ========================================
local function buildBallLayout()
    if S.ballDrawable then
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
                TextView, text = '志', textSize = '40sp',
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

    applyTheme(index)
    S.currentTheme = index

    runOnMainThread(function()
        pcall(function()
            windowManager:removeView(S.mainView)

            S.mainView = luajava.loadlayout(buildMainLayout())
            S.logView = getView(IDS.logView)
            S.contentContainer = getView(IDS.contentContainer)

            if S.contentContainer then
                local sections = S.devUnlocked and devPanelSections or mainPanelSections
                fillPanel(sections)
            end

            if not S.devUnlocked then
                restoreMainToggles()
            end

            local pt = getView(IDS.pageTitle)
            if pt then
                pt:setText(S.devUnlocked and '开发者工具' or '小志助手')
            end

            -- 重新渲染日志（使用新主题颜色）
            renderLogs()

            windowManager:addView(S.mainView, S.mainParams)

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
        '🎨  默认（科技渐变背景）',
    }, 1, '请选择悬浮窗背景模式')

    if modeChoice == 1 then
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
        S.bgDrawable = nil
        S.bgImagePath = nil
    end

    -- === 0.5 悬浮球图片选择 ===
    local ballChoice = gg.choice({
        '🖼  自选悬浮球图片',
        '🔵  默认悬浮球（渐变）',
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
        local dm = app.context:getResources():getDisplayMetrics()
        local winW = math.floor(dm.widthPixels * 0.88)
        local winH = math.floor(dm.heightPixels * 0.75)

        S.mainParams = newParams(winW, winH)
        S.mainView = luajava.loadlayout(buildMainLayout())

        S.logView = getView(IDS.logView)
        S.contentContainer = getView(IDS.contentContainer)

        if S.contentContainer then
            fillPanel(mainPanelSections)
        end

        S.ballParams = newParams(120, 120)
        S.ballView = luajava.loadlayout(buildBallLayout())

        windowManager:addView(S.mainView, S.mainParams)
    end)

    gg.sleep(500)

    addLog('SYSTEM', '小志助手已启动 v8.0 科技指挥中心', 'SUCCESS')
    addLog('SYSTEM', '偏移已通过 dump.cs 验证')
    addLog('SYSTEM', '6套风格可切换: 科技蓝/暗紫/暗绿/暗红/暗金/纯黑')
    if S.bgDrawable then
        addLog('SYSTEM', '背景模式: 自选图片')
    else
        addLog('SYSTEM', '背景模式: 科技渐变')
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

    while not S.exitFlag do
        park()
    end

    -- === 3. 清理 ===
    runOnMainThread(function()
        pcall(function() windowManager:removeView(S.mainView) end)
        pcall(function() windowManager:removeView(S.ballView) end)
    end)
    pcall(function()
        for _, key in ipairs(featureOrder) do
            local feat = Features[key]
            if feat and (feat.frozenItems or feat.savedValues) then
                removePatch(feat)
            end
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
    pcall(function()
        for _, key in ipairs(featureOrder) do
            local feat = Features[key]
            if feat and (feat.frozenItems or feat.savedValues) then
                removePatch(feat)
            end
        end
    end)
end)

pcall(function() gg.setVisible(true) end)
pcall(function() luajava.setFloatingWindowHide(false) end)

if not ok then
    pcall(function()
        gg.alert('悬浮窗错误:\n' .. tostring(err))
    end)
end
