-- LSP
-- Native Neovim LSP + Mason

local servers = {
	"lua_ls",
	"bashls",
	"jsonls",
	"yamlls",
	"html",
	"cssls",
	"ts_ls",
	"dockerls",
	"docker_compose_language_service",
	"intelephense",
}

return {
	{
		"mason-org/mason-lspconfig.nvim",
		lazy = false,
		dependencies = {
			{
				"mason-org/mason.nvim",
				opts = {
					ui = {
						border = "rounded",
						icons = {
							package_installed = "✓",
							package_pending = "➜",
							package_uninstalled = "✗",
						},
					},
				},
			},
			{
				"neovim/nvim-lspconfig",
				lazy = false,
			},
		},
		opts = {
			ensure_installed = servers,
			automatic_enable = servers,
		},
		config = function(_, opts)
			vim.diagnostic.config({
				signs = true,
				underline = true,
				virtual_text = {
					spacing = 2,
					source = "if_many",
					prefix = "●",
				},
				virtual_lines = false,
				update_in_insert = false,
				severity_sort = true,
				float = {
					border = "rounded",
					source = "if_many",
					header = "",
					prefix = "",
				},
			})

			local group = vim.api.nvim_create_augroup("UserLspConfig", {
				clear = true,
			})

			vim.api.nvim_create_autocmd("LspAttach", {
				group = group,
				desc = "Налаштування LSP для buffer",
				callback = function(event)
					local bufnr = event.buf

					local function map(mode, lhs, rhs, desc)
						vim.keymap.set(mode, lhs, rhs, {
							buffer = bufnr,
							silent = true,
							desc = desc,
						})
					end

					map("n", "gd", vim.lsp.buf.definition, "LSP: Definition")
					map("n", "gD", vim.lsp.buf.declaration, "LSP: Declaration")
					map("n", "gr", vim.lsp.buf.references, "LSP: References")
					map("n", "gi", vim.lsp.buf.implementation, "LSP: Implementation")
					map("n", "gt", vim.lsp.buf.type_definition, "LSP: Type definition")
					map("n", "K", vim.lsp.buf.hover, "LSP: Hover")
					map("i", "<C-k>", vim.lsp.buf.signature_help, "LSP: Signature help")
					map({ "n", "v" }, "<leader>ca", vim.lsp.buf.code_action, "LSP: Code action")
					map("n", "<leader>rn", vim.lsp.buf.rename, "LSP: Rename")
					map("n", "<leader>ls", vim.lsp.buf.document_symbol, "LSP: Document symbols")
					map("n", "<leader>lS", vim.lsp.buf.workspace_symbol, "LSP: Workspace symbols")
					map("n", "<leader>ld", vim.diagnostic.open_float, "LSP: Diagnostic")
					map("n", "<leader>lq", vim.diagnostic.setloclist, "LSP: Diagnostic list")
					map("n", "]d", function()
						vim.diagnostic.jump({ count = 1, float = true })
					end, "Diagnostic: Next")
					map("n", "[d", function()
						vim.diagnostic.jump({ count = -1, float = true })
					end, "Diagnostic: Previous")
				end,
			})

			require("mason-lspconfig").setup(opts)
		end,
	},
}
