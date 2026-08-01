elgg.import("AlGui")

import "irene.window.algui.AlGuiData"
import "irene.window.algui.AlGuiDialogBox"
import "irene.window.algui.AlGuiSoundEffect"
import "irene.window.algui.AlGuiWindowView"
import "android.view.Gravity"
import "android.graphics.Typeface"

-- ============================================
-- 小志助手 v9.1 — 末日科技风格 UI (AlGui)
-- 功能：视角/无敌/暴击/暴击倍率/无限火力/六豆
--       移速/伤害/霸体/免伤/锁血/满能量/须佐持续
--       自定义改值/清除自定义/复制角色地址
--       一键全开/全关、开发者密码模式
--       锁链地址整合查看
-- 偏移全部通过 dump.cs 验证（像素火影 v1.38）
-- ============================================

-- 隐藏 GG 图标
pcall(function() gg.setVisible(false) end)

-- ========================================
-- 共享状态
-- ========================================
local S = {
    devUnlocked = false,
    customPatches = {},
    cameraAddr = nil,
    -- 全局锁链地址整合表
    allFrozenAddrs = {},
}

-- ========================================
-- 日志系统
-- ========================================
local function log(msg, level)
    level = level or 'INFO'
    local prefix = '[' .. level .. '] '
    pcall(function() print(prefix .. msg) end)
end

-- ========================================
-- 通知快捷函数
-- ========================================
local function notify(title, msg, titleColor)
    titleColor = titleColor or 0xFFAA0000
    pcall(function()
        if Inform then
            Inform.showCustomizeNotification(
                0xFF121212, null, 0,
                title, titleColor,
                msg, 0xFF909090,
                2500
            )
        end
    end)
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
-- 内存补丁：执行 / 移除
-- ========================================
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
            -- 记录到全局锁链地址表
            table.insert(S.allFrozenAddrs, {
                featName = feat.name,
                address = addr,
                flags = p.flags,
                value = p.value,
            })
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
    -- 从全局锁链地址表移除该功能的地址
    for i = #S.allFrozenAddrs, 1, -1 do
        if S.allFrozenAddrs[i].featName == feat.name then
            table.remove(S.allFrozenAddrs, i)
        end
    end
end

