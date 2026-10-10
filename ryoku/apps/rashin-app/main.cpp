#include <gtk/gtk.h>
#include <libsoup/soup.h>
#include <webkit2/webkit2.h>

#include <cstdlib>
#include <optional>
#include <string>

#ifndef RASHIN_APP_VERSION
#define RASHIN_APP_VERSION "0.0.0"
#endif

namespace {

constexpr int kDefaultPort = 3600;
constexpr int kDefaultWidth = 1280;
constexpr int kDefaultHeight = 820;
constexpr guint kPollIntervalMs = 500;

constexpr const char *kBootPage = R"HTML(
<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="color-scheme" content="dark">
<style>
  html, body {
    width: 100%;
    height: 100%;
    margin: 0;
    background: #000;
    color: #cdc4ba;
  }
  body {
    display: grid;
    place-items: center;
  }
  main {
    text-align: center;
  }
  h1 {
    margin: 0 0 12px;
    font: 400 42px/1.1 Georgia, "Times New Roman", serif;
  }
  p {
    margin: 0;
    color: #958f87;
    font: 14px/1.5 sans-serif;
  }
</style>
</head>
<body>
  <main>
    <h1>Rashin</h1>
    <p>waking the daemon</p>
  </main>
</body>
</html>
)HTML";

struct AppState {
    GtkApplication *application = nullptr;
    GtkWidget *window = nullptr;
    WebKitWebView *web_view = nullptr;
    SoupSession *session = nullptr;
    SoupMessage *ping_message = nullptr;
    GCancellable *cancellable = nullptr;
    guint retry_source = 0;
    guint recovery_source = 0;
    bool polling = false;
    bool quitting = false;
    int port = kDefaultPort;
    int width = kDefaultWidth;
    int height = kDefaultHeight;
    std::string daemon_origin;
    std::string ping_uri;
    std::string chat_uri;
};


std::optional<int> json_integer(const char *json, const char *key) {
    const std::string pattern = "\"" + std::string(key) + "\"\\s*:\\s*([0-9]+)";
    GError *error = nullptr;
    GRegex *regex = g_regex_new(pattern.c_str(), G_REGEX_OPTIMIZE, G_REGEX_MATCH_NOTEMPTY, &error);
    if (!regex) {
        g_clear_error(&error);
        return std::nullopt;
    }

    GMatchInfo *match = nullptr;
    const gboolean found = g_regex_match(regex, json, G_REGEX_MATCH_NOTEMPTY, &match);
    std::optional<int> value;
    if (found) {
        gchar *digits = g_match_info_fetch(match, 1);
        if (digits) {
            char *end = nullptr;
            const long parsed = std::strtol(digits, &end, 10);
            if (end != digits && *end == '\0' && parsed > 0 && parsed <= G_MAXINT)
                value = static_cast<int>(parsed);
            g_free(digits);
        }
    }

    if (match)
        g_match_info_free(match);
    g_regex_unref(regex);
    return value;
}

std::string state_file_path() {
    gchar *path = g_build_filename(g_get_user_state_dir(), "ryoku", "rashin-app.json", nullptr);
    std::string result(path);
    g_free(path);
    return result;
}

void load_preferences(AppState *state) {
    const std::string path = state_file_path();
    gchar *contents = nullptr;
    if (!g_file_get_contents(path.c_str(), &contents, nullptr, nullptr))
        return;

    if (const auto width = json_integer(contents, "width"))
        state->width = *width;
    if (const auto height = json_integer(contents, "height"))
        state->height = *height;
    g_free(contents);
}

void save_preferences(AppState *state) {
    if (!state->window)
        return;

    gtk_window_get_size(GTK_WINDOW(state->window), &state->width, &state->height);
    const std::string path = state_file_path();
    gchar *directory = g_path_get_dirname(path.c_str());
    if (g_mkdir_with_parents(directory, 0700) == 0) {
        gchar *json = g_strdup_printf("{\n  \"width\": %d,\n  \"height\": %d\n}\n",
                                      state->width, state->height);
        g_file_set_contents(path.c_str(), json, -1, nullptr);
        g_free(json);
    }
    g_free(directory);
}

