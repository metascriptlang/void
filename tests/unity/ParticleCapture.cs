using System;
using System.Collections.Generic;
using System.Globalization;
using System.IO;
using System.Text;
using UnityEditor;
using UnityEngine;

public static class ParticleCapture
{
    const uint Seed = 12345;
    static string outDir;

    class Case
    {
        public string name;
        public float dt;
        public int steps;
        public string settings = "{}";
        public Action<ParticleSystem> configure;
        public Action<ParticleSystem, int> beforeStep;
        public int cap = 64;
        public bool compact;
        public bool remainingOnly;
        public bool stats;
        public bool lastFrameOnly;
        public bool bakeUV;
        public bool bakeQuads;
        public bool bakePose;
    }

    public static void Run()
    {
        var args = Environment.GetCommandLineArgs();
        outDir = null;
        for (int i = 0; i < args.Length - 1; i++)
            if (args[i] == "-goldenDir") outDir = args[i + 1];
        if (outDir == null) throw new Exception("ParticleCapture: pass -goldenDir <dir>");
        Directory.CreateDirectory(outDir);

        var original = PlayerSettings.colorSpace;
        PlayerSettings.colorSpace = ColorSpace.Gamma;
        int failed = 0;
        string only = null;
        for (int i = 0; i < args.Length - 1; i++)
            if (args[i] == "-only") only = args[i + 1];
        foreach (var c in Cases())
            if (only == null || c.name.Contains(only)) failed += RunCase(c);
        foreach (var c in Cases3D())
            if (only == null || c.name.Contains(only)) failed += RunCase(c);
        if (only != null) { Debug.Log("ParticleCapture: done, failed cases = " + failed); if (failed > 0) EditorApplication.Exit(1); return; }
        PlayerSettings.colorSpace = ColorSpace.Linear;
        failed += RunCase(ColorCase("color_over_lifetime_linear"));
        failed += RunCase(SubEmitterCase("subemitter_death_linear", ParticleSystemSubEmitterType.Death));
        PlayerSettings.colorSpace = original;
        Debug.Log("ParticleCapture: done, failed cases = " + failed);
        if (failed > 0) EditorApplication.Exit(1);
    }

    // ---------- cases ----------

