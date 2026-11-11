# An example scene for `reel blender` (docs/REELS.md): a cube that turns, 24 frames. A scene file
# builds the scene and sets the frame range. It does not set the engine, the samples, the size or
# the output: `reel blender` does that after this file runs (Cycles, CPU, never EEVEE).
import math

import bpy

bpy.ops.object.select_all(action="SELECT")
bpy.ops.object.delete()

# Linear keys: the cube turns at a constant speed, and frame 25 would equal frame 1 (a loop).
bpy.context.preferences.edit.keyframe_new_interpolation_type = "LINEAR"

bpy.ops.mesh.primitive_cube_add(size=2)
cube = bpy.context.active_object
cube.rotation_euler = (0.4, 0.0, 0.0)
cube.keyframe_insert("rotation_euler", frame=1)
cube.rotation_euler = (0.4, 0.0, math.tau)
cube.keyframe_insert("rotation_euler", frame=25)

bpy.ops.object.light_add(type="SUN", location=(3, -3, 5))
bpy.context.active_object.data.energy = 4

bpy.ops.object.camera_add(location=(0, -12, 2), rotation=(math.radians(80), 0, 0))
bpy.context.scene.camera = bpy.context.active_object

scene = bpy.context.scene
scene.frame_start = 1
scene.frame_end = 24
