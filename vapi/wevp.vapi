[CCode(cheader_filename="wevp-embed.h")]
namespace Wevp {

[CCode(has_target=false)]
public delegate void PongFunc(Wl.Client client, Embedder wl_embedder, uint serial);

[CCode(has_target=false)]
public delegate void CreateViewFunc(Wl.Client client, Embedder wl_embedder, uint serial, uint view_id, Wl.Surface surface, uint width, uint height, uint scale);

[CCode (cname = "struct wevp_embedder_interface", has_type_id = false)]
public struct EmbedderInterface {
    public PongFunc pong;
    public CreateViewFunc create_view;
}

[CCode(cname="struct wl_resource", free_function="wl_resource_destroy")]
[Compact]
public class Embedder: Wl.Resource {
    [CCode(cname="wl_resource_create")]
    public static unowned Embedder create(Wl.Client client, ref Wl.Interface ifce, int version, uint id);
    public void send_ping(uint serial);
    public void send_view_requested(uint serial, uint width, uint height, uint scale);
}

[CCode(cname="struct wl_resource", free_function="wl_resource_destroy")]
[Compact]
public class View: Wl.Resource {
    [CCode(cname="wl_resource_create")]
    public static unowned View create(Wl.Client client, ref Wl.Interface ifce, int version, uint id);
    public void send_resized(uint width, uint height);
    public void send_rescaled(uint scale);
}

public static Wl.Interface embedder_interface;
public static Wl.Interface view_interface;

} // namespace Nuv