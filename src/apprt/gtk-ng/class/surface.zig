const std = @import("std");
const assert = std.debug.assert;
const Allocator = std.mem.Allocator;
const adw = @import("adw");
const gdk = @import("gdk");
const gio = @import("gio");
const glib = @import("glib");
const gobject = @import("gobject");
const gtk = @import("gtk");

const apprt = @import("../../../apprt.zig");
const font = @import("../../../font/main.zig");
const input = @import("../../../input.zig");
const internal_os = @import("../../../os/main.zig");
const renderer = @import("../../../renderer.zig");
const terminal = @import("../../../terminal/main.zig");
const CoreSurface = @import("../../../Surface.zig");
const gresource = @import("../build/gresource.zig");
const adw_version = @import("../adw_version.zig");
const gtk_key = @import("../key.zig");
const ApprtSurface = @import("../Surface.zig");
const Common = @import("../class.zig").Common;
const Application = @import("application.zig").Application;
const Config = @import("config.zig").Config;
const ResizeOverlay = @import("resize_overlay.zig").ResizeOverlay;
const ChildExited = @import("surface_child_exited.zig").SurfaceChildExited;
const ClipboardConfirmationDialog = @import("clipboard_confirmation_dialog.zig").ClipboardConfirmationDialog;

const log = std.log.scoped(.gtk_ghostty_surface);

