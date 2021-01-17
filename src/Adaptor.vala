namespace Wevf {

public class Adaptor : Gtk.EventBox {
    
    private static Wevp.ViewInterface impl = {
        Adaptor.change_cursor
    };
    private unowned Display display;
    public unowned Canvas canvas;
    public unowned Wl.Client? client;
    public unowned Wevp.View? view;
    public Surface? surface;
    public uint serial;
    public uint width;
    public uint height;
    public uint scale;
    private uint resize_timeout_id = 0;
    private Gtk.IMContextSimple im_context;
    private string? im_string = null;

    public Adaptor(Display display, Canvas canvas) {
        this.display = display;
        this.canvas = canvas;
        this.im_context = new Gtk.IMContextSimple();
        canvas.show();
        add(canvas);
        above_child = true;
        visible_window = false;;
        can_focus = true;
        focus_on_click = true;
        add_events(
            Gdk.EventMask.BUTTON_RELEASE_MASK
            | Gdk.EventMask.BUTTON_PRESS_MASK
            | Gdk.EventMask.POINTER_MOTION_MASK
            | Gdk.EventMask.SCROLL_MASK     
            | Gdk.EventMask.KEY_PRESS_MASK 
            | Gdk.EventMask.KEY_RELEASE_MASK 
            | Gdk.EventMask.FOCUS_CHANGE_MASK
            | Gdk.EventMask.LEAVE_NOTIFY_MASK 
            | Gdk.EventMask.ENTER_NOTIFY_MASK 
            | Gdk.EventMask.VISIBILITY_NOTIFY_MASK
        );
        canvas.size_allocate.connect_after(on_size_allocate);
        canvas.notify["scale-factor"].connect_after(on_scale_factor_changed);
        button_press_event.connect(on_button_event);
        button_release_event.connect(on_button_event);
        motion_notify_event.connect(on_motion_notify_event);
        key_press_event.connect(on_key_event);
        key_release_event.connect(on_key_event);
        focus_in_event.connect(on_focus_event);
        focus_out_event.connect(on_focus_event);
        scroll_event.connect(on_scroll_event);
        enter_notify_event.connect(on_crossing_event);
        leave_notify_event.connect(on_crossing_event);
        realize.connect_after(on_realize);
    }

    ~Adaptor() {
        realize.disconnect(on_realize);
        enter_notify_event.disconnect(on_crossing_event);
        leave_notify_event.disconnect(on_crossing_event);
        scroll_event.disconnect(on_scroll_event);
        focus_in_event.disconnect(on_focus_event);
        focus_out_event.disconnect(on_focus_event);
        key_press_event.disconnect(on_key_event);
        key_release_event.disconnect(on_key_event);
        motion_notify_event.disconnect(on_motion_notify_event);
        button_release_event.disconnect(on_button_event);
        button_press_event.disconnect(on_button_event);
        canvas.notify["scale-factor"].disconnect(on_scale_factor_changed);
        canvas.size_allocate.disconnect(on_size_allocate);
        canvas.set_surface(null);

        if (view != null) {
            view.send_released();
        }
    }

    public void check_state() {
        if (view == null) {
            return;
        }

        uint width = (uint) canvas.get_allocated_width();
        uint height = (uint) canvas.get_allocated_height();
        uint scale = (uint) canvas.scale_factor;
        if (this.width != width || this.height != height) {
            this.width = width;
            this.height = height;
            view.send_resized(width, height);
        }
        if (this.scale != scale) {
            this.scale = scale;
            view.send_rescaled(scale);
        }
        display.dispatch();
    }

    public void attach_view(Wl.Client? client, Wevp.View view, Surface surface) {
        this.serial = 0;
        this.client = client;
        this.view = view;
        this.surface = surface;
        view.set_implementation(&Adaptor.impl, this, null);
        canvas.set_surface(surface);
        view.send_focus_event(has_focus ? Wevp.EventType.FOCUS_IN : Wevp.EventType.FOCUS_OUT);
    }

    private void on_size_allocate(Gtk.Allocation alloc) {
        if (resize_timeout_id != 0) {
            Source.remove(resize_timeout_id);
        }
        resize_timeout_id = Timeout.add(10, () => {
            resize_timeout_id = 0;
            check_state();
            return false;
        });
    }

    private void on_scale_factor_changed(GLib.Object o, ParamSpec p) {
        check_state();
    }

    private bool on_key_event(Gdk.EventKey event) {
        string? str = ((unichar) Gdk.keyval_to_unicode(event.keyval)).to_string();
        debug("%s(%s:%s:%s): %u, %u, %u", event.type.to_string(), Gdk.keyval_name(event.keyval), event.str, str, event.keyval, event.hardware_keycode, (uint) event.group);
        if (im_context.filter_keypress(event)) {
            if (im_string != null) {
                str = (owned) im_string;
            } else {
                return true;
            }
        }
        
        Wevp.EventType type;
        switch (event.type) {
        case Gdk.EventType.KEY_PRESS:
            type = Wevp.EventType.KEY_PRESS;
            break;
        case Gdk.EventType.KEY_RELEASE:
            type = Wevp.EventType.KEY_RELEASE;
            break;
        default:
            return false;
        }
        debug("%s(%s:%s:%s): %u, %u, %u", type.to_string(), Gdk.keyval_name(event.keyval), event.str, str, event.keyval, event.hardware_keycode, (uint) event.group);
        if (view != null) {
            view.send_key_event(type, Gdk.keyval_name(event.keyval), Keyboard.serialize_modifiers(event.state), event.keyval, event.hardware_keycode, (uint) event.state, str);
        }
        return false;
    }

    private bool on_button_event(Gdk.EventButton event) {
        Wevp.EventType type;
        switch (event.type) {
        case Gdk.EventType.BUTTON_PRESS:
            type = Wevp.EventType.MOUSE_PRESS;
            break;
        case Gdk.EventType.BUTTON_RELEASE:
            type = Wevp.EventType.MOUSE_RELEASE;
            break;
        case Gdk.EventType.DOUBLE_BUTTON_PRESS:
            type = Wevp.EventType.MOUSE_DOUBLE_CLICK;
            break;
        default:
            return false;
        }
        grab_focus();
        send_mouse_event(type, event.button, event.state, event.x, event.y, event.x_root, event.y_root);
        return false;
    }

    private bool on_focus_event(Gdk.EventFocus event) {
        Wevp.EventType type = event.@in == 0 ? Wevp.EventType.FOCUS_OUT : Wevp.EventType.FOCUS_IN;
        if (type == Wevp.EventType.FOCUS_IN) {
            grab_focus();
            im_context.focus_in();
        } else {
            im_context.focus_out();
        }
        debug("%s", type.to_string());
        if (view != null) {
            view.send_focus_event(type);
        }
        return false;
    }

    private bool on_motion_notify_event(Gdk.EventMotion event) {
        send_mouse_event(Wevp.EventType.MOUSE_MOVE, 0, event.state, event.x, event.y, event.x_root, event.y_root);
        return false;
    }

    private void send_mouse_event(Wevp.EventType type, uint button, Gdk.ModifierType state, double x, double y, double x_root, double y_root) {
        if (type != Wevp.EventType.MOUSE_MOVE) {
            debug("%s(%u): [%f, %f] [%f, %f]", type.to_string(), button, x, y, x_root, y_root);
        }
        if (view != null) {
            view.send_mouse_event(type, (Wevp.MouseButton) button, Keyboard.serialize_modifiers(state), x, y, x, y, x_root, y_root);
        }
    }

    private bool on_scroll_event(Gdk.EventScroll event) {
        Wevp.EventType type;
        switch (event.direction) {
        case Gdk.ScrollDirection.UP:
            type = Wevp.EventType.SCROLL_UP;
            break;
        case Gdk.ScrollDirection.DOWN:
            type = Wevp.EventType.SCROLL_DOWN;
            break;
        case Gdk.ScrollDirection.LEFT:
            type = Wevp.EventType.SCROLL_LEFT;
            break;
        case Gdk.ScrollDirection.RIGHT:
            type = Wevp.EventType.SCROLL_RIGHT;
            break;
        default:
            return false;
        }
        debug("%s: [%f, %f] [%f, %f] [%f, %f]", type.to_string(), event.delta_x, event.delta_y, event.x, event.y, event.x_root, event.y_root);
        if (view != null) {
            view.send_scroll_event(type, Keyboard.serialize_modifiers(event.state), event.delta_x, event.delta_y, event.x, event.y, event.x, event.y, event.x_root, event.y_root);
            return true;
        }
        return false;
        
    }

    private bool on_crossing_event(Gdk.EventCrossing event) {
        Wevp.EventType type;
        switch (event.type) {
        case Gdk.EventType.ENTER_NOTIFY:
            type = Wevp.EventType.ENTER;
            break;
        case Gdk.EventType.LEAVE_NOTIFY:
            type = Wevp.EventType.LEAVE;
            break;
        default:
            return false;
        }
        if (view != null) {
            view.send_crossing_event(type, event.x, event.y, event.x, event.y, event.x_root, event.y_root);
        }
        return true;
    }

    public override bool focus(Gtk.DirectionType direction) {
        debug("Grab focus");
        grab_focus();
        return Gdk.EVENT_STOP;
    }

    private static void change_cursor(Wl.Client client, Wevp.View wl_view, string? name) {
        unowned Adaptor? self = (Adaptor) wl_view.get_user_data();
        var display = self.get_window().get_display();
        self.get_window().set_cursor(new Gdk.Cursor.from_name(display, name));
    }

    private void on_realize() {
        im_context.set_client_window(get_window());
        im_context.commit.connect(on_im_commited);
    }

    private void on_im_commited(string str) {
        this.im_string = str;
    }
}

} // namespace Wevf