    static IEnumerable<Case> Cases()
    {
        foreach (var tc in TieCases()) yield return tc;
                yield return new Case {
            name = "emission_rate10_dt60", dt = 1f / 60f, steps = 60,
            settings = S("rateOverTime", 10, "startSpeed", 1, "startLifetime", 5, "shape", "disabled"),
            configure = ps => Base(ps, 10, 1, 5) };

        yield return new Case {
            name = "emission_rate7_dt100ms", dt = 0.1f, steps = 20,
            settings = S("rateOverTime", 7, "startSpeed", 1, "startLifetime", 10, "shape", "disabled"),
            configure = ps => Base(ps, 7, 1, 10) };

        yield return new Case {
            name = "burst_loop_t0", dt = 0.3f, steps = 10,
            settings = S("duration", 1, "loop", true, "burst", "time 0 count 5", "rateOverTime", 0, "startSpeed", 1, "startLifetime", 10),
            configure = ps => { Base(ps, 0, 1, 10); var m = ps.main; m.duration = 1; m.loop = true;
                ps.emission.SetBursts(new[] { new ParticleSystem.Burst(0f, 5) }); } };

        yield return new Case {
            name = "burst_cycles", dt = 0.05f, steps = 40,
            settings = S("duration", 2, "loop", false, "burst", "time 0.1 count 2 cycleCount 3 repeatInterval 0.2", "startSpeed", 1, "startLifetime", 10),
            configure = ps => { Base(ps, 0, 1, 10); var m = ps.main; m.duration = 2; m.loop = false;
                var b = new ParticleSystem.Burst(0.1f, 2); b.cycleCount = 3; b.repeatInterval = 0.2f;
                ps.emission.SetBursts(new[] { b }); } };

        foreach (var hz in new[] { 30, 144 })
        {
            yield return new Case {
                name = "burst_probability_dt" + hz, dt = 1f / hz, steps = 5 * hz, lastFrameOnly = true,
                settings = S("duration", 5, "loop", false, "burst", "time 0 count 1 cycleCount 0 repeatInterval 0.1 probability 0.5", "startSpeed", 1, "startLifetime", 10),
                configure = ps => { Base(ps, 0, 1, 10); var m = ps.main; m.duration = 5; m.loop = false;
                    var b = new ParticleSystem.Burst(0f, 1); b.cycleCount = 0; b.repeatInterval = 0.1f; b.probability = 0.5f;
                    ps.emission.SetBursts(new[] { b }); } };
        }

        yield return ShapeBurst("shape_cone_r0_a30_base", "Cone radius 0.0001 angle 30", ps => {
            var sh = ps.shape; sh.shapeType = ParticleSystemShapeType.Cone; sh.radius = 0.0001f; sh.angle = 30; });
        yield return ShapeBurst("shape_cone_r1_a30_base", "Cone radius 1 angle 30", ps => {
            var sh = ps.shape; sh.shapeType = ParticleSystemShapeType.Cone; sh.radius = 1; sh.angle = 30; });
        yield return ShapeBurst("shape_cone_r1_a30_volume", "ConeVolume radius 1 angle 30 length 5", ps => {
            var sh = ps.shape; sh.shapeType = ParticleSystemShapeType.ConeVolume; sh.radius = 1; sh.angle = 30; sh.length = 5; });
        yield return ShapeBurst("shape_sphere_thickness05", "Sphere radius 1 radiusThickness 0.5", ps => {
            var sh = ps.shape; sh.shapeType = ParticleSystemShapeType.Sphere; sh.radius = 1; sh.radiusThickness = 0.5f; });

        foreach (var arc in new[] { 180, 360 })
        {
            int a = arc;
            yield return new Case {
                name = "shape_circle_arc" + a + "_burstspread4", dt = 0.0001f, steps = 1, cap = 4,
                settings = S("shape", "Circle radius 1 arc " + a + " arcMode BurstSpread", "burst", "time 0 count 4", "startSpeed", 1),
                configure = ps => { Base(ps, 0, 1, 5);
                    var sh = ps.shape; sh.enabled = true; sh.shapeType = ParticleSystemShapeType.Circle; sh.radius = 1; sh.radiusThickness = 0;
                    sh.arc = a; sh.arcMode = ParticleSystemShapeMultiModeValue.BurstSpread;
                    ps.emission.SetBursts(new[] { new ParticleSystem.Burst(0f, 4) }); } };
        }

        yield return new Case {
            name = "shape_circle_loop_speed1", dt = 0.1f, steps = 20,
            settings = S("shape", "Circle radius 1 radiusThickness 0 arc 360 arcMode Loop arcSpeed 1", "rateOverTime", 10, "startSpeed", 1, "startLifetime", 10),
            configure = ps => { Base(ps, 10, 1, 10);
                var sh = ps.shape; sh.enabled = true; sh.shapeType = ParticleSystemShapeType.Circle; sh.radius = 1; sh.radiusThickness = 0;
                sh.arc = 360; sh.arcMode = ParticleSystemShapeMultiModeValue.Loop; sh.arcSpeed = 1; } };

        foreach (var v in new[] { ("vol_speedmod05_gravity", 0.5f, 2f, 1f, 0f), ("vol_speedmod1_gravity", 1f, 2f, 1f, 0f), ("vol_speedmod05_linearx1", 0.5f, 0f, 0f, 1f) })
        {
            var (n, mod, speed, grav, lx) = v;
            yield return new Case {
                name = n, dt = 1f / 60f, steps = 60,
                settings = S("startSpeed", speed, "gravityModifier", grav, "velocityOverLifetime", "x " + lx + " y 0 z 0 speedModifier " + mod, "burst", "time 0 count 1", "shape", "disabled (direction +z)"),
                configure = ps => { Base(ps, 0, speed, 5); var m = ps.main; m.gravityModifier = grav; Burst1(ps);
                    var vol = ps.velocityOverLifetime; vol.enabled = true;
                    vol.x = lx; vol.y = 0; vol.z = 0; vol.speedModifier = mod; } };
        }

        yield return new Case {
            name = "vol_orbitalz_2pi", dt = 1f / 60f, steps = 60,
            settings = S("velocityOverLifetime", "orbitalZ 6.2831853 (2pi) orbitalOffset 0 radial 0", "spawn", "(1,0,0) via Box shape scale 1e-6 at position (1,0,0)", "startSpeed", 0, "space", "Local"),
            configure = ps => { Base(ps, 0, 0, 5); Burst1(ps);
                var sh = ps.shape; sh.enabled = true; sh.shapeType = ParticleSystemShapeType.Box; sh.scale = Vector3.one * 1e-6f; sh.position = new Vector3(1, 0, 0);
                var vol = ps.velocityOverLifetime; vol.enabled = true;
                vol.orbitalX = 0; vol.orbitalY = 0; vol.orbitalZ = 2f * Mathf.PI; vol.orbitalOffsetX = 0; vol.orbitalOffsetY = 0; vol.orbitalOffsetZ = 0; vol.radial = 0; } };

        foreach (var hz in new[] { 60, 30 })
            yield return new Case {
                name = "limit_velocity_dampen05_dt" + hz, dt = 1f / hz, steps = hz / 2,
                settings = S("startSpeed", 10, "limit", 5, "dampen", 0.5, "drag", 0),
                configure = ps => { Base(ps, 0, 10, 5); Burst1(ps);
                    var lv = ps.limitVelocityOverLifetime; lv.enabled = true; lv.limit = 5; lv.dampen = 0.5f; lv.drag = 0; } };

        foreach (var bySize in new[] { false, true })
            foreach (var byVel in new[] { false, true })
            {
                bool bs = bySize, bv = byVel;
                yield return new Case {
                    name = "drag1_size2_speed10" + (bs ? "_bySize" : "") + (bv ? "_byVelocity" : ""), dt = 1f / 60f, steps = 60,
                    settings = S("startSpeed", 10, "startSize", 2, "drag", 1, "multiplyDragByParticleSize", bs, "multiplyDragByParticleVelocity", bv, "limit", 100000),
                    configure = ps => { Base(ps, 0, 10, 5); var m = ps.main; m.startSize = 2; Burst1(ps);
                        var lv = ps.limitVelocityOverLifetime; lv.enabled = true; lv.limit = 100000; lv.dampen = 0; lv.drag = 1;
                        lv.multiplyDragByParticleSize = bs; lv.multiplyDragByParticleVelocity = bv; } };
            }

        foreach (var rnd in new[] { true, false })
        {
            bool r = rnd;
            yield return new Case {
                name = "force_twoconstants_" + (r ? "randomized" : "fixed"), dt = 1f / 60f, steps = 30, cap = 4,
                settings = S("forceOverLifetime", "x TwoConstants(-1,1) y 0 z 0", "randomized", r, "burst", "time 0 count 4", "startSpeed", 0),
                configure = ps => { Base(ps, 0, 0, 5); ps.emission.SetBursts(new[] { new ParticleSystem.Burst(0f, 4) });
                    var f = ps.forceOverLifetime; f.enabled = true;
                    f.x = new ParticleSystem.MinMaxCurve(-1, 1); f.y = new ParticleSystem.MinMaxCurve(0, 0); f.z = new ParticleSystem.MinMaxCurve(0, 0);
                    f.randomized = r; } };
        }

        yield return new Case {
            name = "gravity_modifier_curve", dt = 0.05f, steps = 30,
            settings = S("gravityModifier", "curve linear (0,0)->(1,1) multiplier 1", "duration", 2, "loop", false, "bursts", "count 1 at t=0 and count 1 at t=0.5", "startSpeed", 0, "gravity", "Physics.gravity"),
            configure = ps => { Base(ps, 0, 0, 5); var m = ps.main; m.duration = 2; m.loop = false;
                m.gravityModifier = new ParticleSystem.MinMaxCurve(1f, AnimationCurve.Linear(0, 0, 1, 1));
                ps.emission.SetBursts(new[] { new ParticleSystem.Burst(0f, 1), new ParticleSystem.Burst(0.5f, 1) }); } };

        yield return CollisionCase("collision_plane_bounce05_dampen025_loss02", 0.5f, 0.25f, 0.2f, 0f);
        yield return CollisionCase("collision_plane_minkill3", 0.5f, 0f, 0f, 3f);

        yield return SubEmitterCase("subemitter_birth", ParticleSystemSubEmitterType.Birth);
        yield return SubEmitterCase("subemitter_death", ParticleSystemSubEmitterType.Death);

        yield return new Case {
            name = "size_over_lifetime_linear", dt = 0.1f, steps = 12,
            settings = S("startSize", 2, "startLifetime", 1, "sizeOverLifetime", "curve linear (0,0)->(1,1) multiplier 1"),
            configure = ps => { Base(ps, 0, 0, 1); var m = ps.main; m.startSize = 2; Burst1(ps);
                var so = ps.sizeOverLifetime; so.enabled = true; so.size = new ParticleSystem.MinMaxCurve(1f, AnimationCurve.Linear(0, 0, 1, 1)); } };

        yield return new Case {
            name = "rotation_over_lifetime_90dps", dt = 0.1f, steps = 20,
            settings = S("rotationOverLifetime", "z constant 90 deg/s (set as radians)", "startRotation", 0),
            configure = ps => { Base(ps, 0, 0, 5); Burst1(ps);
                var ro = ps.rotationOverLifetime; ro.enabled = true; ro.z = 90f * Mathf.Deg2Rad; } };

        yield return ColorCase("color_over_lifetime_gamma");

        yield return new Case {
            name = "texture_sheet_4x4_wholesheet", dt = 1f / 16f, steps = 17, bakeUV = true,
            settings = S("textureSheetAnimation", "4x4 WholeSheet frameOverTime default", "startLifetime", 1, "read", "BakeMesh(camera at (0,0,-10) facing +z) uv0 min corner per quad"),
            configure = ps => { Base(ps, 0, 0, 1); Burst1(ps);
                var ts = ps.textureSheetAnimation; ts.enabled = true; ts.numTilesX = 4; ts.numTilesY = 4;
                ts.animation = ParticleSystemAnimationType.WholeSheet;
                var cam = new GameObject("camera").AddComponent<Camera>(); cam.transform.SetParent(ps.transform, false);
                cam.transform.position = new Vector3(0, 0, -10); } };

        foreach (var ls in new[] { 1f, 2f })
            foreach (var vs in new[] { 0f, 0.5f })
            {
                float lsc = ls, vsc = vs;
                yield return StretchCase("stretch_ls" + lsc + "_vs" + (vsc == 0f ? "0" : "05"), lsc, vsc, 1f, 0f, false, (3f, 4f));
            }
        yield return StretchCase("stretch_size2_rot45_total", 1f, 0.5f, 2f, 45f, false, (3f, 0f), forceY: 4f);
        yield return StretchCase("stretch_still", 1f, 0.5f, 1f, 0f, false, (0f, 0f));
        yield return StretchCase("stretch_size3d_1x3", 1f, 0.5f, 1f, 0f, false, (3f, 4f), size3D: (1f, 3f));
        yield return StretchCase("stretch_pivot", 1f, 0f, 1f, 0f, false, (3f, 4f), pivot: (0.5f, 0.25f));
        yield return StretchCase("stretch_pivotx05_ls2", 2f, 0f, 1f, 0f, false, (3f, 4f), pivot: (0.5f, 0f));
        yield return StretchCase("stretch_pivoty05_ls2", 2f, 0f, 1f, 0f, false, (3f, 4f), pivot: (0f, 0.5f));
        yield return StretchCase("stretch_size3d_2x3_vs05_pivot", 1f, 0.5f, 1f, 0f, false, (3f, 4f), size3D: (2f, 3f), pivot: (0.5f, 0.5f));
        yield return StretchCase("billboard_pivot_rot0", 1f, 0f, 2f, 0f, false, (3f, 4f), billboard: true, pivot: (0.5f, 0.25f));
        yield return StretchCase("billboard_pivot_rot45", 1f, 0f, 2f, 45f, false, (3f, 4f), billboard: true, pivot: (0.5f, 0.25f));
        yield return StretchCase("billboard_size3d_1x3_rot45", 1f, 0f, 1f, 45f, false, (3f, 4f), billboard: true, size3D: (1f, 3f));
        yield return StretchCase("billboard_velocity_rot0", 1f, 0f, 1f, 0f, true, (3f, 4f));
        yield return StretchCase("billboard_velocity_rot45", 1f, 0f, 1f, 45f, true, (3f, 4f));
        yield return StretchCase("billboard_view_rot45", 1f, 0f, 1f, 45f, false, (3f, 4f), billboard: true);

        foreach (var freeform in new[] { false, true })
            foreach (var rotateWith in new[] { false, true })
            {
                bool ff = freeform, rw = rotateWith;
                yield return RenderCase("stretch_freeform" + (ff ? "1" : "0") + "_rotwith" + (rw ? "1" : "0"),
                    StretchCase("", 1f, 5f, 1f, 45f, false, (0.3f, 0.4f), size3D: (1f, 2f)),
                    S("freeformStretching", ff, "rotateWithStretchDirection", rw),
                    (ps, r) => { r.freeformStretching = ff; r.rotateWithStretchDirection = rw; });
            }
        foreach (var rotateWith in new[] { false, true })
        {
            bool rw = rotateWith;
            yield return RenderCase("stretch_freeform1_rotwith" + (rw ? "1" : "0") + "_size2x1_ls2_rot0",
                StretchCase("", 2f, 5f, 1f, 0f, false, (0.3f, 0.4f), size3D: (2f, 1f)),
                S("freeformStretching", true, "rotateWithStretchDirection", rw),
                (ps, r) => { r.freeformStretching = true; r.rotateWithStretchDirection = rw; });
        }
        foreach (var rotateWith in new[] { false, true })
        {
            bool rw = rotateWith;
            yield return RenderCase("stretch_freeform1_rotwith" + (rw ? "1" : "0") + "_pivot",
                StretchCase("", 1f, 5f, 1f, 45f, false, (0.3f, 0.4f), size3D: (1f, 2f), pivot: (0.5f, 0.25f)),
                S("freeformStretching", true, "rotateWithStretchDirection", rw),
                (ps, r) => { r.freeformStretching = true; r.rotateWithStretchDirection = rw; });
        }
        yield return RenderCase("billboard_view_rot45_noroll", StretchCase("", 1f, 0f, 1f, 45f, false, (3f, 4f), billboard: true),
            S("allowRoll", false), (ps, r) => r.allowRoll = false);
        yield return RenderCase("billboard_view_size1x3_rot45_noroll", StretchCase("", 1f, 0f, 1f, 45f, false, (3f, 4f), billboard: true, size3D: (1f, 3f)),
            S("allowRoll", false), (ps, r) => r.allowRoll = false);

        foreach (var align in new[] { ParticleSystemRenderSpace.View, ParticleSystemRenderSpace.Local, ParticleSystemRenderSpace.World })
            foreach (var worldSpace in new[] { false, true })
            {
                var al = align; bool ws = worldSpace;
                yield return RenderCase("billboard_moved_" + al.ToString().ToLowerInvariant() + "_" + (ws ? "world" : "local"),
                    StretchCase("", 1f, 0f, 1f, 20f, false, (3f, 4f), billboard: true, size3D: (1f, 3f)),
                    S("emitter", "position (2, 1, 0), rotation z 30 degrees", "simulationSpace", ws ? "World" : "Local", "alignment", al.ToString()),
                    (ps, r) => {
                        var m = ps.main; m.simulationSpace = ws ? ParticleSystemSimulationSpace.World : ParticleSystemSimulationSpace.Local;
                        r.alignment = al;
                        ps.transform.SetPositionAndRotation(new Vector3(2f, 1f, 0f), Quaternion.Euler(0f, 0f, 30f)); });
            }

        // Orthographic size 10 at aspect 2 unless the case says otherwise: the viewport is 20 high and 40 wide.
        foreach (var (tag, size, max, min, s3, aspect, ortho) in new (string, float, float, float, (float, float), float, float)[] {
            ("max_big", 5f, 0.1f, 0f, (5f, 5f), 2f, 10f), ("max_wide", 1f, 0.1f, 0f, (8f, 3f), 2f, 10f), ("max_tall", 1f, 0.1f, 0f, (3f, 8f), 2f, 10f),
            ("min_small", 0.2f, 0.5f, 0.1f, (0.2f, 0.2f), 2f, 10f), ("min_thin", 1f, 0.5f, 0.1f, (0.2f, 6f), 2f, 10f), ("inside", 1f, 0.5f, 0.05f, (1f, 1f), 2f, 10f),
            ("max_big_aspect1", 5f, 0.1f, 0f, (5f, 5f), 1f, 10f), ("max_big_aspect05", 5f, 0.1f, 0f, (5f, 5f), 0.5f, 10f),
            ("max_big_ortho5", 5f, 0.1f, 0f, (5f, 5f), 2f, 5f), ("min_small_aspect05", 0.2f, 0.5f, 0.1f, (0.2f, 0.2f), 0.5f, 10f) })
        {
            float mx = max, mn = min, asp = aspect, orth = ortho;
            yield return RenderCase("billboard_clamp_" + tag, StretchCase("", 1f, 0f, size, 0f, false, (3f, 4f), billboard: true, size3D: s3),
                S("minParticleSize", mn, "maxParticleSize", mx, "cameraAspect", asp, "orthographicSize", orth),
                (ps, r) => { r.minParticleSize = mn; r.maxParticleSize = mx; var cam = ps.GetComponentInChildren<Camera>(); cam.aspect = asp; cam.orthographicSize = orth; });
        }
        foreach (var (tag, s3, min, max) in new (string, (float, float), float, float)[] {
            ("stretch_clamp_max", (1f, 2f), 0f, 0.1f), ("stretch_clamp_max_big", (2f, 5f), 0f, 0.1f),
            ("stretch_clamp_max_wide", (5f, 2f), 0f, 0.1f), ("stretch_clamp_min", (0.2f, 0.2f), 0.1f, 0.5f) })
        {
            float mn = min, mx = max;
            yield return RenderCase(tag, StretchCase("", 1f, 0.5f, 1f, 0f, false, (3f, 4f), size3D: s3),
                S("minParticleSize", mn, "maxParticleSize", mx, "cameraAspect", 2f, "orthographicSize", 10f),
                (ps, r) => { r.minParticleSize = mn; r.maxParticleSize = mx; var cam = ps.GetComponentInChildren<Camera>(); cam.aspect = 2f; });
        }

        // The size limits on a freeform stretch: the base quad is 1 x 2, stretched to about 2.25 times its length.
        foreach (var (tag, min, max) in new (string, float, float)[] {
            ("max_base", 0f, 0.04f), ("max_stretched", 0f, 0.1f), ("min_big", 0.1f, 0.5f), ("inside", 0.01f, 0.5f) })
            foreach (var rotateWith in new[] { false, true })
            {
                float mn = min, mx = max; bool rw = rotateWith;
                yield return RenderCase("stretch_freeform1_rotwith" + (rw ? "1" : "0") + "_clamp_" + tag,
                    StretchCase("", 1f, 5f, 1f, 45f, false, (0.3f, 0.4f), size3D: (1f, 2f)),
                    S("freeformStretching", true, "rotateWithStretchDirection", rw, "minParticleSize", mn, "maxParticleSize", mx, "cameraAspect", 2f, "orthographicSize", 10f),
                    (ps, r) => { r.freeformStretching = true; r.rotateWithStretchDirection = rw; r.minParticleSize = mn; r.maxParticleSize = mx;
                        ps.GetComponentInChildren<Camera>().aspect = 2f; });
            }

        foreach (var rotateWith in new[] { false, true })
        {
            bool rw = rotateWith;
            yield return RenderCase("stretch_freeform1_rotwith" + (rw ? "1" : "0") + "_pivot_clamp_max_base",
                StretchCase("", 1f, 5f, 1f, 45f, false, (0.3f, 0.4f), size3D: (1f, 2f), pivot: (0.5f, 0.25f)),
                S("freeformStretching", true, "rotateWithStretchDirection", rw, "minParticleSize", 0f, "maxParticleSize", 0.04f, "cameraAspect", 2f, "orthographicSize", 10f),
                (ps, r) => { r.freeformStretching = true; r.rotateWithStretchDirection = rw; r.maxParticleSize = 0.04f;
                    ps.GetComponentInChildren<Camera>().aspect = 2f; });
        }

        // The size limits under the moved, turned emitter of billboard_moved_*: a quad above the maximum, one below the minimum.
        foreach (var align in new[] { ParticleSystemRenderSpace.View, ParticleSystemRenderSpace.Local, ParticleSystemRenderSpace.World })
            foreach (var worldSpace in new[] { false, true })
                foreach (var (tag, size, min, max) in new (string, float, float, float)[] { ("max", 5f, 0f, 0.1f), ("min", 0.2f, 0.1f, 0.5f) })
                {
                    var al = align; bool ws = worldSpace; float sz = size, mn = min, mx = max;
                    yield return RenderCase("billboard_moved_" + al.ToString().ToLowerInvariant() + "_" + (ws ? "world" : "local") + "_clamp_" + tag,
                        StretchCase("", 1f, 0f, sz, 20f, false, (3f, 4f), billboard: true, size3D: (sz, sz * 3f / 1f)),
                        S("emitter", "position (2, 1, 0), rotation z 30 degrees", "simulationSpace", ws ? "World" : "Local", "alignment", al.ToString(),
                          "minParticleSize", mn, "maxParticleSize", mx, "cameraAspect", 2f, "orthographicSize", 10f),
                        (ps, r) => {
                            var m = ps.main; m.simulationSpace = ws ? ParticleSystemSimulationSpace.World : ParticleSystemSimulationSpace.Local;
                            r.alignment = al; r.minParticleSize = mn; r.maxParticleSize = mx;
                            ps.GetComponentInChildren<Camera>().aspect = 2f;
                            ps.transform.SetPositionAndRotation(new Vector3(2f, 1f, 0f), Quaternion.Euler(0f, 0f, 30f)); });
                }

        foreach (var damp in new[] { true, false })
        {
            bool dmp = damp;
            yield return new Case {
                name = "noise_strength1_freq05_" + (dmp ? "damped" : "undamped"), dt = 1f / 60f, steps = 120, stats = true, cap = 4,
                settings = S("noise", "strength 1 frequency 0.5 damping " + dmp + " scrollSpeed 0 octaves 1", "burst", "time 0 count 64", "shape", "Sphere radius 5", "startSpeed", 0),
                configure = ps => { Base(ps, 0, 0, 5); ps.emission.SetBursts(new[] { new ParticleSystem.Burst(0f, 64) });
                    var sh = ps.shape; sh.enabled = true; sh.shapeType = ParticleSystemShapeType.Sphere; sh.radius = 5;
                    var n = ps.noise; n.enabled = true; n.strength = 1; n.frequency = 0.5f; n.damping = dmp; n.scrollSpeed = 0; } };
        }

        yield return new Case {
            name = "inherit_velocity_initial_transform", dt = 1f / 60f, steps = 60,
            settings = S("space", "World", "emitterVelocityMode", "Transform", "inheritVelocity", "Initial 1", "emitter", "moved +x 5 u/s before each step", "rateOverTime", 10, "startSpeed", 0),
            configure = ps => { Base(ps, 10, 0, 5); var m = ps.main; m.simulationSpace = ParticleSystemSimulationSpace.World;
                m.emitterVelocityMode = ParticleSystemEmitterVelocityMode.Transform;
                var iv = ps.inheritVelocity; iv.enabled = true; iv.mode = ParticleSystemInheritVelocityMode.Initial; iv.curve = 1; },
            beforeStep = (ps, s) => ps.transform.position = new Vector3(5f * s / 60f, 0, 0) };

        yield return new Case {
            name = "inherit_velocity_initial_custom", dt = 1f / 60f, steps = 60,
            settings = S("space", "World", "emitterVelocityMode", "Custom (5,0,0), emitter static", "inheritVelocity", "Initial 1", "rateOverTime", 10, "startSpeed", 0),
            configure = ps => { Base(ps, 10, 0, 5); var m = ps.main; m.simulationSpace = ParticleSystemSimulationSpace.World;
                m.emitterVelocityMode = ParticleSystemEmitterVelocityMode.Custom; m.emitterVelocity = new Vector3(5, 0, 0);
                var iv = ps.inheritVelocity; iv.enabled = true; iv.mode = ParticleSystemInheritVelocityMode.Initial; iv.curve = 1; } };

        yield return new Case {
            name = "prewarm_rate10_life1", dt = 1f / 60f, steps = 30,
            settings = S("duration", 1, "loop", true, "prewarm", true, "rateOverTime", 10, "startLifetime", 1, "startSpeed", 1),
            configure = ps => { Base(ps, 10, 1, 1); var m = ps.main; m.duration = 1; m.loop = true; m.prewarm = true; } };

        yield return new Case {
            name = "ring_pause_until_replaced_max4", dt = 0.05f, steps = 30,
            settings = S("maxParticles", 4, "ringBufferMode", "PauseUntilReplaced", "rateOverTime", 10, "startLifetime", 0.1, "startSpeed", 1),
            configure = ps => { Base(ps, 10, 1, 0.1f); var m = ps.main; m.maxParticles = 4; m.ringBufferMode = ParticleSystemRingBufferMode.PauseUntilReplaced; } };

        foreach (var ev in new[] { "enter", "inside", "exit", "outside" })
            yield return TriggerCase(ev);
    }


