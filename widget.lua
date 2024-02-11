-------------------------------------------------
-- awesomewm widget to check protovpn status
--
-- @author Philippe IVALDI
-- @copyright 2024 Philippe IVALDI
-------------------------------------------------
local awful = require("awful")
local wibox = require("wibox")
local gears = require("gears")
local beautiful = require("beautiful")

local is_initialized = false

local tooltip = awful.tooltip {
  mode = 'outside',
  visible = false,
  preferred_positions = { 'bottom' },
  ontop = true,
  border_width = 2,
  border_color = beautiful.bg_focus,
  widget = wibox.widget.textbox,
}

local popup = awful.popup {
    ontop = true,
    visible = false,
    shape = function(cr, width, height)
        gears.shape.rounded_rect(cr, width, height, 4)
    end,
    border_width = 1,
    border_color = beautiful.bg_focus,
    maximum_width = 400,
    offset = { y = 5 },
    widget = {}
}


local waiting_status = "…"
local last_status = waiting_status
local connect_options = "--sc"
local timeout = 10
local format_ok = '<span color="#22FF22">⚛</span>'
local format_ko = '<span color="#FF2222">☠</span>'
local format_error = '<span color="#FF2222">⚠</span>'
local font = ""
local protonvpn_cli_path = "protonvpn"

local wdg = wibox.widget {
  {
    {
      {
        id = "textbox",
        text = last_status,
        widget = wibox.widget.textbox
      },
      layout = wibox.layout.fixed.horizontal,
    },
    left = 1,
    right = 1,
    layout = wibox.container.margin
  },
  widget = wibox.container.background,

  set_status = function(self, textbox_markup, tooltip_text)
    last_status = tooltip_text
    self:get_children_by_id("textbox")[1]:set_markup(textbox_markup)
    tooltip.text = tooltip_text
  end,

  connect = function(self)
    self:set_status(waiting_status, "Reconnecting…")
    awful.spawn.easy_async(
      protonvpn_cli_path .. " c " .. connect_options,
      function(stdout, stderr, _, exitcode)
        local format = ""
        if exitcode ~= 0 then
          format = format_ko
          last_status = stdout .. "\n" .. stderr
        else
          if string.find(stderr .. stdout, ".*Connected!.*") then
            format = format_ok
            last_status = stdout
          else
            format = format_ko
            last_status = stdout .. "\n" .. stderr
          end
        end

        self:set_status(format, last_status)
      end
    )
  end,

  disconnect = function(self)
    self:set_status(waiting_status, "Disconnecting…")
    awful.spawn.easy_async(
      protonvpn_cli_path .. " d ",
      function(stdout, stderr, _, exitcode)
        local format = ""
        if exitcode ~= 0 then
          format = format_error
          last_status = stdout .. "\n" .. stderr
        else
          if string.find(stderr .. stdout, "^Disconnected\\.") then
            format = format_ko
            last_status = stdout
          else
            format = format_error
            last_status = stdout .. "\n" .. stderr
          end
        end

        self:set_status(format, last_status)
      end
    )
  end,
}

local menu_items = {
  { name = "(Re)Connect",
    cmd = function()
      wdg:connect()
    end,
    txt_icon = "▶"
  },
  { name = "Disconnect",
    cmd = function()
      wdg:disconnect()
    end,
    txt_icon = "✖"
  },
}

local function build_menu()
  -- awful.menu(terms):toggle()
  local rows = { layout = wibox.layout.fixed.vertical }
  for _, item in ipairs(menu_items) do
    local row = wibox.widget {
      {
        {
          {
            text = item.txt_icon,
            widget = wibox.widget.textbox
          },
          {
            text = item.name,
            font = beautiful.font,
            widget = wibox.widget.textbox
          },
          spacing = 12,
          layout = wibox.layout.fixed.horizontal
        },
        margins = 8,
        layout = wibox.container.margin
      },
      bg = beautiful.bg_normal,
      widget = wibox.container.background
    }

    row:connect_signal("mouse::enter", function(c) c:set_bg(beautiful.bg_focus) end)
    row:connect_signal("mouse::leave", function(c) c:set_bg(beautiful.bg_normal) end)

    local old_cursor, old_wibox
    row:connect_signal("mouse::enter", function()
      local wb = mouse.current_wibox
      old_cursor, old_wibox = wb.cursor, wb
      wb.cursor = "pointer"
    end)
    row:connect_signal("mouse::leave", function()
      if old_wibox then
        old_wibox.cursor = old_cursor
        old_wibox = nil
      end
    end)

    row:buttons(awful.util.table.join(awful.button({}, 1, function()
      popup.visible = not popup.visible
      item.cmd()
    end)))

    table.insert(rows, row)
  end

  popup:setup(rows)

  wdg:buttons(
    awful.util.table.join(
      awful.button({}, 1, function()
          if popup.visible then
            popup.visible = not popup.visible
          else
            popup:move_next_to(mouse.current_widget_geometry)
          end
      end)
    )
  )
end

local function update_status()
  awful.spawn.easy_async(
    protonvpn_cli_path .. " s",
    function(stdout, stderr, _, exitcode)
      local format = ""
      if exitcode ~= 0 or stderr ~= "" or not string.find(stdout, "^Status: +Connected.*") then
        format = format_ko
        last_status = stdout .. "\n" .. stderr
      else
        format = format_ok
        last_status = stdout
      end

      wdg:set_status(format, last_status)
    end
  )
end

local function show_tooltip()
  return function()
    tooltip.text = last_status
  end
end

local function init()
  if not is_initialized then
    tooltip:add_to_object(wdg)
    tooltip.font = font
    wdg:get_children_by_id("textbox")[1].font = font
    build_menu()

    local proton_timer = timer({ timeout = timeout })
    proton_timer:connect_signal(
      "timeout",
      function()
        update_status()
      end)

    proton_timer:start()

    wdg:connect_signal('mouse::enter', show_tooltip())

    is_initialized = true
  end
end

local function worker(user_args)
  local args = user_args or {}
  connect_options = args.connect_options or connect_options
  timeout = args.timeout or timeout
  format_ok = args.format_ok or format_ok
  format_ko = args.format_ok or format_ko
  font = args.font or (beautiful.font:gsub("%s%d+$", "") .. " 14")
  protonvpn_cli_path = args.protonvpn_cli_path or protonvpn_cli_path

  init()

  return wdg
end

return worker
