-- Omarchy Mobile Clean: rounded corners and quiet borders. The shell's
-- cards and sheets take their corner radius from decoration:rounding.
local active_border_color = "rgb(c9d0db)"
local inactive_border_color = "rgb(e4e8ef)"

hl.config({
  general = {
    col = {
      active_border = active_border_color,
      inactive_border = inactive_border_color,
    },
  },

  decoration = {
    rounding = 16,
  },

  group = {
    col = {
      border_active = active_border_color,
      border_inactive = inactive_border_color,
    },
  },
})