    static readonly (string, float)[] TieSteps = {
        ("60", 1f / 60f), ("40", 0.025f), ("20", 0.05f), ("10", 0.1f), ("120", 1f / 120f), ("144", 1f / 144f), ("100", 0.01f) };

    // Exact float boundaries of the emission clock: each case lists every particle's remaining lifetime at every frame,
    // so the step a spawn, a burst or a death lands in is read from the counts.
    static IEnumerable<Case> TieCases()
    {
        foreach (var (rate, label, dt) in new (float, string, float)[] {
            (10f, "60", 1f / 60f), (10f, "40", 0.025f), (10f, "10", 0.1f), (10f, "120", 1f / 120f), (25f, "50", 0.02f), (50f, "25", 0.04f), (13f, "144", 1f / 144f) })
        {
            float r = rate, d = dt;
            yield return new Case {
                name = "tie_emission_r" + r + "_hz" + label, dt = d, steps = (int)(1.5f / d), cap = 200, remainingOnly = true,
                settings = S("rateOverTime", r, "startLifetime", 2, "startSpeed", 0, "shape", "disabled"),
                configure = ps => Base(ps, r, 0, 2) };
        }
        foreach (var (label, dt) in TieSteps)
            foreach (var at in new[] { 0.1f, 0.3f })
            {
                float d = dt, t = at;
                yield return new Case {
                    name = "tie_burst_t" + (int)Math.Round(t * 1000) + "_hz" + label, dt = d, steps = (int)((t + 0.3f) / d), cap = 200, remainingOnly = true,
                    settings = S("burst", "time " + t + " count 1", "rateOverTime", 0, "startLifetime", 2, "startSpeed", 0),
                    configure = ps => { Base(ps, 0, 0, 2); ps.emission.SetBursts(new[] { new ParticleSystem.Burst(t, 1) }); } };
            }
        // A burst that falls inside a sub-step, first and repeated.
        foreach (var (label, dt) in new (string, float)[] { ("10", 0.1f), ("20", 0.05f), ("60", 1f / 60f) })
        {
            float d = dt;
            yield return new Case {
                name = "tie_burst_inside_hz" + label, dt = d, steps = (int)(0.6f / d), cap = 200, remainingOnly = true,
                settings = S("burst", "time 0.113 count 1", "rateOverTime", 0, "startLifetime", 2, "startSpeed", 0),
                configure = ps => { Base(ps, 0, 0, 2); ps.emission.SetBursts(new[] { new ParticleSystem.Burst(0.113f, 1) }); } };
            yield return new Case {
                name = "tie_burst_repeat_hz" + label, dt = d, steps = (int)(0.6f / d), cap = 200, remainingOnly = true,
                settings = S("burst", "time 0.113 count 1 cycleCount 4 repeatInterval 0.0733", "duration", 5, "rateOverTime", 0, "startLifetime", 2, "startSpeed", 0),
                configure = ps => { Base(ps, 0, 0, 2); ps.emission.SetBursts(new[] { new ParticleSystem.Burst(0.113f, 1, 1, 4, 0.0733f) }); } };
        }
        foreach (var life in new[] { 0.1f, 0.3f, 1f })
            foreach (var (label, dt) in TieSteps)
            {
                float l = life, d = dt;
                yield return new Case {
                    name = "tie_death_life" + (int)Math.Round(l * 1000) + "_hz" + label, dt = d, steps = (int)((l + 0.15f) / d), cap = 200, remainingOnly = true,
                    settings = S("burst", "time 0 count 1", "rateOverTime", 0, "startLifetime", l, "startSpeed", 0),
                    configure = ps => { Base(ps, 0, 0, l); Burst1(ps); } };
            }
        // World-space spawns: where a particle born inside a step starts, with the emitter moving, and with inherited velocity.
        foreach (var (label, dt) in new (string, float)[] { ("60", 1f / 60f), ("10", 0.1f) })
        {
            float d = dt;
            yield return new Case {
                name = "tie_world_moved_hz" + label, dt = d, steps = (int)(0.5f / d), cap = 200,
                settings = S("space", "World", "emitter", "moved +x 5 u/s before each step", "rateOverTime", 10, "startLifetime", 2, "startSpeed", 0),
                configure = ps => { Base(ps, 10, 0, 2); var m = ps.main; m.simulationSpace = ParticleSystemSimulationSpace.World; },
                beforeStep = (ps, s) => ps.transform.position = new Vector3(5f * s * d, 0, 0) };
        }
        foreach (var (tag, inherit, speed) in new (string, float, float)[] { ("speed1", 1f, 1f), ("half", 0.5f, 0f) })
        {
            float inh = inherit, spd = speed;
            yield return new Case {
                name = "tie_world_custom_" + tag + "_hz60", dt = 1f / 60f, steps = 24, cap = 200,
                settings = S("space", "World", "emitterVelocityMode", "Custom (5,0,0), emitter static", "inheritVelocity", "Initial " + inh, "rateOverTime", 10, "startLifetime", 2, "startSpeed", spd),
                configure = ps => { Base(ps, 10, spd, 2); var m = ps.main; m.simulationSpace = ParticleSystemSimulationSpace.World;
                    m.emitterVelocityMode = ParticleSystemEmitterVelocityMode.Custom; m.emitterVelocity = new Vector3(5, 0, 0);
                    var iv = ps.inheritVelocity; iv.enabled = true; iv.mode = ParticleSystemInheritVelocityMode.Initial; iv.curve = inh; } };
        }
        // A looping system whose cycle ends exactly on a step: duration 1, steps of 1/16 or 1/60, a burst at 0 and a rate.
        foreach (var (label, dt) in new (string, float)[] { ("16", 0.0625f), ("60", 1f / 60f), ("40", 0.025f), ("10", 0.1f) })
        {
            float d = dt;
            yield return new Case {
                name = "tie_wrap_hz" + label, dt = d, steps = (int)(2.6f / d), cap = 200, remainingOnly = true,
                settings = S("duration", 1, "loop", true, "burst", "time 0 count 1", "rateOverTime", 10, "startLifetime", 5, "startSpeed", 0),
                configure = ps => { Base(ps, 10, 0, 5); var m = ps.main; m.duration = 1; ps.emission.SetBursts(new[] { new ParticleSystem.Burst(0f, 1) }); } };
        }
    }

