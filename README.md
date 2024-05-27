fence-preview
=============

A plugin for previewing images from nvim.
Somewhat of a reimplementation of [vim-graphical-preview](https://github.com/bytesnake/vim-graphical-preview),
which refused to compile on my Linux box.

Forked from (and depends upon) [nvim-image-extmarks](https://github.com/queue-miscreant/nvim-image-extmarks).


Requirements
------------

- ImageMagick
- LaTeX (optional)
- Python libraries:
    - pynvim
    - wand (Python Imagemagick wrapper)
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

- LaTeX update rendering currently forces all images to be available first
