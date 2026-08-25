-- rime.lua
-- ==========================================================
--  1. date_translator      ：日期时间输入（rq/sj/xq/dt/ts）
--  2. number_translator    ：数字大写转换（金额大写/数字小写）
--  3. autocap_filter       ：英文候选自动大写（首字母/全大写）
--  4. en_spacer            ：英文单词前自动补空格
--  5. manual_segmentation  ：手动反引号分词，隔离造句引擎
--  6. pin_cand_filter      ：置顶候选（固定词条强制排前）
--  7. reduce_emoji_filter  ：Emoji 候选降频（后置特定 Emoji）
--  8. reduce_english_filter：英文候选降频（后置特定英文词）
--  9. select_character     ：选字上屏 + 频次记录（wubi.freq.txt）
-- 10. submit               ：手动造词（Ctrl+Return）
-- 11. memory_translator    ：手动造词记忆（临时词库查询）
-- 12. sort_filter          ：三维绝对排序（短码透传/长码词组优先）
-- 13. paging_or_commit     ：单页顶字上屏（逗号/句号直接上屏）
-- 14. weight_updater       ：权重离线结算（阅后即焚 + 纯净日志 + 日期轮转）
-- ==========================================================
--  全局命名空间（多方案隔离）
-- ==========================================================
_G._rime_wubi = _G._rime_wubi or {}
local NS = _G._rime_wubi
NS.memory_db = NS.memory_db or {}
NS.commit_history_texts = NS.commit_history_texts or {}
NS.freq_log_queue = NS.freq_log_queue or {}
NS.manual_segments = NS.manual_segments or {} -- 手动分词缓存队列
NS.modules = NS.modules or {}                  -- 模块隔离表

-- 提交计数器与阈值（实现自动动态更新）
NS.commit_counter = NS.commit_counter or 0
NS.COMMIT_THRESHOLD = 200

-- ==========================================================
--  UTF-8 辅助函数（优先内置库）
-- ==========================================================
local utf8_len, utf8_offset
if pcall(function() return utf8.len("测") end) then
    utf8_len = utf8.len
    utf8_offset = utf8.offset
else
    utf8_len = function(str)
        if not str then return 0 end
        local len = 0
        for _ in string.gmatch(str, "[%z\1-\127\194-\244][\128-\191]*") do
            len = len + 1
        end
        return len
    end
    utf8_offset = function(str, n)
        if not str or n == 0 then return 1 end
        local chars = {}
        for char in string.gmatch(str, "[%z\1-\127\194-\244][\128-\191]*") do
            table.insert(chars, char)
        end
        local idx = n > 0 and n or #chars + n + 1
        if idx < 1 or idx > #chars then return nil end
        local pos = 1
        for i = 1, idx - 1 do
            pos = pos + #chars[i]
        end
        return pos
    end
end

-- ==========================================================
--  基础路径及共享内存加载
-- ==========================================================
local function get_shared_dict_path()
    if rime_api and rime_api.get_user_data_dir then
        return rime_api.get_user_data_dir() .. "/dicts/wubi.chaos.dict.yaml"
    end
    return "dicts/wubi.chaos.dict.yaml"
end

local db_file = get_shared_dict_path()

local function ensure_dir_exists(file_path)
    local dir = file_path:match("^(.*)/[^/]+$")
    if dir then
        if package.config:sub(1,1) == '\\' then
            os.execute('if not exist "' .. dir .. '" mkdir "' .. dir .. '"')
        else
            os.execute('mkdir -p "' .. dir .. '"')
        end
    end
end
ensure_dir_exists(db_file)

local function load_db()
    NS.memory_db = {}
    local status, f = pcall(io.open, db_file, "r")
    if not status or not f then return end
    for line in f:lines() do
        if not line:match("^#") and not line:match("^%-") and not line:match("^[\t ]*$") and line:match("%S") then
            local text, code, weight = line:match("^(.-)\t(.-)\t?(%d*)$")
            if text and code then
                local lower_code = code:lower()
                if not NS.memory_db[lower_code] then NS.memory_db[lower_code] = {} end
                local w = tonumber(weight) or 1
                local found = false
                for _, v in ipairs(NS.memory_db[lower_code]) do
                    if v.text == text then
                        if w > v.weight then v.weight = w end
                        found = true
                        break
                    end
                end
                if not found then
                    table.insert(NS.memory_db[lower_code], {text=text, weight=w})
                end
            end
        end
    end
    f:close()
end

load_db()
local modules = {}

--------------------------------------------------------------------------------
-- 1. date_translator
--------------------------------------------------------------------------------
do
    local function yield_cand(seg, text)
        local cand = Candidate('', seg.start, seg._end, text, '')
        cand.quality = 100
        yield(cand)
    end
    local M = {}
    function M.init(env)
        local config = env.engine.schema.config
        env.name_space = env.name_space:gsub('^*', '')
        M.date = config:get_string(env.name_space .. '/date') or 'rq'
        M.time = config:get_string(env.name_space .. '/time') or 'sj'
        M.week = config:get_string(env.name_space .. '/week') or 'xq'
        M.datetime = config:get_string(env.name_space .. '/datetime') or 'dt'
        M.timestamp = config:get_string(env.name_space .. '/timestamp') or 'ts'
    end
    function M.func(input, seg, env)
        local current_time = os.time()
        if input == M.date then
            yield_cand(seg, os.date('%Y-%m-%d', current_time))
            yield_cand(seg, os.date('%Y%m%d', current_time))
            yield_cand(seg, os.date('%Y年%m月%d日', current_time):gsub('年0', '年'):gsub('月0', '月'))
        elseif input == M.time then
            yield_cand(seg, os.date('%H:%M', current_time))
            yield_cand(seg, os.date('%H:%M:%S', current_time))
        elseif input == M.week then
            local week_tab = { '日', '一', '二', '三', '四', '五', '六' }
            local text = week_tab[tonumber(os.date('%w', current_time)) + 1]
            yield_cand(seg, '星期' .. text)
            yield_cand(seg, '周' .. text)
        elseif input == M.datetime then
            -- 新增：安全构造 ISO 时区偏移
            local raw_tz = os.date('%z')
            local iso_tz = raw_tz:match('^([+-]%d%d):?(%d%d)$')
            if iso_tz then
                iso_tz = iso_tz .. ':' .. raw_tz:sub(-2)
            else
                iso_tz = 'Z'
            end
            -- 改动：第一行改为 ISO 8601 带时区格式
            -- 以下三行保持原样
            yield_cand(seg, os.date('%Y%m%d%H%M%S', current_time))
            yield_cand(seg, os.date('%Y-%m-%d %H:%M', current_time))
            yield_cand(seg, os.date('%Y-%m-%dT%H:%M:%S', current_time) .. iso_tz)
        elseif input == M.timestamp then
            yield_cand(seg, string.format('%d', current_time))
        end
    end
    modules.date_translator = M
