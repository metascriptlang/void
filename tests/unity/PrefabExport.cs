using System;
using System.IO;
using UnityEditor;
using UnityEngine;

public static class PrefabExport
{
    public static void Run()
    {
        string outDir = null;
        var args = Environment.GetCommandLineArgs();
        for (int i = 0; i < args.Length - 1; i++)
            if (args[i] == "-prefabDir") outDir = args[i + 1];
        if (outDir == null) throw new Exception("PrefabExport: pass -prefabDir <dir>");
        Directory.CreateDirectory(outDir);
        Directory.CreateDirectory("Assets/Prefabs");

        Save(Fountain(), outDir, "fountain");
        Save(Curves(), outDir, "curves");
        Save(SubEmitters(), outDir, "subEmitters");
        Save(TrailsCollision(), outDir, "trailsCollision");
        Debug.Log("PrefabExport: done");
    }

    static void Save(GameObject go, string outDir, string name)
    {
        string path = "Assets/Prefabs/" + name + ".prefab";
        PrefabUtility.SaveAsPrefabAsset(go, path);
        UnityEngine.Object.DestroyImmediate(go);
        File.Copy(path, Path.Combine(outDir, name + ".prefab"), true);
    }

    static ParticleSystem NewSystem(string name, Transform parent = null)
    {
        var go = new GameObject(name);
        if (parent != null) go.transform.SetParent(parent, false);
        var ps = go.AddComponent<ParticleSystem>();
        ps.Stop(true, ParticleSystemStopBehavior.StopEmittingAndClear);
        return ps;
    }

    static AnimationCurve Curve(params float[] tv)
    {
        var c = new AnimationCurve();
        for (int i = 0; i + 1 < tv.Length; i += 2) c.AddKey(tv[i], tv[i + 1]);
        return c;
    }

    static GameObject Fountain()
    {
        var ps = NewSystem("Fountain");
        var m = ps.main;
        m.duration = 4f; m.loop = true; m.prewarm = false;
        m.startLifetime = 2f; m.startSpeed = 6f; m.startSize = 0.2f;
        m.startColor = new Color(1f, 0.5f, 0.25f, 0.75f);
        m.gravityModifier = 1f; m.maxParticles = 500;
        m.simulationSpace = ParticleSystemSimulationSpace.World;
        m.playOnAwake = false; ps.useAutoRandomSeed = false; ps.randomSeed = 777;
        var e = ps.emission; e.rateOverTime = 50f;
        var burst = new ParticleSystem.Burst(0.5f, 20, 30, 3, 0.25f); burst.probability = 0.5f;
        e.SetBursts(new[] { burst });
        var s = ps.shape; s.shapeType = ParticleSystemShapeType.Cone; s.angle = 20f; s.radius = 0.5f;
        s.radiusThickness = 0.5f; s.arc = 270f; s.position = new Vector3(0f, 0.1f, 0f);
        s.rotation = new Vector3(-90f, 0f, 0f);
        return ps.gameObject;
    }

