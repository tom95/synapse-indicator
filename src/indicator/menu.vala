
public class Menu : Gtk.Menu
{
	Gtk.Entry entry;
	MatchItem entry_item;

	public signal void search (string text);

	public Menu ()
	{
		reserve_toggle_size = false;
		take_focus = true;

		entry = new Gtk.Entry ();

		entry.primary_icon_name = "edit-find-symbolic";
		entry_item = new MatchItem ("Search:", entry, true);
		append (entry_item);

		// block any clicks on the item
		entry_item.button_release_event.connect ((e) => { return true; });
		entry_item.button_press_event.connect ((e) => { return true; });
		entry_item.draw.connect ((cr) => {
			if (get_children ().length () < 2)
				return false;

			cr.move_to (0, entry_item.get_allocated_height () - 0.5);
			cr.rel_line_to (entry_item.get_allocated_width (), 0);
			cr.set_line_width (1);
			cr.set_source_rgba (0, 0, 0, 0.2);
			cr.stroke ();
			return false;
		});

		key_press_event.connect ((e) => {
			switch (e.keyval) {
				case Gdk.Key.Escape:
				case Gdk.Key.Up:
				case Gdk.Key.Down:
				case Gdk.Key.Return:
				case Gdk.Key.KP_Enter:
					return false;
				case Gdk.Key.Left:
				case Gdk.Key.Right:
					show_context_menu ();
					return true;
				default:
					entry.key_press_event (e);
					if (entry.text == "")
						clear ();
					else
						search (entry.text);
					return true;
			}
		});

		move_current.connect ((dir) => {
			// see if the next item will be the search entry
			var next = get_children ().index (get_selected_item ()) +
				(dir == Gtk.MenuDirectionType.NEXT ? 1 : -1);
			// if so, select it so the move which comes after we're
			// done here will skip it
			if (next == 0 || next == get_children ().length ()) {
				select_item (entry_item);
			}
		});

		width_request = 480;
	}

	public override void show ()
	{
		clear ();
		entry.text = "";
		base.show ();
		grab_focus ();
		entry.grab_focus ();
	}

	public void show_matches (Gee.List<Synapse.Match> matches)
	{
		clear ();

		entry_item.outer_box.margin_bottom = 12;

		var current_type = -2;
		foreach (var match in matches) {
			var tophit = current_type == -2;
			var title = tophit ? "Top hit" : "";
			if (!tophit) {
				if (current_type != match.match_type) {
					current_type = match.match_type;
					switch (current_type) {
						case Synapse.MatchType.APPLICATION:
							title = _("Applications");
							break;
						case Synapse.MatchType.TEXT:
							title = _("Texts");
							break;
						case Synapse.MatchType.GENERIC_URI:
							title = _("Files");
							break;
						case Synapse.MatchType.ACTION:
							title = _("Actions");
							break;
						case Synapse.MatchType.SEARCH:
							title = _("Search");
							break;
						case Synapse.MatchType.UNKNOWN:
							break;
						default:
							title = _("Other");
							break;
					}
				}
			} else
				current_type = -1;

			if (match.match_type == Synapse.MatchType.UNKNOWN) {
				var actions = Main.sink.find_actions_for_match (match, null, Synapse.QueryFlags.ALL);
				foreach (var action in actions) {
					var item = new MatchItem.with_action (action, match, tophit);
					append (item);
					// if we are the tophit, only make the first item large
					if (tophit)
						tophit = false;
				}

				continue;
			}

			var item = new MatchItem.with_match (match, title, tophit);
			append (item);
		}
		show_all ();
		select_item (get_children ().nth_data (1));
	}

	public void clear ()
	{
		entry_item.outer_box.margin_bottom = 0;
		foreach (var child in get_children ()) {
			if (child == entry_item)
				continue;
			child.destroy ();
		}
	}

	public void do_search (Synapse.Match match, Synapse.Match target)
	{
		clear ();

		var search = match as Synapse.SearchMatch;
		search.search_source = target;

		search.search (entry.text, Synapse.QueryFlags.ALL, null, null, (obj, res) => {
			var matches = search.search.end (res);
			show_matches (matches);
		});
	}

	public void show_context_menu ()
	{
		var active = get_selected_item () as MatchItem;
		var menu = new Gtk.Menu ();
		menu.key_press_event.connect (take_arrow_keys);

		var actions = Main.sink.find_actions_for_match (active.match, null, Synapse.QueryFlags.ALL);
		foreach (var action in actions) {
			var item = new MatchItem.contextual (action, active.match, false);
			menu.append (item);
		}

		menu.show_all ();
		active.submenu = menu;
		active.activate_item ();
	}

	bool take_arrow_keys (Gtk.Widget menu, Gdk.EventKey event)
	{
		switch (event.keyval) {
			case Gdk.Key.Left:
			case Gdk.Key.Right:
				(menu as Gtk.Menu).popdown ();
				menu.destroy ();
				return true;
			case Gdk.Key.Return:
				var item = (menu as Gtk.Menu).get_selected_item () as MatchItem;
				var is_search = item.match.match_type == Synapse.MatchType.SEARCH;
				if (is_search)
					do_search (item.match, item.target);
				return is_search;
		}

		return false;
	}
}