end

--------------------------------------------------------------------------------
-- 2. number_translator
--------------------------------------------------------------------------------
do
    local function splitNumPart(str)
        local part = {}
        part.int, part.dot, part.dec = string.match(str, "^(%d*)(%.?)(%d*)")
        return part
    end
    local function decimal_func(str, posMap, valMap)
        local dec
        posMap = posMap or { [1] = "角"; [2] = "分"; [3] = "厘"; [4] = "毫" }
        valMap = valMap or { [0] = "零"; "壹"; "贰"; "叁"; "肆"; "伍"; "陆"; "柒"; "捌"; "玖" }
        if #str > 4 then dec = string.sub(tostring(str), 1, 4) else dec = tostring(str) end
        dec = string.gsub(dec, "0+$", "")
        if dec == "" then return "整" end
        local result = ""
        for pos = 1, #dec do
            local val = tonumber(string.sub(dec, pos, pos))
            if val ~= 0 then result = result .. valMap[val] .. posMap[pos] else result = result .. valMap[val] end
        end
        result = result:gsub(valMap[0] .. valMap[0], valMap[0])
        return result:gsub(valMap[0] .. valMap[0], valMap[0])
    end
    local function formatNum(num, t)
        local digitUnit, wordFigure
        local result = ""
        num = tostring(num)
        if tonumber(t) < 1 then
            digitUnit = { "", "十", "百", "千" }
            wordFigure = { "〇", "一", "二", "三", "四", "五", "六", "七", "八", "九" }
        else
            digitUnit = { "", "拾", "佰", "仟" }
            wordFigure = { "零", "壹", "贰", "叁", "肆", "伍", "陆", "柒", "捌", "玖" }
        end
        if string.len(num) > 4 or tonumber(num) == 0 then return wordFigure[1] end
        local lens = string.len(num)
        for i = 1, lens do
            local n = wordFigure[tonumber(string.sub(num, -i, -i)) + 1]
            if n ~= wordFigure[1] then result = n .. digitUnit[i] .. result else result = n .. result end
        end
        result = result:gsub(wordFigure[1] .. wordFigure[1], wordFigure[1])
        result = result:gsub(wordFigure[1] .. "$", "")
        result = result:gsub(wordFigure[1] .. "$", "")
        return result
    end
    local function number2cnChar(num, flag, digitUnit, wordFigure)
        local result = ""
        num = tostring(num)
        local num1, num2 = math.modf(num)
        if tonumber(num2) ~= 0 then return "数值超限！" end
        if tonumber(flag) < 1 then
            digitUnit = digitUnit or { [1] = "万"; [2] = "亿" }
            wordFigure = wordFigure or { [1] = "〇"; [2] = "一"; [3] = "十"; [4] = "元" }
        else
            digitUnit = digitUnit or { [1] = "万"; [2] = "亿" }
            wordFigure = wordFigure or { [1] = "零"; [2] = "壹"; [3] = "拾"; [4] = "元" }
        end
        local lens = string.len(num1)
        if lens < 5 then
            result = formatNum(num1, flag)
            if tonumber(flag) < 1 and tonumber(num1) >= 10 and tonumber(num1) < 20 then
                result = result:gsub("^一十", "十")
            elseif tonumber(flag) >= 1 and tonumber(num1) >= 10 and tonumber(num1) < 20 then
                result = result:gsub("^壹拾", "拾")
            end
        elseif lens < 9 then
            result = formatNum(string.sub(num1, 1, -5), flag) .. digitUnit[1] .. formatNum(string.sub(num1, -4, -1), flag)
        elseif lens < 13 then
            result = formatNum(string.sub(num1, 1, -9), flag) .. digitUnit[2] .. formatNum(string.sub(num1, -8, -5), flag) .. digitUnit[1] .. formatNum(string.sub(num1, -4, -1), flag)
        else
            return "数值超限！"
        end
        result = result:gsub("^" .. wordFigure[1], "")
        result = result:gsub(wordFigure[1] .. digitUnit[1], "")
        result = result:gsub(wordFigure[1] .. digitUnit[2], "")
        result = result:gsub(wordFigure[1] .. wordFigure[1], wordFigure[1])
        result = result:gsub(wordFigure[1] .. "$", "")
        if lens > 4 then result = result:gsub("^" .. wordFigure[2] .. wordFigure[3], wordFigure[3]) end
        if result ~= "" then result = result .. wordFigure[4] else return "数值超限！" end
        return result
    end
    local function number2zh(num, t)
        local result = ""
        local wordFigure
        if tonumber(t) < 1 then
            wordFigure = { "〇", "一", "二", "三", "四", "五", "六", "七", "八", "九" }
        else
            wordFigure = { "零", "壹", "贰", "叁", "肆", "伍", "陆", "柒", "捌", "玖" }
        end
        if tostring(num) == nil then return "" end
        for pos = 1, string.len(num) do
            local digit = tonumber(string.sub(num, pos, pos))
            if digit then
                result = result .. wordFigure[digit + 1]
            end
        end
        result = result:gsub(wordFigure[1] .. wordFigure[1], wordFigure[1])
        return result
    end
    local function number_translatorFunc(num)
        local numberPart = splitNumPart(num)
        local result = {}
        table.insert(result, { number2cnChar(numberPart.int, 1) .. decimal_func(numberPart.dec, { [1] = "角"; [2] = "分"; [3] = "厘"; [4] = "毫" }, { [0] = "零"; "壹"; "贰"; "叁"; "肆"; "伍"; "陆"; "柒"; "捌"; "玖" }), "〔金额大写〕" })
        if numberPart.dot ~= "" then
            table.insert(result, { number2cnChar(numberPart.int, 0, { "万", "亿" }, { "〇", "一", "十", "点" }) .. number2zh(numberPart.dec, 0), "〔数字小写〕" })
            table.insert(result, { number2cnChar(numberPart.int, 1, { "萬", "億" }, { "〇", "一", "十", "点" }) .. number2zh(numberPart.dec, 1), "〔数字大写〕" })
        else
            table.insert(result, { number2cnChar(numberPart.int, 0, { "万", "亿" }, { "〇", "一", "十", "" }), "〔数字小写〕" })
            table.insert(result, { number2cnChar(numberPart.int, 1, { "萬", "億" }, { "零", "壹", "拾", "" }), "〔数字大写〕" })
        end
        table.insert(result, { number2cnChar(numberPart.int, 0) .. decimal_func(numberPart.dec, { [1] = "角"; [2] = "分"; [3] = "厘"; [4] = "毫" }, { [0] = "〇"; "一"; "二"; "三"; "四"; "五"; "六"; "七"; "八"; "九" }), "〔金额小写〕" })
        return result
    end
    local function number_translator(input, seg, env)
        if string.match(input, "^([A-TV-Z]+%d+)(%.?)(%d*)$") then
            local str = string.gsub(input, "^(%a+)", "")
            local numberPart = number_translatorFunc(str)
            for i = 1, #numberPart do
                yield(Candidate(input, seg.start, seg._end, numberPart[i][1], numberPart[i][2]))
            end
        end
    end
    modules.number_translator = number_translator
