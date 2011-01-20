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

using Plank.Items;
using Plank.Services.Drawing;

namespace Plank
{
	public class DockRenderer : GLib.Object
	{
		DockWindow window;
		
		PlankSurface background_buffer;
		PlankSurface main_buffer;
		PlankSurface indicator_buffer;
		PlankSurface urgent_indicator_buffer;
		
		public int DockWidth {
			get { return (int) window.Items.Items.length () * (ItemPadding+ Prefs.IconSize) + 2 * DockPadding + 4 * theme.LineWidth; }
		}
		
		public int DockHeight {
			get { return 2 * theme.get_top_offset () + IndicatorSize / 2 + DockPadding + (int) (Prefs.Zoom * Prefs.IconSize) + 2 * theme.get_bottom_offset () + theme.UrgentBounceHeight; }
		}
		
		public int VisibleDockHeight {
			get { return 2 * theme.get_top_offset () + IndicatorSize / 2 + DockPadding + Prefs.IconSize + 2 * theme.get_bottom_offset (); }
		}
		
		int IndicatorSize {
			get { return (int) (theme.IndicatorSize / 10.0 * Prefs.IconSize); }
		}
		
		int DockPadding {
			get { return (int) (theme.Padding / 10.0 * Prefs.IconSize); }
		}
		
		int ItemPadding {
			get { return (int) (theme.ItemPadding / 10.0 * Prefs.IconSize); }
		}
		
		int UrgentHueShift {
			get { return 150; }
		}
		
		DockPreferences Prefs {
			get { return window.Prefs; }
		}
		
		DockThemeRenderer theme;
		
		public DockRenderer (DockWindow window)
		{
			this.window = window;
			
			theme = new DockThemeRenderer ();
			theme.BottomRoundness = 0;
			theme.load ("dock");
			theme.notify.connect (theme_changed);
			
			window.notify["HoveredItem"].connect (animation_state_changed);
			Prefs.notify.connect (reset_buffers);
		}
		
		void theme_changed ()
		{
			window.set_size ();
		}
		
		void animation_state_changed ()
		{
			animated_draw ();
		}
		
		public void reset_buffers ()
		{
			main_buffer = null;
			background_buffer = null;
			indicator_buffer = null;
			urgent_indicator_buffer = null;
			
			animated_draw ();
		}
		
		public Gdk.Rectangle item_region (DockItem item)
		{
			Gdk.Rectangle rect = Gdk.Rectangle ();
			
			rect.x = 2 * theme.LineWidth + DockPadding + item.Position * (ItemPadding + Prefs.IconSize);
			rect.y = DockHeight - VisibleDockHeight;
			rect.width = Prefs.IconSize + ItemPadding;
			rect.height = VisibleDockHeight;
			
			return rect;
		}
		
		public void draw_dock (Context cr)
		{
			if (main_buffer != null && (main_buffer.Height != DockHeight || main_buffer.Width != DockWidth))
				reset_buffers ();
			
			if (main_buffer == null)
				main_buffer = new PlankSurface.with_surface (DockWidth, DockHeight, cr.get_target ());
			
			main_buffer.Clear ();
			
			draw_dock_background (main_buffer);
			
			foreach (DockItem item in window.Items.Items)
				draw_item (main_buffer, item);
			
			cr.set_operator (Operator.SOURCE);
			cr.set_source_surface (main_buffer.Internal, 0, 0);
			cr.paint ();
		}
		
		void draw_dock_background (PlankSurface surface)
		{
			if (background_buffer == null || background_buffer.Width != surface.Width || background_buffer.Height != VisibleDockHeight) {
				background_buffer = new PlankSurface.with_plank_surface (surface.Width, VisibleDockHeight, surface);
				theme.draw_background (background_buffer);
			}
			
			surface.Context.set_source_surface (background_buffer.Internal, 0, surface.Height - background_buffer.Height);
			surface.Context.paint ();
		}
		
