-- COLORSCHEME
-- Onehalfdark

return {
	{
		"ClearAspect/onehalf",

		lazy = false,
		priority = 1000,

		opts = {
			transparency = false,
		},

		config = function(_, opts)
			require("onehalf").setup(opts)
			vim.cmd.colorscheme("onehalfdark")
		end,
	},
}
