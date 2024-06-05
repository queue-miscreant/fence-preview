fence-preview
=============

A plugin for previewing images from nvim.
Somewhat of a reimplementation of [vim-graphical-preview](https://github.com/bytesnake/vim-graphical-preview),
which refused to compile on my Linux box.

A sister project to [nvim-image-extmarks](https://github.com/queue-miscreant/nvim-image-extmarks),
which it depends upon.


Requirements
------------

- ImageMagick
- LaTeX (optional)
- Python libraries:
    - pynvim
    - wand (Python ImageMagick wrapper)
- Plugins
    - [nvim-image-extmarks](https://github.com/queue-miscreant/nvim-image-extmarks)


Installation
------------

### Vundle

<!--
Place the following in `~/.config/nvim/init.vim`:
```vim
Plugin '...', { 'do': ':UpdateRemotePlugins' }
```
Make sure the file is sourced and run `:PluginInstall`.
-->


Commands
--------

Plugin commands


Functions
---------

Exposed functions


Keys
----

Plugin keybinds


Configuration
-------------

Global variables


Highlights
----------

Plugin highlights


TODOs
-----

- Regenerate LaTeX only when cursor is outside fence (and extmark can be re-rendered)
- Identify fences by position in file
  - The cursor can be detected as "in fence 1, 2, 3..." 
- Open fence content in split
    - "Phantom" preamble for "math" (TeX) content
    - [-] BufWrite triggers update to fence and shows preview in parent buffer
    - Height can be controlled by a comment in the split 
- Forced heights use folds outside of fences
    - Open fold by entering split
    - This requires extra logic for extmark height!
- Default LaTeX display is not eye-searing
    - Simple: white text on black
    - Difficult: configurable, white text on transparent
    - Hide content with highlights
    - Highlight removed when cursor crosses fence
- Errors along the LaTeX toolchain render as extmark errors