int daemon_port() {
    gchar *path = g_build_filename(g_get_user_config_dir(), "ryoku", "rashin.json", nullptr);
    gchar *contents = nullptr;
    int port = kDefaultPort;
    if (g_file_get_contents(path, &contents, nullptr, nullptr)) {
        if (const auto configured = json_integer(contents, "port");
            configured && *configured <= 65535) {
            port = *configured;
        }
        g_free(contents);
    }
    g_free(path);
    return port;
}

void show_boot_page(AppState *state) {
    if (state->web_view)
        webkit_web_view_load_html(state->web_view, kBootPage, state->daemon_origin.c_str());
}

void send_ping(AppState *state);

gboolean retry_ping(gpointer data) {
    auto *state = static_cast<AppState *>(data);
    state->retry_source = 0;
    send_ping(state);
    return G_SOURCE_REMOVE;
}

void schedule_ping(AppState *state) {
    if (!state->quitting && state->polling && state->retry_source == 0)
        state->retry_source = g_timeout_add(kPollIntervalMs, retry_ping, state);
}

void ping_finished(GObject *source, GAsyncResult *result, gpointer data) {
    auto *state = static_cast<AppState *>(data);
    GError *error = nullptr;
    GBytes *body = soup_session_send_and_read_finish(
        SOUP_SESSION(source), result, &error);
    const guint status = soup_message_get_status(state->ping_message);

    const bool ready = body && SOUP_STATUS_IS_SUCCESSFUL(status);
    if (body)
        g_bytes_unref(body);
    g_clear_error(&error);
    g_clear_object(&state->ping_message);

    if (state->quitting)
        return;
    if (ready) {
        state->polling = false;
        webkit_web_view_load_uri(state->web_view, state->chat_uri.c_str());
        return;
    }
    schedule_ping(state);
}

void send_ping(AppState *state) {
    if (state->quitting || !state->polling || state->ping_message)
        return;

    state->ping_message = soup_message_new("GET", state->ping_uri.c_str());
    if (!state->ping_message) {
        schedule_ping(state);
        return;
    }

    soup_session_send_and_read_async(
        state->session,
        state->ping_message,
        G_PRIORITY_DEFAULT,
        state->cancellable,
        ping_finished,
        state);
}

void begin_polling(AppState *state) {
    if (state->quitting)
        return;
    state->polling = true;
    if (!state->ping_message && state->retry_source == 0)
        send_ping(state);
}

gboolean recover_daemon(gpointer data) {
    auto *state = static_cast<AppState *>(data);
    state->recovery_source = 0;
    if (!state->quitting) {
        show_boot_page(state);
        begin_polling(state);
    }
    return G_SOURCE_REMOVE;
}

gboolean load_failed(WebKitWebView *, WebKitLoadEvent, const gchar *,
                     GError *, gpointer data) {
    auto *state = static_cast<AppState *>(data);
    if (!state->quitting && state->recovery_source == 0)
        state->recovery_source = g_idle_add(recover_daemon, state);
    return TRUE;
}

bool is_daemon_uri(const AppState *state, const char *uri) {
    GError *error = nullptr;
    GUri *parsed = g_uri_parse(uri, G_URI_FLAGS_NONE, &error);
    if (!parsed) {
        g_clear_error(&error);
        return false;
    }

    const char *scheme = g_uri_get_scheme(parsed);
    const char *host = g_uri_get_host(parsed);
    int port = g_uri_get_port(parsed);
    if (port < 0 && scheme && g_ascii_strcasecmp(scheme, "http") == 0)
        port = 80;
    const bool matches =
        scheme && host &&
        g_ascii_strcasecmp(scheme, "http") == 0 &&
        g_ascii_strcasecmp(host, "127.0.0.1") == 0 &&
        port == state->port;
    g_uri_unref(parsed);
    return matches;
}