    // ---------- 3D render modes ----------
    // One World-space particle drifting with a world velocity, seen by a perspective or orthographic camera
    // that is placed, turned and rolled, from a moved and turned emitter. BakeMesh returns world corners.

    struct Pose
    {
        public Vector3 camPos, camEuler, emPos, emEuler;
        public bool ortho; public float fov, aspect, orthoSize;
        public static Pose Persp(float camZ = -8f) => new Pose { camPos = new Vector3(1.5f, 2f, camZ), camEuler = new Vector3(10f, -15f, 12f),
            fov = 50f, aspect = 1.5f, orthoSize = 6f, emPos = new Vector3(2f, 1f, 1f), emEuler = new Vector3(20f, 30f, 40f) };
        public Pose Orthographic() { var p = this; p.ortho = true; return p; }
        // A second placement with a different yaw, pitch, roll and emitter turn, so a rule that fits one pose is checked on another.
        public static Pose Persp2() => new Pose { camPos = new Vector3(-3f, 1f, -6f), camEuler = new Vector3(-25f, 40f, -8f),
            fov = 40f, aspect = 1.5f, orthoSize = 6f, emPos = new Vector3(-1f, 2f, 0f), emEuler = new Vector3(-30f, -50f, 15f) };
    }

    struct Mode3D
    {
        public ParticleSystemRenderMode mode;
        public ParticleSystemRenderSpace align;
        public Vector3 pivot;
        public float lengthScale, velocityScale, cameraVelocityScale;
        public bool freeform, rotateWith, allowRoll;
        public float min, max;
        public Vector3 velocity;
        public (float, float) size;
        public float rotDeg, sizeZ;
    }

