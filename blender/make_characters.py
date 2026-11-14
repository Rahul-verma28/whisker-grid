"""
Builds every playable character in Blender, rigged with simple pivots and animated.
For each character it writes:
  - assets/characters/<id>_icon.png   head portrait with a cartoon outline (board, shop, HUD)
  - assets/characters/<id>.glb         3D model with animations "idle" and "happy"

Run headless from the project root:
  "C:/Program Files/Blender Foundation/Blender 5.3/blender.exe" -b -P blender/make_characters.py
Build only some:  ... -P blender/make_characters.py -- dog bunny
"""
import bpy
import math
import os
import sys
from mathutils import Vector

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(ROOT, "assets", "characters")
os.makedirs(OUT, exist_ok=True)
FPS = 24


class Rig:
    """Holds the pivots (empties) every part hangs from, plus helpers to make parts."""

    def __init__(self):
        bpy.ops.wm.read_factory_settings(use_empty=True)
        self.scene = bpy.context.scene
        self.scene.render.fps = FPS
        self.mats = {}
        self.parts = []      # (object, in_portrait)
        self.pivots = {}
        self.pivot("Root", (0, 0, 0), None)
        self.pivot("Head", (0, -0.02, 1.0), "Root")
        self.pivot("Tail", (0, 0.42, 0.28), "Root")
        for s, side in ((-1, "L"), (1, "R")):
            self.pivot("Eye" + side, (0.23 * s, -0.53, 1.45), "Head")

    # ---------- scene helpers ----------
    def pivot(self, name, loc, parent):
        e = bpy.data.objects.new(name, None)
        e.empty_display_size = 0.1
        e.location = loc
        self.scene.collection.objects.link(e)
        if parent:
            self._parent(e, self.pivots[parent])
        self.pivots[name] = e
        return e

    def _parent(self, obj, parent):
        bpy.context.view_layer.update()
        obj.parent = parent
        obj.matrix_parent_inverse = parent.matrix_world.inverted()

    def mat(self, name, rgb, rough=0.6):
        if name in self.mats:
            return self.mats[name]
        m = bpy.data.materials.new(name)
        try:
            m.use_nodes = True
        except Exception:
            pass
        bsdf = m.node_tree.nodes.get("Principled BSDF")
        if bsdf:
            bsdf.inputs["Base Color"].default_value = (*rgb, 1.0)
            bsdf.inputs["Roughness"].default_value = rough
        m.diffuse_color = (*rgb, 1.0)
        self.mats[name] = m
        return m

    def _finish(self, obj, name, mat, parent, portrait):
        obj.name = name
        obj.data.materials.append(mat)
        bpy.context.view_layer.objects.active = obj
        for o in bpy.context.selected_objects:
            o.select_set(False)
        obj.select_set(True)
        bpy.ops.object.shade_smooth()
        self._parent(obj, self.pivots[parent])
        self.parts.append((obj, portrait))
        return obj

    def ball(self, name, loc, scale, mat, parent="Root", rot=(0, 0, 0), portrait=None):
        bpy.ops.mesh.primitive_uv_sphere_add(segments=40, ring_count=20, radius=1.0, location=loc, rotation=rot)
        o = bpy.context.active_object
        o.scale = scale
        if portrait is None:
            portrait = parent not in ("Root", "Tail")
        return self._finish(o, name, mat, parent, portrait)

    def cone(self, name, loc, rot, r1, r2, depth, mat, parent):
        bpy.ops.mesh.primitive_cone_add(vertices=32, radius1=r1, radius2=r2, depth=depth, location=loc, rotation=rot)
        return self._finish(bpy.context.active_object, name, mat, parent, True)

    def tube(self, name, pts, radius, mat, parent="Root", end_radius=1.0, portrait=None):
        curve = bpy.data.curves.new(name + "Curve", "CURVE")
        curve.dimensions = "3D"
        curve.bevel_depth = radius
        curve.bevel_resolution = 4
        curve.use_fill_caps = True
        spline = curve.splines.new("BEZIER")
        spline.bezier_points.add(len(pts) - 1)
        for bp, p in zip(spline.bezier_points, pts):
            bp.co = p
            bp.handle_left_type = bp.handle_right_type = "AUTO"
        spline.bezier_points[-1].radius = end_radius
        obj = bpy.data.objects.new(name, curve)
        self.scene.collection.objects.link(obj)
        bpy.context.view_layer.objects.active = obj
        for o in bpy.context.selected_objects:
            o.select_set(False)
        obj.select_set(True)
        bpy.ops.object.convert(target="MESH")
        if portrait is None:
            portrait = parent not in ("Root", "Tail")
        return self._finish(obj, name, mat, parent, portrait)

    # ---------- shared anatomy ----------
    def body(self, fur, chest, paw, feet_long=1.0):
        F = self.mat("Fur", fur)
        C = self.mat("Chest", chest)
        P = self.mat("Paw", paw)
        self.ball("Body", (0, 0.06, 0.6), (0.48, 0.45, 0.56), F)
        self.ball("Chest", (0, -0.27, 0.64), (0.28, 0.2, 0.38), C)
        for s in (-1, 1):
            self.ball(f"Haunch{s}", (0.3 * s, 0.14, 0.3), (0.22, 0.3, 0.25), F)
            self.ball(f"Foot{s}", (0.34 * s, -0.08, 0.06), (0.12, 0.2 * feet_long, 0.07), P)
            self.ball(f"Leg{s}", (0.16 * s, -0.22, 0.3), (0.105, 0.105, 0.28), F)
            self.ball(f"Paw{s}", (0.17 * s, -0.33, 0.07), (0.12, 0.16, 0.08), P)
        return F, C, P

    def head(self, fur, iris, cheek_fluff=True, eye_y=0.0):
        F = self.mat("Fur", fur)
        B = self.mat("EyeBlack", (0.03, 0.025, 0.03), 0.12)
        I = self.mat("Iris", iris, 0.15)
        S = self.mat("Shine", (1, 1, 1), 0.05)
        K = self.mat("Blush", (1.0, 0.5, 0.58), 0.5)
        self.ball("Head", (0, -0.05, 1.42), (0.62, 0.54, 0.5), F, "Head")
        if cheek_fluff:
            for s in (-1, 1):
                self.ball(f"Fluff{s}", (0.4 * s, -0.06, 1.3), (0.22, 0.22, 0.17), F, "Head")
        for s, side in ((-1, "L"), (1, "R")):
            p = "Eye" + side
            x = 0.23 * s
            self.ball(f"EyeWhite{side}", (x, -0.52, 1.45), (0.15, 0.07, 0.185), B, p)
            self.ball(f"Iris{side}", (x, -0.56, 1.44), (0.125, 0.035, 0.155), I, p)
            self.ball(f"Pupil{side}", (x, -0.585, 1.44), (0.08, 0.02, 0.11), B, p)
            self.ball(f"Spark{side}", (x + 0.05, -0.605, 1.51), (0.05, 0.012, 0.05), S, p)
            self.ball(f"Spark2{side}", (x - 0.045, -0.6, 1.385), (0.025, 0.008, 0.025), S, p)
            self.ball(f"Blush{side}", (0.4 * s, -0.43, 1.3), (0.08, 0.03, 0.045), K, "Head")
        return F

    def mouth(self, y=-0.615, z=1.25, color=(0.3, 0.15, 0.1)):
        M = self.mat("Mouth", color, 0.4)
        self.tube("Mouth", [(-0.085, y + 0.012, z + 0.02), (-0.042, y, z - 0.02), (0, y - 0.004, z + 0.015),
                            (0.042, y, z - 0.02), (0.085, y + 0.012, z + 0.02)], 0.011, M, "Head")

    def whiskers(self, color, y=-0.57, z=1.28):
        W = self.mat("Whisker", color, 0.5)
        for s in (-1, 1):
            for k in range(3):
                dz = (k - 1) * 0.045
                self.tube(f"Whisker{s}{k}", [(0.16 * s, y, z + dz), (0.34 * s, y + 0.03, z + dz * 1.6 + 0.01),
                                             (0.52 * s, y + 0.08, z + dz * 2.4)], 0.006, W, "Head")