    static GameObject Curves()
    {
        var ps = NewSystem("Curves");
        var m = ps.main;
        m.startLifetime = new ParticleSystem.MinMaxCurve(1f, 3f);
        m.startSpeed = new ParticleSystem.MinMaxCurve(2f, Curve(0f, 0f, 1f, 1f));
        m.startRotation = new ParticleSystem.MinMaxCurve(0.5f, 1.5f);
        m.startColor = new ParticleSystem.MinMaxGradient(new Color(1f, 0f, 0f, 1f), new Color(0f, 0f, 1f, 0.5f));
        m.gravityModifier = new ParticleSystem.MinMaxCurve(0.5f, Curve(0f, 0.2f, 1f, 1f));
        m.simulationSpace = ParticleSystemSimulationSpace.Local;

        var g = new Gradient();
        g.SetKeys(
            new[] { new GradientColorKey(Color.red, 0f), new GradientColorKey(Color.green, 0.5f), new GradientColorKey(Color.blue, 1f) },
            new[] { new GradientAlphaKey(0f, 0f), new GradientAlphaKey(1f, 0.25f), new GradientAlphaKey(0f, 1f) });
        var col = ps.colorOverLifetime; col.enabled = true; col.color = new ParticleSystem.MinMaxGradient(g);

        var sz = ps.sizeOverLifetime; sz.enabled = true;
        var sc = new AnimationCurve(new Keyframe(0f, 0.1f, 0f, 2f), new Keyframe(0.5f, 1f, 0f, 0f), new Keyframe(1f, 0.2f, -1f, -1f));
        sz.size = new ParticleSystem.MinMaxCurve(3f, sc);

        var rot = ps.rotationOverLifetime; rot.enabled = true; rot.z = new ParticleSystem.MinMaxCurve(0.5f, 1f);
        var vel = ps.velocityOverLifetime; vel.enabled = true; vel.space = ParticleSystemSimulationSpace.World;
        vel.x = 1f; vel.y = new ParticleSystem.MinMaxCurve(1f, 2f); vel.z = 0f; vel.speedModifier = 0.5f;
        vel.radial = 0.25f;
        var frc = ps.forceOverLifetime; frc.enabled = true; frc.x = 0.5f; frc.y = -1f; frc.z = 0f; frc.randomized = true;
        var lim = ps.limitVelocityOverLifetime; lim.enabled = true; lim.limit = 4f; lim.dampen = 0.3f; lim.drag = 0.1f;
        var inh = ps.inheritVelocity; inh.enabled = true; inh.mode = ParticleSystemInheritVelocityMode.Current; inh.curve = 0.5f;
        var ext = ps.externalForces; ext.enabled = true; ext.multiplier = 2f;
        var cbs = ps.colorBySpeed; cbs.enabled = true; cbs.color = new ParticleSystem.MinMaxGradient(g); cbs.range = new Vector2(1f, 5f);
        var sbs = ps.sizeBySpeed; sbs.enabled = true; sbs.size = new ParticleSystem.MinMaxCurve(2f, Curve(0f, 0f, 1f, 1f)); sbs.range = new Vector2(0f, 8f);
        var rbs = ps.rotationBySpeed; rbs.enabled = true; rbs.z = 1.5f; rbs.range = new Vector2(0f, 3f);
        var noise = ps.noise; noise.enabled = true; noise.strength = 2f; noise.frequency = 0.75f;
        noise.octaveCount = 2; noise.quality = ParticleSystemNoiseQuality.Medium; noise.damping = false;
        noise.scrollSpeed = 0.5f; noise.positionAmount = 0.8f;
        var tsa = ps.textureSheetAnimation; tsa.enabled = true; tsa.numTilesX = 4; tsa.numTilesY = 2;
        tsa.cycleCount = 2; tsa.frameOverTime = new ParticleSystem.MinMaxCurve(1f, Curve(0f, 0f, 1f, 1f));
        var lt = ps.lights; lt.enabled = true; lt.ratio = 0.5f; lt.intensity = 2f; lt.range = 3f; lt.maxLights = 5;
        var cd = ps.customData; cd.enabled = true;
        cd.SetMode(ParticleSystemCustomData.Custom1, ParticleSystemCustomDataMode.Vector);
        cd.SetVectorComponentCount(ParticleSystemCustomData.Custom1, 2);
        cd.SetVector(ParticleSystemCustomData.Custom1, 0, 1f);
        cd.SetVector(ParticleSystemCustomData.Custom1, 1, new ParticleSystem.MinMaxCurve(2f, Curve(0f, 0f, 1f, 1f)));
        var r = ps.GetComponent<ParticleSystemRenderer>();
        r.renderMode = ParticleSystemRenderMode.Stretch; r.velocityScale = 0.2f; r.lengthScale = 3f; r.sortingOrder = 4;
        return ps.gameObject;
    }