    static Mode3D M(ParticleSystemRenderMode mode, ParticleSystemRenderSpace align = ParticleSystemRenderSpace.View) => new Mode3D {
        mode = mode, align = align, lengthScale = 1.5f, velocityScale = 0.4f, allowRoll = true, max = 0.5f,
        velocity = new Vector3(1.5f, 0.5f, 1f), size = (1f, 2f), rotDeg = 25f };

    static Case Render3D(string name, Mode3D m, Pose pose, Action<ParticleSystem, int> moveCamera = null) => new Case {
        name = name, dt = 0.1f, steps = 3, bakeQuads = true, bakePose = true, cap = 4, beforeStep = moveCamera,
        settings = S("renderMode", m.mode.ToString(), "alignment", m.align.ToString(),
            "lengthScale", m.lengthScale, "velocityScale", m.velocityScale, "cameraVelocityScale", m.cameraVelocityScale,
            "freeformStretching", m.freeform, "rotateWithStretchDirection", m.rotateWith, "allowRoll", m.allowRoll,
            "pivot", V(m.pivot), "minParticleSize", m.min, "maxParticleSize", m.max,
            "velocity", V(m.velocity), "startSize3D", "(" + m.size.Item1 + ", " + m.size.Item2 + ", " + (m.sizeZ == 0f ? 1f : m.sizeZ) + ")", "startRotationDeg", m.rotDeg,
            "simulationSpace", "World", "read", "BakeMesh world corners; pose = camera and emitter transforms per frame"),
        configure = ps => {
            Base(ps, 0, 0, 5); Burst1(ps);
            var main = ps.main; main.simulationSpace = ParticleSystemSimulationSpace.World;
            main.startSize3D = true; main.startSizeX = m.size.Item1; main.startSizeY = m.size.Item2; main.startSizeZ = m.sizeZ == 0f ? 1f : m.sizeZ;
            main.startRotation = m.rotDeg * Mathf.Deg2Rad;
            var vo = ps.velocityOverLifetime; vo.enabled = true; vo.space = ParticleSystemSimulationSpace.World;
            vo.x = m.velocity.x; vo.y = m.velocity.y; vo.z = m.velocity.z;
            var r = ps.GetComponent<ParticleSystemRenderer>();
            r.renderMode = m.mode; r.alignment = m.align; r.pivot = m.pivot;
            r.lengthScale = m.lengthScale; r.velocityScale = m.velocityScale; r.cameraVelocityScale = m.cameraVelocityScale;
            r.freeformStretching = m.freeform; r.rotateWithStretchDirection = m.rotateWith; r.allowRoll = m.allowRoll;
            r.minParticleSize = m.min; r.maxParticleSize = m.max;
            ps.transform.SetPositionAndRotation(pose.emPos, Quaternion.Euler(pose.emEuler));
            var cam = new GameObject("camera").AddComponent<Camera>(); cam.transform.SetParent(ps.transform, false);
            cam.orthographic = pose.ortho; cam.orthographicSize = pose.orthoSize; cam.fieldOfView = pose.fov; cam.aspect = pose.aspect;
            cam.transform.SetPositionAndRotation(pose.camPos, Quaternion.Euler(pose.camEuler)); } };

