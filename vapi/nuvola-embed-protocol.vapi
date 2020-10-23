[CCode(cheader_filename="nuvola-embed-protocol.h")]
namespace Nuv {

[CCode(has_target=false)]
public delegate void PongFunc(Wl.Client client, Wl.Resource resource, uint serial);

[CCode(has_target=false)]
public delegate void NewViewFunc(Wl.Client client, Wl.Resource resource, uint serial, uint id, uint width, uint height, uint scale);

[CCode (cname = "struct nuv_embeder_interface", has_type_id = false)]
public struct EmbederInterface {
    public PongFunc pong;
    public NewViewFunc new_view;
}

[CCode(cname="struct wl_resource", free_function="wl_resource_destroy")]
[Compact]
public class Embeder: Wl.Resource {
    [CCode(cname="wl_resource_create")]
    public Embeder(Wl.Client client, ref Wl.Interface ifce, int version, uint id);
    public void send_ping(uint serial);
    public void send_view_request(uint serial, uint width, uint height, uint scale);
}

[CCode(cname="struct wl_resource", free_function="wl_resource_destroy")]
[Compact]
public class View: Wl.Resource {
    [CCode(cname="wl_resource_create")]
    public View(Wl.Client client, ref Wl.Interface ifce, int version, uint id);
    public void send_resize(uint width, uint height);
    public void send_rescale(uint scale);
}

public static Wl.Interface embeder_interface;
public static Wl.Interface view_interface;

} // namespace Nuv