-- ========================================
-- 功能定义（偏移全部通过 dump.cs 验证）
-- GG flags: 4=DWORD(int/bool), 16=FLOAT(float)
-- ========================================
local Features = {
    -- ===== 改视角 =====
    viewAngle = {
        name = '改视角', desc = '修改镜头大小',
        enabled = false, restoreValue = 8,
        patches = {
            { so = {"libil2cpp.so", "Cd"}, offset = {0xE0338, 0x530, 0x100, 0xF8}, is32 = true, flags = 16, value = 15 },
            { so = {"libil2cpp.so", "Cd"}, offset = {0xE0338, 0xB8, 0xF0, 0xF8}, is32 = true, flags = 16, value = 15 },
        }
    },
    -- ===== 无敌 =====
    invincible = {
        name = '无敌', desc = '免疫所有伤害',
        enabled = false, restoreValue = 0,
        patches = {
            { so = {"libil2cpp.so:bss", "Cb"}, offset = {0x21DF88, 0x590, 0x250}, is32 = true, flags = 4, value = 1 },
            { so = {"libil2cpp.so:bss", "Cb"}, offset = {0x211990, 0x610, 0x590, 0x250}, is32 = true, flags = 4, value = 1 },
        }
    },
    -- ===== 暴击率 =====
    crit = {
        name = '暴击率', desc = '暴击率 100%',
        enabled = false, restoreValue = 10,
        patches = {
            { so = {"libil2cpp.so:bss", "Cb"}, offset = {0x21DF88, 0x590, 0x164}, is32 = true, flags = 16, value = 100 },
            { so = {"libil2cpp.so:bss", "Cb"}, offset = {0x211990, 0x610, 0x590, 0x164}, is32 = true, flags = 16, value = 100 },
        }
    },
    -- ===== 暴击倍率 =====
    critMulti = {
        name = '暴击倍率', desc = '暴击伤害 x50',
        enabled = false,
        patches = {
            { so = {"libil2cpp.so:bss", "Cb"}, offset = {0x21DF88, 0x590, 0x168}, is32 = true, flags = 16, value = 50 },
            { so = {"libil2cpp.so:bss", "Cb"}, offset = {0x211990, 0x610, 0x590, 0x168}, is32 = true, flags = 16, value = 50 },
        }
    },
    -- ===== 无限火力 =====
    infiniteFire = {
        name = '无限火力', desc = '全技能无冷却',
        enabled = false, restoreType = 'unfreeze',
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
    -- ===== 六豆 =====
    sixBean = {
        name = '六豆', desc = '奥义点数锁定 6',
        enabled = false, restoreType = 'unfreeze',
        patches = {
            { so = {"libil2cpp.so:bss", "Cb"}, offset = {0x21DF88, 0x590, 0x90}, is32 = true, flags = 4, value = 6 },
            { so = {"libil2cpp.so:bss", "Cb"}, offset = {0x211990, 0x610, 0x590, 0x90}, is32 = true, flags = 4, value = 6 },
            { so = {"libil2cpp.so:bss", "Cb"}, offset = {0x21DF88, 0x590, 0x94}, is32 = true, flags = 4, value = 6 },
            { so = {"libil2cpp.so:bss", "Cb"}, offset = {0x211990, 0x610, 0x590, 0x94}, is32 = true, flags = 4, value = 6 },
            { so = {"libil2cpp.so:bss", "Cb"}, offset = {0x21DF88, 0x590, 0x98}, is32 = true, flags = 4, value = 6 },
            { so = {"libil2cpp.so:bss", "Cb"}, offset = {0x211990, 0x610, 0x590, 0x98}, is32 = true, flags = 4, value = 6 },
        }
    },
    -- ===== 移速加速 =====
    moveSpeed = {
        name = '移速加速', desc = '移动速度大幅提升',
        enabled = false,
        patches = {
            { so = {"libil2cpp.so:bss", "Cb"}, offset = {0x21DF88, 0x590, 0x140}, is32 = true, flags = 16, value = 20 },
            { so = {"libil2cpp.so:bss", "Cb"}, offset = {0x211990, 0x610, 0x590, 0x140}, is32 = true, flags = 16, value = 20 },
        }
    },
    -- ===== 伤害加成 =====
    damageBoost = {
        name = '伤害加成', desc = '所有伤害大幅提升',
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
    -- ===== 霸体 =====
    superArmor = {
        name = '霸体', desc = '免疫击退击飞',
        enabled = false, restoreValue = 0,
        patches = {
            { so = {"libil2cpp.so:bss", "Cb"}, offset = {0x21DF88, 0x590, 0x26C}, is32 = true, flags = 4, value = 1 },
            { so = {"libil2cpp.so:bss", "Cb"}, offset = {0x211990, 0x610, 0x590, 0x26C}, is32 = true, flags = 4, value = 1 },
            { so = {"libil2cpp.so:bss", "Cb"}, offset = {0x21DF88, 0x590, 0x268}, is32 = true, flags = 4, value = 999 },
            { so = {"libil2cpp.so:bss", "Cb"}, offset = {0x211990, 0x610, 0x590, 0x268}, is32 = true, flags = 4, value = 999 },
        }
    },
    -- ===== 免伤 =====
    damageReduce = {
        name = '免伤', desc = '受到伤害减少 100%',
        enabled = false,
        patches = {
            { so = {"libil2cpp.so:bss", "Cb"}, offset = {0x21DF88, 0x590, 0x1E4}, is32 = true, flags = 16, value = 1 },
            { so = {"libil2cpp.so:bss", "Cb"}, offset = {0x211990, 0x610, 0x590, 0x1E4}, is32 = true, flags = 16, value = 1 },
        }
    },
    -- ===== 锁血 =====
    fullHP = {
        name = '锁血', desc = '血量锁定 99999',
        enabled = false,
        patches = {
            { so = {"libil2cpp.so:bss", "Cb"}, offset = {0x21DF88, 0x590, 0x84}, is32 = true, flags = 4, value = 99999 },
            { so = {"libil2cpp.so:bss", "Cb"}, offset = {0x211990, 0x610, 0x590, 0x84}, is32 = true, flags = 4, value = 99999 },
            { so = {"libil2cpp.so:bss", "Cb"}, offset = {0x21DF88, 0x590, 0x80}, is32 = true, flags = 4, value = 99999 },
            { so = {"libil2cpp.so:bss", "Cb"}, offset = {0x211990, 0x610, 0x590, 0x80}, is32 = true, flags = 4, value = 99999 },
        }
    },
    -- ===== 满能量 =====
    fullEnergy = {
        name = '满能量', desc = '能量锁定 100',
        enabled = false,
        patches = {
            { so = {"libil2cpp.so:bss", "Cb"}, offset = {0x21DF88, 0x590, 0x88}, is32 = true, flags = 16, value = 100 },
            { so = {"libil2cpp.so:bss", "Cb"}, offset = {0x211990, 0x610, 0x590, 0x88}, is32 = true, flags = 16, value = 100 },
            { so = {"libil2cpp.so:bss", "Cb"}, offset = {0x21DF88, 0x590, 0x8C}, is32 = true, flags = 16, value = 100 },
            { so = {"libil2cpp.so:bss", "Cb"}, offset = {0x211990, 0x610, 0x590, 0x8C}, is32 = true, flags = 16, value = 100 },
        }
    },
    -- ===== 须佐持续 =====
    susanoo = {
        name = '须佐持续', desc = '解斑须佐持续时间改10',
        enabled = false,
        patches = {
            { so = {"libil2cpp.so:bss", "Cb"}, offset = {0x21DF88, 0x590, 0x358}, is32 = true, flags = 16, value = 10 },
            { so = {"libil2cpp.so:bss", "Cb"}, offset = {0x211990, 0x610, 0x590, 0x358}, is32 = true, flags = 16, value = 10 },
        }
    },
}

-- 所有可切换功能列表
local toggleKeys = {
    'viewAngle', 'invincible', 'crit', 'critMulti', 'infiniteFire', 'sixBean',
    'moveSpeed', 'damageBoost', 'superArmor', 'damageReduce',
    'fullHP', 'fullEnergy', 'susanoo'
}

-- ========================================
-- 功能切换逻辑
-- ========================================
local function toggleFeature(key, isChecked)
    local feat = Features[key]
    if not feat then return end

    feat.enabled = isChecked

    -- 内存操作必须在独立线程执行，不能在 UI 线程调用 GG
    thread(function()
        if isChecked then
            local ok, e = pcall(function() execPatch(feat.patches, feat) end)
            if ok then
                log(feat.name .. ' 已开启', 'SUCCESS')
                notify(feat.name .. ' 启动', '功能已激活', 0xFFAA0000)
                pcall(function() gg.toast(feat.name .. ' 开启成功') end)
            else
                log(feat.name .. ' 失败: ' .. tostring(e), 'ERROR')
                notify(feat.name .. ' 失败', tostring(e), 0xFFFF0000)
                feat.enabled = false
                feat.frozenItems = nil
            end
        else
            pcall(function() removePatch(feat) end)
            log(feat.name .. ' 已关闭', 'WARN')
            notify(feat.name .. ' 关闭', '功能已停止', 0xFF606060)
            pcall(function() gg.toast(feat.name .. ' 已关闭') end)
        end
    end)
end

-- ========================================
-- 一键全开 / 全关
-- ========================================
local function allOn()
    thread(function()
        for _, k in ipairs(toggleKeys) do
            local feat = Features[k]
            if feat and not feat.enabled then
                feat.enabled = true
                pcall(function() execPatch(feat.patches, feat) end)
            end
        end
        log('一键全开完成', 'SUCCESS')
        notify('系统过载', '所有战斗功能已激活', 0xFFAA0000)
        pcall(function() AlGuiSoundEffect.getAudio(context).playSoundEffect(AlGuiSoundEffect.INFORM_WARNING) end)
    end)
end

local function allOff()
    thread(function()
        for _, k in ipairs(toggleKeys) do
            local feat = Features[k]
            if feat and feat.enabled then
                feat.enabled = false
                pcall(function() removePatch(feat) end)
            end
        end
        log('一键全关完成', 'WARN')
        notify('系统恢复', '所有战斗功能已停止', 0xFF606060)
    end)
end

-- ========================================
-- 开发者功能
-- ========================================
local function customMod()
    -- gg.prompt + 内存操作全部在独立线程执行
    thread(function()
        local input = gg.prompt({
            '[1] 实例地址(如 0x12345678, 可从复制角色地址获取)',
            '[2] 偏移量(如 0x164, 十六进制)',
            '[3] 写入数值',
            '[4] 类型: 4=整数(DWORD) 16=浮点(FLOAT)',
            '[5] 是否冻结: 1=冻结 0=不冻结',
        }, { '0x0', '0x164', '100', '16', '1' },
        { 'text', 'text', 'text', 'text', 'text' })
        if not input then return end

        local baseAddr = tonumber(input[1]) or 0
        if baseAddr == 0 then
            notify('地址无效', '实例地址解析失败', 0xFFFF0000)
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
        })

        log(string.format('自定义改值: 0x%X+0x%X=0x%X → %s', baseAddr, offset, addr, input[3]), 'SUCCESS')
        notify('写入完成', string.format('0x%X = %s', addr, input[3]), 0xFFAA0000)
    end)
