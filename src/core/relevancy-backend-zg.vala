/*
 * Copyright (C) 2010 Michal Hruby <michal.mhr@gmail.com>
 *
 * This library is free software; you can redistribute it and/or
 * modify it under the terms of the GNU Lesser General Public
 * License as published by the Free Software Foundation; either
 * version 2.1 of the License, or (at your option) any later version.
 *
 * This library is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
 * Lesser General Public License for more details.
 *
 * You should have received a copy of the GNU Lesser General Public License
 * along with this program.  If not, see <http://www.gnu.org/licenses/>.
 *
 * Authored by Michal Hruby <michal.mhr@gmail.com>
 *
 */

namespace Synapse
{
  private class ZeitgeistRelevancyBackend: Object, RelevancyBackend
  {
    private Zeitgeist.Log zg_log;
    private Gee.Map<string, int> application_popularity;
    private Gee.Map<string, int> uri_popularity;

    private const float MULTIPLIER = 65535.0f;

    construct
    {
      zg_log = new Zeitgeist.Log ();
      application_popularity = new Gee.HashMap<string, int> ();
      uri_popularity = new Gee.HashMap<string, int> ();

      load_application_relevancies.begin ();
    }

    private async void load_application_relevancies ()
    {
      Idle.add (load_application_relevancies.callback, Priority.LOW);
      yield;

      int64 end = Zeitgeist.Timestamp.now ();
      int64 start = end - Zeitgeist.Timestamp.WEEK * 4;
      Zeitgeist.TimeRange tr = new Zeitgeist.TimeRange (start, end);

      var event = new Zeitgeist.Event ();
      event.set_interpretation ("!" + Zeitgeist.ZG_LEAVE_EVENT);
      var subject = new Zeitgeist.Subject ();
      subject.set_interpretation (Zeitgeist.NFO_SOFTWARE);
      subject.set_uri ("application://*");
      event.add_subject (subject);

      var ptr_arr = new PtrArray ();
      ptr_arr.add (event);

      Zeitgeist.ResultSet rs;

      try
      {
        rs = yield zg_log.find_events (tr, (owned) ptr_arr,
                                       Zeitgeist.StorageState.ANY,
                                       256,
                                       Zeitgeist.ResultType.MOST_POPULAR_SUBJECTS,
                                       null);

        application_popularity.clear ();
        uint size = rs.size ();
        uint index = 0;

        // Zeitgeist (0.6) doesn't have any stats API, so let's approximate

        foreach (Zeitgeist.Event e in rs)
        {
          if (e.num_subjects () <= 0) continue;
          Zeitgeist.Subject s = e.get_subject (0);

          float power = index / (size * 2) + 0.5f; // linearly <0.5, 1.0>
          float relevancy = 1.0f / Math.powf (index + 1, power);
          application_popularity[s.get_uri ()] = (int)(relevancy * MULTIPLIER);

          index++;
        }
      }
      catch (Error err)
      {
        warning ("%s", err.message);
        return;
      }
    }
    
    public float get_application_popularity (string desktop_id)
    {
      if (desktop_id in application_popularity)
      {
        return application_popularity[desktop_id] / MULTIPLIER;
      }

      return 0.0f;
    }
    
    public float get_uri_popularity (string uri)
    {
      if (uri in uri_popularity)
      {
        return uri_popularity[uri] / MULTIPLIER;
      }

      return 0.0f;
    }
    
    public void application_launched (AppInfo app_info)
    {
      // detect if the Zeitgeist GIO module is installed
      Type zg_gio_module = Type.from_name ("GAppLaunchHandlerZeitgeist");
      // FIXME: perhaps we should check app_info.should_show?
      //   but user specifically asked to open this, so probably not
      //   otoh the gio module won't pick it up if it's not should_show
      if (zg_gio_module != 0) return;

      string app_uri = null;
      if (app_info.get_id () != null)
      {
        app_uri = "application://" + app_info.get_id ();
      }
      else if (app_info is DesktopAppInfo)
      {
        var basename = Path.get_basename ((app_info as DesktopAppInfo).get_filename ());
        app_uri = "application://" + basename;
      }

      push_app_launch (app_uri, app_info.get_display_name ());
    }

    private void push_app_launch (string app_uri, string? display_name)
    {
      //debug ("pushing launch event: %s [%s]", app_uri, display_name);
      var event = new Zeitgeist.Event ();
      var subject = new Zeitgeist.Subject ();

      event.set_actor ("application://synapse.desktop");
      event.set_interpretation (Zeitgeist.ZG_ACCESS_EVENT);
      event.set_manifestation (Zeitgeist.ZG_USER_ACTIVITY);
      event.add_subject (subject);

      subject.set_uri (app_uri);
      subject.set_interpretation (Zeitgeist.NFO_SOFTWARE);
      subject.set_manifestation (Zeitgeist.NFO_SOFTWARE_ITEM);
      subject.set_mimetype ("application/x-desktop");
      subject.set_text (display_name);

      zg_log.insert_events_no_reply (event, null);

      // and refresh
      load_application_relevancies.begin ();
    }
  }
}
