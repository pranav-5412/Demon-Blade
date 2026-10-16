extends SceneTree

func _init():
    var dummy = Node.new()
    var hurtbox = Node.new()
    hurtbox.name = "Hurtbox"
    dummy.add_child(hurtbox)

    var start = Time.get_ticks_usec()
    for i in range(100000):
        var hb = dummy.get_node("Hurtbox")
    var end = Time.get_ticks_usec()
    var get_node_time = end - start

    var cached_hb = dummy.get_node("Hurtbox")
    start = Time.get_ticks_usec()
    for i in range(100000):
        var hb = cached_hb
    end = Time.get_ticks_usec()
    var cached_time = end - start

    print("get_node time: ", get_node_time, " us")
    print("cached time: ", cached_time, " us")
    print("Improvement: ", float(get_node_time) / float(cached_time), "x")
    quit()