# ======================================================================== characters

def build_cat(r):
    fur, white = (0.96, 0.55, 0.2), (0.99, 0.95, 0.9)
    F, C, P = r.body(fur, white, white)
    F = r.head(fur, (0.45, 0.72, 0.25))
    stripe = r.mat("Stripe", (0.78, 0.33, 0.08))
    for i, x in enumerate((-0.13, 0.0, 0.13)):
        r.ball(f"Stripe{i}", (x, -0.32, 1.78 - abs(x) * 0.45), (0.035, 0.09, 0.13), stripe, "Head")
    for i, z in enumerate((0.95, 0.75, 0.55)):
        r.ball(f"BackStripe{i}", (0, 0.4, z), (0.36 - i * 0.02, 0.12, 0.045), stripe)
    for s, side in ((-1, "L"), (1, "R")):
        r.pivot("Ear" + side, (0.3 * s, 0.0, 1.76), "Head")
        r.cone(f"Ear{side}", (0.33 * s, 0.0, 1.9), (0, 0.36 * s, 0), 0.21, 0.035, 0.38, F, "Ear" + side)
        r.cone(f"InnerEar{side}", (0.32 * s, -0.08, 1.88), (0, 0.36 * s, 0), 0.12, 0.02, 0.26,
               r.mat("Pink", (1.0, 0.6, 0.66)), "Ear" + side)
        r.ball(f"Muzzle{side}", (0.08 * s, -0.52, 1.29), (0.12, 0.1, 0.09), r.mat("White", white), "Head")
    r.ball("Chin", (0, -0.47, 1.2), (0.1, 0.08, 0.06), r.mat("White", white), "Head")
    r.ball("Nose", (0, -0.62, 1.35), (0.05, 0.035, 0.035), r.mat("Nose", (0.95, 0.42, 0.5), 0.3), "Head")
    r.mouth(y=-0.61, z=1.27)
    r.whiskers((0.98, 0.95, 0.92))
    r.tube("Tail", [(0.0, 0.45, 0.25), (0.35, 0.75, 0.45), (0.45, 0.7, 0.95), (0.3, 0.6, 1.2)], 0.075, F, "Tail", 0.7)
    r.ball("TailTip", (0.3, 0.6, 1.2), (0.06, 0.06, 0.07), r.mat("White", white), "Tail")