end

--------------------------------------------------------------------------------
-- 3. autocap_filter
--------------------------------------------------------------------------------
do
    local function autocap_filter(input, env)
        local code = env.engine.context.input
        local codeLen = #code
        local codeAllUCase = false
        local codeUCase = false
        if codeLen == 1 or code:find("^[%l%p]") then
            for cand in input:iter() do yield(cand) end
            return
        elseif code:find("^%u%u+.*") then codeAllUCase = true elseif code:find("^%u.*") then codeUCase = true end
        local pureCode = code:gsub("[%s%p]", "")
        for cand in input:iter() do
            local text = cand.text
            local pureText = text:gsub("[%s%p]", "")
            if text:find("[^%w%p%s]") or text:find("%s") or pureText:find("^" .. code) or (cand.type ~= "completion" and pureCode:lower() ~= pureText:lower()) then
                yield(cand)
            elseif codeAllUCase then yield(Candidate(cand.type, 0, codeLen, text:upper(), cand.comment))
            elseif codeUCase then yield(Candidate(cand.type, 0, codeLen, text:gsub("^%a", string.upper), cand.comment))
            else yield(cand) end
        end
    end
    modules.autocap_filter = autocap_filter
end

--------------------------------------------------------------------------------
-- 4. en_spacer
--------------------------------------------------------------------------------
do
    local F = {}
    function F.func(input, env)
        local latest_text = env.engine.context.commit_history:latest_text()
        for cand in input:iter() do
            if cand.text:match('^[%a\']+[%a\']*$') and latest_text and #latest_text > 0 and latest_text:find('^ ?[%a\']+[%a\']*$') then
                cand = cand:to_shadow_candidate('en_spacer', cand.text:gsub('(%a+\'?%a*)', ' %1'), cand.comment)
            end
            yield(cand)
        end
    end
    modules.en_spacer = F
end