    static IEnumerable<Case> Cases3D()
    {
        var pivot = new Vector3(0.5f, 0.25f, 0.6f);
        var bb = ParticleSystemRenderMode.Billboard;
        foreach (var (tag, pose) in new[] { ("", Pose.Persp()), ("ortho_", Pose.Persp().Orthographic()) })
        {
            foreach (var al in new[] { ParticleSystemRenderSpace.View, ParticleSystemRenderSpace.World, ParticleSystemRenderSpace.Local,
                                       ParticleSystemRenderSpace.Facing, ParticleSystemRenderSpace.Velocity })
            {
                var a = M(bb, al);
                string n = "p3d_" + tag + "bb_" + al.ToString().ToLowerInvariant();
                yield return Render3D(n, a, pose);
                var withPivot = a; withPivot.pivot = pivot;
                yield return Render3D(n + "_pivot", withPivot, pose);
            }
            var noRoll = M(bb); noRoll.allowRoll = false;
            yield return Render3D("p3d_" + tag + "bb_view_noroll", noRoll, pose);
            noRoll.pivot = pivot;
            yield return Render3D("p3d_" + tag + "bb_view_noroll_pivot", noRoll, pose);

            var st = M(ParticleSystemRenderMode.Stretch);
            yield return Render3D("p3d_" + tag + "stretch", st, pose);
            var stPivot = st; stPivot.pivot = pivot;
            yield return Render3D("p3d_" + tag + "stretch_pivot", stPivot, pose);
            var ff = st; ff.freeform = true;
            yield return Render3D("p3d_" + tag + "stretch_freeform", ff, pose);
            var ffRot = ff; ffRot.rotateWith = true;
            yield return Render3D("p3d_" + tag + "stretch_freeform_rotwith", ffRot, pose);
            var ffPivot = ff; ffPivot.pivot = pivot;
            yield return Render3D("p3d_" + tag + "stretch_freeform_pivot", ffPivot, pose);
            var stWorld = st; stWorld.align = ParticleSystemRenderSpace.World;
            yield return Render3D("p3d_" + tag + "stretch_world", stWorld, pose);

            foreach (var mode in new[] { ParticleSystemRenderMode.HorizontalBillboard, ParticleSystemRenderMode.VerticalBillboard })
            {
                var h = M(mode);
                string n = "p3d_" + tag + mode.ToString().Replace("Billboard", "").ToLowerInvariant();
                yield return Render3D(n, h, pose);
                h.pivot = pivot;
                yield return Render3D(n + "_pivot", h, pose);
            }
        }

        // Horizontal and Vertical billboards one input at a time: identity pose, then each of the particle's turn,
        // the emitter's turn, the camera's roll, the camera's yaw and pitch.
        var still = new Pose { camPos = new Vector3(0f, 0f, -8f), fov = 50f, aspect = 1.5f, orthoSize = 6f, emPos = new Vector3(0f, 0f, 1f) };
        foreach (var mode in new[] { ParticleSystemRenderMode.HorizontalBillboard, ParticleSystemRenderMode.VerticalBillboard })
        {
            string k = "p3d_diag_" + mode.ToString().Replace("Billboard", "").ToLowerInvariant();
            var d = M(mode); d.rotDeg = 0f; d.velocity = new Vector3(0.5f, 0.2f, 0.3f);
            yield return Render3D(k + "_base", d, still);
            var turned = d; turned.rotDeg = 25f;
            yield return Render3D(k + "_rot25", turned, still);
            var em = still; em.emEuler = new Vector3(0f, 30f, 0f);
            yield return Render3D(k + "_emyaw30", d, em);
            var em2 = still; em2.emEuler = new Vector3(0f, 0f, 40f);
            yield return Render3D(k + "_emroll40", d, em2);
            var roll = still; roll.camEuler = new Vector3(0f, 0f, 12f);
            yield return Render3D(k + "_camroll12", d, roll);
            var yaw = still; yaw.camEuler = new Vector3(0f, -30f, 0f);
            yield return Render3D(k + "_camyaw30", d, yaw);
            var pitch = still; pitch.camEuler = new Vector3(20f, 0f, 0f);
            yield return Render3D(k + "_campitch20", d, pitch);
            foreach (var (pk, pv) in new[] { ("px", new Vector3(0.5f, 0f, 0f)), ("py", new Vector3(0f, 0.25f, 0f)), ("pz", new Vector3(0f, 0f, 0.6f)) })
            {
                var pd = d; pd.pivot = pv; pd.size = (2f, 3f);
                yield return Render3D(k + "_" + pk + "_size2x3", pd, still);
                var pr = turned; pr.pivot = pv; pr.size = (2f, 3f);
                yield return Render3D(k + "_" + pk + "_size2x3_rot25", pr, still);
            }
            var big = d; big.size = (2f, 3f);
            yield return Render3D(k + "_size2x3", big, still);
        }

        var deep = M(bb); deep.pivot = pivot; deep.sizeZ = 3f;
        yield return Render3D("p3d_bb_view_pivot_sizez3", deep, Pose.Persp());
        var deepWorld = deep; deepWorld.align = ParticleSystemRenderSpace.World;
        yield return Render3D("p3d_bb_world_pivot_sizez3", deepWorld, Pose.Persp());

        var zWide = M(bb); zWide.pivot = new Vector3(0f, 0f, 0.6f); zWide.size = (2f, 3f);
        yield return Render3D("p3d_bb_view_pz_size2x3", zWide, Pose.Persp());

        // The camera moves 2 units along its own x per frame; the control keeps it still.
        var cvs = M(ParticleSystemRenderMode.Stretch); cvs.cameraVelocityScale = 1f;
        yield return Render3D("p3d_stretch_cvs_static", cvs, Pose.Persp());
        yield return Render3D("p3d_stretch_cvs_moving", cvs, Pose.Persp(), (ps, s) => {
            var t = ps.GetComponentInChildren<Camera>().transform; t.position = t.position + t.right * 2f; });
        var cvsOff = M(ParticleSystemRenderMode.Stretch);
        yield return Render3D("p3d_stretch_cvs0_moving", cvsOff, Pose.Persp(), (ps, s) => {
            var t = ps.GetComponentInChildren<Camera>().transform; t.position = t.position + t.right * 2f; });

        // Min and max size against the viewport, near and far under a perspective camera.
        foreach (var (tag, z) in new[] { ("near", -2f), ("mid", -8f), ("far", -20f) })
        {
            var mx = M(bb); mx.size = (5f, 5f); mx.max = 0.1f;
            yield return Render3D("p3d_clamp_max_" + tag, mx, Pose.Persp(z));
            var mxWide = M(bb); mxWide.size = (8f, 3f); mxWide.max = 0.1f;
            yield return Render3D("p3d_clamp_max_wide_" + tag, mxWide, Pose.Persp(z));
            var mn = M(bb); mn.size = (0.2f, 0.2f); mn.min = 0.1f; mn.max = 0.5f;
            yield return Render3D("p3d_clamp_min_" + tag, mn, Pose.Persp(z));
            var sm = M(ParticleSystemRenderMode.Stretch); sm.size = (2f, 5f); sm.max = 0.1f;
            yield return Render3D("p3d_stretch_clamp_max_" + tag, sm, Pose.Persp(z));
        }
        var inside = M(bb); inside.size = (1f, 1f); inside.min = 0.01f; inside.max = 0.5f;
        yield return Render3D("p3d_clamp_inside", inside, Pose.Persp());

        // The same modes from the second placement, each with a pivot.
        var pose2 = Pose.Persp2();
        var pose2Pivot = new Vector3(0.5f, 0.25f, 0.6f);
        foreach (var al in new[] { ParticleSystemRenderSpace.View, ParticleSystemRenderSpace.World, ParticleSystemRenderSpace.Local,
                                   ParticleSystemRenderSpace.Facing, ParticleSystemRenderSpace.Velocity })
        {
            var a = M(bb, al); a.pivot = pose2Pivot;
            yield return Render3D("p3d_pose2_bb_" + al.ToString().ToLowerInvariant(), a, pose2);
        }
        var p2NoRoll = M(bb); p2NoRoll.allowRoll = false; p2NoRoll.pivot = pose2Pivot;
        yield return Render3D("p3d_pose2_bb_view_noroll", p2NoRoll, pose2);
        var p2Stretch = M(ParticleSystemRenderMode.Stretch); p2Stretch.pivot = pose2Pivot;
        yield return Render3D("p3d_pose2_stretch", p2Stretch, pose2);
        var p2Freeform = p2Stretch; p2Freeform.freeform = true; p2Freeform.rotateWith = true;
        yield return Render3D("p3d_pose2_stretch_freeform_rotwith", p2Freeform, pose2);
        foreach (var mode in new[] { ParticleSystemRenderMode.HorizontalBillboard, ParticleSystemRenderMode.VerticalBillboard })
        {
            var h = M(mode); h.pivot = pose2Pivot;
            yield return Render3D("p3d_pose2_" + mode.ToString().Replace("Billboard", "").ToLowerInvariant(), h, pose2);
        }
    }

    static void BakePose(StringBuilder sb, ParticleSystem ps)
    {
        var cam = ps.GetComponentInChildren<Camera>();
        var t = cam.transform;
        sb.Append(", \"pose\": {\"camera\": {\"pos\": ").Append(V(t.position))
          .Append(", \"right\": ").Append(V(t.right)).Append(", \"up\": ").Append(V(t.up)).Append(", \"forward\": ").Append(V(t.forward))
          .Append(", \"orthographic\": ").Append(cam.orthographic ? "true" : "false")
          .Append(", \"fov\": ").Append(F(cam.fieldOfView)).Append(", \"aspect\": ").Append(F(cam.aspect))
          .Append(", \"orthographicSize\": ").Append(F(cam.orthographicSize)).Append("}")
          .Append(", \"emitter\": {\"pos\": ").Append(V(ps.transform.position))
          .Append(", \"right\": ").Append(V(ps.transform.right)).Append(", \"up\": ").Append(V(ps.transform.up)).Append(", \"forward\": ").Append(V(ps.transform.forward)).Append("}}");
    }

    static void Base(ParticleSystem ps, float rate, float speed, float life)
    {
        var m = ps.main;
        m.duration = 5; m.loop = true; m.playOnAwake = false; m.startDelay = 0;
        m.startLifetime = life; m.startSpeed = speed; m.startSize = 1; m.startRotation = 0;
        m.startColor = Color.white; m.gravityModifier = 0; m.maxParticles = 1000;
        m.simulationSpace = ParticleSystemSimulationSpace.Local;
        var e = ps.emission; e.enabled = true; e.rateOverTime = rate; e.SetBursts(new ParticleSystem.Burst[0]);
        var sh = ps.shape; sh.enabled = false;
    }

    static void Burst1(ParticleSystem ps) => ps.emission.SetBursts(new[] { new ParticleSystem.Burst(0f, 1) });

    // One particle moving in the xy plane (velocityOverLifetime is animated velocity, force is stored),
    // seen by an orthographic camera at (0,0,-10) facing +z, so the baked quad is the 2D case.
    static Case StretchCase(string name, float lengthScale, float velocityScale, float size, float rotDeg,
        bool velocityAlignment, (float, float) vol, float forceY = 0f, bool billboard = false,
        (float, float)? size3D = null, (float, float)? pivot = null) => new Case {
        name = name, dt = 0.1f, steps = 3, bakeQuads = true, cap = 4,
        settings = S("renderMode", velocityAlignment || billboard ? "Billboard" : "Stretch", "alignment", velocityAlignment ? "Velocity" : "View",
            "lengthScale", lengthScale, "velocityScale", velocityScale, "startSize", size, "startRotationDeg", rotDeg,
            "velocityOverLifetime", "linear (" + vol.Item1 + ", " + vol.Item2 + ", 0) local", "forceY", forceY,
            "startSize3D", size3D.HasValue ? "(" + size3D.Value.Item1 + ", " + size3D.Value.Item2 + ")" : "off",
            "pivot", pivot.HasValue ? "(" + pivot.Value.Item1 + ", " + pivot.Value.Item2 + ", 0)" : "(0, 0, 0)",
            "camera", "orthographic size 10 at (0,0,-10) facing +z", "read", "BakeMesh vertex positions and uv0 per quad"),
        configure = ps => {
            Base(ps, 0, 0, 5); Burst1(ps);
            var m = ps.main; m.startSize = size;
            if (size3D.HasValue) { m.startSize3D = true; m.startSizeX = size3D.Value.Item1; m.startSizeY = size3D.Value.Item2; m.startSizeZ = 1f; }
            m.startRotation = rotDeg * Mathf.Deg2Rad;
            var vo = ps.velocityOverLifetime; vo.enabled = true; vo.space = ParticleSystemSimulationSpace.Local;
            vo.x = vol.Item1; vo.y = vol.Item2; vo.z = 0f;
            if (forceY != 0f) { var fo = ps.forceOverLifetime; fo.enabled = true; fo.space = ParticleSystemSimulationSpace.Local; fo.y = forceY; }
            var r = ps.GetComponent<ParticleSystemRenderer>();
            r.renderMode = velocityAlignment || billboard ? ParticleSystemRenderMode.Billboard : ParticleSystemRenderMode.Stretch;
            r.alignment = velocityAlignment ? ParticleSystemRenderSpace.Velocity : ParticleSystemRenderSpace.View;
            r.lengthScale = lengthScale; r.velocityScale = velocityScale; r.cameraVelocityScale = 0f;
            if (pivot.HasValue) r.pivot = new Vector3(pivot.Value.Item1, pivot.Value.Item2, 0f);
            var cam = new GameObject("camera").AddComponent<Camera>(); cam.transform.SetParent(ps.transform, false);
            cam.transform.position = new Vector3(0, 0, -10); cam.orthographic = true; cam.orthographicSize = 10; } };

