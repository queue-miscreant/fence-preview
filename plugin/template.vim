if !has("nvim")
  echo "Plugin not supported outside of nvim"
  finish
endif

if !exists("g:nvim_image_extmarks_loaded")
  echo "Missing dependency nvim_image_extmarks"
  finish
endif

lua require "fence_preview"