gboolean decide_policy(WebKitWebView *, WebKitPolicyDecision *decision,
                       WebKitPolicyDecisionType type, gpointer data) {
    if (type != WEBKIT_POLICY_DECISION_TYPE_NAVIGATION_ACTION &&
        type != WEBKIT_POLICY_DECISION_TYPE_NEW_WINDOW_ACTION) {
        return FALSE;
    }

    auto *state = static_cast<AppState *>(data);
    auto *navigation = WEBKIT_NAVIGATION_POLICY_DECISION(decision);
    WebKitNavigationAction *action =
        webkit_navigation_policy_decision_get_navigation_action(navigation);
    WebKitURIRequest *request = webkit_navigation_action_get_request(action);
    const char *uri = webkit_uri_request_get_uri(request);
    if (!uri || g_str_has_prefix(uri, "about:") || is_daemon_uri(state, uri))
        return FALSE;

    GError *error = nullptr;
    gtk_show_uri_on_window(GTK_WINDOW(state->window), uri, GDK_CURRENT_TIME, &error);
    g_clear_error(&error);
    webkit_policy_decision_ignore(decision);
    return TRUE;
}

gboolean permission_request(WebKitWebView *, WebKitPermissionRequest *request,
                            gpointer) {
    if (WEBKIT_IS_NOTIFICATION_PERMISSION_REQUEST(request))
        webkit_permission_request_allow(request);
    else
        webkit_permission_request_deny(request);
    return TRUE;
}

gboolean window_configured(GtkWidget *, GdkEventConfigure *event, gpointer data) {
    auto *state = static_cast<AppState *>(data);
    if (event->width > 0)
        state->width = event->width;
    if (event->height > 0)
        state->height = event->height;
    return FALSE;
}

gboolean window_delete(GtkWidget *, GdkEvent *, gpointer data) {
    auto *state = static_cast<AppState *>(data);
    save_preferences(state);
    state->quitting = true;
    if (state->retry_source != 0) {
        g_source_remove(state->retry_source);
        state->retry_source = 0;
    }
    if (state->recovery_source != 0) {
        g_source_remove(state->recovery_source);
        state->recovery_source = 0;
    }
    g_cancellable_cancel(state->cancellable);
    g_application_quit(G_APPLICATION(state->application));
    return FALSE;
}

void window_destroyed(GtkWidget *, gpointer data) {
    static_cast<AppState *>(data)->window = nullptr;
}

void quit_action(GSimpleAction *, GVariant *, gpointer data) {
    auto *state = static_cast<AppState *>(data);
    if (state->window)
        gtk_window_close(GTK_WINDOW(state->window));
}

void reload_action(GSimpleAction *, GVariant *, gpointer data) {
    auto *state = static_cast<AppState *>(data);
    if (state->web_view)
        webkit_web_view_reload(state->web_view);
}

void startup(GtkApplication *application, gpointer data) {
    const GActionEntry actions[] = {
        {"quit", quit_action, nullptr, nullptr, nullptr},
        {"reload", reload_action, nullptr, nullptr, nullptr},
    };
    g_action_map_add_action_entries(
        G_ACTION_MAP(application), actions, G_N_ELEMENTS(actions), data);
    const char *quit_accels[] = {"<Primary>q", nullptr};
    const char *reload_accels[] = {"<Primary>r", nullptr};
    gtk_application_set_accels_for_action(
        application, "app.quit", quit_accels);
    gtk_application_set_accels_for_action(
        application, "app.reload", reload_accels);
}

