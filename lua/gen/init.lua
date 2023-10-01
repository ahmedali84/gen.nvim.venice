local M = {}

local curr_buffer = nil
local start_pos = nil
local end_pos = nil

local function trim_table(tbl)
    local function is_whitespace(str) return str:match("^%s*$") ~= nil end

    while #tbl > 0 and (tbl[1] == "" or is_whitespace(tbl[1])) do
        table.remove(tbl, 1)
    end

    while #tbl > 0 and (tbl[#tbl] == "" or is_whitespace(tbl[#tbl])) do
        table.remove(tbl, #tbl)
    end

    return tbl
end

M.exec = function(opts)
    pcall(io.popen, 'ollama serve > /dev/null 2>&1 &')
    curr_buffer = vim.fn.bufnr('%')
    start_pos = vim.fn.getpos("'<")
    end_pos = vim.fn.getpos("'>")
    end_pos[3] = vim.fn.col("'>") -- in case of `V`, it would be maxcol instead

    local content = table.concat(vim.api.nvim_buf_get_text(curr_buffer,
                                                           start_pos[2] - 1,
                                                           start_pos[3] - 1,
                                                           end_pos[2] - 1,
                                                           end_pos[3] - 1, {}),
                                 '\n')
    local text = vim.fn.shellescape(lines)

    local function substitute_placeholders(input)
        if not input then return end
        local text = input
        text = string.gsub(text, "%$text", content)
        text = string.gsub(text, "%$filetype", vim.bo.filetype)
        if string.find(text, "$input1") then
            local input1 = vim.fn.input("input1: ")
            text = string.gsub(text, "%$input1", input1)
        end
        return text
    end

    local instruction = substitute_placeholders(opts.prompt)
    local extractor = substitute_placeholders(opts.extract)
    local cmd = 'ollama run mistral:instruct """' .. instruction .. '"""'
    if result_buffer then vim.cmd('bd' .. result_buffer) end
    -- vim.cmd('vs enew')
    local width = math.floor(vim.o.columns * 0.9) -- 90% of the current editor's width
    local height = math.floor(vim.o.lines * 0.9)
    local row = math.floor((vim.o.lines - height) / 2)
    local col = math.floor((vim.o.columns - width) / 2)

    local cursor = vim.api.nvim_win_get_cursor(0)
    local new_win_width = vim.api.nvim_win_get_width(0)
    local win_height = vim.api.nvim_win_get_height(0)

    local middle_row = win_height / 2

    local new_win_height = math.floor(win_height / 2)
    local new_win_row
    if cursor[1] <= middle_row then
        new_win_row = 5
    else
        new_win_row = -5 - new_win_height
    end

    local win_opts = {
        relative = 'cursor',
        width = new_win_width,
        height = new_win_height,
        row = new_win_row,
        col = 0,
        style = 'minimal',
        border = 'single'
    }
    result_buffer = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_buf_set_option(result_buffer, 'filetype', 'markdown')

    local float_win = vim.api.nvim_open_win(result_buffer, true, win_opts)

    local result_string = ''
    local lines = {}
    local job_id = vim.fn.jobstart(cmd, {
        on_stdout = function(_, data, _)
            result_string = result_string .. table.concat(data, '\n')
            lines = vim.split(result_string, '\n', true)
            vim.api.nvim_buf_set_lines(result_buffer, 0, -1, false, lines)
        end,
        on_exit = function(a, b)
            if b == 0 and opts.replace then
                if extractor then
                    local extracted = result_string:match(extractor)
                    if not extracted then
                        vim.cmd('bd ' .. result_buffer)
                        return
                    end
                    lines = vim.split(extracted, '\n', true)
                end
                lines = trim_table(lines)
                vim.api.nvim_buf_set_text(curr_buffer, start_pos[2] - 1,
                                          start_pos[3] - 1, end_pos[2] - 1,
                                          end_pos[3] - 1, lines)
                vim.cmd('bd ' .. result_buffer)
            end
        end
    })
    vim.keymap.set('n', '<esc>', function() vim.fn.jobstop(job_id) end,
                   {buffer = result_buffer})

    vim.api.nvim_buf_attach(result_buffer, false,
                            {on_detach = function() result_buffer = nil end})

end

M.prompts = {
    Summarize = {prompt = "Summarize the following text:\n\n```\n$text\n```"},
    Ask = {prompt = "Regarding the following text, $input1:\n\n```\n$text\n```"},
    Enhance_Grammar = {
        prompt = "Enhance the grammar and spelling in the following text:\n\n```\n$text\n```",
        replace = true
    },
    Enhance_Wording = {
        prompt = "Enhance the wording in the following text:\n\n```\n$text\n```",
        replace = true
    },
    Make_Concise = {
        prompt = "Make the following text as simple and concise as possible:\n\n```\n$text\n```",
        replace = true
    },
    Make_List = {
        prompt = "Render the following text as a markdown list:\n\n```\n$text\n```",
        replace = true
    },
    Make_Table = {
        prompt = "Render the following text as a markdown table:\n\n```\n$text\n```",
        replace = true
    },
    Review_Code = {
        prompt = "Review the following code and make concise suggestions:\n\n```$filetype\n$text\n```"
    },
    Enhance_Code = {
        prompt = "Enhance the following code, only ouput the result in format ```$filetype\n...\n```:\n\n```$filetype\n$text\n```",
        replace = true,
        extract = "```$filetype\n(.-)```"
    },
    Change_Code = {
        prompt = "Regarding the following code, $input1, only ouput the result in format ```$filetype\n...\n```:\n\n```$filetype\n$text\n```",
        replace = true,
        extract = "```$filetype\n(.-)```"
    }
}

function select_prompt(cb)
    local promptKeys = {}
    for key, _ in pairs(M.prompts) do table.insert(promptKeys, key) end
    vim.ui.select(promptKeys, {
        prompt = 'Prompt:',
        format_item = function(item)
            return table.concat(vim.split(item, '_'), ' ')
        end
    }, function(item, idx) cb(item) end)
end

vim.api.nvim_create_user_command('Gen', function()
    select_prompt(function(item) M.exec(M.prompts[item]) end)

end, {range = true, nargs = '?'})

return M