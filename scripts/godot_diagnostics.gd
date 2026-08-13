#!/usr/bin/env -S godot --headless --script
extends SceneTree

func _init():
    var root = "res://"
    print("[DIAG] Starting script diagnostics in project: " + ProjectSettings.globalize_path(root))
    var dir = DirAccess.open(root)
    if dir == null:
        printerr("[DIAG] Failed to open project root: " + root)
        quit(1)
    _scan_dir_recursive(dir, root)
    print("[DIAG] Diagnostics complete")
    quit()

func _scan_dir_recursive(dir: DirAccess, path_prefix: String) -> void:
    dir.list_dir_begin()
    var file_name = dir.get_next()
    while file_name != "":
        if dir.current_is_dir():
            var subdir_path = path_prefix.path_join(file_name)
            var subdir = DirAccess.open(subdir_path)
            if subdir:
                _scan_dir_recursive(subdir, subdir_path)
        else:
            if file_name.ends_with(".gd"):
                var file_res_path = path_prefix.path_join(file_name)
                _check_script(file_res_path)
        file_name = dir.get_next()
    dir.list_dir_end()

func _check_script(res_path: String) -> void:
    print("[DIAG] Loading: " + res_path)
    var script = ResourceLoader.load(res_path)
    # ResourceLoader.load logs errors to stderr on failure; also check returned value
    if script == null:
        printerr("[DIAG][ERROR] Failed to load script: " + res_path)
    else:
        print("[DIAG][OK] Loaded: " + res_path)