		void draw_item (PlankSurface surface, DockItem item)
		{
			var icon_surface = new PlankSurface.with_plank_surface (surface.Width, surface.Height, surface);
			
			// load the icon
			var pbuf = Drawing.load_icon (item.Icon, Prefs.IconSize, Prefs.IconSize);
			cairo_set_source_pixbuf (icon_surface.Context, pbuf, 0, 0);
			icon_surface.Context.paint ();
			
			// get draw regions
			var draw_rect = item_region (item);
			var hover_rect = draw_rect;
			
			draw_rect.x += ItemPadding / 2;
			draw_rect.y += 2 * theme.get_top_offset () + DockPadding;
			draw_rect.height -= DockPadding;
			
			// lighten or darken the icon
			var lighten = 0.0;
			var darken = 0.0;
			
			var click_time = new DateTime.now_utc ().difference (item.LastClicked);
			if (click_time < theme.ClickTime) {
				var clickAnimationProgress = click_time / (double) theme.ClickTime;
			
				switch (item.ClickedAnimation) {
				case ClickAnimation.BOUNCE:
					if (!Gdk.Screen.get_default ().is_composited ())
						break;
					draw_rect.y -= (int) Math.fabs (Math.sin (2 * Math.PI * clickAnimationProgress) * theme.LaunchBounceHeight);
					break;
				case ClickAnimation.DARKEN:
					darken = Math.fmax (0, Math.sin (Math.PI * 2 * clickAnimationProgress)) * 0.5;
					break;
				case ClickAnimation.LIGHTEN:
					lighten = Math.fmax (0, Math.sin (Math.PI * 2 * clickAnimationProgress)) * 0.5;
					break;
				}
			}
			
			if (window.HoveredItem == item && !Prefs.zoom_enabled ())
				lighten = 0.2;
			
			if (window.HoveredItem == item && window.MenuVisible)
				darken += 0.4;
			
			// glow the icon
			if (lighten > 0) {
				icon_surface.Context.set_operator (Cairo.Operator.ADD);
				icon_surface.Context.paint_with_alpha (lighten);
				icon_surface.Context.set_operator (Cairo.Operator.OVER);
			}
			
			// darken the icon
			if (darken > 0) {
				icon_surface.Context.rectangle (0, 0, Prefs.IconSize, Prefs.IconSize);
				icon_surface.Context.set_source_rgba (0, 0, 0, darken);
				
				icon_surface.Context.set_operator (Cairo.Operator.ATOP);
				icon_surface.Context.fill ();
				icon_surface.Context.set_operator (Cairo.Operator.OVER);
			}
			
			var urgent_time = new DateTime.now_utc ().difference (item.LastUrgent);
			if (Gdk.Screen.get_default().is_composited () && (item.State & ItemState.URGENT) != 0 && urgent_time < theme.BounceTime)
				draw_rect.y -= (int) Math.fabs (Math.sin (Math.PI * urgent_time / (double) theme.BounceTime) * theme.UrgentBounceHeight);
			
			// draw active glow
			var active_time = new DateTime.now_utc ().difference (item.LastActive);
			var opacity = Math.fmin (1, active_time / (double) theme.ActiveTime);
			if ((item.State & ItemState.ACTIVE) == 0)
				opacity = 1 - opacity;
			draw_active_glow (surface, hover_rect, Drawing.average_color (pbuf), opacity);
			
			// draw the icon
			surface.Context.set_source_surface (icon_surface.Internal, draw_rect.x, draw_rect.y);
			surface.Context.paint ();
			
			// draw indicators
			if (item.Indicator != IndicatorState.NONE) {
				if (indicator_buffer == null)
					create_normal_indicator ();
				if (urgent_indicator_buffer == null)
					create_urgent_indicator ();
				
				var indicator = (item.State & ItemState.URGENT) != 0 ? urgent_indicator_buffer : indicator_buffer;
				
				var x = hover_rect.x + hover_rect.width / 2 - indicator.Width / 2;
				// have to do the (int) cast to avoid valac segfault (valac 0.11.4)
 				var y = DockHeight - indicator.Height / 2 - 2 * (int) theme.get_bottom_offset () - IndicatorSize / 24.0;
				
				if (item.Indicator == IndicatorState.SINGLE) {
					surface.Context.set_source_surface (indicator.Internal, x, y);
					surface.Context.paint ();
				} else {
					surface.Context.set_source_surface (indicator.Internal, x - 3, y);
					surface.Context.paint ();
					surface.Context.set_source_surface (indicator.Internal, x + 3, y);
					surface.Context.paint ();
				}
			}
		}
		