end

local function customClear()
    if not S.customPatches or #S.customPatches == 0 then
        notify('无修改', '没有自定义修改记录', 0xFF606060)
        return
    end
    -- 内存操作在独立线程执行
    thread(function()
        local frozenItems, restoreVals = {}, {}
        for _, cp in ipairs(S.customPatches) do
            if cp.frozen then
                table.insert(frozenItems, {address = cp.address, flags = cp.flags})
            end
            if cp.oldValue ~= nil then
                table.insert(restoreVals, {address = cp.address, flags = cp.flags, value = cp.oldValue})
            end
        end
        if #frozenItems > 0 then pcall(function() gg.removeListItems(frozenItems) end) end
        if #restoreVals > 0 then pcall(function() gg.setValues(restoreVals) end) end
        local count = #S.customPatches
        S.customPatches = {}
        log(string.format('已清除 %d 个自定义修改', count), 'WARN')
        notify('清除完成', string.format('已恢复 %d 个修改', count), 0xFF606060)
    end)
end

local function copyCharAddr()
    -- 内存操作在独立线程执行
    thread(function()
        local offsetInv = 0x250
        local addrInvP1 = S_Pointer({"libil2cpp.so:bss", "Cb"}, {0x21DF88, 0x590, offsetInv}, true)
        local addrInvP2 = S_Pointer({"libil2cpp.so:bss", "Cb"}, {0x211990, 0x610, 0x590, offsetInv}, true)

        local addrP1, addrP2 = nil, nil
        if addrInvP1 and addrInvP1 > 0x10000 then addrP1 = addrInvP1 - offsetInv end
        if addrInvP2 and addrInvP2 > 0x10000 then addrP2 = addrInvP2 - offsetInv end

        if not addrP1 and not addrP2 then
            notify('未找到', '请确保已进入战斗', 0xFFFF0000)
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

        pcall(function() gg.copyText(text) end)
        log('角色地址已复制: ' .. text, 'SUCCESS')
        notify('地址已复制', text, 0xFFAA0000)
    end)
