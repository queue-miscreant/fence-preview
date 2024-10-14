if !has("nvim")
  echohl ErrorMsg
  echo "fence-preview: Plugin not supported outside of nvim"
  echohl
  finish
endif

hi default link FencePreviewText Comment
hi default link FencePreviewPath FencePreviewText
hi default link FencePreviewError ErrorMsg

" let g:image_extmarks_slow_insert = 1
