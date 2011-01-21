//  
//  Copyright (C) 2011 Robert Dyer
// 
//  This program is free software: you can redistribute it and/or modify
//  it under the terms of the GNU General Public License as published by
//  the Free Software Foundation, either version 3 of the License, or
//  (at your option) any later version.
// 
//  This program is distributed in the hope that it will be useful,
//  but WITHOUT ANY WARRANTY; without even the implied warranty of
//  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
//  GNU General Public License for more details.
// 
//  You should have received a copy of the GNU General Public License
//  along with this program.  If not, see <http://www.gnu.org/licenses/>.
// 

using Cairo;
using Gdk;
using Gtk;
using Pango;

using Plank.Drawing;

namespace Plank.Widgets
{
	public class HoverWindow : CompositedWindow
	{
		const int HOVER_HEIGHT = 26;
		
		public string Text { get; set; }
		
		ThemeRenderer theme;
		
		Pango.Layout layout;
		
		double text_offset;
		
		public HoverWindow ()
		{
			base.with_type (Gtk.WindowType.POPUP);
			
			theme = new ThemeRenderer ();
			theme.TopRoundness = 3;
			theme.BottomRoundness = 3;
			theme.load ("hover");
			theme.notify.connect (theme_changed);
			
			set_accept_focus (false);
			can_focus = false;
			skip_pager_hint = true;
			skip_taskbar_hint = true;
			set_type_hint (WindowTypeHint.DOCK);
			
			set_redraw_on_allocate (true);
			
			update_layout ();
			style_set.connect (() => update_layout ());
			
			notify["Text"].connect (invalidate);
			
			stick ();
			show_all ();
			hide ();
		}
		
		void theme_changed ()
		{
			background_buffer = null;
			queue_draw ();
		}
		
		public void move_hover (int item_x, int item_y)
		{
			var x = item_x - width_request / 2;
			var y = item_y - height_request - 10;
			
			Gdk.Rectangle monitor;
			get_screen ().get_monitor_geometry (get_screen ().get_monitor_at_point (item_x, item_y), out monitor);
			
			x = (int) Math.fmax (monitor.x, Math.fmin (x, monitor.x + monitor.width - width_request));
			y = (int) Math.fmax (monitor.y, Math.fmin (y, monitor.y + monitor.height - height_request));
			
			move (x, y);
		}
		
		void update_layout ()
		{
			layout = new Pango.Layout (pango_context_get ());
			layout.set_ellipsize (EllipsizeMode.END);
			
			var font_description = get_style ().font_desc;
			font_description.set_absolute_size ((int) (11 * Pango.SCALE));
			font_description.set_weight (Weight.BOLD);
			layout.set_font_description (font_description);
			
			invalidate ();
		}
		
		DockSurface background_buffer;
		
		void invalidate ()
		{
			background_buffer = null;
			
			if (Text == "" || Text == null)
				Text = " ";
			
			// calculate the text layout to find the size
			layout.set_text (Text, -1);
			
			// make the buffer
			Pango.Rectangle ink_rect, logical_rect;
			layout.get_pixel_extents (out ink_rect, out logical_rect);
			if (logical_rect.width > 0.8 * Screen.get_default ().width ()) {
				layout.set_width ((int) (0.8 * Screen.get_default ().width () * Pango.SCALE));
				layout.get_pixel_extents (out ink_rect, out logical_rect);
			}
			
			var buffer = HOVER_HEIGHT - logical_rect.height;
			text_offset = buffer / 2;
			
			set_size_request ((int) Math.fmax (HOVER_HEIGHT, buffer + logical_rect.width), HOVER_HEIGHT);
		}
		
		void draw_background ()
		{
			background_buffer = new DockSurface (width_request, height_request);
			
			// draw the background
			theme.draw_background (background_buffer);
			
			// draw the text
			background_buffer.Context.move_to (text_offset, text_offset);
			background_buffer.Context.set_source_rgb (1, 1, 1);
			Pango.cairo_show_layout (background_buffer.Context, layout);
		}
		
		public override bool expose_event (EventExpose event)
		{
			if (background_buffer == null || background_buffer.Height != height_request || background_buffer.Width != width_request)
				draw_background ();
			
			if (background_buffer == null)
				return base.expose_event (event);
			
			var cr = cairo_create (event.window);
			
			cr.set_operator (Operator.SOURCE);
			cr.set_source_surface (background_buffer.Internal, 0, 0);
			cr.paint ();
			
			return true;
		}
	}
}