end

-- ========================================
-- 查看所有锁链地址（整合）
-- ========================================
local function viewFrozenAddrs()
    thread(function()
        if not S.allFrozenAddrs or #S.allFrozenAddrs == 0 then
            notify('无锁链', '当前没有冻结的地址', 0xFF606060)
            return
        end

        -- 按功能分组整理
        local groups = {}
        local groupOrder = {}
        for _, item in ipairs(S.allFrozenAddrs) do
            if not groups[item.featName] then
                groups[item.featName] = {}
                table.insert(groupOrder, item.featName)
            end
            table.insert(groups[item.featName], item)
        end

        -- 构建显示文本
        local text = string.format('=== 锁链地址汇总 (%d条) ===\n\n', #S.allFrozenAddrs)
        for _, fname in ipairs(groupOrder) do
            local items = groups[fname]
            text = text .. string.format('【%s】(%d条)\n', fname, #items)
            for _, item in ipairs(items) do
                local typeName = (item.flags == 4) and 'DWORD' or 'FLOAT'
                text = text .. string.format('  0x%X | %s | %s\n', item.address, typeName, tostring(item.value))
            end
            text = text .. '\n'
        end

        -- 复制到剪贴板 + 弹框显示
        pcall(function() gg.copyText(text) end)
        log('锁链地址已生成: ' .. #S.allFrozenAddrs .. ' 条', 'SUCCESS')

        -- 用 gg.alert 显示摘要
        local summary = string.format('共 %d 条锁链地址，已复制到剪贴板\n\n', #S.allFrozenAddrs)
        for _, fname in ipairs(groupOrder) do
            summary = summary .. string.format('%s: %d条\n', fname, #groups[fname])
        end
        pcall(function() gg.alert(summary, '确定') end)
        notify('锁链地址', string.format('共%d条已复制', #S.allFrozenAddrs), 0xFFAA0000)
    end)
end

-- ========================================
-- 开发者工具弹框（必须在 UI 线程调用）
-- ========================================
local function showDevToolsDialog()
    alDev = AlGuiDialogBox.showDiaLog(
        context, 0xE6202020, 5,

        -- 标题
        gui.addTextView("开发者工具", 16, 0xFFAA0000, Typeface.create(Typeface.DEFAULT, Typeface.BOLD)),
        -- 分割线
        gui.addLine(nil, 1, 0xFF555555, true),
        -- 描述
        gui.addTextView("授权等级：Ω | 高级功能已解锁", 10, 0xFF909090, null),

        -- 自定义改值按钮
        gui.addButton(
            "自定义改值", 12, 0xFFFFFFFF, null,
            3, 0xFFAA0000, 1, 0xFF660000,
            LinearLayout.LayoutParams.MATCH_PARENT, LinearLayout.LayoutParams.WRAP_CONTENT,
            AlGui.T_ButtonOnChangeListener({
                onClick = function(button, back, buttonText, isChecked)
                    customMod()
                end
            })
        ),

        -- 清除自定义按钮
        gui.addButton(
            "清除自定义修改", 12, 0xFFFFFFFF, null,
            3, 0xFF660000, 1, 0xFF330000,
            LinearLayout.LayoutParams.MATCH_PARENT, LinearLayout.LayoutParams.WRAP_CONTENT,
            AlGui.T_ButtonOnChangeListener({
                onClick = function(button, back, buttonText, isChecked)
                    customClear()
                end
            })
        ),

        -- 复制角色地址按钮
        gui.addButton(
            "复制角色地址", 12, 0xFFFFFFFF, null,
            3, 0xFF606060, 1, 0xFF303030,
            LinearLayout.LayoutParams.MATCH_PARENT, LinearLayout.LayoutParams.WRAP_CONTENT,
            AlGui.T_ButtonOnChangeListener({
                onClick = function(button, back, buttonText, isChecked)
                    copyCharAddr()
                end
            })
        ),

        -- 查看锁链地址
        gui.addButton(
            "查看锁链地址", 12, 0xFFFFFFFF, null,
            3, 0xFF505050, 1, 0xFF252525,
            LinearLayout.LayoutParams.MATCH_PARENT, LinearLayout.LayoutParams.WRAP_CONTENT,
            AlGui.T_ButtonOnChangeListener({
                onClick = function(button, back, buttonText, isChecked)
                    viewFrozenAddrs()
                end
            })
        ),

        -- 关闭按钮
        gui.addButton(
            "关闭", 12, 0xFFFFFFFF, null,
            3, 0xFFFF5555, 1, 0xFFAA0000,
            LinearLayout.LayoutParams.MATCH_PARENT, LinearLayout.LayoutParams.WRAP_CONTENT,
            AlGui.T_ButtonOnChangeListener({
                onClick = function(button, back, buttonText, isChecked)
                    if alDev then alDev.dismiss() end
                end
            })
        )
    )
end

-- ========================================
-- 开发者密码验证 + 入口
-- ========================================
local function showDevDialog()
    if S.devUnlocked then
        -- 已解锁，直接在 UI 线程显示弹框
        showDevToolsDialog()
        return
    end
    -- 未解锁：gg.prompt 必须在独立线程
    thread(function()
        local input = gg.prompt({'请输入开发者密码:'}, {''}, {'text'})
        if not input then return end
        if input[1] ~= '085236qw' then
            notify('密码错误', '授权失败', 0xFFFF0000)
            pcall(function() AlGuiSoundEffect.getAudio(context).playSoundEffect(AlGuiSoundEffect.INFORM_ERROR) end)
            return
        end
        S.devUnlocked = true
        notify('授权通过', '开发者模式已解锁', 0xFFAA0000)
        pcall(function() AlGuiSoundEffect.getAudio(context).playSoundEffect(AlGuiSoundEffect.INFORM_SUCCESS) end)
        -- 弹框必须回到 UI 线程（showDiaLog 需要 Looper）
        Lock.Ui(function()
            showDevToolsDialog()
        end)
    end)
end

-- ========================================
-- 清理所有功能
-- ========================================
local function cleanupAll()
    pcall(function()
        for _, k in ipairs(toggleKeys) do
            local feat = Features[k]
            if feat and (feat.frozenItems or feat.savedValues) then
                removePatch(feat)
            end
        end
        -- 清理自定义修改
        if S.customPatches and #S.customPatches > 0 then
            local frozenItems, restoreVals = {}, {}
            for _, cp in ipairs(S.customPatches) do
                if cp.frozen then
                    table.insert(frozenItems, {address = cp.address, flags = cp.flags})
                end
                if cp.oldValue ~= nil then
                    table.insert(restoreVals, {address = cp.address, flags = cp.flags, value = cp.oldValue})
                end
            end
            if #frozenItems > 0 then gg.removeListItems(frozenItems) end
            if #restoreVals > 0 then gg.setValues(restoreVals) end
            S.customPatches = {}
        end
        -- 清空全局锁链地址表
        S.allFrozenAddrs = {}
    end)
    log('所有功能已清理', 'WARN')
end

-- ========================================
-- 初始化末日科技风格UI
-- ========================================
Lock.Ui(function()
    -- 清理旧UI
    if AlGui.algui then
        AlGui.algui.clearBall()
        AlGui.algui.clearMenu()
        AlGuiWindowView.clearAllViews(context)
        gui = AlGui.newGUI(context)
    else
        gui = AlGui.GUI(context)
    end

    -- 初始化通知系统
    if AlGuiBubbleNotification.bn then
        Inform = AlGuiBubbleNotification.newInform(context)
    else
        Inform = AlGuiBubbleNotification.Inform(context)
    end

    -- 末日科技风格配置
    gui.getMenuMainTitle().setText("小志助手")
    gui.getMenuSubTitle().setText("v9.0 - 末日控制系统")
    gui.getMenuExplanation().setText("警告：异常环境专用系统 | 授权等级：Ω")
    gui.getMenuBottomLeftButton().setText("隐藏/长按退出")
    gui.getMenuBottomRightButton().setText("最小化")

    -- 长按退出（含清理）
    gui.getMenuBottomLeftButton().setOnLongClickListener(luajava.createProxy(
        "android.view.View$OnLongClickListener",
        {
            onLongClick = function(edit)
                -- 清理 + 退出都在独立线程执行，避免 UI 线程调用 GG
                thread(function()
                    cleanupAll()
                    pcall(function() AlGuiBubbleNotification.Inform(context).clearW() end)
                    pcall(function() gui.clearMenu() end)
                    pcall(function() gui.clearBall() end)
                    pcall(function() AlGuiWindowView.clearAllViews(context) end)
                    luajava.exit()
                end)
                return true
            end
        }
    ))

    -- 样式配置 (末日科技风格)
    gui.setBallImage(null, 50, 50)
    gui.setAllViewMargins(6, 6, 6, 6)
    AlGuiData.menuScrollWidth = 820
    AlGuiData.menuScrollHeight = 580
    AlGuiData.rootLayoutFilletRadius = 2
    AlGuiData.rootLayoutStrokeWidth = 1.5
    AlGuiData.menuTopLineFilletRadius = 1
    AlGuiData.menuTransparency = 0.97
    AlGuiData.rootLayoutBackColor = 0xE6121212    -- 深黑背景
    AlGuiData.rootLayoutStrokeColor = 0xFF606060  -- 灰色边框
    AlGuiData.menuTopLineColor = 0xFFAA0000       -- 暗红色
    AlGuiData.menuMainTitleTextColor = 0xFFAA0000 -- 暗红标题
    AlGuiData.menuSubTitleTextColor = 0xFF606060
    AlGuiData.menuExplanationBackColor = 0x30121212
    AlGuiData.menuExplanationTextColor = 0xFF909090
    AlGuiData.menuScrollBackColor = 0x90101010
    AlGuiData.menuBottLeftButtonTextColor = 0xFFAA0000
    AlGuiData.menuBottRightButtonTextColor = 0xFF606060
    AlGuiData.menuBottRightTriangleColor = 0xFF606060

    gui.updateMenuAppearance()
    gui.updateMenu()

    -- ============= ⚔ 战斗强化 =============
    local combatModule = gui.addCollapse(
        gui.getMenuScrollingListLayout(),
        "⚔ 战斗强化", 12, 0xFFAA0000, Typeface.create(Typeface.DEFAULT, Typeface.BOLD),
        4, 0x40121212, 1, 0xFF606060,
        false
    )

    -- 改视角
    gui.addSwitch(
        combatModule,
        "改视角", 11, 0xFF909090, null,
        "修改镜头大小", 8, 0xFF606060, null,
        0xFFAA0000, 0xFF660000,
        0xFF303030, 0xFF121212,
        AlGui.T_SwitchOnChangeListener({
            onClick = function(aSwitch, desc, isChecked)
                toggleFeature('viewAngle', isChecked)
            end
        })
    )

    -- 无敌
    gui.addSwitch(
        combatModule,
        "无敌", 11, 0xFF909090, null,
        "免疫所有伤害", 8, 0xFF606060, null,
        0xFFAA0000, 0xFF660000,
        0xFF303030, 0xFF121212,
        AlGui.T_SwitchOnChangeListener({
            onClick = function(aSwitch, desc, isChecked)
                toggleFeature('invincible', isChecked)
            end
        })
    )

    -- 暴击率
    gui.addSwitch(
        combatModule,
        "暴击率", 11, 0xFF909090, null,
        "暴击率 100%", 8, 0xFF606060, null,
        0xFFAA0000, 0xFF660000,
        0xFF303030, 0xFF121212,
        AlGui.T_SwitchOnChangeListener({
            onClick = function(aSwitch, desc, isChecked)
                toggleFeature('crit', isChecked)
            end
        })
    )

    -- 暴击倍率
    gui.addSwitch(
        combatModule,
        "暴击倍率", 11, 0xFF909090, null,
        "暴击伤害 x50", 8, 0xFF606060, null,
        0xFFAA0000, 0xFF660000,
        0xFF303030, 0xFF121212,
        AlGui.T_SwitchOnChangeListener({
            onClick = function(aSwitch, desc, isChecked)
                toggleFeature('critMulti', isChecked)
            end
        })
    )

    -- 无限火力
    gui.addSwitch(
        combatModule,
        "无限火力", 11, 0xFF909090, null,
        "全技能无冷却", 8, 0xFF606060, null,
        0xFFAA0000, 0xFF660000,
        0xFF303030, 0xFF121212,
        AlGui.T_SwitchOnChangeListener({
            onClick = function(aSwitch, desc, isChecked)
                toggleFeature('infiniteFire', isChecked)
            end
        })
    )

    -- 六豆
    gui.addSwitch(
        combatModule,
        "六豆", 11, 0xFF909090, null,
        "奥义点数锁定 6", 8, 0xFF606060, null,
        0xFFAA0000, 0xFF660000,
        0xFF303030, 0xFF121212,
        AlGui.T_SwitchOnChangeListener({
            onClick = function(aSwitch, desc, isChecked)
                toggleFeature('sixBean', isChecked)
            end
        })
    )

    -- ============= ⚡ 属性提升 =============
    local attrModule = gui.addCollapse(
        gui.getMenuScrollingListLayout(),
        "⚡ 属性提升", 12, 0xFF606060, Typeface.create(Typeface.DEFAULT, Typeface.BOLD),
        4, 0x40121212, 1, 0xFF606060,
        false
    )

    -- 移速加速
    gui.addSwitch(
        attrModule,
        "移速加速", 11, 0xFF909090, null,
        "移动速度大幅提升", 8, 0xFF606060, null,
        0xFFAA0000, 0xFF660000,
        0xFF303030, 0xFF121212,
        AlGui.T_SwitchOnChangeListener({
            onClick = function(aSwitch, desc, isChecked)
                toggleFeature('moveSpeed', isChecked)
            end
        })
    )

    -- 伤害加成
    gui.addSwitch(
        attrModule,
        "伤害加成", 11, 0xFF909090, null,
        "所有伤害大幅提升", 8, 0xFF606060, null,
        0xFFAA0000, 0xFF660000,
        0xFF303030, 0xFF121212,
        AlGui.T_SwitchOnChangeListener({
            onClick = function(aSwitch, desc, isChecked)
                toggleFeature('damageBoost', isChecked)
            end
        })
    )

    -- 霸体
    gui.addSwitch(
        attrModule,
        "霸体", 11, 0xFF909090, null,
        "免疫击退击飞", 8, 0xFF606060, null,
        0xFFAA0000, 0xFF660000,
        0xFF303030, 0xFF121212,
        AlGui.T_SwitchOnChangeListener({
            onClick = function(aSwitch, desc, isChecked)
                toggleFeature('superArmor', isChecked)
            end
        })
    )

    -- 免伤
    gui.addSwitch(
        attrModule,
        "免伤", 11, 0xFF909090, null,
        "受到伤害减少 100%", 8, 0xFF606060, null,
        0xFFAA0000, 0xFF660000,
        0xFF303030, 0xFF121212,
        AlGui.T_SwitchOnChangeListener({
            onClick = function(aSwitch, desc, isChecked)
                toggleFeature('damageReduce', isChecked)
            end
        })
    )

    -- 锁血
    gui.addSwitch(
        attrModule,
        "锁血", 11, 0xFF909090, null,
        "血量锁定 99999", 8, 0xFF606060, null,
        0xFFAA0000, 0xFF660000,
        0xFF303030, 0xFF121212,
        AlGui.T_SwitchOnChangeListener({
            onClick = function(aSwitch, desc, isChecked)
                toggleFeature('fullHP', isChecked)
            end
        })
    )

    -- 满能量
    gui.addSwitch(
        attrModule,
        "满能量", 11, 0xFF909090, null,
        "能量锁定 100", 8, 0xFF606060, null,
        0xFFAA0000, 0xFF660000,
        0xFF303030, 0xFF121212,
        AlGui.T_SwitchOnChangeListener({
            onClick = function(aSwitch, desc, isChecked)
                toggleFeature('fullEnergy', isChecked)
            end
        })
    )

    -- 须佐持续
    gui.addSwitch(
        attrModule,
        "须佐持续", 11, 0xFF909090, null,
        "解斑须佐持续时间改10", 8, 0xFF606060, null,
        0xFFAA0000, 0xFF660000,
        0xFF303030, 0xFF121212,
        AlGui.T_SwitchOnChangeListener({
            onClick = function(aSwitch, desc, isChecked)
                toggleFeature('susanoo', isChecked)
            end
        })
    )

    -- ============= 🔥 快捷操作 =============
    local quickModule = gui.addCollapse(
        gui.getMenuScrollingListLayout(),
        "🔥 快捷操作", 12, 0xFFAA0000, Typeface.create(Typeface.DEFAULT, Typeface.BOLD),
        4, 0x40121212, 1, 0xFF606060,
        false
    )

    -- 一键全开
    gui.addButton(
        quickModule,
        "一键全开", 12, 0xFFFFFFFF, null,
        3, 0xFFAA0000, 1, 0xFF660000,
        LinearLayout.LayoutParams.MATCH_PARENT, LinearLayout.LayoutParams.WRAP_CONTENT,
        AlGui.T_ButtonOnChangeListener({
            onClick = function(button, back, buttonText, isChecked)
                allOn()
            end
        })
    )

    -- 一键全关
    gui.addButton(
        quickModule,
        "一键全关", 12, 0xFFFFFFFF, null,
        3, 0xFF660000, 1, 0xFF330000,
        LinearLayout.LayoutParams.MATCH_PARENT, LinearLayout.LayoutParams.WRAP_CONTENT,
        AlGui.T_ButtonOnChangeListener({
            onClick = function(button, back, buttonText, isChecked)
                allOff()
            end
        })
    )

    -- ============= 🖥 系统控制 =============
    local systemModule = gui.addCollapse(
        gui.getMenuScrollingListLayout(),
        "🖥 系统控制", 12, 0xFF606060, Typeface.create(Typeface.DEFAULT, Typeface.BOLD),
        4, 0x40121212, 1, 0xFF606060,
        false
    )

    -- 选择进程
    gui.addButton(
        systemModule,
        "选择进程", 12, 0xFFFFFFFF, null,
        3, 0xFF606060, 1, 0xFF303030,
        LinearLayout.LayoutParams.MATCH_PARENT, LinearLayout.LayoutParams.WRAP_CONTENT,
        AlGui.T_ButtonOnChangeListener({
            onClick = function(button, back, buttonText, isChecked)
                thread(function()
                    pcall(function() gg.setProcessX() end)
                    notify('进程选择', '已打开进程选择器', 0xFF606060)
                end)
            end
        })
    )

    -- 开发者模式
    gui.addButton(
        systemModule,
        "开发者模式", 12, 0xFFFFFFFF, null,
        3, 0xFFAA0000, 1, 0xFF660000,
        LinearLayout.LayoutParams.MATCH_PARENT, LinearLayout.LayoutParams.WRAP_CONTENT,
        AlGui.T_ButtonOnChangeListener({
            onClick = function(button, back, buttonText, isChecked)
                showDevDialog()
            end
        })
    )

    -- 显示悬浮球
    gui.showBall()

    -- 初始通知
    Inform.showCustomizeNotification(
        0xFF121212,
        null, 0,
        "系统激活", 0xFFAA0000,
        "小志助手 v9.0 末日控制系统已加载", 0xFF909090,
        4000
    )
    pcall(function() AlGuiSoundEffect.getAudio(context).playSoundEffect(AlGuiSoundEffect.INFORM_WARNING) end)
end, nil, function(err)
    -- 错误时清理（在独立线程执行避免再次崩溃）
    thread(function()
        pcall(function() cleanupAll() end)
        pcall(function() AlGuiWindowView.clearAllViews(context) end)
        print("系统崩溃: " .. tostring(err))
        luajava.exit()
    end)
end)
