Reasons to not like floating windows
====================================

Option 1: Window always open, enter only when in InsertEnter while between fences
--------------------------------------------------------------------------------

This is a good idea, but it has the disadvantage having to play nice with the `number` option.

If the sign column is enabled in the child window, it is not enabled in the parent, and
there is no autocmd to detect if a sign has been added.

Changes in the parent buffer (for example, undos, deleting the fence) must be reflected in
the child buffer.

Extmarks must be reset when content in the parent buffer is changed, since content at `end_row` is overwritten

`a` and `A` must be treated specially


Option 2: Window opened when the cursor is moved between fences
-------------------------------------------------------------------------------

Similar disadvantages to above.

This has the additional disadvantage of deleting the undo tree when the buffer is closed.
While this can be addressed by keeping the buffer open, it is annoying when in the parent
window and an undo places the cursor within the fence.


Option 3: Splits
--------------------------------------------------------------------------------

Does not obscure text in the parent buffer.

Parent buffer can be used as preview when working on another buffer.

Only need to sync changes and redraw parent on write to the child buffer.



Reasons to regenerate the whole node tree on buffer change
==========================================================

Diffs would be great, for example, for only updating the contents of one fence.
However, this isn't quite feasible. For example, it's not clear what adding "```" will do
at an arbitrary line of the file.

Additionally, arbitrary buffer contents can cause the lengths of other nodes to change, for example, file nodes.

On the other hand, calculating fence boundaries in Lua for speed is a very good idea.
