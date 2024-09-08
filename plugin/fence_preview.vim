if !has("nvim")
  echohl ErrorMsg
  echo "fence-preview: Plugin not supported outside of nvim"
  echohl
  finish
endif

if !exists("g:nvim_image_extmarks_loaded")
  echohl ErrorMsg
  echo "fence-preview: Missing dependency nvim_image_extmarks"
  echohl
  finish
endif


" Can use virtual extmarks instead of inline ones
let g:fence_preview_image_extmark_handler = get(
      \ g:,
      \ "fence_preview_image_extmark_handler",
      \ "sixel_virtual")
if g:image_extmarks_allow_virtual == 0
  let g:fence_preview_image_extmark_handler = 
      \ "sixel_inline"
end

hi default link FencePreviewText Comment
hi default link FencePreviewPath FencePreviewText
hi default link FencePreviewError ErrorMsg

" let g:image_extmarks_slow_insert = 1
