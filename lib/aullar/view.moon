-- Copyright 2014 Nils Nordman <nino at nordman.org>
-- License: MIT (see LICENSE)

ffi = require 'ffi'
ffi_cast = ffi.cast

Gdk = require 'ljglibs.gdk'
Gtk = require 'ljglibs.gtk'
Pango = require 'ljglibs.pango'
Layout = Pango.Layout
require 'ljglibs.cairo.cairo'
pango_cairo = Pango.cairo
Cursor = require 'aullar.cursor'
Buffer = require 'aullar.buffer'
{:define_class} = require 'aullar.util'
{:parse_key_event} = require 'ljglibs.util'
{:max, :min, :abs} = math

insertable_character = (event) ->
  return false if event.ctrl or event.alt or event.meta or event.super or not event.character
  true

contains_newlines = (s) ->
  s\find('[\n\r]') != nil

on_key_press = (area, event, view) ->
  event = parse_key_event event

  if view.on_key_press
    handled = view.on_key_press view, event
    return if handled == true

  if insertable_character(event)
    view\insert event.character

draw_cursor = (base_y, column, cr, layout, height, view) ->
  cr\save!
  rect = layout\index_to_pos column
  cr\set_source_rgb 1, 0, 0
  base_x = math.max rect.x / 1024 - 1, 0
  cr\rectangle base_x, base_y + rect.y / 1024, view.cursor_width, rect.height / 1024
  cr\fill!
  cr\restore!

signals = {
  on_draw: (_, cr, view) -> view._draw view, cr
  on_screen_changed: (_, _, view) -> view._on_screen_changed view
  on_size_allocate: (_, allocation, view) ->
    view._on_size_allocate view, ffi_cast('GdkRectangle *', allocation)
}

View = {
  new: (@_buffer = Buffer('')) =>
    @cursor_width = 1.5
    @line_spacing = 0.1
    @_first_visible_line = 1
    @_last_visible_line = 1
    @area = Gtk.DrawingArea!
    @cursor = Cursor @

    with @area
      .can_focus = true
      \add_events Gdk.KEY_PRESS_MASK
      \on_key_press_event on_key_press, @
      \on_draw signals.on_draw, @
      \on_screen_changed signals.on_screen_changed, @
      \on_size_allocate signals.on_size_allocate, @

    @_reset_display!

  properties: {

    first_visible_line: {
      get: => @_first_visible_line
      set: (line) =>
        if line != @_first_visible_line
          @_first_visible_line = line
          @_last_visible_line = line
          @area\queue_draw!
    }

    last_visible_line: {
      get: => @_last_visible_line
      set: (line) =>
        -- todo: variable height lines
        @first_visible_line = (line - @lines_showing) + 1
        @_last_visible_line = line
    }

    lines_showing: => @last_visible_line - @first_visible_line + 1

    buffer: {
      get: => @_buffer
      set: (buffer) =>
        @_buffer = buffer
    }
  }

  insert: (text) =>
    cur_pos = @cursor.pos
    @_buffer\insert cur_pos - 1, text

    if contains_newlines(text)
      @refresh_display cur_pos - 1, nil, true
    else
      @refresh_display cur_pos - 1, cur_pos + #text - 1, true

    @cursor.pos += #text

  delete_back: =>
    cur_line = @cursor.line
    cur_pos = @cursor.pos
    @cursor\backward!
    @_buffer\delete @cursor.pos - 1, cur_pos - @cursor.pos

    if cur_line != @cursor.line -- lines changed, everything after is invalid
      @refresh_display @cursor.pos - 1, nil, true
    else -- within the current line
      @refresh_display @cursor.pos - 1, cur_pos - 1, true

  to_gobject: => @area

  _draw: (cr) =>
    p_ctx = @area.pango_context
    line_spacing = @line_spacing
    cursor_pos = @cursor.pos - 1
    clip = cr.clip_extents

    cr\move_to 0, 0
    cr\set_source_rgb 0, 0, 0
    x, y = 0, 0
    last_visible_line = 0

    for line in @_buffer\lines @_first_visible_line
      d_line = @display_lines[line.nr]
      break if y >= clip.y2

      if y >= clip.y1
        pango_cairo.show_layout cr, d_line.layout

        if cursor_pos >= line.start_offset and cursor_pos <= line.end_offset
          draw_cursor y, cursor_pos - line.start_offset, cr, d_line.layout, height, @

      if y + d_line.height < clip.y2
        last_visible_line = line.nr

      y += d_line.height + d_line.spacing_bottom
      cr\move_to x, y

    @_last_visible_line = max(@_last_visible_line or 0, last_visible_line)

  refresh_display: (from_offset, to_offset, invalidate = false) =>
    return unless @_last_visible_line and @width
    d_lines = @display_lines
    min_y, max_y = nil, nil
    y = 0
    last_valid = 0

    for line_nr = @_first_visible_line, @_last_visible_line
      d_line = d_lines[line_nr]
      line = @_buffer\get_line line_nr
      after = to_offset and line.start_offset > to_offset
      break if after
      before = line.end_offset < from_offset

      if not(before or after) or (after and not to_offset)
        d_lines[line.nr] = nil if invalidate
        min_y or= y
        max_y = y + d_line.height + d_line.spacing_bottom
      else
        last_valid = max last_valid, line.nr

      y += d_line.height + d_line.spacing_bottom


    if invalidate and not to_offset
      max_y = @height
      for line_nr = last_valid + 1, @_max_display_line
        d_lines[line_nr] = nil

      @_max_display_line = last_valid

    if min_y
      @area\queue_draw_area 0, min_y, @width, max_y - min_y

  _on_screen_changed: =>
    @_reset_display!

  _on_size_allocate: (allocation) =>
    @_reset_display!
    @width = allocation.width
    @height = allocation.height

  _reset_display: =>
    @_max_display_line = 0
    v = @
    @display_lines = setmetatable {}, {
      __index: (t, nr) ->
        line = v.buffer\get_line nr
        layout = Layout v.area.pango_context
        layout\set_text line.text, line.size
        width, height = layout\get_pixel_size!
        spacing_bottom = height * v.line_spacing
        d_line = {
          width: width + v.cursor_width, :height,
          :layout, :spacing_bottom
        }
        v._max_display_line = max v._max_display_line, nr
        rawset t, nr, d_line
        d_line
    }
}

define_class View