def build_dog(r):
    fur, white = (0.88, 0.65, 0.4), (0.99, 0.95, 0.88)
    dark = r.mat("Dark", (0.5, 0.3, 0.17))
    F, C, P = r.body(fur, white, white)
    F = r.head(fur, (0.42, 0.25, 0.12), cheek_fluff=False)
    r.ball("Patch", (0.22, -0.43, 1.53), (0.19, 0.11, 0.2), dark, "Head")
    for s, side in ((-1, "L"), (1, "R")):
        r.pivot("Ear" + side, (0.5 * s, -0.02, 1.72), "Head")
        r.ball(f"Ear{side}", (0.6 * s, -0.02, 1.45), (0.14, 0.09, 0.32), dark, "Ear" + side, rot=(0, -0.3 * s, 0))
        r.ball(f"Jowl{side}", (0.09 * s, -0.5, 1.26), (0.14, 0.12, 0.1), r.mat("White", white), "Head")
    r.ball("Snout", (0, -0.48, 1.31), (0.2, 0.15, 0.13), r.mat("White", white), "Head")
    r.ball("Nose", (0, -0.64, 1.37), (0.08, 0.055, 0.055), r.mat("Nose", (0.06, 0.05, 0.05), 0.15), "Head")
    r.ball("NoseShine", (0.025, -0.69, 1.39), (0.02, 0.01, 0.012), r.mat("Shine", (1, 1, 1)), "Head")
    r.mouth(y=-0.62, z=1.24, color=(0.25, 0.12, 0.08))
    r.ball("Tongue", (0, -0.6, 1.17), (0.055, 0.03, 0.065), r.mat("Tongue", (1.0, 0.45, 0.55), 0.35), "Head")
    r.tube("Tail", [(0.0, 0.45, 0.32), (0.05, 0.7, 0.6), (0.0, 0.72, 0.9)], 0.07, F, "Tail", 0.55)
    r.ball("TailTip", (0.0, 0.72, 0.9), (0.055, 0.055, 0.07), r.mat("White", white), "Tail")