    static GameObject SubEmitters()
    {
        var parent = NewSystem("Parent");
        var m = parent.main; m.simulationSpace = ParticleSystemSimulationSpace.World;
        m.startLifetime = 1f; m.startSpeed = 3f;
        var birth = NewSystem("BirthChild", parent.transform);
        var bm = birth.main; bm.simulationSpace = ParticleSystemSimulationSpace.World; bm.startLifetime = 0.5f;
        var death = NewSystem("DeathChild", parent.transform);
        var dm = death.main; dm.simulationSpace = ParticleSystemSimulationSpace.World; dm.startSize = 0.4f;
        var e = death.emission; e.rateOverTime = 0f;
        e.SetBursts(new[] { new ParticleSystem.Burst(0f, 8) });
        var grand = NewSystem("Grandchild", death.transform);
        var gm = grand.main; gm.simulationSpace = ParticleSystemSimulationSpace.World; gm.startSize = 0.1f;
        var ge = grand.emission; ge.rateOverTime = 0f;
        ge.SetBursts(new[] { new ParticleSystem.Burst(0f, 2) });
        var subs = parent.subEmitters; subs.enabled = true;
        subs.AddSubEmitter(birth, ParticleSystemSubEmitterType.Birth, ParticleSystemSubEmitterProperties.InheritColor);
        subs.AddSubEmitter(death, ParticleSystemSubEmitterType.Death,
            ParticleSystemSubEmitterProperties.InheritColor | ParticleSystemSubEmitterProperties.InheritSize, 0.5f);
        var dsubs = death.subEmitters; dsubs.enabled = true;
        dsubs.AddSubEmitter(grand, ParticleSystemSubEmitterType.Collision, ParticleSystemSubEmitterProperties.InheritNothing);
        return parent.gameObject;
    }

    static GameObject TrailsCollision()
    {
        var ps = NewSystem("TrailsCollision");
        var m = ps.main; m.startSpeed = 4f; m.gravityModifier = 1f;
        var tr = ps.trails; tr.enabled = true; tr.mode = ParticleSystemTrailMode.PerParticle; tr.ratio = 0.5f;
        tr.lifetime = 0.4f; tr.minVertexDistance = 0.1f; tr.worldSpace = true; tr.dieWithParticles = false;
        tr.sizeAffectsWidth = false; tr.inheritParticleColor = false; tr.widthOverTrail = new ParticleSystem.MinMaxCurve(1f, Curve(0f, 1f, 1f, 0f));
        tr.textureMode = ParticleSystemTrailTextureMode.Tile;
        var g = new Gradient();
        g.SetKeys(new[] { new GradientColorKey(Color.white, 0f), new GradientColorKey(Color.yellow, 1f) },
                  new[] { new GradientAlphaKey(1f, 0f), new GradientAlphaKey(0f, 1f) });
        tr.colorOverLifetime = new ParticleSystem.MinMaxGradient(g);
        tr.colorOverTrail = new ParticleSystem.MinMaxGradient(g);
        var floor = new GameObject("Floor"); floor.transform.SetParent(ps.transform, false);
        floor.transform.localPosition = new Vector3(0f, -2f, 0f);
        var col = ps.collision; col.enabled = true; col.type = ParticleSystemCollisionType.Planes;
        col.mode = ParticleSystemCollisionMode.Collision3D;
        col.SetPlane(0, floor.transform);
        col.dampen = 0.2f; col.bounce = 0.6f; col.lifetimeLoss = 0.1f; col.minKillSpeed = 0.5f; col.maxKillSpeed = 50f;
        col.radiusScale = 0.9f; col.sendCollisionMessages = true;
        var trg = ps.trigger; trg.enabled = true; trg.inside = ParticleSystemOverlapAction.Callback;
        trg.enter = ParticleSystemOverlapAction.Kill; trg.radiusScale = 0.5f;
        return ps.gameObject;
    }
}