    // A StretchCase with more of the renderer set: `extra` is a settings object merged into the case's.
    static Case RenderCase(string name, Case c, string extra, Action<ParticleSystem, ParticleSystemRenderer> more)
    {
        var inner = c.configure;
        c.name = name;
        c.settings = c.settings.Substring(0, c.settings.Length - 1) + ", " + extra.Substring(1);
        c.configure = ps => { inner(ps); more(ps, ps.GetComponent<ParticleSystemRenderer>()); ResetCamera(ps); };
        return c;
    }

    // The camera is a child of the system for BakeMesh; keep it at (0,0,-10) facing +z whatever the system's placement.
    static void ResetCamera(ParticleSystem ps) =>
        ps.GetComponentInChildren<Camera>().transform.SetPositionAndRotation(new Vector3(0, 0, -10), Quaternion.identity);

    static Case ShapeBurst(string name, string shape, Action<ParticleSystem> set) => new Case {
        name = name, dt = 0.0001f, steps = 1, cap = 512, compact = true,
        settings = S("shape", shape, "burst", "time 0 count 512", "startSpeed", 1, "note", "velocity = direction"),
        configure = ps => { Base(ps, 0, 1, 5); var sh = ps.shape; sh.enabled = true; set(ps);
            ps.emission.SetBursts(new[] { new ParticleSystem.Burst(0f, 512) }); } };

    static Case ColorCase(string name) => new Case {
        name = name, dt = 0.1f, steps = 12,
        settings = S("colorOverLifetime", "gradient 2 keys red(t0) -> green(t1), alpha 1, mode Blend", "startLifetime", 1, "gradientColorSpace", new Gradient().colorSpace.ToString()),
        configure = ps => { Base(ps, 0, 0, 1); Burst1(ps);
            var g = new Gradient();
            g.SetKeys(new[] { new GradientColorKey(Color.red, 0), new GradientColorKey(Color.green, 1) },
                      new[] { new GradientAlphaKey(1, 0), new GradientAlphaKey(1, 1) });
            var col = ps.colorOverLifetime; col.enabled = true; col.color = g; } };

    static Case CollisionCase(string name, float bounce, float dampen, float loss, float minKill) => new Case {
        name = name, dt = 1f / 60f, steps = 120,
        settings = S("space", "World", "emitter", "(0,1,0)", "startSpeed", 1, "direction", "+z", "gravityModifier", 1, "startSize", 0.02,
                     "collision", "Planes, plane at origin (normal +y)", "bounce", bounce, "dampen", dampen, "lifetimeLoss", loss, "minKillSpeed", minKill, "radiusScale", 1),
        configure = ps => { Base(ps, 0, 1, 5); var m = ps.main; m.simulationSpace = ParticleSystemSimulationSpace.World;
            m.gravityModifier = 1; m.startSize = 0.02f; Burst1(ps);
            ps.transform.position = new Vector3(0, 1, 0);
            var plane = new GameObject("plane"); plane.transform.SetParent(ps.transform, false); plane.transform.position = Vector3.zero;
            var col = ps.collision; col.enabled = true; col.type = ParticleSystemCollisionType.Planes; col.SetPlane(0, plane.transform);
            col.bounce = bounce; col.dampen = dampen; col.lifetimeLoss = loss; col.minKillSpeed = minKill; col.radiusScale = 1; } };

    static Case SubEmitterCase(string name, ParticleSystemSubEmitterType kind) => new Case {
        name = name, dt = 1f / 60f, steps = 40,
        settings = S("parent", "burst 1 at t0, startLifetime 0.5, startSpeed 1 (+z), startColor (1,0.5,0.25,1), startSize 2, World",
                     "child", "rate 0, burst 3 at t0, startLifetime 5, startSpeed 0, startColor (0.5,1,1,1), startSize 0.5, shape disabled, World",
                     "subEmitter", kind.ToString() + " InheritColor|InheritSize probability 1"),
        configure = ps => { Base(ps, 0, 1, 0.5f); var m = ps.main; m.simulationSpace = ParticleSystemSimulationSpace.World;
            m.startColor = new Color(1, 0.5f, 0.25f, 1); m.startSize = 2; Burst1(ps);
            var child = MakeChild(ps, "child");
            Base(child, 0, 0, 5); var cm = child.main; cm.simulationSpace = ParticleSystemSimulationSpace.World;
            cm.startColor = new Color(0.5f, 1, 1, 1); cm.startSize = 0.5f;
            child.emission.SetBursts(new[] { new ParticleSystem.Burst(0f, 3) });
            var sub = ps.subEmitters; sub.enabled = true;
            sub.AddSubEmitter(child, kind, ParticleSystemSubEmitterProperties.InheritColor | ParticleSystemSubEmitterProperties.InheritSize); } };

    static Case TriggerCase(string ev) => new Case {
        name = "trigger_" + ev + "_kill", dt = 0.1f, steps = 30,
        settings = S("space", "World", "trigger", "SphereCollider at origin radius 1; " + ev + " = Kill, other events Ignore",
                     "particle", "burst 1 at origin (inside), startSpeed 1 along +z, startSize 0.01, radiusScale 1"),
        configure = ps => { Base(ps, 0, 1, 5); var m = ps.main; m.simulationSpace = ParticleSystemSimulationSpace.World; m.startSize = 0.01f; Burst1(ps);
            var go = new GameObject("sphere"); go.transform.SetParent(ps.transform, false);
            var sc = go.AddComponent<SphereCollider>(); sc.radius = 1;
            Physics.SyncTransforms();
            var t = ps.trigger; t.enabled = true; t.AddCollider(sc); t.radiusScale = 1;
            t.enter = ev == "enter" ? ParticleSystemOverlapAction.Kill : ParticleSystemOverlapAction.Ignore;
            t.inside = ev == "inside" ? ParticleSystemOverlapAction.Kill : ParticleSystemOverlapAction.Ignore;
            t.exit = ev == "exit" ? ParticleSystemOverlapAction.Kill : ParticleSystemOverlapAction.Ignore;
            t.outside = ev == "outside" ? ParticleSystemOverlapAction.Kill : ParticleSystemOverlapAction.Ignore; } };

    static ParticleSystem MakeChild(ParticleSystem parent, string name)
    {
        var go = new GameObject(name);
        go.transform.SetParent(parent.transform, false);
        var ps = go.AddComponent<ParticleSystem>();
        ps.Stop(true, ParticleSystemStopBehavior.StopEmittingAndClear);
        ps.useAutoRandomSeed = false;
        ps.randomSeed = Seed + 1;
        return ps;
    }

    // ---------- runner ----------