pub const Surface = extern struct {
    const Self = @This();
    parent_instance: Parent,
    pub const Parent = adw.Bin;
    pub const getGObjectType = gobject.ext.defineClass(Self, .{
        .name = "GhosttySurface",
        .instanceInit = &init,
        .classInit = &Class.init,
        .parent_class = &Class.parent,
        .private = .{ .Type = Private, .offset = &Private.offset },
    });

    pub const properties = struct {
        pub const config = struct {
            pub const name = "config";
            const impl = gobject.ext.defineProperty(
                name,
                Self,
                ?*Config,
                .{
                    .nick = "Config",
                    .blurb = "The configuration that this surface is using.",
                    .accessor = C.privateObjFieldAccessor("config"),
                },
            );
        };

        pub const @"child-exited" = struct {
            pub const name = "child-exited";
            const impl = gobject.ext.defineProperty(
                name,
                Self,
                bool,
                .{
                    .nick = "Child Exited",
                    .blurb = "True when the child process has exited.",
                    .default = false,
                    .accessor = gobject.ext.privateFieldAccessor(
                        Self,
                        Private,
                        &Private.offset,
                        "child_exited",
                    ),
                },
            );
        };

        pub const @"font-size-request" = struct {
            pub const name = "font-size-request";
            const impl = gobject.ext.defineProperty(
                name,
                Self,
                ?*font.face.DesiredSize,
                .{
                    .nick = "Desired Font Size",
                    .blurb = "The desired font size, only affects initialization.",
                    .accessor = C.privateBoxedFieldAccessor("font_size_request"),
                },
            );
        };

        pub const focused = struct {
            pub const name = "focused";
            const impl = gobject.ext.defineProperty(
                name,
                Self,
                bool,
                .{
                    .nick = "Focused",
                    .blurb = "The focused state of the surface.",
                    .default = false,
                    .accessor = gobject.ext.privateFieldAccessor(
                        Self,
                        Private,
                        &Private.offset,
                        "focused",
                    ),
                },
            );
        };

        pub const @"mouse-hidden" = struct {
            pub const name = "mouse-hidden";
            const impl = gobject.ext.defineProperty(
                name,
                Self,
                bool,
                .{
                    .nick = "Mouse Hidden",
                    .blurb = "Whether the mouse cursor should be hidden.",
                    .default = false,
                    .accessor = gobject.ext.privateFieldAccessor(
                        Self,
                        Private,
                        &Private.offset,
                        "mouse_hidden",
                    ),
                },
            );
        };

        pub const @"mouse-shape" = struct {
            pub const name = "mouse-shape";
            const impl = gobject.ext.defineProperty(
                name,
                Self,
                terminal.MouseShape,
                .{
                    .nick = "Mouse Shape",
                    .blurb = "The current mouse shape to show for the surface.",
                    .default = .text,
                    .accessor = gobject.ext.privateFieldAccessor(
                        Self,
                        Private,
                        &Private.offset,
                        "mouse_shape",
                    ),
                },
            );
        };

        pub const @"mouse-hover-url" = struct {
            pub const name = "mouse-hover-url";
            pub const get = impl.get;
            pub const set = impl.set;
            const impl = gobject.ext.defineProperty(
                name,
                Self,
                ?[:0]const u8,
                .{
                    .nick = "Mouse Hover URL",
                    .blurb = "The URL the mouse is currently hovering over (if any).",
                    .default = null,
                    .accessor = C.privateStringFieldAccessor("mouse_hover_url"),
                },
            );
        };

        pub const pwd = struct {
            pub const name = "pwd";
            pub const get = impl.get;
            pub const set = impl.set;
            const impl = gobject.ext.defineProperty(
                name,
                Self,
                ?[:0]const u8,
                .{
                    .nick = "Working Directory",
                    .blurb = "The current working directory as reported by core.",
                    .default = null,
                    .accessor = C.privateStringFieldAccessor("pwd"),
                },
            );
        };

        pub const title = struct {
            pub const name = "title";
            pub const get = impl.get;
            pub const set = impl.set;
            const impl = gobject.ext.defineProperty(
                name,
                Self,
                ?[:0]const u8,
                .{
                    .nick = "Title",
                    .blurb = "The title of the surface.",
                    .default = null,
                    .accessor = C.privateStringFieldAccessor("title"),
                },
            );
        };

        pub const zoom = struct {
            pub const name = "zoom";
            const impl = gobject.ext.defineProperty(
                name,
                Self,
                bool,
                .{
                    .nick = "Zoom",
                    .blurb = "Whether the surface should be zoomed.",
                    .default = false,
                    .accessor = gobject.ext.privateFieldAccessor(
                        Self,
                        Private,
                        &Private.offset,
                        "zoom",
                    ),
                },
            );
        };
    };

    pub const signals = struct {
        /// Emitted whenever the surface would like to be closed for any
        /// reason.
        ///
        /// The surface view does NOT handle its own close confirmation.
        /// If there is a process alive then the boolean parameter will
        /// specify it and the parent widget should handle this request.
        ///
        /// This signal lets the containing widget decide how closure works.
        /// This lets this Surface widget be used as a split, tab, etc.
        /// without it having to be aware of its own semantics.
        pub const @"close-request" = struct {
            pub const name = "close-request";
            pub const connect = impl.connect;
            const impl = gobject.ext.defineSignal(
                name,
                Self,
                &.{*const CloseScope},
                void,
            );
        };

        /// The bell is rung.
        ///
        /// The surface view handles the audio bell feature but none of the
        /// others so it is up to the embedding widget to react to this.
        pub const bell = struct {
            pub const name = "bell";
            pub const connect = impl.connect;
            const impl = gobject.ext.defineSignal(
                name,
                Self,
                &.{},
                void,
            );
        };

        /// Emitted whenever the clipboard has been written.
        pub const @"clipboard-write" = struct {
            pub const name = "clipboard-write";
            pub const connect = impl.connect;
            const impl = gobject.ext.defineSignal(
                name,
                Self,
                &.{
                    apprt.Clipboard,
                    [*:0]const u8,
                },
                void,
            );
        };

        /// Emitted whenever the surface reads the clipboard.
        pub const @"clipboard-read" = struct {
            pub const name = "clipboard-read";
            pub const connect = impl.connect;
            const impl = gobject.ext.defineSignal(
                name,
                Self,
                &.{},
                void,
            );
        };

        /// Emitted when the focus wants to be brought to the top and
        /// focused.
        pub const @"present-request" = struct {
            pub const name = "present-request";
            pub const connect = impl.connect;
            const impl = gobject.ext.defineSignal(
                name,
                Self,
                &.{},
                void,
            );
        };

        /// Emitted when this surface requests its container to toggle its
        /// fullscreen state.
        pub const @"toggle-fullscreen" = struct {
            pub const name = "toggle-fullscreen";
            pub const connect = impl.connect;
            const impl = gobject.ext.defineSignal(
                name,
                Self,
                &.{},
                void,
            );
        };

        /// Emitted when this surface requests its container to toggle its
        /// maximized state.
        pub const @"toggle-maximize" = struct {
            pub const name = "toggle-maximize";
            pub const connect = impl.connect;
            const impl = gobject.ext.defineSignal(
                name,
                Self,
                &.{},
                void,
            );
        };
    };

    const Private = struct {
        /// The configuration that this surface is using.
        config: ?*Config = null,

        /// The cgroup created for this surface. This will be created
        /// if `Application.transient_cgroup_base` is set.
        cgroup_path: ?[]const u8 = null,

        /// The requested font size. This only applies to initialization
        /// and has no effect later.
        font_size_request: ?*font.face.DesiredSize = null,

        /// The mouse shape to show for the surface.
        mouse_shape: terminal.MouseShape = .default,

        /// Whether the mouse should be hidden or not as requested externally.
        mouse_hidden: bool = false,

        /// The URL that the mouse is currently hovering over.
        mouse_hover_url: ?[:0]const u8 = null,

        /// The current working directory. This has to be reported externally,
        /// usually by shell integration which then talks to libghostty
        /// which triggers this property.
        ///
        /// If this is set prior to initialization then the surface will
        /// start in this pwd. If it is set after, it has no impact on the
        /// core surface.
        pwd: ?[:0]const u8 = null,

        /// The title of this surface, if any has been set.
        title: ?[:0]const u8 = null,

        /// The current focus state of the terminal based on the
        /// focus events.
        focused: bool = true,

        /// Whether this surface is "zoomed" or not. A zoomed surface
        /// shows up taking the full bounds of a split view.
        zoom: bool = false,

        /// The GLAarea that renders the actual surface. This is a binding
        /// to the template so it doesn't have to be unrefed manually.
        gl_area: *gtk.GLArea,

        /// The labels for the left/right sides of the URL hover tooltip.
        url_left: *gtk.Label,
        url_right: *gtk.Label,

        /// The resize overlay
        resize_overlay: *ResizeOverlay,

        /// The apprt Surface.
        rt_surface: ApprtSurface = undefined,

        /// The core surface backing this GTK surface. This starts out
        /// null because it can't be initialized until there is an available
        /// GLArea that is realized.
        //
        // NOTE(mitchellh): This is a limitation we should definitely remove
        // at some point by modifying our OpenGL renderer for GTK to
        // start in an unrealized state. There are other benefits to being
        // able to initialize the surface early so we should aim for that,
        // eventually.
        core_surface: ?*CoreSurface = null,

        /// Cached metrics for libghostty callbacks
        size: apprt.SurfaceSize,
        cursor_pos: apprt.CursorPos,

        /// Various input method state. All related to key input.
        in_keyevent: IMKeyEvent = .false,
        im_context: *gtk.IMMulticontext,
        im_composing: bool = false,
        im_buf: [128]u8 = undefined,
        im_len: u7 = 0,

        /// True when we have a precision scroll in progress
        precision_scroll: bool = false,

        /// True when the child has exited.
        child_exited: bool = false,

        // Progress bar
        progress_bar_timer: ?c_uint = null,

        // Template binds
        child_exited_overlay: *ChildExited,
        drop_target: *gtk.DropTarget,
        progress_bar_overlay: *gtk.ProgressBar,

        pub var offset: c_int = 0;
    };

    pub fn new() *Self {
        return gobject.ext.newInstance(Self, .{});
    }

    pub fn core(self: *Self) ?*CoreSurface {
        const priv = self.private();
        return priv.core_surface;
    }

    pub fn rt(self: *Self) *ApprtSurface {
        const priv = self.private();
        return &priv.rt_surface;
    }

    /// Set the parent of this surface. This will extract the information
    /// required to initialize this surface with the proper values but doesn't
    /// retain any memory.
    ///
    /// If the surface is already realized this does nothing.
    pub fn setParent(
        self: *Self,
        parent: *CoreSurface,
    ) void {
        const priv = self.private();

        // This is a mistake! We can only set a parent before surface
        // realization. We log this because this is probably a logic error.
        if (priv.core_surface != null) {
            log.warn("setParent called after surface is already realized", .{});
            return;
        }

        // Setup our font size
        const font_size_ptr = glib.ext.create(font.face.DesiredSize);
        errdefer glib.ext.destroy(font_size_ptr);
        font_size_ptr.* = parent.font_size;
        priv.font_size_request = font_size_ptr;
        self.as(gobject.Object).notifyByPspec(properties.@"font-size-request".impl.param_spec);

        // Setup our pwd
        if (parent.rt_surface.surface.getPwd()) |pwd| {
            priv.pwd = glib.ext.dupeZ(u8, pwd);
            self.as(gobject.Object).notifyByPspec(properties.pwd.impl.param_spec);
        }
    }

    /// Force the surface to redraw itself. Ghostty often will only redraw
    /// the terminal in reaction to internal changes. If there are external
    /// events that invalidate the surface, such as the widget moving parents,
    /// then we should force a redraw.
    pub fn redraw(self: *Self) void {
        const priv = self.private();
        priv.gl_area.queueRender();
    }

    /// Ring the bell.
    pub fn ringBell(self: *Self) void {
        // TODO: Audio feature

        signals.bell.impl.emit(
            self,
            null,
            .{},
            null,
        );
    }

    pub fn toggleFullscreen(self: *Self) void {
        signals.@"toggle-fullscreen".impl.emit(
            self,
            null,
            .{},
            null,
        );
    }

    pub fn toggleMaximize(self: *Self) void {
        signals.@"toggle-maximize".impl.emit(
            self,
            null,
            .{},
            null,
        );
    }

    /// Set the current progress report state.
    pub fn setProgressReport(
        self: *Self,
        value: terminal.osc.Command.ProgressReport,
    ) void {
        const priv = self.private();

        // No matter what, we stop the timer because if we're removing
        // then we're done and otherwise we restart it.
        if (priv.progress_bar_timer) |timer| {
            if (glib.Source.remove(timer) == 0) {
                log.warn("unable to remove progress bar timer", .{});
            }
            priv.progress_bar_timer = null;
        }

        const progress_bar = priv.progress_bar_overlay;
        switch (value.state) {
            // Remove the progress bar
            .remove => {
                progress_bar.as(gtk.Widget).setVisible(@intFromBool(false));
                return;
            },

            // Set the progress bar to a fixed value if one was provided, otherwise pulse.
            // Remove the `error` CSS class so that the progress bar shows as normal.
            .set => {
                progress_bar.as(gtk.Widget).removeCssClass("error");
                if (value.progress) |progress| {
                    progress_bar.setFraction(computeFraction(progress));
                } else {
                    progress_bar.pulse();
                }
            },

            // Set the progress bar to a fixed value if one was provided, otherwise pulse.
            // Set the `error` CSS class so that the progress bar shows as an error color.
            .@"error" => {
                progress_bar.as(gtk.Widget).addCssClass("error");
                if (value.progress) |progress| {
                    progress_bar.setFraction(computeFraction(progress));
                } else {
                    progress_bar.pulse();
                }
            },

            // The state of progress is unknown, so pulse the progress bar to
            // indicate that things are still happening.
            .indeterminate => {
                progress_bar.pulse();
            },

            // If a progress value was provided, set the progress bar to that value.
            // Don't pulse the progress bar as that would indicate that things were
            // happening. Otherwise this is mainly used to keep the progress bar on
            // screen instead of timing out.
            .pause => {
                if (value.progress) |progress| {
                    progress_bar.setFraction(computeFraction(progress));
                }
            },
        }

        // Assume all states lead to visibility
        assert(value.state != .remove);
        progress_bar.as(gtk.Widget).setVisible(@intFromBool(true));

        // Start our timer to remove bad actor programs that stall
        // the progress bar.
        const progress_bar_timeout_seconds = 15;
        assert(priv.progress_bar_timer == null);
        priv.progress_bar_timer = glib.timeoutAdd(
            progress_bar_timeout_seconds * std.time.ms_per_s,
            progressBarTimer,
            self,
        );
    }

    /// The progress bar hasn't been updated by the TUI recently, remove it.
    fn progressBarTimer(ud: ?*anyopaque) callconv(.c) c_int {
        const self: *Self = @ptrCast(@alignCast(ud.?));
        const priv = self.private();
        priv.progress_bar_timer = null;
        self.setProgressReport(.{ .state = .remove });
        return @intFromBool(glib.SOURCE_REMOVE);
    }

    /// Request that this terminal come to the front and become focused.
    /// It is up to the embedding widget to react to this.
    pub fn present(self: *Self) void {
        signals.@"present-request".impl.emit(
            self,
            null,
            .{},
            null,
        );
    }

    /// Key press event (press or release).
    ///
    /// At a high level, we want to construct an `input.KeyEvent` and
    /// pass that to `keyCallback`. At a low level, this is more complicated
    /// than it appears because we need to construct all of this information
    /// and its not given to us.
    ///
    /// For all events, we run the GdkEvent through the input method context.
    /// This allows the input method to capture the event and trigger
    /// callbacks such as preedit, commit, etc.
    ///
    /// There are a couple important aspects to the prior paragraph: we must
    /// send ALL events through the input method context. This is because
    /// input methods use both key press and key release events to determine
    /// the state of the input method. For example, fcitx uses key release
    /// events on modifiers (i.e. ctrl+shift) to switch the input method.
    ///
    /// We set some state to note we're in a key event (self.in_keyevent)
    /// because some of the input method callbacks change behavior based on
    /// this state. For example, we don't want to send character events
    /// like "a" via the input "commit" event if we're actively processing
    /// a keypress because we'd lose access to the keycode information.
    /// However, a "commit" event may still happen outside of a keypress
    /// event from e.g. a tablet or on-screen keyboard.
    ///
    /// Finally, we take all of the information in order to determine if we have
    /// a unicode character or if we have to map the keyval to a code to
    /// get the underlying logical key, etc.
    ///
    /// Then we can emit the keyCallback.
    pub fn keyEvent(
        self: *Surface,
        action: input.Action,
        ec_key: *gtk.EventControllerKey,
        keyval: c_uint,
        keycode: c_uint,
        gtk_mods: gdk.ModifierType,
    ) bool {
        log.warn("keyEvent action={}", .{action});
        const event = ec_key.as(gtk.EventController).getCurrentEvent() orelse return false;
        const key_event = gobject.ext.cast(gdk.KeyEvent, event) orelse return false;
        const priv = self.private();

        // The block below is all related to input method handling. See the function
        // comment for some high level details and then the comments within
        // the block for more specifics.
        {
            // This can trigger an input method so we need to notify the im context
            // where the cursor is so it can render the dropdowns in the correct
            // place.
            if (priv.core_surface) |surface| {
                const ime_point = surface.imePoint();
                priv.im_context.as(gtk.IMContext).setCursorLocation(&.{
                    .f_x = @intFromFloat(ime_point.x),
                    .f_y = @intFromFloat(ime_point.y),
                    .f_width = 1,
                    .f_height = 1,
                });
            }

            // We note that we're in a keypress because we want some logic to
            // depend on this. For example, we don't want to send character events
            // like "a" via the input "commit" event if we're actively processing
            // a keypress because we'd lose access to the keycode information.
            //
            // We have to maintain some additional state here of whether we
            // were composing because different input methods call the callbacks
            // in different orders. For example, ibus calls commit THEN preedit
            // end but simple calls preedit end THEN commit.
            priv.in_keyevent = if (priv.im_composing) .composing else .not_composing;
            defer priv.in_keyevent = .false;

            // Pass the event through the input method which returns true if handled.
            // Confusingly, not all events handled by the input method result
            // in this returning true so we have to maintain some additional
            // state about whether we were composing or not to determine if
            // we should proceed with key encoding.
            //
            // Cases where the input method does not mark the event as handled:
            //
            // - If we change the input method via keypress while we have preedit
            //   text, the input method will commit the pending text but will not
            //   mark it as handled. We use the `.composing` state to detect
            //   this case.
            //
            // - If we switch input methods (i.e. via ctrl+shift with fcitx),
            //   the input method will handle the key release event but will not
            //   mark it as handled. I don't know any way to detect this case so
            //   it will result in a key event being sent to the key callback.
            //   For Kitty text encoding, this will result in modifiers being
            //   triggered despite being technically consumed. At the time of
            //   writing, both Kitty and Alacritty have the same behavior. I
            //   know of no way to fix this.
            const im_handled = priv.im_context.as(gtk.IMContext).filterKeypress(event) != 0;
            // log.warn("GTKIM: im_handled={} im_len={} im_composing={}", .{
            //     im_handled,
            //     self.im_len,
            //     self.im_composing,
            // });

            // If the input method handled the event, you would think we would
            // never proceed with key encoding for Ghostty but that is not the
            // case. Input methods will handle basic character encoding like
            // typing "a" and we want to associate that with the key event.
            // So we have to check additional state to determine if we exit.
            if (im_handled) {
                // If we are composing then we're in a preedit state and do
                // not want to encode any keys. For example: type a deadkey
                // such as single quote on a US international keyboard layout.
                if (priv.im_composing) return true;

                // If we were composing and now we're not it means that we committed
                // the text. We also don't want to encode a key event for this.
                // Example: enable Japanese input method, press "konn" and then
                // press enter. The final enter should not be encoded and "konn"
                // (in hiragana) should be written as "こん".
                if (priv.in_keyevent == .composing) return true;

                // Not composing and our input method buffer is empty. This could
                // mean that the input method reacted to this event by activating
                // an onscreen keyboard or something equivalent. We don't know.
                // But the input method handled it and didn't give us text so
                // we will just assume we should not encode this. This handles a
                // real scenario when ibus starts the emoji input method
                // (super+.).
                if (priv.im_len == 0) return true;
            }

            // At this point, for the sake of explanation of internal state:
            // it is possible that im_len > 0 and im_composing == false. This
            // means that we received a commit event from the input method that
            // we want associated with the key event. This is common: its how
            // basic character translation for simple inputs like "a" work.
        }

        // We always reset the length of the im buffer. There's only one scenario
        // we reach this point with im_len > 0 and that's if we received a commit
        // event from the input method. We don't want to keep that state around
        // since we've handled it here.
        defer priv.im_len = 0;

        // Get the keyvals for this event.
        const keyval_unicode = gdk.keyvalToUnicode(keyval);
        const keyval_unicode_unshifted: u21 = gtk_key.keyvalUnicodeUnshifted(
            priv.gl_area.as(gtk.Widget),
            key_event,
            keycode,
        );

        // We want to get the physical unmapped key to process physical keybinds.
        // (These are keybinds explicitly marked as requesting physical mapping).
        const physical_key = keycode: for (input.keycodes.entries) |entry| {
            if (entry.native == keycode) break :keycode entry.key;
        } else .unidentified;

        // Get our modifier for the event
        const mods: input.Mods = gtk_key.eventMods(
            event,
            physical_key,
            gtk_mods,
            action,
            Application.default().winproto(),
        );

        // Get our consumed modifiers
        const consumed_mods: input.Mods = consumed: {
            const T = @typeInfo(gdk.ModifierType);
            std.debug.assert(T.@"struct".layout == .@"packed");
            const I = T.@"struct".backing_integer.?;

            const masked = @as(I, @bitCast(key_event.getConsumedModifiers())) & @as(I, gdk.MODIFIER_MASK);
            break :consumed gtk_key.translateMods(@bitCast(masked));
        };

        // log.debug("key pressed key={} keyval={x} physical_key={} composing={} text_len={} mods={}", .{
        //     key,
        //     keyval,
        //     physical_key,
        //     priv.im_composing,
        //     priv.im_len,
        //     mods,
        // });

        // If we have no UTF-8 text, we try to convert our keyval to
        // a text value. We have to do this because GTK will not process
        // "Ctrl+Shift+1" (on US keyboards) as "Ctrl+!" but instead as "".
        // But the keyval is set correctly so we can at least extract that.
        if (priv.im_len == 0 and keyval_unicode > 0) im: {
            if (std.math.cast(u21, keyval_unicode)) |cp| {
                // We don't want to send control characters as IM
                // text. Control characters are handled already by
                // the encoder directly.
                if (cp < 0x20) break :im;

                if (std.unicode.utf8Encode(cp, &priv.im_buf)) |len| {
                    priv.im_len = len;
                } else |_| {}
            }
        }

        // Invoke the core Ghostty logic to handle this input.
        const surface = priv.core_surface orelse return false;
        const effect = surface.keyCallback(.{
            .action = action,
            .key = physical_key,
            .mods = mods,
            .consumed_mods = consumed_mods,
            .composing = priv.im_composing,
            .utf8 = priv.im_buf[0..priv.im_len],
            .unshifted_codepoint = keyval_unicode_unshifted,
        }) catch |err| {
            log.err("error in key callback err={}", .{err});
            return false;
        };

        switch (effect) {
            .closed => return true,
            .ignored => {},
            .consumed => if (action == .press or action == .repeat) {
                // If we were in the composing state then we reset our context.
                // We do NOT want to reset if we're not in the composing state
                // because there is other IME state that we want to preserve,
                // such as quotation mark ordering for Chinese input.
                if (priv.im_composing) {
                    priv.im_context.as(gtk.IMContext).reset();
                    surface.preeditCallback(null) catch {};
                }

                return true;
            },
        }

        return false;
    }

    /// Scale x/y by the GDK device scale.
    fn scaledCoordinates(
        self: *Self,
        x: f64,
        y: f64,
    ) struct { x: f64, y: f64 } {
        const gl_area = self.private().gl_area;
        const scale_factor: f64 = @floatFromInt(
            gl_area.as(gtk.Widget).getScaleFactor(),
        );

        return .{
            .x = x * scale_factor,
            .y = y * scale_factor,
        };
    }

    /// Initialize the cgroup for this surface if it hasn't been
    /// already. While this is `init`-prefixed, we prefer to call this
    /// in the realize function because we don't need to create a cgroup
    /// if we don't init a surface.
    fn initCgroup(self: *Self) void {
        const priv = self.private();

        // If we already have a cgroup path then we don't do it again.
        if (priv.cgroup_path != null) return;

        const app = Application.default();
        const alloc = app.allocator();
        const base = app.cgroupBase() orelse return;

        // For the unique group name we use the self pointer. This may
        // not be a good idea for security reasons but not sure yet. We
        // may want to change this to something else eventually to be safe.
        var buf: [256]u8 = undefined;
        const name = std.fmt.bufPrint(
            &buf,
            "surfaces/{X}.scope",
            .{@intFromPtr(self)},
        ) catch unreachable;

        // Create the cgroup. If it fails, no big deal... just ignore.
        internal_os.cgroup.create(base, name, null) catch |err| {
            log.warn("failed to create surface cgroup err={}", .{err});
            return;
        };

        // Success, save the cgroup path.
        priv.cgroup_path = std.fmt.allocPrint(
            alloc,
            "{s}/{s}",
            .{ base, name },
        ) catch null;
    }

    /// Deletes the cgroup if set.
    fn clearCgroup(self: *Self) void {
        const priv = self.private();
        const path = priv.cgroup_path orelse return;

        internal_os.cgroup.remove(path) catch |err| {
            // We don't want this to be fatal in any way so we just log
            // and continue. A dangling empty cgroup is not a big deal
            // and this should be rare.
            log.warn(
                "failed to remove cgroup for surface path={s} err={}",
                .{ path, err },
            );
        };

        Application.default().allocator().free(path);
        priv.cgroup_path = null;
    }

    //---------------------------------------------------------------
    // Libghostty Callbacks

    pub fn close(self: *Self, scope: CloseScope) void {
        signals.@"close-request".impl.emit(
            self,
            null,
            .{&scope},
            null,
        );
    }

    pub fn childExited(
        self: *Self,
        data: apprt.surface.Message.ChildExited,
    ) bool {
        // Even if we don't support the overlay, we still keep our property
        // up to date for anyone listening.
        const priv = self.private();
        priv.child_exited = true;
        self.as(gobject.Object).notifyByPspec(
            properties.@"child-exited".impl.param_spec,
        );

        // If we have the noop child exited overlay then we don't do anything
        // for child exited. The false return will force libghostty to show
        // the normal text-based message.
        if (comptime @hasDecl(ChildExited, "noop")) {
            return false;
        }

        priv.child_exited_overlay.setData(&data);
        return true;
    }

    pub fn cgroupPath(self: *Self) ?[]const u8 {
        return self.private().cgroup_path;
    }

    pub fn getContentScale(self: *Self) apprt.ContentScale {
        const priv = self.private();
        const gl_area = priv.gl_area;

        const gtk_scale: f32 = scale: {
            const widget = gl_area.as(gtk.Widget);
            // Future: detect GTK version 4.12+ and use gdk_surface_get_scale so we
            // can support fractional scaling.
            const scale = widget.getScaleFactor();
            if (scale <= 0) {
                log.warn("gtk_widget_get_scale_factor returned a non-positive number: {}", .{scale});
                break :scale 1.0;
            }
            break :scale @floatFromInt(scale);
        };

        // Also scale using font-specific DPI, which is often exposed to the user
        // via DE accessibility settings (see https://docs.gtk.org/gtk4/class.Settings.html).
        const xft_dpi_scale = xft_scale: {
            // gtk-xft-dpi is font DPI multiplied by 1024. See
            // https://docs.gtk.org/gtk4/property.Settings.gtk-xft-dpi.html
            const settings = gtk.Settings.getDefault() orelse break :xft_scale 1.0;
            var value = std.mem.zeroes(gobject.Value);
            defer value.unset();
            _ = value.init(gobject.ext.typeFor(c_int));
            settings.as(gobject.Object).getProperty("gtk-xft-dpi", &value);
            const gtk_xft_dpi = value.getInt();

            // Use a value of 1.0 for the XFT DPI scale if the setting is <= 0
            // See:
            // https://gitlab.gnome.org/GNOME/libadwaita/-/commit/a7738a4d269bfdf4d8d5429ca73ccdd9b2450421
            // https://gitlab.gnome.org/GNOME/libadwaita/-/commit/9759d3fd81129608dd78116001928f2aed974ead
            if (gtk_xft_dpi <= 0) {
                log.warn("gtk-xft-dpi was not set, using default value", .{});
                break :xft_scale 1.0;
            }

            // As noted above gtk-xft-dpi is multiplied by 1024, so we divide by
            // 1024, then divide by the default value (96) to derive a scale. Note
            // gtk-xft-dpi can be fractional, so we use floating point math here.
            const xft_dpi: f32 = @as(f32, @floatFromInt(gtk_xft_dpi)) / 1024.0;
            break :xft_scale xft_dpi / 96.0;
        };

        const scale = gtk_scale * xft_dpi_scale;
        return .{ .x = scale, .y = scale };
    }

    pub fn getSize(self: *Self) apprt.SurfaceSize {
        const priv = self.private();
        // By the time this is called, we should be in a widget tree.
        // This should not be called before that. We ensure this by initializing
        // the surface in `glareaResize`. This is VERY important because it
        // avoids the pty having an incorrect initial size.
        assert(priv.size.width >= 0 and priv.size.height >= 0);
        return priv.size;
    }

    pub fn getCursorPos(self: *Self) apprt.CursorPos {
        return self.private().cursor_pos;
    }

    pub fn defaultTermioEnv(self: *Self) !std.process.EnvMap {
        _ = self;

        const alloc = Application.default().allocator();
        var env = try internal_os.getEnvMap(alloc);
        errdefer env.deinit();

        // Don't leak these GTK environment variables to child processes.
        env.remove("GDK_DEBUG");
        env.remove("GDK_DISABLE");
        env.remove("GSK_RENDERER");

        // Remove some environment variables that are set when Ghostty is launched
        // from a `.desktop` file, by D-Bus activation, or systemd.
        env.remove("GIO_LAUNCHED_DESKTOP_FILE");
        env.remove("GIO_LAUNCHED_DESKTOP_FILE_PID");
        env.remove("DBUS_STARTER_ADDRESS");
        env.remove("DBUS_STARTER_BUS_TYPE");
        env.remove("INVOCATION_ID");
        env.remove("JOURNAL_STREAM");
        env.remove("NOTIFY_SOCKET");

        // Unset environment varies set by snaps if we're running in a snap.
        // This allows Ghostty to further launch additional snaps.
        if (env.get("SNAP")) |_| {
            env.remove("SNAP");
            env.remove("DRIRC_CONFIGDIR");
            env.remove("__EGL_EXTERNAL_PLATFORM_CONFIG_DIRS");
            env.remove("__EGL_VENDOR_LIBRARY_DIRS");
            env.remove("LD_LIBRARY_PATH");
            env.remove("LIBGL_DRIVERS_PATH");
            env.remove("LIBVA_DRIVERS_PATH");
            env.remove("VK_LAYER_PATH");
            env.remove("XLOCALEDIR");
            env.remove("GDK_PIXBUF_MODULEDIR");
            env.remove("GDK_PIXBUF_MODULE_FILE");
            env.remove("GTK_PATH");
        }

        return env;
    }

    pub fn clipboardRequest(
        self: *Self,
        clipboard_type: apprt.Clipboard,
        state: apprt.ClipboardRequest,
    ) !void {
        try Clipboard.request(
            self,
            clipboard_type,
            state,
        );
    }

    pub fn setClipboardString(
        self: *Self,
        val: [:0]const u8,
        clipboard_type: apprt.Clipboard,
        confirm: bool,
    ) void {
        Clipboard.set(
            self,
            val,
            clipboard_type,
            confirm,
        );
    }

    /// Focus this surface. This properly focuses the input part of
    /// our surface.
    pub fn grabFocus(self: *Self) void {
        const priv = self.private();
        _ = priv.gl_area.as(gtk.Widget).grabFocus();
    }

    //---------------------------------------------------------------
    // Virtual Methods

    fn init(self: *Self, _: *Class) callconv(.C) void {
        gtk.Widget.initTemplate(self.as(gtk.Widget));

        const priv = self.private();

        // Initialize some private fields so they aren't undefined
        priv.rt_surface = .{ .surface = self };
        priv.precision_scroll = false;
        priv.cursor_pos = .{ .x = 0, .y = 0 };
        priv.mouse_shape = .text;
        priv.mouse_hidden = false;
        priv.focused = true;
        priv.size = .{ .width = 0, .height = 0 };

        // If our configuration is null then we get the configuration
        // from the application.
        if (priv.config == null) {
            const app = Application.default();
            priv.config = app.getConfig();
        }

        // Setup our input method state
        priv.in_keyevent = .false;
        priv.im_composing = false;
        priv.im_len = 0;

        // Set up to handle items being dropped on our surface. Files can be dropped
        // from Nautilus and strings can be dropped from many programs. The order
        // of these types matter.
        var drop_target_types = [_]gobject.Type{
            gdk.FileList.getGObjectType(),
            gio.File.getGObjectType(),
            gobject.ext.types.string,
        };
        priv.drop_target.setGtypes(&drop_target_types, drop_target_types.len);

        // Initialize our GLArea. We only set the values we can't set
        // in our blueprint file.
        const gl_area = priv.gl_area;
        gl_area.setRequiredVersion(
            renderer.OpenGL.MIN_VERSION_MAJOR,
            renderer.OpenGL.MIN_VERSION_MINOR,
        );
        gl_area.as(gtk.Widget).setCursorFromName("text");

        // Initialize our config
        self.propConfig(undefined, null);
    }

    fn dispose(self: *Self) callconv(.C) void {
        const priv = self.private();
        if (priv.config) |v| {
            v.unref();
            priv.config = null;
        }
        if (priv.progress_bar_timer) |timer| {
            if (glib.Source.remove(timer) == 0) {
                log.warn("unable to remove progress bar timer", .{});
            }
            priv.progress_bar_timer = null;
        }

        gtk.Widget.disposeTemplate(
            self.as(gtk.Widget),
            getGObjectType(),
        );

        gobject.Object.virtual_methods.dispose.call(
            Class.parent,
            self.as(Parent),
        );
    }

    fn finalize(self: *Self) callconv(.C) void {
        const priv = self.private();
        if (priv.core_surface) |v| {
            // Remove ourselves from the list of known surfaces in the app.
            // We do this before deinit in case a callback triggers
            // searching for this surface.
            Application.default().core().deleteSurface(self.rt());

            // Deinit the surface
            v.deinit();
            const alloc = Application.default().allocator();
            alloc.destroy(v);

            priv.core_surface = null;
        }
        if (priv.mouse_hover_url) |v| {
            glib.free(@constCast(@ptrCast(v)));
            priv.mouse_hover_url = null;
        }
        if (priv.font_size_request) |v| {
            glib.ext.destroy(v);
            priv.font_size_request = null;
        }
        if (priv.pwd) |v| {
            glib.free(@constCast(@ptrCast(v)));
            priv.pwd = null;
        }
        if (priv.title) |v| {
            glib.free(@constCast(@ptrCast(v)));
            priv.title = null;
        }
        self.clearCgroup();

        gobject.Object.virtual_methods.finalize.call(
            Class.parent,
            self.as(Parent),
        );
    }

    //---------------------------------------------------------------
    // Properties

    /// Returns the title property without a copy.
    pub fn getTitle(self: *Self) ?[:0]const u8 {
        return self.private().title;
    }

    /// Returns the pwd property without a copy.
    pub fn getPwd(self: *Self) ?[:0]const u8 {
        return self.private().pwd;
    }

    /// Change the configuration for this surface.
    pub fn setConfig(self: *Self, config: *Config) void {
        const priv = self.private();
        if (priv.config) |c| c.unref();
        priv.config = config.ref();
        self.as(gobject.Object).notifyByPspec(properties.config.impl.param_spec);
    }

    fn propConfig(
        self: *Self,
        _: *gobject.ParamSpec,
        _: ?*anyopaque,
    ) callconv(.c) void {
        const priv = self.private();
        const config = if (priv.config) |c| c.get() else return;

        // resize-overlay-duration
        {
            const ms = config.@"resize-overlay-duration".asMilliseconds();
            var value = gobject.ext.Value.newFrom(ms);
            defer value.unset();
            gobject.Object.setProperty(
                priv.resize_overlay.as(gobject.Object),
                "duration",
                &value,
            );
        }

        // resize-overlay-position
        {
            const hv: struct {
                gtk.Align, // halign
                gtk.Align, // valign
            } = switch (config.@"resize-overlay-position") {
                .center => .{ .center, .center },
                .@"top-left" => .{ .start, .start },
                .@"top-right" => .{ .end, .start },
                .@"top-center" => .{ .center, .start },
                .@"bottom-left" => .{ .start, .end },
                .@"bottom-right" => .{ .end, .end },
                .@"bottom-center" => .{ .center, .end },
            };

            var halign = gobject.ext.Value.newFrom(hv[0]);
            defer halign.unset();
            var valign = gobject.ext.Value.newFrom(hv[1]);
            defer valign.unset();
            gobject.Object.setProperty(
                priv.resize_overlay.as(gobject.Object),
                "overlay-halign",
                &halign,
            );
            gobject.Object.setProperty(
                priv.resize_overlay.as(gobject.Object),
                "overlay-valign",
                &valign,
            );
        }
    }

    fn propMouseHoverUrl(
        self: *Self,
        _: *gobject.ParamSpec,
        _: ?*anyopaque,
    ) callconv(.c) void {
        const priv = self.private();
        const visible = if (priv.mouse_hover_url) |v| v.len > 0 else false;
        priv.url_left.as(gtk.Widget).setVisible(if (visible) 1 else 0);
    }

    fn propMouseHidden(
        self: *Self,
        _: *gobject.ParamSpec,
        _: ?*anyopaque,
    ) callconv(.c) void {
        const priv = self.private();

        // If we're hidden we set it to "none"
        if (priv.mouse_hidden) {
            priv.gl_area.as(gtk.Widget).setCursorFromName("none");
            return;
        }

        // If we're not hidden we just trigger the mouse shape
        // prop notification to handle setting the proper mouse shape.
        self.propMouseShape(undefined, null);
    }

    fn propMouseShape(
        self: *Self,
        _: *gobject.ParamSpec,
        _: ?*anyopaque,
    ) callconv(.c) void {
        const priv = self.private();

        // If our mouse should be hidden currently then we don't
        // do anything.
        if (priv.mouse_hidden) return;

        const name: [:0]const u8 = switch (priv.mouse_shape) {
            .default => "default",
            .help => "help",
            .pointer => "pointer",
            .context_menu => "context-menu",
            .progress => "progress",
            .wait => "wait",
            .cell => "cell",
            .crosshair => "crosshair",
            .text => "text",
            .vertical_text => "vertical-text",
            .alias => "alias",
            .copy => "copy",
            .no_drop => "no-drop",
            .move => "move",
            .not_allowed => "not-allowed",
            .grab => "grab",
            .grabbing => "grabbing",
            .all_scroll => "all-scroll",
            .col_resize => "col-resize",
            .row_resize => "row-resize",
            .n_resize => "n-resize",
            .e_resize => "e-resize",
            .s_resize => "s-resize",
            .w_resize => "w-resize",
            .ne_resize => "ne-resize",
            .nw_resize => "nw-resize",
            .se_resize => "se-resize",
            .sw_resize => "sw-resize",
            .ew_resize => "ew-resize",
            .ns_resize => "ns-resize",
            .nesw_resize => "nesw-resize",
            .nwse_resize => "nwse-resize",
            .zoom_in => "zoom-in",
            .zoom_out => "zoom-out",
        };

        // Set our new cursor.
        priv.gl_area.as(gtk.Widget).setCursorFromName(name.ptr);
    }

    //---------------------------------------------------------------
    // Signal Handlers

    fn childExitedClose(
        _: *ChildExited,
        self: *Self,
    ) callconv(.c) void {
        // This closes the surface with no confirmation.
        self.close(.{ .surface = false });
    }

    fn dtDrop(
        _: *gtk.DropTarget,
        value: *gobject.Value,
        _: f64,
        _: f64,
        self: *Self,
    ) callconv(.c) c_int {
        const alloc = Application.default().allocator();

        if (g_value_holds(
            value,
            gdk.FileList.getGObjectType(),
        )) {
            var data = std.ArrayList(u8).init(alloc);
            defer data.deinit();

            var shell_escape_writer: internal_os.ShellEscapeWriter(std.ArrayList(u8).Writer) = .{
                .child_writer = data.writer(),
            };
            const writer = shell_escape_writer.writer();

            const list: ?*glib.SList = list: {
                const unboxed = value.getBoxed() orelse return 0;
                const fl: *gdk.FileList = @ptrCast(@alignCast(unboxed));
                break :list fl.getFiles();
            };
            defer if (list) |v| v.free();

            {
                var current: ?*glib.SList = list;
                while (current) |item| : (current = item.f_next) {
                    const file: *gio.File = @ptrCast(@alignCast(item.f_data orelse continue));
                    const path = file.getPath() orelse continue;
                    const slice = std.mem.span(path);
                    defer glib.free(path);

                    writer.writeAll(slice) catch |err| {
                        log.err("unable to write path to buffer: {}", .{err});
                        continue;
                    };
                    writer.writeAll("\n") catch |err| {
                        log.err("unable to write to buffer: {}", .{err});
                        continue;
                    };
                }
            }

            const string = data.toOwnedSliceSentinel(0) catch |err| {
                log.err("unable to convert to a slice: {}", .{err});
                return 0;
            };
            defer alloc.free(string);
            Clipboard.paste(self, string);
            return 1;
        }

        if (g_value_holds(value, gio.File.getGObjectType())) {
            const object = value.getObject() orelse return 0;
            const file = gobject.ext.cast(gio.File, object) orelse return 0;
            const path = file.getPath() orelse return 0;
            var data = std.ArrayList(u8).init(alloc);
            defer data.deinit();

            var shell_escape_writer: internal_os.ShellEscapeWriter(std.ArrayList(u8).Writer) = .{
                .child_writer = data.writer(),
            };
            const writer = shell_escape_writer.writer();
            writer.writeAll(std.mem.span(path)) catch |err| {
                log.err("unable to write path to buffer: {}", .{err});
                return 0;
            };
            writer.writeAll("\n") catch |err| {
                log.err("unable to write to buffer: {}", .{err});
                return 0;
            };

            const string = data.toOwnedSliceSentinel(0) catch |err| {
                log.err("unable to convert to a slice: {}", .{err});
                return 0;
            };
            defer alloc.free(string);
            return 1;
        }

        if (g_value_holds(value, gobject.ext.types.string)) {
            if (value.getString()) |string| {
                Clipboard.paste(self, std.mem.span(string));
            }
            return 1;
        }

        return 1;
    }

    fn ecKeyPressed(
        ec_key: *gtk.EventControllerKey,
        keyval: c_uint,
        keycode: c_uint,
        gtk_mods: gdk.ModifierType,
        self: *Self,
    ) callconv(.c) c_int {
        return @intFromBool(self.keyEvent(
            .press,
            ec_key,
            keyval,
            keycode,
            gtk_mods,
        ));
    }

    fn ecKeyReleased(
        ec_key: *gtk.EventControllerKey,
        keyval: c_uint,
        keycode: c_uint,
        state: gdk.ModifierType,
        self: *Self,
    ) callconv(.c) void {
        _ = self.keyEvent(
            .release,
            ec_key,
            keyval,
            keycode,
            state,
        );
    }

    fn ecFocusEnter(_: *gtk.EventControllerFocus, self: *Self) callconv(.c) void {
        const priv = self.private();
        priv.focused = true;
        priv.im_context.as(gtk.IMContext).focusIn();
        _ = glib.idleAddOnce(idleFocus, self.ref());
    }

    fn ecFocusLeave(_: *gtk.EventControllerFocus, self: *Self) callconv(.c) void {
        const priv = self.private();
        priv.focused = false;
        priv.im_context.as(gtk.IMContext).focusOut();
        _ = glib.idleAddOnce(idleFocus, self.ref());
    }

    /// The focus callback must be triggered on an idle loop source because
    /// there are actions within libghostty callbacks (such as showing close
    /// confirmation dialogs) that can trigger focus loss and cause a deadlock
    /// because the lock may be held during the callback.
    ///
    /// Userdata should be a `*Surface`. This will unref once.
    fn idleFocus(ud: ?*anyopaque) callconv(.c) void {
        const self: *Self = @ptrCast(@alignCast(ud orelse return));
        defer self.unref();

        const priv = self.private();
        const surface = priv.core_surface orelse return;
        surface.focusCallback(priv.focused) catch |err| {
            log.warn("error in focus callback err={}", .{err});
        };
    }

    fn gcMouseDown(
        gesture: *gtk.GestureClick,
        _: c_int,
        x: f64,
        y: f64,
        self: *Self,
    ) callconv(.c) void {
        const event = gesture.as(gtk.EventController).getCurrentEvent() orelse return;

        // If we don't have focus, grab it.
        const priv = self.private();
        const gl_area_widget = priv.gl_area.as(gtk.Widget);
        if (gl_area_widget.hasFocus() == 0) {
            _ = gl_area_widget.grabFocus();
        }

        // Report the event
        const consumed = if (priv.core_surface) |surface| consumed: {
            const gtk_mods = event.getModifierState();
            const button = translateMouseButton(gesture.as(gtk.GestureSingle).getCurrentButton());
            const mods = gtk_key.translateMods(gtk_mods);
            break :consumed surface.mouseButtonCallback(
                .press,
                button,
                mods,
            ) catch |err| err: {
                log.warn("error in key callback err={}", .{err});
                break :err false;
            };
        } else false;

        // TODO: context menu
        _ = consumed;
        _ = x;
        _ = y;
    }

    fn gcMouseUp(
        gesture: *gtk.GestureClick,
        _: c_int,
        _: f64,
        _: f64,
        self: *Self,
    ) callconv(.c) void {
        const event = gesture.as(gtk.EventController).getCurrentEvent() orelse return;

        const priv = self.private();
        if (priv.core_surface) |surface| {
            const gtk_mods = event.getModifierState();
            const button = translateMouseButton(gesture.as(gtk.GestureSingle).getCurrentButton());
            const mods = gtk_key.translateMods(gtk_mods);
            _ = surface.mouseButtonCallback(
                .release,
                button,
                mods,
            ) catch |err| {
                log.warn("error in key callback err={}", .{err});
                return;
            };
        }
    }

    fn ecMouseMotion(
        ec: *gtk.EventControllerMotion,
        x: f64,
        y: f64,
        self: *Self,
    ) callconv(.c) void {
        const event = ec.as(gtk.EventController).getCurrentEvent() orelse return;
        const priv = self.private();

        const scaled = self.scaledCoordinates(x, y);
        const pos: apprt.CursorPos = .{
            .x = @floatCast(scaled.x),
            .y = @floatCast(scaled.y),
        };

        // There seem to be at least two cases where GTK issues a mouse motion
        // event without the cursor actually moving:
        // 1. GLArea is resized under the mouse. This has the unfortunate
        //    side effect of causing focus to potentially change when
        //    `focus-follows-mouse` is enabled.
        // 2. The window title is updated. This can cause the mouse to unhide
        //    incorrectly when hide-mouse-when-typing is enabled.
        // To prevent incorrect behavior, we'll only grab focus and
        // continue with callback logic if the cursor has actually moved.
        const is_cursor_still = @abs(priv.cursor_pos.x - pos.x) < 1 and
            @abs(priv.cursor_pos.y - pos.y) < 1;
        if (is_cursor_still) return;

        // If we don't have focus, and we want it, grab it.
        if (priv.config) |config| {
            const gl_area_widget = priv.gl_area.as(gtk.Widget);
            if (gl_area_widget.hasFocus() == 0 and
                config.get().@"focus-follows-mouse")
            {
                _ = gl_area_widget.grabFocus();
            }
        }

        // Our pos changed, update
        priv.cursor_pos = pos;

        // Notify the callback
        if (priv.core_surface) |surface| {
            const gtk_mods = event.getModifierState();
            const mods = gtk_key.translateMods(gtk_mods);
            surface.cursorPosCallback(priv.cursor_pos, mods) catch |err| {
                log.warn("error in cursor pos callback err={}", .{err});
            };
        }
    }

    fn ecMouseLeave(
        ec_motion: *gtk.EventControllerMotion,
        self: *Self,
    ) callconv(.c) void {
        const event = ec_motion.as(gtk.EventController).getCurrentEvent() orelse return;

        // Get our modifiers
        const priv = self.private();
        if (priv.core_surface) |surface| {
            // If we have a core surface then we can send the cursor pos
            // callback with an invalid position to indicate the mouse left.
            const gtk_mods = event.getModifierState();
            const mods = gtk_key.translateMods(gtk_mods);
            surface.cursorPosCallback(
                .{ .x = -1, .y = -1 },
                mods,
            ) catch |err| {
                log.warn("error in cursor pos callback err={}", .{err});
                return;
            };
        }
    }

    fn ecMouseScrollPrecisionBegin(
        _: *gtk.EventControllerScroll,
        self: *Self,
    ) callconv(.c) void {
        self.private().precision_scroll = true;
    }

    fn ecMouseScrollPrecisionEnd(
        _: *gtk.EventControllerScroll,
        self: *Self,
    ) callconv(.c) void {
        self.private().precision_scroll = false;
    }

    fn ecMouseScroll(
        _: *gtk.EventControllerScroll,
        x: f64,
        y: f64,
        self: *Self,
    ) callconv(.c) c_int {
        const priv = self.private();
        const surface = priv.core_surface orelse return 0;

        // Multiply precision scrolls by 10 to get a better response from
        // touchpad scrolling
        const multiplier: f64 = if (priv.precision_scroll) 10.0 else 1.0;
        const scroll_mods: input.ScrollMods = .{
            .precision = priv.precision_scroll,
        };

        const scaled = self.scaledCoordinates(x, y);
        surface.scrollCallback(
            // We invert because we apply natural scrolling to the values.
            // This behavior has existed for years without Linux users complaining
            // but I suspect we'll have to make this configurable in the future
            // or read a system setting.
            scaled.x * -1 * multiplier,
            scaled.y * -1 * multiplier,
            scroll_mods,
        ) catch |err| {
            log.warn("error in scroll callback err={}", .{err});
            return 0;
        };

        return 1;
    }

    fn imPreeditStart(
        _: *gtk.IMMulticontext,
        self: *Self,
    ) callconv(.c) void {
        // log.warn("GTKIM: preedit start", .{});

        // Start our composing state for the input method and reset our
        // input buffer to empty.
        const priv = self.private();
        priv.im_composing = true;
        priv.im_len = 0;
    }

    fn imPreeditChanged(
        ctx: *gtk.IMMulticontext,
        self: *Self,
    ) callconv(.c) void {
        const priv = self.private();

        // Any preedit change should mark that we're composing. Its possible this
        // is false using fcitx5-hangul and typing "dkssud<space>" ("안녕"). The
        // second "s" results in a "commit" for "안" which sets composing to false,
        // but then immediately sends a preedit change for the next symbol. With
        // composing set to false we won't commit this text. Therefore, we must
        // ensure it is set here.
        priv.im_composing = true;

        // We can't set our preedit on our surface unless we're realized.
        // We do this now because we want to still keep our input method
        // state coherent.
        const surface = priv.core_surface orelse return;

        // Get our pre-edit string that we'll use to show the user.
        var buf: [*:0]u8 = undefined;
        ctx.as(gtk.IMContext).getPreeditString(
            &buf,
            null,
            null,
        );
        defer glib.free(buf);
        const str = std.mem.sliceTo(buf, 0);

        // Update our preedit state in Ghostty core
        // log.warn("GTKIM: preedit change str={s}", .{str});
        surface.preeditCallback(str) catch |err| {
            log.warn(
                "error in preedit callback err={}",
                .{err},
            );
        };
    }

    fn imPreeditEnd(
        _: *gtk.IMMulticontext,
        self: *Self,
    ) callconv(.c) void {
        // log.warn("GTKIM: preedit end", .{});

        // End our composing state for GTK, allowing us to commit the text.
        const priv = self.private();
        priv.im_composing = false;

        // End our preedit state in Ghostty core
        const surface = priv.core_surface orelse return;
        surface.preeditCallback(null) catch |err| {
            log.warn("error in preedit callback err={}", .{err});
        };
    }

    fn imCommit(
        _: *gtk.IMMulticontext,
        bytes: [*:0]u8,
        self: *Self,
    ) callconv(.c) void {
        const priv = self.private();
        const str = std.mem.sliceTo(bytes, 0);

        // log.debug("GTKIM: input commit composing={} keyevent={} str={s}", .{
        //     self.im_composing,
        //     self.in_keyevent,
        //     str,
        // });

        // We need to handle commit specially if we're in a key event.
        // Specifically, GTK will send us a commit event for basic key
        // encodings like "a" (on a US layout keyboard). We don't want
        // to treat this as IME committed text because we want to associate
        // it with a key event (i.e. "a" key press).
        switch (priv.in_keyevent) {
            // If we're not in a key event then this commit is from
            // some other source (i.e. on-screen keyboard, tablet, etc.)
            // and we want to commit the text to the core surface.
            .false => {},

            // If we're in a composing state and in a key event then this
            // key event is resulting in a commit of multiple keypresses
            // and we don't want to encode it alongside the keypress.
            .composing => {},

            // If we're not composing then this commit is just a normal
            // key encoding and we want our key event to handle it so
            // that Ghostty can be aware of the key event alongside
            // the text.
            .not_composing => {
                if (str.len > priv.im_buf.len) {
                    log.warn("not enough buffer space for input method commit", .{});
                    return;
                }

                // Copy our committed text to the buffer
                @memcpy(priv.im_buf[0..str.len], str);
                priv.im_len = @intCast(str.len);

                // log.debug("input commit len={}", .{priv.im_len});
                return;
            },
        }

        // If we reach this point from above it means we're composing OR
        // not in a keypress. In either case, we want to commit the text
        // given to us because that's what GTK is asking us to do. If we're
        // not in a keypress it means that this commit came via a non-keyboard
        // event (i.e. on-screen keyboard, tablet of some kind, etc.).

        // Committing ends composing state
        priv.im_composing = false;

        // We can't set our preedit on our surface unless we're realized.
        // We do this now because we want to still keep our input method
        // state coherent.
        if (priv.core_surface) |surface| {
            // End our preedit state. Well-behaved input methods do this for us
            // by triggering a preedit-end event but some do not (ibus 1.5.29).
            surface.preeditCallback(null) catch |err| {
                log.warn("error in preedit callback err={}", .{err});
            };

            // Send the text to the core surface, associated with no key (an
            // invalid key, which should produce no PTY encoding).
            _ = surface.keyCallback(.{
                .action = .press,
                .key = .unidentified,
                .mods = .{},
                .consumed_mods = .{},
                .composing = false,
                .utf8 = str,
            }) catch |err| {
                log.warn("error in key callback err={}", .{err});
            };
        }
    }

    fn glareaRealize(
        _: *gtk.GLArea,
        self: *Self,
    ) callconv(.c) void {
        log.debug("realize", .{});

        // If we already have an initialized surface then we notify it.
        // If we don't, we'll initialize it on the first resize so we have
        // our proper initial dimensions.
        const priv = self.private();
        if (priv.core_surface) |v| realize: {
            // We need to make the context current so we can call GL functions.
            // This is required for all surface operations.
            priv.gl_area.makeCurrent();
            if (priv.gl_area.getError()) |err| {
                log.warn("failed to make GL context current: {s}", .{err.f_message orelse "(no message)"});
                log.warn("this error is usually due to a driver or gtk bug", .{});
                log.warn("this is a common cause of this issue: https://gitlab.gnome.org/GNOME/gtk/-/issues/4950", .{});
                break :realize;
            }

            v.renderer.displayRealized() catch |err| {
                log.warn("core displayRealized failed err={}", .{err});
                break :realize;
            };

            self.redraw();
        }

        // Setup our input method. We do this here because this will
        // create a strong reference back to ourself and we want to be
        // able to release that in unrealize.
        priv.im_context.as(gtk.IMContext).setClientWidget(self.as(gtk.Widget));
    }

    fn glareaUnrealize(
        gl_area: *gtk.GLArea,
        self: *Self,
    ) callconv(.c) void {
        log.debug("unrealize", .{});

        // Notify our core surface
        const priv = self.private();
        if (priv.core_surface) |surface| {
            // There is no guarantee that our GLArea context is current
            // when unrealize is emitted, so we need to make it current.
            gl_area.makeCurrent();
            if (gl_area.getError()) |err| {
                // I don't know a scenario this can happen, but it means
                // we probably leaked memory because displayUnrealized
                // below frees resources that aren't specifically OpenGL
                // related. I didn't make the OpenGL renderer handle this
                // scenario because I don't know if its even possible
                // under valid circumstances, so let's log.
                log.warn(
                    "gl_area_make_current failed in unrealize msg={s}",
                    .{err.f_message orelse "(no message)"},
                );
                log.warn("OpenGL resources and memory likely leaked", .{});
                return;
            }

            surface.renderer.displayUnrealized();
        }

        // Unset our input method
        priv.im_context.as(gtk.IMContext).setClientWidget(null);
    }

    fn glareaRender(
        _: *gtk.GLArea,
        _: *gdk.GLContext,
        self: *Self,
    ) callconv(.c) c_int {
        // If we don't have a surface then we failed to initialize for
        // some reason and there's nothing to draw to the GLArea.
        const priv = self.private();
        const surface = priv.core_surface orelse return 1;

        surface.renderer.drawFrame(true) catch |err| {
            log.warn("failed to draw frame err={}", .{err});
            return 0;
        };

        return 1;
    }

    fn glareaResize(
        gl_area: *gtk.GLArea,
        width: c_int,
        height: c_int,
        self: *Self,
    ) callconv(.c) void {
        // Some debug output to help understand what GTK is telling us.
        {
            const widget = gl_area.as(gtk.Widget);
            const scale_factor = widget.getScaleFactor();
            const window_scale_factor = scale: {
                const root = widget.getRoot() orelse break :scale 0;
                const gtk_native = root.as(gtk.Native);
                const gdk_surface = gtk_native.getSurface() orelse break :scale 0;
                break :scale gdk_surface.getScaleFactor();
            };

            log.debug("gl resize width={} height={} scale={} window_scale={}", .{
                width,
                height,
                scale_factor,
                window_scale_factor,
            });
        }

        // Store our cached size
        const priv = self.private();
        priv.size = .{
            .width = @intCast(width),
            .height = @intCast(height),
        };

        // If our surface is realize, we send callbacks.
        if (priv.core_surface) |surface| {
            // We also update the content scale because there is no signal for
            // content scale change and it seems to trigger a resize event.
            surface.contentScaleCallback(self.getContentScale()) catch |err| {
                log.warn("error in content scale callback err={}", .{err});
            };

            surface.sizeCallback(priv.size) catch |err| {
                log.warn("error in size callback err={}", .{err});
            };

            // Setup our resize overlay if configured
            self.resizeOverlaySchedule();

            return;
        }

        // If we don't have a surface, then we initialize it.
        self.initSurface() catch |err| {
            log.warn("surface failed to initialize err={}", .{err});
        };
    }

    const InitError = Allocator.Error || error{
        GLAreaError,
        SurfaceError,
    };

    fn initSurface(self: *Self) InitError!void {
        const priv = self.private();
        assert(priv.core_surface == null);
        const gl_area = priv.gl_area;

        // We need to make the context current so we can call GL functions.
        // This is required for all surface operations.
        gl_area.makeCurrent();
        if (gl_area.getError()) |err| {
            log.warn("failed to make GL context current: {s}", .{err.f_message orelse "(no message)"});
            log.warn("this error is usually due to a driver or gtk bug", .{});
            log.warn("this is a common cause of this issue: https://gitlab.gnome.org/GNOME/gtk/-/issues/4950", .{});
            return error.GLAreaError;
        }

        const app = Application.default();
        const alloc = app.allocator();

        // Initialize our cgroup if we can.
        self.initCgroup();
        errdefer self.clearCgroup();

        // Make our pointer to store our surface
        const surface = try alloc.create(CoreSurface);
        errdefer alloc.destroy(surface);

        // Add ourselves to the list of surfaces on the app.
        try app.core().addSurface(self.rt());
        errdefer app.core().deleteSurface(self.rt());

        // Initialize our surface configuration.
        var config = try apprt.surface.newConfig(
            app.core(),
            priv.config.?.get(),
        );
        defer config.deinit();

        // Properties that can impact surface init
        if (priv.font_size_request) |size| config.@"font-size" = size.points;
        if (priv.pwd) |pwd| config.@"working-directory" = pwd;

        // Initialize the surface
        surface.init(
            alloc,
            &config,
            app.core(),
            app.rt(),
            &priv.rt_surface,
        ) catch |err| {
            log.warn("failed to initialize surface err={}", .{err});
            return error.SurfaceError;
        };
        errdefer surface.deinit();

        // Store it!
        priv.core_surface = surface;
    }

    fn resizeOverlaySchedule(self: *Self) void {
        const priv = self.private();
        const surface = priv.core_surface orelse return;

        // Only show the resize overlay if its enabled
        const config = if (priv.config) |c| c.get() else return;
        switch (config.@"resize-overlay") {
            .always, .@"after-first" => {},
            .never => return,
        }

        // If we have resize overlays enabled, setup an idler
        // to show that. We do this in an idle tick because doing it
        // during the resize results in flickering.
        var buf: [32]u8 = undefined;
        priv.resize_overlay.setLabel(text: {
            const grid_size = surface.size.grid();
            break :text std.fmt.bufPrintZ(
                &buf,
                "{d} x {d}",
                .{
                    grid_size.columns,
                    grid_size.rows,
                },
            ) catch |err| err: {
                log.warn("unable to format text: {}", .{err});
                break :err "";
            };
        });
        priv.resize_overlay.schedule();
    }

    fn ecUrlMouseEnter(
        _: *gtk.EventControllerMotion,
        _: f64,
        _: f64,
        self: *Self,
    ) callconv(.c) void {
        const priv = self.private();
        const right = priv.url_right.as(gtk.Widget);
        right.setVisible(1);
    }

    fn ecUrlMouseLeave(
        _: *gtk.EventControllerMotion,
        self: *Self,
    ) callconv(.c) void {
        const priv = self.private();
        const right = priv.url_right.as(gtk.Widget);
        right.setVisible(0);
    }

    const C = Common(Self, Private);
    pub const as = C.as;
    pub const ref = C.ref;
    pub const unref = C.unref;
    const private = C.private;

    pub const Class = extern struct {
        parent_class: Parent.Class,
        var parent: *Parent.Class = undefined;
        pub const Instance = Self;

        fn init(class: *Class) callconv(.C) void {
            gobject.ext.ensureType(ResizeOverlay);
            gobject.ext.ensureType(ChildExited);
            gtk.Widget.Class.setTemplateFromResource(
                class.as(gtk.Widget.Class),
                comptime gresource.blueprint(.{
                    .major = 1,
                    .minor = 2,
                    .name = "surface",
                }),
            );

            // Bindings
            class.bindTemplateChildPrivate("gl_area", .{});
            class.bindTemplateChildPrivate("url_left", .{});
            class.bindTemplateChildPrivate("url_right", .{});
            class.bindTemplateChildPrivate("child_exited_overlay", .{});
            class.bindTemplateChildPrivate("progress_bar_overlay", .{});
            class.bindTemplateChildPrivate("resize_overlay", .{});
            class.bindTemplateChildPrivate("drop_target", .{});
            class.bindTemplateChildPrivate("im_context", .{});

            // Template Callbacks
            class.bindTemplateCallback("focus_enter", &ecFocusEnter);
            class.bindTemplateCallback("focus_leave", &ecFocusLeave);
            class.bindTemplateCallback("key_pressed", &ecKeyPressed);
            class.bindTemplateCallback("key_released", &ecKeyReleased);
            class.bindTemplateCallback("mouse_down", &gcMouseDown);
            class.bindTemplateCallback("mouse_up", &gcMouseUp);
            class.bindTemplateCallback("mouse_motion", &ecMouseMotion);
            class.bindTemplateCallback("mouse_leave", &ecMouseLeave);
            class.bindTemplateCallback("scroll", &ecMouseScroll);
            class.bindTemplateCallback("scroll_begin", &ecMouseScrollPrecisionBegin);
            class.bindTemplateCallback("scroll_end", &ecMouseScrollPrecisionEnd);
            class.bindTemplateCallback("drop", &dtDrop);
            class.bindTemplateCallback("gl_realize", &glareaRealize);
            class.bindTemplateCallback("gl_unrealize", &glareaUnrealize);
            class.bindTemplateCallback("gl_render", &glareaRender);
            class.bindTemplateCallback("gl_resize", &glareaResize);
            class.bindTemplateCallback("im_preedit_start", &imPreeditStart);
            class.bindTemplateCallback("im_preedit_changed", &imPreeditChanged);
            class.bindTemplateCallback("im_preedit_end", &imPreeditEnd);
            class.bindTemplateCallback("im_commit", &imCommit);
            class.bindTemplateCallback("url_mouse_enter", &ecUrlMouseEnter);
            class.bindTemplateCallback("url_mouse_leave", &ecUrlMouseLeave);
            class.bindTemplateCallback("child_exited_close", &childExitedClose);
            class.bindTemplateCallback("notify_config", &propConfig);
            class.bindTemplateCallback("notify_mouse_hover_url", &propMouseHoverUrl);
            class.bindTemplateCallback("notify_mouse_hidden", &propMouseHidden);
            class.bindTemplateCallback("notify_mouse_shape", &propMouseShape);

            // Properties
            gobject.ext.registerProperties(class, &.{
                properties.config.impl,
                properties.@"child-exited".impl,
                properties.@"font-size-request".impl,
                properties.focused.impl,
                properties.@"mouse-shape".impl,
                properties.@"mouse-hidden".impl,
                properties.@"mouse-hover-url".impl,
                properties.pwd.impl,
                properties.title.impl,
                properties.zoom.impl,
            });

            // Signals
            signals.@"close-request".impl.register(.{});
            signals.bell.impl.register(.{});
            signals.@"clipboard-read".impl.register(.{});
            signals.@"clipboard-write".impl.register(.{});
            signals.@"present-request".impl.register(.{});
            signals.@"toggle-fullscreen".impl.register(.{});
            signals.@"toggle-maximize".impl.register(.{});

            // Virtual methods
            gobject.Object.virtual_methods.dispose.implement(class, &dispose);
            gobject.Object.virtual_methods.finalize.implement(class, &finalize);
        }

        pub const as = C.Class.as;
        pub const bindTemplateChildPrivate = C.Class.bindTemplateChildPrivate;
        pub const bindTemplateCallback = C.Class.bindTemplateCallback;
    };

    /// The scope of a close request.
    pub const CloseScope = union(enum) {
        /// Close the surface. The boolean determines if there is a
        /// process active.
        surface: bool,

        /// Close the tab. We can't know if there are processes active
        /// for the entire tab scope so listeners must query the app.
        tab,

        /// Close the window.
        window,

        pub const getGObjectType = gobject.ext.defineBoxed(
            CloseScope,
            .{ .name = "GhosttySurfaceCloseScope" },
        );
    };
};