def build_bunny(r):
    fur, cream = (0.97, 0.96, 0.98), (1.0, 0.95, 0.9)
    F, C, P = r.body(fur, cream, cream, feet_long=1.45)
    F = r.head(fur, (0.35, 0.28, 0.4), cheek_fluff=False)
    pink = r.mat("Pink", (1.0, 0.62, 0.7))
    for s, side in ((-1, "L"), (1, "R")):
        r.pivot("Ear" + side, (0.18 * s, 0.0, 1.8), "Head")
        r.ball(f"Ear{side}", (0.21 * s, 0.0, 2.22), (0.11, 0.07, 0.42), F, "Ear" + side, rot=(0, 0.14 * s, 0))
        r.ball(f"InnerEar{side}", (0.225 * s, -0.06, 2.22), (0.06, 0.03, 0.32), pink, "Ear" + side, rot=(0, 0.14 * s, 0))
        r.ball(f"Muzzle{side}", (0.07 * s, -0.52, 1.3), (0.1, 0.09, 0.085), r.mat("Cream", cream), "Head")
    r.ball("Nose", (0, -0.62, 1.37), (0.05, 0.035, 0.035), r.mat("Nose", (1.0, 0.5, 0.6), 0.3), "Head")
    r.ball("Tooth", (0, -0.585, 1.19), (0.045, 0.02, 0.05), r.mat("Tooth", (1, 1, 1), 0.3), "Head")
    r.mouth(y=-0.6, z=1.25, color=(0.55, 0.35, 0.38))
    r.whiskers((0.75, 0.7, 0.72))
    r.ball("Puff", (0, 0.55, 0.4), (0.17, 0.17, 0.17), F, "Tail")


def build_mouse(r):
    fur, light = (0.6, 0.6, 0.68), (0.93, 0.91, 0.93)
    F, C, P = r.body(fur, light, (1.0, 0.72, 0.76))
    F = r.head(fur, (0.2, 0.2, 0.28), cheek_fluff=False)
    pink = r.mat("Pink", (1.0, 0.62, 0.7))
    for s, side in ((-1, "L"), (1, "R")):
        r.pivot("Ear" + side, (0.36 * s, 0.0, 1.7), "Head")
        r.ball(f"Ear{side}", (0.46 * s, 0.0, 1.86), (0.28, 0.06, 0.28), F, "Ear" + side, rot=(0, 0, 0.2 * s))
        r.ball(f"InnerEar{side}", (0.46 * s, -0.05, 1.86), (0.2, 0.03, 0.2), pink, "Ear" + side, rot=(0, 0, 0.2 * s))
    r.ball("Snout", (0, -0.53, 1.31), (0.17, 0.17, 0.13), r.mat("Light", light), "Head")
    r.ball("Nose", (0, -0.7, 1.35), (0.055, 0.04, 0.045), r.mat("Nose", (1.0, 0.5, 0.6), 0.3), "Head")
    r.mouth(y=-0.66, z=1.24)
    r.whiskers((0.25, 0.22, 0.28), y=-0.62, z=1.3)
    r.tube("Tail", [(0.0, 0.45, 0.15), (0.5, 0.75, 0.2), (0.75, 0.55, 0.7), (0.55, 0.35, 0.98)], 0.028, pink, "Tail", 0.6)


CHARACTERS = {"cat": build_cat, "dog": build_dog, "bunny": build_bunny, "mouse": build_mouse}


# ======================================================================== animation

def key(obj, path, frame, value):
    setattr(obj, path, value)
    obj.keyframe_insert(data_path=path, frame=frame)