    static int RunCase(Case c)
    {
        var go = new GameObject(c.name);
        try
        {
            var ps = go.AddComponent<ParticleSystem>();
            ps.Stop(true, ParticleSystemStopBehavior.StopEmittingAndClear);
            ps.useAutoRandomSeed = false;
            ps.randomSeed = Seed;
            c.configure(ps);
            var children = new List<ParticleSystem>();
            foreach (var p in go.GetComponentsInChildren<ParticleSystem>()) if (p != ps) children.Add(p);

            var sb = new StringBuilder();
            sb.Append("{\n\"unityVersion\": ").Append(Q(Application.unityVersion));
            sb.Append(",\n\"colorSpace\": ").Append(Q(PlayerSettings.colorSpace.ToString()));
            sb.Append(",\n\"activeColorSpace\": ").Append(Q(QualitySettings.activeColorSpace.ToString()));
            sb.Append(",\n\"caseName\": ").Append(Q(c.name));
            sb.Append(",\n\"dt\": ").Append(F(c.dt));
            sb.Append(",\n\"steps\": ").Append(c.steps);
            sb.Append(",\n\"randomSeed\": ").Append(Seed);
            sb.Append(",\n\"simulate\": \"frame 0 = Simulate(0, withChildren:true, restart:true, fixedTimeStep:false); frame k = Simulate(dt, true, false, false)\"");
            sb.Append(",\n\"settings\": ").Append(c.settings);
            sb.Append(",\n\"frames\": [\n");
            ps.Simulate(0f, true, true, false);
            Frame(sb, c, ps, children, 0);
            for (int s = 1; s <= c.steps; s++)
            {
                c.beforeStep?.Invoke(ps, s);
                ps.Simulate(c.dt, true, false, false);
                sb.Append(",\n");
                Frame(sb, c, ps, children, s);
            }
            sb.Append("\n]\n}\n");
            File.WriteAllText(Path.Combine(outDir, c.name + ".json"), sb.ToString());
            Debug.Log("ParticleCapture: wrote " + c.name);
            return 0;
        }
        catch (Exception e)
        {
            Debug.LogError("ParticleCapture: case " + c.name + " failed: " + e);
            return 1;
        }
        finally { UnityEngine.Object.DestroyImmediate(go); }
    }

    static void Frame(StringBuilder sb, Case c, ParticleSystem ps, List<ParticleSystem> children, int step)
    {
        sb.Append("{\"step\": ").Append(step).Append(", \"time\": ").Append(F(ps.time)).Append(", \"count\": ").Append(ps.particleCount);
        bool dump = !c.lastFrameOnly || step == c.steps;
        var parts = Read(ps);
        if (c.stats) Stats(sb, parts);
        if (dump) { sb.Append(", \"particles\": "); Particles(sb, c, ps, parts); }
        if (c.bakeUV) BakeUV(sb, ps);
        if (c.bakeQuads) BakeQuads(sb, ps);
        if (c.bakePose) BakePose(sb, ps);
        if (children.Count > 0)
        {
            sb.Append(", \"children\": [");
            for (int i = 0; i < children.Count; i++)
            {
                if (i > 0) sb.Append(", ");
                var cp = Read(children[i]);
                sb.Append("{\"name\": ").Append(Q(children[i].name)).Append(", \"count\": ").Append(children[i].particleCount).Append(", \"particles\": ");
                Particles(sb, c, children[i], cp);
                sb.Append("}");
            }
            sb.Append("]");
        }
        sb.Append("}");
    }

    static ParticleSystem.Particle[] Read(ParticleSystem ps)
    {
        var arr = new ParticleSystem.Particle[Math.Max(1, ps.particleCount)];
        int n = ps.GetParticles(arr);
        Array.Resize(ref arr, n);
        return arr;
    }

    static void Particles(StringBuilder sb, Case c, ParticleSystem ps, ParticleSystem.Particle[] parts)
    {
        sb.Append("[");
        int n = Math.Min(parts.Length, c.cap);
        for (int i = 0; i < n; i++)
        {
            var p = parts[i];
            sb.Append(i > 0 ? ",\n  " : "\n  ");
            if (c.remainingOnly)
            {
                sb.Append("{\"remaining\": ").Append(F(p.remainingLifetime)).Append("}");
                continue;
            }
            if (c.compact)
            {
                sb.Append("{\"pos\": ").Append(V(p.position)).Append(", \"vel\": ").Append(V(p.velocity)).Append("}");
                continue;
            }
            Color col = p.GetCurrentColor(ps);
            Color sc = p.startColor;
            sb.Append("{\"pos\": ").Append(V(p.position))
              .Append(", \"vel\": ").Append(V(p.velocity))
              .Append(", \"anim\": ").Append(V(p.animatedVelocity))
              .Append(", \"total\": ").Append(V(p.totalVelocity))
              .Append(", \"startSize\": ").Append(V(p.startSize3D))
              .Append(", \"size\": ").Append(V(p.GetCurrentSize3D(ps)))
              .Append(", \"rot\": ").Append(V(p.rotation3D))
              .Append(", \"color\": [").Append(F(col.r)).Append(", ").Append(F(col.g)).Append(", ").Append(F(col.b)).Append(", ").Append(F(col.a)).Append("]")
              .Append(", \"startColor\": [").Append(F(sc.r)).Append(", ").Append(F(sc.g)).Append(", ").Append(F(sc.b)).Append(", ").Append(F(sc.a)).Append("]")
              .Append(", \"remaining\": ").Append(F(p.remainingLifetime))
              .Append(", \"startLifetime\": ").Append(F(p.startLifetime))
              .Append(", \"seed\": ").Append(p.randomSeed).Append("}");
        }
        sb.Append("]");
    }

    static void Stats(StringBuilder sb, ParticleSystem.Particle[] parts)
    {
        if (parts.Length == 0) return;
        float sum = 0, min = float.MaxValue, max = 0;
        foreach (var p in parts)
        {
            float m = p.animatedVelocity.magnitude;
            sum += m; min = Mathf.Min(min, m); max = Mathf.Max(max, m);
        }
        sb.Append(", \"animSpeedMean\": ").Append(F(sum / parts.Length)).Append(", \"animSpeedMin\": ").Append(F(min)).Append(", \"animSpeedMax\": ").Append(F(max));
    }

    static void BakeUV(StringBuilder sb, ParticleSystem ps)
    {
        try
        {
            var mesh = new Mesh();
            ps.GetComponent<ParticleSystemRenderer>().BakeMesh(mesh, ps.GetComponentInChildren<Camera>(), ParticleSystemBakeMeshOptions.Default);
            var uv = new List<Vector2>();
            mesh.GetUVs(0, uv);
            sb.Append(", \"bakedQuadUVMin\": [");
            for (int q = 0; q + 3 < uv.Count; q += 4)
            {
                var a = Vector2.Min(Vector2.Min(uv[q], uv[q + 1]), Vector2.Min(uv[q + 2], uv[q + 3]));
                if (q > 0) sb.Append(", ");
                sb.Append("[").Append(F(a.x)).Append(", ").Append(F(a.y)).Append("]");
            }
            sb.Append("], \"bakedVertexCount\": ").Append(uv.Count);
            UnityEngine.Object.DestroyImmediate(mesh);
        }
        catch (Exception e) { sb.Append(", \"bakeError\": ").Append(Q(e.Message)); }
    }

    static void BakeQuads(StringBuilder sb, ParticleSystem ps)
    {
        try
        {
            var mesh = new Mesh();
            ps.GetComponent<ParticleSystemRenderer>().BakeMesh(mesh, ps.GetComponentInChildren<Camera>(), ParticleSystemBakeMeshOptions.Default);
            var pos = new List<Vector3>();
            var uv = new List<Vector2>();
            mesh.GetVertices(pos);
            mesh.GetUVs(0, uv);
            sb.Append(", \"bakedQuads\": [");
            for (int q = 0; q + 3 < pos.Count; q += 4)
            {
                if (q > 0) sb.Append(", ");
                sb.Append("{\"pos\": [");
                for (int k = 0; k < 4; k++) sb.Append(k > 0 ? ", " : "").Append(V(pos[q + k]));
                sb.Append("], \"uv\": [");
                for (int k = 0; k < 4; k++) sb.Append(k > 0 ? ", " : "").Append("[").Append(F(uv[q + k].x)).Append(", ").Append(F(uv[q + k].y)).Append("]");
                sb.Append("]}");
            }
            sb.Append("]");
            UnityEngine.Object.DestroyImmediate(mesh);
        }
        catch (Exception e) { sb.Append(", \"bakeError\": ").Append(Q(e.Message)); }
    }

    // ---------- json ----------

    static string F(float f) => float.IsNaN(f) || float.IsInfinity(f) ? Q(f.ToString(CultureInfo.InvariantCulture)) : f.ToString("R", CultureInfo.InvariantCulture);
    static string V(Vector3 v) => "[" + F(v.x) + ", " + F(v.y) + ", " + F(v.z) + "]";
    static string Q(string s) => "\"" + s.Replace("\\", "\\\\").Replace("\"", "\\\"").Replace("\n", "\\n").Replace("\r", "") + "\"";

    static string S(params object[] kv)
    {
        var sb = new StringBuilder("{");
        for (int i = 0; i + 1 < kv.Length; i += 2)
        {
            if (i > 0) sb.Append(", ");
            sb.Append(Q((string)kv[i])).Append(": ");
            var v = kv[i + 1];
            if (v is bool b) sb.Append(b ? "true" : "false");
            else if (v is int n) sb.Append(n);
            else if (v is float f) sb.Append(F(f));
            else if (v is double d) sb.Append(F((float)d));
            else sb.Append(Q(v.ToString()));
        }
        return sb.Append("}").ToString();
    }
}
