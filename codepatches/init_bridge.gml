if (!instance_exists(o_autochartswitch_bridge))
{
    var _bridge = instance_create_depth(0, 0, 100000, o_autochartswitch_bridge);
    _bridge.persistent = true;
}