def push_to_nla(objects, track_name):
    """Moves each object's current action into an NLA track; tracks with the same name
    across objects are merged into one glTF animation."""
    for obj in objects:
        ad = obj.animation_data
        if not ad or not ad.action:
            continue
        act = ad.action
        act.name = f"{track_name}_{obj.name}"
        track = ad.nla_tracks.new()
        track.name = track_name
        strip = track.strips.new(track_name, int(act.frame_range[0]), act)
        try:
            strip.action_slot = ad.action_slot
        except Exception:
            pass
        ad.action = None


def animate(r):
    P = r.pivots
    body = next(o for o, _ in r.parts if o.name == "Body")
    base_body = tuple(body.scale)
    ears = [P[k] for k in ("EarL", "EarR") if k in P]
    eyes = [P["EyeL"], P["EyeR"]]
    animated = [P["Root"], P["Head"], P["Tail"], body] + ears + eyes

    # ---- idle: 3 s loop. breathe, look around, tail sway, ear twitch, blink
    for f, k in ((1, 1.0), (37, 1.025), (73, 1.0)):
        key(body, "scale", f, (base_body[0] * k, base_body[1] * k, base_body[2] * (2 - k) ** -1))
    for f, (rx, ry, rz) in ((1, (0, 0, 0)), (20, (0.04, 0.09, 0.08)), (45, (-0.03, -0.06, -0.06)), (73, (0, 0, 0))):
        key(P["Head"], "rotation_euler", f, (rx, ry, rz))
    for f, z in ((1, -0.25), (19, 0.25), (37, -0.25), (55, 0.25), (73, -0.25)):
        key(P["Tail"], "rotation_euler", f, (0, 0, z))
    for i, e in enumerate(ears):
        s = -1 if i == 0 else 1
        for f, y in ((1, 0), (50, 0), (53, 0.25 * s), (56, 0), (59, 0.15 * s), (62, 0), (73, 0)):
            key(e, "rotation_euler", f, (0, y, 0))
    for e in eyes:
        for f, z in ((1, 1), (40, 1), (42, 0.08), (44, 1), (73, 1)):
            key(e, "scale", f, (1, 1, z))
    key(P["Root"], "location", 1, (0, 0, 0))
    key(P["Root"], "location", 73, (0, 0, 0))
    push_to_nla(animated, "idle")

    # ---- happy: 1.25 s loop. hop with squash & stretch, head bob, fast tail wag, smiley eyes
    for f, z, sq in ((1, 0.0, 0.9), (4, 0.0, 1.0), (11, 0.38, 1.06), (19, 0.0, 1.0), (22, 0.0, 0.9), (31, 0.0, 0.9)):
        key(P["Root"], "location", f, (0, 0, z))
        key(P["Root"], "scale", f, ((2 - sq), (2 - sq), sq))
    for f, ry in ((1, -0.18), (16, 0.18), (31, -0.18)):
        key(P["Head"], "rotation_euler", f, (-0.1, ry, 0))
    for f, z in ((1, -0.6), (5, 0.6), (9, -0.6), (13, 0.6), (17, -0.6), (21, 0.6), (25, -0.6), (31, -0.6)):
        key(P["Tail"], "rotation_euler", f, (0, 0, z))
    for i, e in enumerate(ears):
        s = -1 if i == 0 else 1
        for f, y in ((1, 0.2 * s), (11, -0.25 * s), (21, 0.2 * s), (31, 0.2 * s)):
            key(e, "rotation_euler", f, (0, y, 0))
    for e in eyes:
        key(e, "scale", 1, (1.05, 1, 0.5))
        key(e, "scale", 31, (1.05, 1, 0.5))
    key(body, "scale", 1, base_body)
    key(body, "scale", 31, base_body)
    push_to_nla(animated, "happy")

    # rest pose for rendering
    for o in animated:
        if o.animation_data:
            o.animation_data.action = None
    for e in eyes:
        e.scale = (1, 1, 1)
    P["Root"].location = (0, 0, 0)
    P["Root"].scale = (1, 1, 1)
    for k in ("Head", "Tail"):
        P[k].rotation_euler = (0, 0, 0)
    for e in ears:
        e.rotation_euler = (0, 0, 0)
    body.scale = base_body


# ======================================================================== render + export