		void draw_active_glow (PlankSurface surface, Gdk.Rectangle rect, RGBColor color, double opacity)
		{
			if (opacity == 0)
				return;
			
			rect.y += 2 * theme.get_top_offset ();
			rect.height -= 2 * theme.get_top_offset () + 2 * theme.get_bottom_offset ();
			surface.Context.rectangle (rect.x, rect.y, rect.width, rect.height);
			
			var gradient = new Pattern.linear (0, rect.y, 0, rect.y + rect.height);
			gradient.add_color_stop_rgba (0, color.R, color.G, color.B, 0);
			gradient.add_color_stop_rgba (1, color.R, color.G, color.B, 0.6 * opacity);
			
			surface.Context.set_source (gradient);
			surface.Context.fill ();
		}
		
		void create_normal_indicator ()
		{
			var color = RGBColor.from_gdk (window.get_style ().bg [StateType.SELECTED]);
			color = color.set_min_value (90 / (double) uint16.MAX).set_min_sat (0.4);
			indicator_buffer = create_indicator (IndicatorSize, color.R, color.G, color.B);
		}
		
		void create_urgent_indicator ()
		{
			var color = RGBColor.from_gdk (window.get_style ().bg [StateType.SELECTED]);
			color = color.set_min_value (90 / (double) uint16.MAX).add_hue (UrgentHueShift).set_sat (1);
			urgent_indicator_buffer = create_indicator (IndicatorSize, color.R, color.G, color.B);
		}
		
		PlankSurface create_indicator (int size, double r, double g, double b)
		{
			PlankSurface surface = new PlankSurface.with_plank_surface (size, size, background_buffer);
			surface.Clear ();

			var cr = surface.Context;
			
			var x = size / 2;
			var y = x;
			
			cr.move_to (x, y);
			cr.arc (x, y, size / 2, 0, Math.PI * 2);
			
			var rg = new Pattern.radial (x, y, 0, x, y, size / 2);
			rg.add_color_stop_rgba (0, 1, 1, 1, 1);
			rg.add_color_stop_rgba (0.1, r, g, b, 1);
			rg.add_color_stop_rgba (0.2, r, g, b, 0.6);
			rg.add_color_stop_rgba (0.25, r, g, b, 0.25);
			rg.add_color_stop_rgba (0.5, r, g, b, 0.15);
			rg.add_color_stop_rgba (1.0, r, g, b, 0.0);
			
			cr.set_source (rg);
			cr.fill ();
			
			return surface;
		}
		
		uint animation_timer = 0;
		
		bool animation_needed ()
		{
			DateTime now = new DateTime.now_utc ();
			
			foreach (DockItem item in window.Items.Items) {
				if (now.difference (item.LastClicked) < theme.ClickTime)
					return true;
				if (now.difference (item.LastUrgent) < theme.BounceTime)
					return true;
				if (now.difference (item.LastActive) < theme.ActiveTime)
					return true;
			}
				
			return false;
		}
		
		public void animated_draw ()
		{
			if (animation_timer > 0) 
				return;
			
			window.queue_draw ();
			
			if (animation_needed ())
				animation_timer = GLib.Timeout.add (1000 / 60, draw_timeout);
		}
		
		bool draw_timeout ()
		{
			window.queue_draw ();
			
			if (animation_needed ())
				return true;
			
			if (animation_timer > 0)
				GLib.Source.remove (animation_timer);
			animation_timer = 0;

			return false;
		}
	}
}