--------------------------------------------------------------------------------
-- 5. manual_segmentation (终极隔离分词：记录文本、强行清空编码、斩断造句图)
--------------------------------------------------------------------------------
do
    local M = {}
    function M.init(env)
        if not env.commit_connected then
            env.engine.context.commit_notifier:connect(function(ctx)
                if NS.manual_segments and #NS.manual_segments > 0 then
                    NS.manual_segments = {}
                end
            end)
            env.commit_connected = true
        end
    end

    function M.func(key, env)
        if key:release() or key:alt() or key:ctrl() or key:super() then return 2 end

        local key_code = key.keycode
        local key_repr = key:repr()
        local context = env.engine.context

        if key_code == 96 or key_repr == "grave" or key_repr == "`" then
            if context:is_composing() then
                if context:has_menu() then
                    local cand = context:get_selected_candidate()
                    if cand then
                        local cand_text = cand.text
                        local prefix = ""
                        if NS.manual_segments and #NS.manual_segments > 0 then
                            prefix = table.concat(NS.manual_segments, "")
                        end

                        if prefix ~= "" and cand_text:sub(1, #prefix) == prefix then
                            cand_text = cand_text:sub(#prefix + 1)
                        end

                        NS.manual_segments = NS.manual_segments or {}
                        table.insert(NS.manual_segments, cand_text)
                    end
                end

                context:clear()
                return 1
            end
            return 2
        end

        if key_repr == "Escape" then
            if NS.manual_segments and #NS.manual_segments > 0 then
                NS.manual_segments = {}
                context:clear()
                return 1
            end
            return 2
        end

        return 2
    end
    modules.manual_segmentation = M
end

--------------------------------------------------------------------------------
-- 6. pin_cand_filter
--------------------------------------------------------------------------------
do
    local function find_index(list, str)
        for i, v in ipairs(list) do if v == str then return i end end
        return 0
    end
    local M = {}
    function M.init(env)
        env.name_space = env.name_space:gsub("^*", "")
        if env.pin_cands ~= nil then return end
        local list = env.engine.schema.config:get_list(env.name_space)
        if not list or list.size == 0 then return end
        local set = {}
        for i = 0, list.size - 1 do
            local preedit, texts = list:get_value_at(i).value:match("([^\t]+)\t(.+)")
            if preedit and texts and #preedit > 0 and #texts > 0 then set[preedit:gsub(" ", "")] = true end
        end
        env.pin_cands = {}
        for i = 0, list.size - 1 do
            local val_str = list:get_value_at(i).value
            local preedit, texts = val_str:match("([^\t]+)\t(.+)")
            if preedit and texts and #preedit > 0 and #texts > 0 then
                local delimiter = "\0"
                if texts:find(" > ") then texts = texts:gsub(" > ", delimiter) else texts = texts:gsub(" ", delimiter) end
                local preedit_no_spaces = preedit:gsub(" ", "")
                env.pin_cands[preedit_no_spaces] = {}
                for text in texts:gmatch("[^" .. delimiter .. "]+") do table.insert(env.pin_cands[preedit_no_spaces], text) end
                if preedit:find(" ") then
                    local preceding_part, last_part = preedit:match("^(.+)%s(%S+)$")
                    if preceding_part and last_part then
                        local p1 = preceding_part:gsub(" ", "") .. last_part:sub(1, 1)
                        local p2 = ""
                        if last_part:match("^[zcs]h") then p2 = preceding_part:gsub(" ", "") .. last_part:sub(1, 2) end
                        for _, p in ipairs({ p1, p2 }) do
                            if p ~= "" and not set[p] then
                                if env.pin_cands[p] ~= nil then
                                    for text in texts:gmatch("[^" .. delimiter .. "]+") do table.insert(env.pin_cands[p], text) end
                                else
                                    env.pin_cands[p] = env.pin_cands[preedit_no_spaces]
                                end
                            end
                        end
                    end
                end
            end
        end
    end
    function M.func(input, env)
        local full_preedit = env.engine.context:get_preedit().text
        local letter_only_preedit = string.gsub(full_preedit, "[^a-zA-Z]", "")
        if env.pin_cands == nil or next(env.pin_cands) == nil or #letter_only_preedit == 0 then
            for cand in input:iter() do yield(cand) end
            return
        end
        local all_cands = {}
        for cand in input:iter() do table.insert(all_cands, cand) end
        local pined = {}
        local others = {}
        local preedit_texts = nil
        if #all_cands > 0 then
            local preedit = all_cands[1].preedit and all_cands[1].preedit:gsub(" ", "") or ""
            preedit_texts = env.pin_cands[preedit]
        end
        if preedit_texts == nil then
            for _, cand in ipairs(all_cands) do yield(cand) end
            return
        end
        for _ = 1, #preedit_texts do table.insert(pined, "") end
        for _, cand in ipairs(all_cands) do
            local idx = find_index(preedit_texts, cand.text)
            if idx ~= 0 then pined[idx] = cand else table.insert(others, cand) end
        end
        for _, cand in ipairs(pined) do if cand ~= "" then yield(cand) end end
        for _, cand in ipairs(others) do yield(cand) end
    end
    modules.pin_cand_filter = M
end

--------------------------------------------------------------------------------
-- 7. reduce_emoji_filter
--------------------------------------------------------------------------------
do
    local M = {}
    function M.init(env)
        local config = env.engine.schema.config
        env.name_space = env.name_space:gsub("^*", "")
        M.idx = config:get_int(env.name_space .. "/idx") or 0
        M.words = {}
        local list = config:get_list(env.name_space .. "/words")
        local listSize = list and list.size or 0
        for i = 0, listSize - 1 do
            local word = list:get_value_at(i):get_string()
            if word then M.words[word] = true end
        end
        local mode = config:get_string(env.name_space .. "/mode")
        if mode == "custom" then
            M.map = M.words
        else
            M.map = {}
        end
    end
    function M.func(translation, env)
        if next(M.map) == nil then
            for cand in translation:iter() do yield(cand) end
            return
        end
        local pending = {}
        local index = 0
        local after_threshold = false
        for cand in translation:iter() do
            if after_threshold then
                yield(cand)
            else
                index = index + 1
                if M.map[cand.text] then
                    table.insert(pending, cand)
                else
                    yield(cand)
                end
                if index >= M.idx + #pending - 1 then
                    for _, c in ipairs(pending) do yield(c) end
                    pending = {}
                    after_threshold = true
                end
            end
        end
        if not after_threshold then
            for _, c in ipairs(pending) do yield(c) end
        end
    end
    modules.reduce_emoji_filter = M
end

--------------------------------------------------------------------------------
-- 8. reduce_english_filter
--------------------------------------------------------------------------------
do
    local M = {}
    function M.init(env)
        local config = env.engine.schema.config
        env.name_space = env.name_space:gsub("^*", "")
        M.idx = config:get_int(env.name_space .. "/idx") or 0
        M.words = {}
        local list = config:get_list(env.name_space .. "/words")
        local listSize = list and list.size or 0
        for i = 0, listSize - 1 do
            local word = list:get_value_at(i):get_string()
            if word then M.words[word] = true end
        end
        local mode = config:get_string(env.name_space .. "/mode")
        if mode == "custom" then
            M.map = M.words
        else
            M.map = {}
        end
    end
    function M.func(input, env)
        if next(M.map) == nil then
            for cand in input:iter() do yield(cand) end
            return
        end
        local code = env.engine.context.input
        if not code then for cand in input:iter() do yield(cand) end return end
        if not M.map[code] then
            for cand in input:iter() do yield(cand) end
            return
        end
        local pending = {}
        local index = 0
        local after_threshold = false
        for cand in input:iter() do
            if after_threshold then
                yield(cand)
            else
                index = index + 1
                local preedit = cand.preedit or ""
                if preedit:find(" ") or not cand.text:match("[a-zA-Z]") then
                    yield(cand)
                else
                    table.insert(pending, cand)
                end
                if index >= M.idx + #pending - 1 then
                    for _, c in ipairs(pending) do yield(c) end
                    pending = {}
                    after_threshold = true
                end
            end
        end
        if not after_threshold then
            for _, c in ipairs(pending) do yield(c) end
        end
    end
    modules.reduce_english_filter = M
end

--------------------------------------------------------------------------------
-- 9. select_character
--------------------------------------------------------------------------------
do
    local select = {}
    function select.init(env)
        local config = env.engine.schema.config
        env.first_key = config:get_string('key_binder/select_first_character')
        env.last_key = config:get_string('key_binder/select_last_character')

        if not env.global_notifier_connected then
            env.engine.context.update_notifier:connect(function(ctx)
                if ctx:is_composing() then
                    NS.last_input_code = ctx.input
                end
                if ctx:has_menu() then
                    local seg = ctx.composition:back()
                    if seg then
                        local cand = seg:get_selected_candidate()
                        if cand then
                            if cand.comment and cand.comment:match("~") then
                                NS.last_cand_type_cache = "jianma"
                            elseif cand.type == "table" and utf8_len(cand.text) >= 2 then
                                NS.last_cand_type_cache = "word"
                            else
                                NS.last_cand_type_cache = "char"
                            end
                        end
                    end
                end
            end)

            env.engine.context.commit_notifier:connect(function(ctx)
                local text = ctx.commit_history:latest_text()
                if text and text ~= "" then
                    table.insert(NS.commit_history_texts, text)
                    if #NS.commit_history_texts > 10 then
                        table.remove(NS.commit_history_texts, 1)
                    end

                    if NS.manual_segments and #NS.manual_segments > 0 then
                        return
                    end

                    local code = NS.last_input_code
                    if code and code:match("^[a-z]+$") and #code <= 5 and utf8_len(text) <= 10 then
                        local cand_type = NS.last_cand_type_cache or "char"
                        local now_str = os.date("%Y-%m-%d %H:%M:%S")
                        local last_len = NS.last_input_len or 0
                        local last_type = NS.last_cand_type or ""
                        local current_len = #code

                        local function safe_obfuscate(str)
                            local res = ""
                            for i = 1, #str do
                                local b = str:byte(i)
                                res = res .. string.format("%02X", (b + 0x5A) % 256)
                            end
                            return res
                        end

                        local obfuscated_text = safe_obfuscate(text)
                        local obfuscated_code = safe_obfuscate(code)

                        local log_line = string.format("%s\t%s\t%d\t%s\t%s\t%d\t%s",
                            obfuscated_text, obfuscated_code, current_len, cand_type, now_str, last_len, last_type)

                        table.insert(NS.freq_log_queue, log_line)
                        NS.commit_counter = (NS.commit_counter or 0) + 1

                        if #NS.freq_log_queue >= 10 then
                            if rime_api and rime_api.get_user_data_dir then
                                local freq_file = rime_api.get_user_data_dir() .. "/dicts/wubi.freq.txt"
                                local status_ok, f = pcall(io.open, freq_file, "a")
                                if status_ok and f then
                                    local all_success = true
                                    for _, ln in ipairs(NS.freq_log_queue) do
                                        local w_ok = pcall(function() f:write(ln .. "\n") end)
                                        if not w_ok then all_success = false end
                                    end
                                    f:close()
                                    if all_success then
                                        NS.freq_log_queue = {}
                                    end
                                end
                            end
                        end

                        if NS.commit_counter >= NS.COMMIT_THRESHOLD then
                            NS.commit_counter = 0
                            if #NS.freq_log_queue > 0 then
                                if rime_api and rime_api.get_user_data_dir then
                                    local freq_file = rime_api.get_user_data_dir() .. "/dicts/wubi.freq.txt"
                                    local status_ok, f = pcall(io.open, freq_file, "a")
                                    if status_ok and f then
                                        local all_success = true
                                        for _, ln in ipairs(NS.freq_log_queue) do
                                            local w_ok = pcall(function() f:write(ln .. "\n") end)
                                            if not w_ok then all_success = false end
                                        end
                                        f:close()
                                        if all_success then
                                            NS.freq_log_queue = {}
                                        end
                                    end
                                end
                            end
                            if _G.WeightUpdater and _G.WeightUpdater.execute then
                                pcall(_G.WeightUpdater.execute)
                            end
                        end

                        NS.last_input_len = current_len
                        NS.last_cand_type = cand_type
                    end
                end
            end)
            env.global_notifier_connected = true
        end
    end

    function select.func(key, env)
        local engine = env.engine
        local context = env.engine.context
        if key:release() then return 2 end
        if not (context:is_composing() or context:has_menu()) then return 2 end
        if not (env.first_key or env.last_key) then return 2 end
        local cand = context:get_selected_candidate()
        if not cand then return 2 end
        local text = cand.text
        local key_repr = key:repr()
        local is_first = (key_repr == env.first_key)
        local is_last = (key_repr == env.last_key)
        if not (is_first or is_last) then return 2 end
        if utf8_len(text) > 1 then
            if is_first then
                local offset = utf8_offset(text, 2)
                if offset then
                    engine:commit_text(text:sub(1, offset - 1))
                else
                    engine:commit_text(text)
                end
            elseif is_last then
                local offset = utf8_offset(text, -1)
                if offset then
                    engine:commit_text(text:sub(offset))
                else
                    engine:commit_text(text)
                end
            end
            context:clear()
            return 1
        else
            engine:commit_text(text)
            context:clear()
            return 1
        end
    end
    modules.select_character = select
end

--------------------------------------------------------------------------------
-- 10. submit
--------------------------------------------------------------------------------
do
    local function append_to_dict(text, code, weight)
        weight = weight or 1
        if NS.memory_db[code] then
            for _, v in ipairs(NS.memory_db[code]) do
                if v.text == text then
                    return false, "已存在"
                end
            end
        end
        local f = io.open(db_file, "a+")
        if not f then return false, "无法打开词库文件" end
        f:write(string.format("%s\t%s\t%d\n", text, code, weight))
        f:close()
        local lower_code = code:lower()
        if not NS.memory_db[lower_code] then NS.memory_db[lower_code] = {} end
        table.insert(NS.memory_db[lower_code], {text=text, weight=weight})
        return true, nil
    end

    local function ensure_dict_exists()
        local f = io.open(db_file, "r")
        if f then f:close(); return true end
        local header = [[# Rime user dictionary
# encoding: utf-8
---
name: wubi_user
version: "1.0"
sort: by_weight
use_preset_vocabulary: true
columns:
  - text
  - code
  - weight
...
]]
        local fw = io.open(db_file, "w")
        if not fw then return false end
        fw:write(header)
        fw:close()
        return true
    end

    local M = {}
    function M.init(env)
        local config = env.engine.schema.config
        local ns = env.name_space:gsub("^*", "")
        env.key = config:get_string(ns .. "/key") or "Control+Return"
    end

    local function old_submit(env)
        local engine = env.engine
        local context = engine.context
        local last_text = context.commit_history:latest_text()
        local cur_code = context.input
        if not last_text or last_text == "" then
            engine:commit_text(" [未捕获中文]")
            context:clear()
            return 1
        end
        if not cur_code or cur_code == "" then
            engine:commit_text(" [未捕获编码]")
            context:clear()
            return 1
        end

        local pure_code = string.gsub(cur_code, "`", "")
        if not pure_code:match("^[a-z]+$") then
            engine:commit_text(" [编码需为纯小写字母]")
            context:clear()
            return 1
        end
        if not ensure_dict_exists() then
            engine:commit_text(" [词库创建失败，请检查目录权限]")
            context:clear()
            return 1
        end
        local ok, err = append_to_dict(last_text, pure_code)
        if ok then
            engine:commit_text(string.format(" [%s -> %s 成功]", last_text, pure_code))
        else
            engine:commit_text(" [写入失败: " .. (err or "未知错误") .. "]")
        end
        context:clear()
        return 1
    end

    local function update_display(context)
        local mode = NS.phrase_mode
        if not mode then return end
        if mode.stage == "combine" then
            local texts = NS.commit_history_texts
            local combined = table.concat(texts, "", mode.start_index, mode.end_index)
            context.input = "→ " .. combined
        elseif mode.stage == "code" then
            context.input = "\x01" .. (mode.code or "")
        end
    end

    local function start_phrase(env)
        local texts = NS.commit_history_texts
        if not texts or #texts == 0 then
            return old_submit(env)
        end
        NS.phrase_mode = {
            stage = "combine",
            start_index = #texts,
            end_index = #texts,
        }
        update_display(env.engine.context)
        return 1
    end

    local function handle_phrase_mode(key, env)
        local context = env.engine.context
        local mode = NS.phrase_mode
        if not mode then return 2 end
        local key_repr = key:repr()

        if key_repr == "Escape" then
            NS.phrase_mode = nil
            context.input = ""
            context:clear()
            return 1
        end

        if mode.stage == "combine" then
            if key_repr == "Left" or key_repr == "KP_Left" then
                if mode.start_index > 1 then
                    mode.start_index = mode.start_index - 1
                    update_display(context)
                end
                return 1
            elseif key_repr == "Right" or key_repr == "KP_Right" then
                if mode.start_index < mode.end_index then
                    mode.start_index = mode.start_index + 1
                    update_display(context)
                end
                return 1
            elseif key_repr == "Return" or key_repr == "KP_Enter" then
                mode.stage = "code"
                mode.code = ""
                local texts = NS.commit_history_texts
                mode.phrase = table.concat(texts, "", mode.start_index, mode.end_index)
                update_display(context)
                return 1
            else
                return 1
            end
        elseif mode.stage == "code" then
            if key_repr == "BackSpace" then
                if mode.code and #mode.code > 0 then
                    mode.code = mode.code:sub(1, -2)
                    update_display(context)
                end
                return 1
            elseif key_repr == "Return" or key_repr == "KP_Enter" then
                local final_code = mode.code
                local final_phrase = mode.phrase
                if not final_code or not final_code:match("^[a-z]+$") then
                    env.engine:commit_text(" [编码需为纯小写字母]")
                    NS.phrase_mode = nil
                    context.input = ""
                    context:clear()
                    return 1
                end
                if not ensure_dict_exists() then
                    env.engine:commit_text(" [词库创建失败]")
                    NS.phrase_mode = nil
                    context.input = ""
                    context:clear()
                    return 1
                end
                local ok, err = append_to_dict(final_phrase, final_code)
                if ok then
                    env.engine:commit_text(string.format(" [%s -> %s 成功]", final_phrase, final_code))
                else
                    env.engine:commit_text(" [写入失败: " .. (err or "未知错误") .. "]")
                end
                NS.phrase_mode = nil
                context.input = ""
                context:clear()
                return 1
            elseif key_repr:match("^[a-z]$") then
                mode.code = (mode.code or "") .. key_repr
                update_display(context)
                return 1
            else
                return 1
            end
        end
        return 2
    end

    function M.func(key, env)
        if key:release() then return 2 end
        if NS.phrase_mode then
            return handle_phrase_mode(key, env)
        end
        local key_repr = key:repr()
        if key_repr ~= env.key then return 2 end
        return start_phrase(env)
    end
    modules.submit = M
end

--------------------------------------------------------------------------------
-- 11. memory_translator
--------------------------------------------------------------------------------
do
    local M = {}
    function M.init(env) end
    function M.func(input, seg, env)
        local lower_input = input:lower()
        local cands = NS.memory_db[lower_input]
        if cands then
            local sorted = {}
            for i, v in ipairs(cands) do sorted[i] = v end
            table.sort(sorted, function(a, b) return a.weight > b.weight end)
            for _, entry in ipairs(sorted) do
                local cand = Candidate("memory", seg.start, seg._end, entry.text, "")
                cand.quality = 999
                yield(cand)
            end
        end
    end
    modules.memory_translator = M
end

--------------------------------------------------------------------------------
-- 12. sort_filter
--------------------------------------------------------------------------------
do
    local M = {}

    local function utf8_len_local(str)
        if not str then return 0 end
        local _, count = string.gsub(str, "[%z\1-\127\194-\244][\128-\191]*", "")
        return count
    end

    function M.func(input, env)
        local context = env.engine.context
        local input_code = context.input or ""
        local clean_code = input_code:gsub(" ", "")
        local input_len = #clean_code

        local prefix = ""
        if NS.manual_segments and #NS.manual_segments > 0 then
            prefix = table.concat(NS.manual_segments, "")
        end

        local singles_or_english = {}
        local phrases = {}

        for cand in input:iter() do
            local raw_text = cand.text
            local is_single = false
            local is_english = raw_text:match("^[a-zA-Z0-9%p%s]+$") ~= nil

            if not is_english then
                is_single = (utf8_len_local(raw_text) == 1)
            end

            local final_cand = cand
            if prefix ~= "" then
                final_cand = cand:to_shadow_candidate(cand.type, prefix .. raw_text, cand.comment)
            end

            if input_len < 4 then
                yield(final_cand)
            else
                if is_single or is_english then
                    table.insert(singles_or_english, final_cand)
                else
                    table.insert(phrases, final_cand)
                end
            end
        end

        if input_len >= 4 then
            local single_penalty = 0
            if #phrases < 3 then
                single_penalty = 10000
            end

            for _, c in ipairs(phrases) do
                yield(c)
            end

            for _, c in ipairs(singles_or_english) do
                local shadow = c:to_shadow_candidate(c.type, c.text, c.comment)
                shadow.quality = (c.quality or 0) - single_penalty
                yield(shadow)
            end
        end
    end

    modules.sort_filter = M
end

--------------------------------------------------------------------------------
-- 13. paging_or_commit
--------------------------------------------------------------------------------
do
    local M = {}
    function M.init(env)
        env.page_size = env.engine.schema.config:get_int("menu/page_size") or 5
    end

    function M.func(key, env)
        if key:release() or key:alt() or key:ctrl() or key:super() then return 2 end
        local key_repr = key:repr()
        if key_repr ~= "comma" and key_repr ~= "period" then return 2 end

        local context = env.engine.context
        if not context:is_composing() or not context:has_menu() or NS.phrase_mode then
            return 2
        end

        local comp = context.composition
        if comp:empty() then return 2 end
        local seg = comp:back()
        if not seg then return 2 end

        local has_multiple_pages = (seg:get_candidate_at(env.page_size) ~= nil)

        if not has_multiple_pages then
            local cand = context:get_selected_candidate()
            if cand then
                env.engine:commit_text(cand.text)
                if key_repr == "comma" then
                    env.engine:commit_text("，")
                else
                    env.engine:commit_text("。")
                end
                context:clear()
                return 1
            end
        end
        return 2
    end
    modules.paging_or_commit = M
end

-- ==========================================================
-- 模块注册
-- ==========================================================
for name, module in pairs(modules) do
    _G[name] = module
    NS.modules[name] = module
end

--------------------------------------------------------------------------------
-- 14. weight_updater（日志轮转：按日期重命名，而非固定 .old）
--------------------------------------------------------------------------------
do
    local WeightUpdater = {}
    local C = {
        base_weight     = 1,
        freq_gain       = 3,
        half_life       = 120,
        enable_jianma   = true,
        enable_mazhang  = true,
        enable_qu       = true,
        jianma_l1_bonus = 1.2,
        jianma_l2_bonus = 1.1,
        jianma_l3_bonus = 1.05,
        mazhang_len1    = 1.2,
        mazhang_len2    = 1.1,
        mazhang_len3    = 1.0,
        mazhang_len4    = 0.9,
        mazhang_len5    = 0.8,
        mazhang_len6    = 0.7,
        qu_h            = 1.02,
        qu_s            = 1.01,
        qu_p            = 0.99,
        qu_n            = 0.98,
        qu_z            = 0.95,
        penalty_chongma = 0.999,
        penalty_xuci    = 0.85,
    }

    local function get_dicts_dir()
        local user_dir = ""
        if rime_api and type(rime_api.get_user_data_dir) == "function" then
            user_dir = rime_api.get_user_data_dir()
        else
            local env = os.getenv
            user_dir = env('APPDATA') and (env('APPDATA') .. '/Rime') or '.'
        end
        user_dir = user_dir:gsub("\\", "/")
        if not user_dir:match("/$") then
            user_dir = user_dir .. "/"
        end
        return user_dir .. "dicts/"
    end

    local dicts = get_dicts_dir()
    local FREQ_FILE = dicts .. 'wubi.freq.txt'
    local LOG_FILE = dicts .. 'wubi.weight.update.log'
    -- 虚词列表：实际文件为 .dict.yaml（YAML 头 + ... 分隔 + 纯词列表体）。
    -- load_xuci_map 的解析器本就按「... 之后取非注释行」工作，直接指向 yaml 即可，
    -- 无需另存一份 .txt（旧代码指向 wubi.xuci.txt 导致文件不存在、惩罚静默失效）。
    local XUCI_FILE = dicts .. 'wubi.xuci.dict.yaml'

    local function load_xuci_map()
        local xuci_map = {}
        local status_ok, f = pcall(io.open, XUCI_FILE, 'r')
        if not status_ok or not f then
            return xuci_map
        end

        local in_body = false
        for line in f:lines() do
            if not in_body then
                if line:match('^%s*%.%.%.%s*$') then
                    in_body = true
                end
            else
                local trimmed = line:gsub('^%s*', ''):gsub('%s*$', '')
                if trimmed ~= '' and not trimmed:match('^#') and not trimmed:match('^name:') and not trimmed:match('^version:') and not trimmed:match('^columns:') then
                    local word = trimmed:match('^([^\t]+)')
                    if word then
                        xuci_map[word] = true
                    end
                end
            end
        end
        f:close()
        return xuci_map
    end

    local function parse_dict(filepath)
        local status_ok, f = pcall(io.open, filepath, 'r')
        if not status_ok or not f then return nil end

        local lines = {}
        local entries = {}
        local code_map = {}
        local pair_idx = {}
        local in_body = false
        local has_duplicates = false

        for line in f:lines() do
            if not in_body then
                table.insert(lines, { text = line, drop = false })
                if line:match('^%s*%.%.%.%s*$') then
                    in_body = true
                end
            else
                local trimmed = line:gsub('^%s*', ''):gsub('%s*$', '')
                if trimmed ~= '' and not trimmed:match('^#') and not trimmed:match('^name:') and not trimmed:match('^version:') then
                    local word, code, weight_str, suffix = trimmed:match('^([^\t]+)\t([^\t]+)\t?(%d*)(.*)$')
                    if word and code then
                        local weight = tonumber(weight_str) or C.base_weight
                        local key = word .. '\t' .. code

                        if pair_idx[key] then
                            local old_idx = pair_idx[key]
                            if weight > entries[old_idx].weight then
                                entries[old_idx].weight = weight
                                entries[old_idx].suffix = suffix
                            end
                            table.insert(lines, { text = line, drop = true })
                            has_duplicates = true
                        else
                            local idx = #entries + 1
                            entries[idx] = { word = word, code = code, weight = weight, suffix = suffix }
                            pair_idx[key] = idx
                            table.insert(lines, { text = line, drop = false, entry_idx = idx })

                            local lower_code = code:lower()
                            if not code_map[lower_code] then code_map[lower_code] = {} end
                            table.insert(code_map[lower_code], idx)
                        end
                    else
                        table.insert(lines, { text = line, drop = false })
                    end
                else
                    table.insert(lines, { text = line, drop = false })
                end
            end
        end
        f:close()
        return { lines = lines, entries = entries, code_map = code_map, has_duplicates = has_duplicates }
    end

    local function write_dict_direct(filepath, lines, entries, new_weights, new_version)
        local tmp_path = filepath .. '.tmp'
        local bak_path = filepath .. '.bak'

        local status_ok, f = pcall(io.open, tmp_path, 'w')
        if not status_ok or not f then return false end

        local write_success, write_err = pcall(function()
            local version_updated = false
            for _, l_obj in ipairs(lines) do
                if not l_obj.drop then
                    if not version_updated and l_obj.text:match('^version:') then
                        f:write(string.format('version: "%s"\n', new_version))
                        version_updated = true
                    elseif l_obj.entry_idx then
                        local e = entries[l_obj.entry_idx]
                        local new_w = new_weights[l_obj.entry_idx]
                        f:write(e.word .. '\t' .. e.code .. '\t' .. string.format('%d', new_w) .. (e.suffix or "") .. '\n')
                    else
                        f:write(l_obj.text .. '\n')
                    end
                end
            end
        end)
        f:close()

        if not write_success then
            os.remove(tmp_path)
            return false
        end

        local original_exists = false
        local ok, f_orig = pcall(io.open, filepath, 'r')
        if ok and f_orig then
            f_orig:close()
            original_exists = true
        end

        if original_exists then
            local rename_ok = os.rename(filepath, bak_path)
            if not rename_ok then
                os.remove(tmp_path)
                return false
            end
        end

        local replace_ok = os.rename(tmp_path, filepath)
        if not replace_ok then
            if original_exists then
                os.rename(bak_path, filepath)
            end
            os.remove(tmp_path)
            return false
        end

        if original_exists then
            os.remove(bak_path)
        end
        return true
    end

    local function load_freq_data()
        local freq_data = {}

        if #NS.freq_log_queue > 0 then
            local freq_file = dicts .. 'wubi.freq.txt'
            local status_ok, f_q = pcall(io.open, freq_file, "a")
            if status_ok and f_q then
                local all_success = true
                for _, ln in ipairs(NS.freq_log_queue) do
                    local w_ok = pcall(function() f_q:write(ln .. "\n") end)
                    if not w_ok then
                        all_success = false
                        break
                    end
                end
                f_q:close()
                if all_success then
                    NS.freq_log_queue = {}
                end
            end
        end

        local parse_ok = true
        local status_ok, f = pcall(io.open, FREQ_FILE, 'r')
        if status_ok and f then
            parse_ok = pcall(function()
                for line in f:lines() do
                    local parts = {}
                    for part in line:gmatch("[^\t]+") do
                        table.insert(parts, part)
                    end

                    if #parts >= 5 then
                        local ob_word = parts[1]
                        local timestamp = parts[5]

                        local function safe_deobfuscate(str)
                            local res = ""
                            for hex in str:gmatch("%x%x") do
                                local b = (tonumber(hex, 16) - 0x5A) % 256
                                if b < 0 then b = b + 256 end
                                res = res .. string.char(b)
                            end
                            return res
                        end

                        local word = safe_deobfuscate(ob_word)
                        local ts_num = os.time()

                        if timestamp:match('^%d+$') then
                            ts_num = tonumber(timestamp)
                        else
                            local y, m, d, h, min, s = timestamp:match('(%d+)[-/](%d+)[-/](%d+)%s+(%d+):(%d+):(%d+)')
                            if y and m and d and h and min and s then
                                ts_num = os.time({year=tonumber(y), month=tonumber(m), day=tonumber(d), hour=tonumber(h), min=tonumber(min), sec=tonumber(s)})
                            end
                        end

                        if not freq_data[word] then
                            freq_data[word] = { count = 0, timestamp = 0 }
                        end
                        freq_data[word].count = freq_data[word].count + 1
                        if ts_num > freq_data[word].timestamp then
                            freq_data[word].timestamp = ts_num
                        end
                    end
                end
            end)
            f:close()

            if not parse_ok then
                freq_data = {}
            else
                local clear_ok, clear_f = pcall(io.open, FREQ_FILE, 'w')
                if clear_ok and clear_f then
                    clear_f:close()
                end
            end
        end

        return freq_data
    end

    local function compute_weight(entry, freq_data, current_time, is_chaos, xuci_map)
        local word = entry.word
        local code = entry.code
        local old_weight = entry.weight
        local freq = freq_data[word]
        local new_weight = old_weight

        if freq then
            local count = freq.count
            local timestamp = freq.timestamp
            local days_diff = math.max(0, (current_time - timestamp) / 86400.0)
            local decay = 0.5 ^ (days_diff / C.half_life)
            local increment = count * C.freq_gain

            if C.enable_jianma then
                local len = #code
                if len == 1 then increment = increment * C.jianma_l1_bonus
                elseif len == 2 then increment = increment * C.jianma_l2_bonus
                elseif len == 3 then increment = increment * C.jianma_l3_bonus end
            end

            if C.enable_mazhang then
                local len = #code
                if len == 1 then increment = increment * C.mazhang_len1
                elseif len == 2 then increment = increment * C.mazhang_len2
                elseif len == 3 then increment = increment * C.mazhang_len3
                elseif len == 4 then increment = increment * C.mazhang_len4
                elseif len == 5 then increment = increment * C.mazhang_len5
                else increment = increment * C.mazhang_len6 end
            end

            if C.enable_qu then
                local first = code:sub(1,1):lower()
                if first:match('[gftdn]') then increment = increment * C.qu_h
                elseif first:match('[hjkl]') then increment = increment * C.qu_s
                elseif first:match('[tq]') then increment = increment * C.qu_p
                elseif first:match('[yp]') then increment = increment * C.qu_n
                elseif first:match('[nbvcxz]') then increment = increment * C.qu_z end
            end

            new_weight = old_weight * decay + increment
        else
            new_weight = old_weight
        end

        if xuci_map[word] then
            new_weight = new_weight * C.penalty_xuci
        end

        if new_weight < C.base_weight * 0.7 then
            new_weight = C.base_weight * 0.7
        end

        return math.floor(new_weight + 0.5)
    end

    local function process_dict(dict_name, is_chaos, freq_data, current_time, xuci_map)
        local filepath = dicts .. dict_name
        local parsed = parse_dict(filepath)
        if not parsed then return nil end

        local entries = parsed.entries
        local code_map = parsed.code_map
        local lines = parsed.lines
        local has_duplicates = parsed.has_duplicates

        local new_weights = {}
        for i, entry in ipairs(entries) do
            new_weights[i] = compute_weight(entry, freq_data, current_time, is_chaos, xuci_map)
        end

        if not is_chaos then
            for code, indices in pairs(code_map) do
                if #indices > 1 then
                    local has_used_in_code = false
                    for _, idx in ipairs(indices) do
                        if freq_data[entries[idx].word] then
                            has_used_in_code = true
                            break
                        end
                    end

                    if has_used_in_code then
                        for _, idx in ipairs(indices) do
                            local entry = entries[idx]
                            if not freq_data[entry.word] then
                                new_weights[idx] = math.floor(new_weights[idx] * C.penalty_chongma + 0.5)
                            end
                        end
                    end
                end
            end
        end

        local changes = {}
        local has_changes = false

        for i, entry in ipairs(entries) do
            if new_weights[i] ~= entry.weight then
                has_changes = true
                table.insert(changes, { word = entry.word, code = entry.code, old = entry.weight, new = new_weights[i] })
            end
        end

        if not has_changes and not has_duplicates then
            return { has_changes = false, entries = #entries }
        end

        local new_version = os.date('%Y-%m-%d')
        local write_ok = write_dict_direct(filepath, lines, entries, new_weights, new_version)

        if not write_ok then return nil end

        return { has_changes = has_changes, changes = changes, entries = #entries }
    end

    function WeightUpdater.execute()
        -- 【日志轮转】当文件超过 1MB 时，重命名为带日期的文件（例如 wubi.weight.update.20260807.log）
        local log_size = 0
        local f_check = io.open(LOG_FILE, "r")
        if f_check then
            log_size = f_check:seek("end")
            f_check:close()
        end
        if log_size > 1048576 then
            local date_str = os.date("%Y%m%d")
            local new_file = dicts .. "wubi.weight.update." .. date_str .. ".log"
            os.remove(new_file)        -- 删除可能存在的同名旧文件
            os.rename(LOG_FILE, new_file)
        end

        local now_ts = os.time()
        local xuci_map = load_xuci_map()
        local freq_data = load_freq_data()

        local dict_list = {
            { name = 'wubi.word.dict.yaml',   chaos = false },
            { name = 'wubi.phrase.dict.yaml', chaos = false },
            { name = 'wubi.user.dict.yaml',   chaos = false },
            { name = 'wubi.long.dict.yaml',   chaos = false },
            { name = 'wubi.low.dict.yaml',    chaos = false },
            { name = 'wubi.chaos.dict.yaml',  chaos = true  },
        }

        local all_changes = {}
        local total_entries = 0
        local up_count = 0
        local down_count = 0

        for _, dict in ipairs(dict_list) do
            local res = process_dict(dict.name, dict.chaos, freq_data, now_ts, xuci_map)
            if res then
                total_entries = total_entries + res.entries
                if res.has_changes then
                    for _, chg in ipairs(res.changes) do
                        table.insert(all_changes, chg)
                        if chg.new > chg.old then
                            up_count = up_count + 1
                        else
                            down_count = down_count + 1
                        end
                    end
                end
            end
        end

        local now_str = os.date("%Y-%m-%d %H:%M:%S", now_ts)
        local lf_ok, lf = pcall(io.open, LOG_FILE, "a")
        if lf_ok and lf then
            lf:write("----------------------------------------\n\n")
            lf:write(string.format("[%s] 权重更新报告（共 %d 个词条，%d ↑，%d ↓）\n", now_str, total_entries, up_count, down_count))

            if #all_changes == 0 then
                lf:write("  (本次部署没有词频调整)\n\n")
            else
                for _, chg in ipairs(all_changes) do
                    lf:write(string.format("  + %s (%s): %d → %d\n", chg.word, chg.code, chg.old, chg.new))
                end
                lf:write("\n")
            end

            lf:write("----------------------------------------\n\n")
            lf:close()
        end
    end

    pcall(WeightUpdater.execute)
end