def setup_render(scene):
    world = bpy.data.worlds.new("World")
    scene.world = world
    try:
        world.use_nodes = True
    except Exception:
        pass
    bg = world.node_tree.nodes.get("Background")
    if bg:
        bg.inputs["Color"].default_value = (1.0, 0.96, 0.9, 1.0)
        bg.inputs["Strength"].default_value = 0.6
    for name, energy, rot in (("Key", 3.2, (50, 0, -30)), ("Rim", 2.0, (120, 0, 150))):
        d = bpy.data.lights.new(name, "SUN")
        d.energy = energy
        o = bpy.data.objects.new(name, d)
        o.rotation_euler = tuple(math.radians(a) for a in rot)
        scene.collection.objects.link(o)
    for engine in ("BLENDER_EEVEE", "BLENDER_EEVEE_NEXT", "CYCLES"):
        try:
            scene.render.engine = engine
            break
        except Exception:
            continue
    scene.render.film_transparent = True
    scene.render.image_settings.file_format = "PNG"
    scene.render.image_settings.color_mode = "RGBA"
    try:
        scene.view_settings.view_transform = "Standard"
    except Exception:
        pass


def bounds(objs):
    lo = Vector((1e9, 1e9, 1e9))
    hi = Vector((-1e9, -1e9, -1e9))
    bpy.context.view_layer.update()
    for obj in objs:
        for corner in obj.bound_box:
            w = obj.matrix_world @ Vector(corner)
            lo = Vector(map(min, lo, w))
            hi = Vector(map(max, hi, w))
    return lo, hi


def build(cid):
    r = Rig()
    CHARACTERS[cid](r)
    animate(r)
    scene = r.scene
    setup_render(scene)

    # icon: head portrait, framed on the head + ears (whiskers may be cropped)
    for obj, portrait in r.parts:
        obj.hide_render = not portrait
    lo, hi = bounds([o for o, p in r.parts if p and not o.name.startswith("Whisker")])
    cam_data = bpy.data.cameras.new("Cam")
    cam = bpy.data.objects.new("Cam", cam_data)
    scene.collection.objects.link(cam)
    scene.camera = cam
    cam_data.type = "ORTHO"
    cam_data.ortho_scale = max(hi.x - lo.x, hi.z - lo.z) * 1.1
    cam.location = ((lo.x + hi.x) / 2, -6, (lo.z + hi.z) / 2)
    cam.rotation_euler = (math.radians(90), 0, 0)
    scene.render.resolution_x = scene.render.resolution_y = 384
    scene.render.filepath = os.path.join(OUT, f"{cid}_icon.png")
    bpy.ops.render.render(write_still=True)
    print("Rendered", scene.render.filepath)

    for obj, _ in r.parts:
        obj.hide_render = False
    bpy.ops.export_scene.gltf(
        filepath=os.path.join(OUT, f"{cid}.glb"),
        export_format="GLB",
        use_selection=False,
        export_cameras=False,
        export_lights=False,
        export_animations=True,
        export_animation_mode="NLA_TRACKS",
    )
    print("Exported", cid)

    # promo art for the store: full body, 3/4 view, playful head tilt (not used in-game)
    art = os.path.join(ROOT, "store", "art")
    os.makedirs(art, exist_ok=True)
    r.pivots["Head"].rotation_euler = (0.05, 0.14, 0.22)
    r.pivots["Tail"].rotation_euler = (0, 0, 0.35)
    cam_data.type = "PERSP"
    cam_data.lens = 55
    cam.location = (2.6, -5.4, 2.1)
    target = bpy.data.objects.new("Target", None)
    target.location = (0.05, 0, 1.05)
    scene.collection.objects.link(target)
    track = cam.constraints.new("TRACK_TO")
    track.target = target
    track.track_axis = "TRACK_NEGATIVE_Z"
    track.up_axis = "UP_Y"
    scene.render.resolution_x = scene.render.resolution_y = 1024
    scene.render.filepath = os.path.join(art, f"{cid}_full.png")
    bpy.ops.render.render(write_still=True)
    print("Rendered", scene.render.filepath)


ids =sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else list(CHARACTERS)
for cid in ids:
    build(cid)