/// The state of the key event while we're doing IM composition.
/// See gtkKeyPressed for detailed descriptions.
pub const IMKeyEvent = enum {
    /// Not in a key event.
    false,

    /// In a key event but im_composing was either true or false
    /// prior to the calling IME processing. This is important to
    /// work around different input methods calling commit and
    /// preedit end in a different order.
    composing,
    not_composing,
};

fn translateMouseButton(button: c_uint) input.MouseButton {
    return switch (button) {
        1 => .left,
        2 => .middle,
        3 => .right,
        4 => .four,
        5 => .five,
        6 => .six,
        7 => .seven,
        8 => .eight,
        9 => .nine,
        10 => .ten,
        11 => .eleven,
        else => .unknown,
    };
}

/// A namespace for our clipboard-related functions so Surface isn't SO large.
const Clipboard = struct {
    /// Set the clipboard contents.
    pub fn set(
        self: *Surface,
        val: [:0]const u8,
        clipboard_type: apprt.Clipboard,
        confirm: bool,
    ) void {
        const priv = self.private();

        // If no confirmation is necessary, set the clipboard.
        if (!confirm) {
            const clipboard = get(
                priv.gl_area.as(gtk.Widget),
                clipboard_type,
            ) orelse return;
            clipboard.setText(val);

            Surface.signals.@"clipboard-write".impl.emit(
                self,
                null,
                .{ clipboard_type, val.ptr },
                null,
            );

            return;
        }

        showClipboardConfirmation(
            self,
            .{ .osc_52_write = clipboard_type },
            val,
        );
    }

    /// Request data from the clipboard (read the clipboard). This
    /// completes asynchronously and will call the `completeClipboardRequest`
    /// core surface API when done.
    pub fn request(
        self: *Surface,
        clipboard_type: apprt.Clipboard,
        state: apprt.ClipboardRequest,
    ) Allocator.Error!void {
        // Get our requested clipboard
        const clipboard = get(
            self.private().gl_area.as(gtk.Widget),
            clipboard_type,
        ) orelse return;

        // Allocate our userdata
        const alloc = Application.default().allocator();
        const ud = try alloc.create(Request);
        errdefer alloc.destroy(ud);
        ud.* = .{
            // Important: we ref self here so that we can't free memory
            // while we have an outstanding clipboard read.
            .self = self.ref(),
            .state = state,
        };
        errdefer self.unref();

        // Read
        clipboard.readTextAsync(
            null,
            clipboardReadText,
            ud,
        );
    }

    /// Paste explicit text directly into the surface, regardless of the
    /// actual clipboard contents.
    pub fn paste(
        self: *Surface,
        text: [:0]const u8,
    ) void {
        if (text.len == 0) return;

        const surface = self.private().core_surface orelse return;
        surface.completeClipboardRequest(
            .paste,
            text,
            false,
        ) catch |err| switch (err) {
            error.UnsafePaste,
            error.UnauthorizedPaste,
            => {
                showClipboardConfirmation(
                    self,
                    .paste,
                    text,
                );
                return;
            },

            else => {
                log.warn(
                    "failed to complete clipboard request err={}",
                    .{err},
                );
                return;
            },
        };
    }

    /// Get the specific type of clipboard for a widget.
    fn get(
        widget: *gtk.Widget,
        clipboard: apprt.Clipboard,
    ) ?*gdk.Clipboard {
        return switch (clipboard) {
            .standard => widget.getClipboard(),
            .selection, .primary => widget.getPrimaryClipboard(),
        };
    }

    fn showClipboardConfirmation(
        self: *Surface,
        req: apprt.ClipboardRequest,
        str: [:0]const u8,
    ) void {
        // Build a text buffer for our contents
        const contents_buf: *gtk.TextBuffer = .new(null);
        defer contents_buf.unref();
        contents_buf.insertAtCursor(str, @intCast(str.len));

        // Confirm
        const dialog = gobject.ext.newInstance(
            ClipboardConfirmationDialog,
            .{
                .request = &req,
                .@"can-remember" = switch (req) {
                    .osc_52_read, .osc_52_write => true,
                    .paste => false,
                },
                .@"clipboard-contents" = contents_buf,
            },
        );

        _ = ClipboardConfirmationDialog.signals.confirm.connect(
            dialog,
            *Surface,
            clipboardConfirmationConfirm,
            self,
            .{},
        );
        _ = ClipboardConfirmationDialog.signals.deny.connect(
            dialog,
            *Surface,
            clipboardConfirmationDeny,
            self,
            .{},
        );

        dialog.present(self.as(gtk.Widget));
    }

    fn clipboardConfirmationConfirm(
        dialog: *ClipboardConfirmationDialog,
        remember: bool,
        self: *Surface,
    ) callconv(.c) void {
        const priv = self.private();
        const surface = priv.core_surface orelse return;
        const req = dialog.getRequest() orelse return;

        // Handle remember
        if (remember) switch (req.*) {
            .osc_52_read => surface.config.clipboard_read = .allow,
            .osc_52_write => surface.config.clipboard_write = .allow,
            .paste => {},
        };

        // Get our text
        const text_buf = dialog.getClipboardContents() orelse return;
        var text_val = gobject.ext.Value.new(?[:0]const u8);
        defer text_val.unset();
        gobject.Object.getProperty(
            text_buf.as(gobject.Object),
            "text",
            &text_val,
        );
        const text = gobject.ext.Value.get(
            &text_val,
            ?[:0]const u8,
        ) orelse return;

        surface.completeClipboardRequest(
            req.*,
            text,
            true,
        ) catch |err| {
            log.warn("failed to complete clipboard request: {}", .{err});
        };
    }

    fn clipboardConfirmationDeny(
        dialog: *ClipboardConfirmationDialog,
        remember: bool,
        self: *Surface,
    ) callconv(.c) void {
        const priv = self.private();
        const surface = priv.core_surface orelse return;
        const req = dialog.getRequest() orelse return;

        // Handle remember
        if (remember) switch (req.*) {
            .osc_52_read => surface.config.clipboard_read = .deny,
            .osc_52_write => surface.config.clipboard_write = .deny,
            .paste => @panic("paste should not be able to be remembered"),
        };
    }

    fn clipboardReadText(
        source: ?*gobject.Object,
        res: *gio.AsyncResult,
        ud: ?*anyopaque,
    ) callconv(.c) void {
        const clipboard = gobject.ext.cast(
            gdk.Clipboard,
            source orelse return,
        ) orelse return;
        const req: *Request = @ptrCast(@alignCast(ud orelse return));

        const alloc = Application.default().allocator();
        defer alloc.destroy(req);

        const self = req.self;
        defer self.unref();

        var gerr: ?*glib.Error = null;
        const cstr_ = clipboard.readTextFinish(res, &gerr);
        if (gerr) |err| {
            defer err.free();
            log.warn(
                "failed to read clipboard err={s}",
                .{err.f_message orelse "(no message)"},
            );
            return;
        }
        const cstr = cstr_ orelse return;
        defer glib.free(cstr);
        const str = std.mem.sliceTo(cstr, 0);

        const surface = self.private().core_surface orelse return;
        surface.completeClipboardRequest(
            req.state,
            str,
            false,
        ) catch |err| switch (err) {
            error.UnsafePaste,
            error.UnauthorizedPaste,
            => {
                showClipboardConfirmation(
                    self,
                    req.state,
                    str,
                );
                return;
            },

            else => {
                log.warn(
                    "failed to complete clipboard request err={}",
                    .{err},
                );
                return;
            },
        };

        Surface.signals.@"clipboard-read".impl.emit(
            self,
            null,
            .{},
            null,
        );
    }

    /// The request we send as userdata to the clipboard read.
    const Request = struct {
        /// "Self" is reffed so we can't dispose it until the clipboard
        /// read is complete. Callers must unref when done.
        self: *Surface,
        state: apprt.ClipboardRequest,
    };
};

/// Check a GValue to see what's type its wrapping. This is equivalent to GTK's
/// `G_VALUE_HOLDS` macro but Zig's C translator does not like it.
fn g_value_holds(value_: ?*gobject.Value, g_type: gobject.Type) bool {
    if (value_) |value| {
        if (value.f_g_type == g_type) return true;
        return gobject.typeCheckValueHolds(value, g_type) != 0;
    }
    return false;
}

/// Compute a fraction [0.0, 1.0] from the supplied progress, which is clamped
/// to [0, 100].
fn computeFraction(progress: u8) f64 {
    return @as(f64, @floatFromInt(std.math.clamp(progress, 0, 100))) / 100.0;
}

test "computeFraction" {
    try std.testing.expectEqual(1.0, computeFraction(100));
    try std.testing.expectEqual(1.0, computeFraction(255));
    try std.testing.expectEqual(0.0, computeFraction(0));
    try std.testing.expectEqual(0.5, computeFraction(50));
}