void activate(GtkApplication *application, gpointer data) {
    auto *state = static_cast<AppState *>(data);

    // WebKitGTK derives its internal page scale from GTK's font DPI.
    // Ryoku already handles display scaling at the compositor/GTK surface
    // level, so letting WebKit apply the session DPI again can shrink or
    // enlarge the web console independently of the native window.
    //
    // Keep the embedded dashboard at the CSS baseline of 96 DPI. GTK and
    // Wayland remain responsible for mapping the window onto the output.
    if (GtkSettings *gtk_settings = gtk_settings_get_default()) {
        gint reported_dpi = -1;
        g_object_get(gtk_settings, "gtk-xft-dpi", &reported_dpi, nullptr);

        g_print("rashin-app: GTK xft DPI = %.2f\n",
                reported_dpi > 0 ? reported_dpi / 1024.0 : -1.0);

        g_object_set(gtk_settings, "gtk-xft-dpi", 96 * 1024, nullptr);
    }
    if (state->window) {
        gtk_window_present(GTK_WINDOW(state->window));
        return;
    }

    state->quitting = false;
    state->port = daemon_port();
    state->daemon_origin = "http://127.0.0.1:" + std::to_string(state->port);
    state->ping_uri = state->daemon_origin + "/api/ping";
    // The window opens on the Ryoku lane, the machine agent; the plain Chat
    // lane and the other sheets are one click away in the console itself.
    state->chat_uri = state->daemon_origin + "/#/ryoku";
    load_preferences(state);

    state->session = soup_session_new();
    g_object_set(state->session, "timeout", 2, nullptr);
    state->cancellable = g_cancellable_new();

    WebKitUserContentManager *content = webkit_user_content_manager_new();
    const std::string host_script =
        "window.rashinHost = { app: true, version: \"" +
        std::string(RASHIN_APP_VERSION) + "\" };";
    WebKitUserScript *script = webkit_user_script_new(
        host_script.c_str(),
        WEBKIT_USER_CONTENT_INJECT_TOP_FRAME,
        WEBKIT_USER_SCRIPT_INJECT_AT_DOCUMENT_START,
        nullptr,
        nullptr);
    webkit_user_content_manager_add_script(content, script);
    webkit_user_script_unref(script);

    state->web_view = WEBKIT_WEB_VIEW(
        webkit_web_view_new_with_user_content_manager(content));
    g_object_unref(content);

    WebKitSettings *settings = webkit_web_view_get_settings(state->web_view);
    webkit_settings_set_enable_javascript(settings, TRUE);
    webkit_settings_set_enable_developer_extras(settings, FALSE);
    webkit_settings_set_media_playback_requires_user_gesture(settings, FALSE);

    GdkRGBA black{0.0, 0.0, 0.0, 1.0};
    webkit_web_view_set_background_color(state->web_view, &black);

    state->window = gtk_application_window_new(application);
    gtk_window_set_title(GTK_WINDOW(state->window), "Rashin");
    gtk_window_set_default_size(GTK_WINDOW(state->window), state->width, state->height);
    gtk_container_add(GTK_CONTAINER(state->window), GTK_WIDGET(state->web_view));

    g_signal_connect(state->window, "configure-event",
                     G_CALLBACK(window_configured), state);
    g_signal_connect(state->window, "delete-event",
                     G_CALLBACK(window_delete), state);
    g_signal_connect(state->window, "destroy",
                     G_CALLBACK(window_destroyed), state);
    g_signal_connect(state->web_view, "load-failed",
                     G_CALLBACK(load_failed), state);
    g_signal_connect(state->web_view, "decide-policy",
                     G_CALLBACK(decide_policy), state);
    g_signal_connect(state->web_view, "permission-request",
                     G_CALLBACK(permission_request), state);

    show_boot_page(state);
    gtk_widget_show_all(state->window);
    begin_polling(state);
}

} // namespace

int main(int argc, char **argv) {
    // Rashin is a small local dashboard, so stability matters more than WebKit's
    // accelerated compositing path. WebKitGTK 2.52 can crash its web process in
    // Skia GPU drawing on the NVIDIA Wayland stack; keep this app on the stable
    // software-composited path without changing WebKit behavior system-wide.
    g_setenv("WEBKIT_DISABLE_COMPOSITING_MODE", "1", FALSE);

    AppState state;
    state.application = gtk_application_new(
        "dev.ryoku.rashin", G_APPLICATION_DEFAULT_FLAGS);

    g_signal_connect(state.application, "startup", G_CALLBACK(startup), &state);
    g_signal_connect(state.application, "activate", G_CALLBACK(activate), &state);

    const int status = g_application_run(
        G_APPLICATION(state.application), argc, argv);
    if (state.retry_source != 0)
        g_source_remove(state.retry_source);
    if (state.recovery_source != 0)
        g_source_remove(state.recovery_source);
    if (state.cancellable)
        g_cancellable_cancel(state.cancellable);
    g_clear_object(&state.cancellable);
    g_clear_object(&state.ping_message);
    g_clear_object(&state.session);
    g_object_unref(state.application);
    return status;
}
