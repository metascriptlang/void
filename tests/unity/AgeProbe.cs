using System;
using System.Collections.Generic;
using System.Globalization;
using System.IO;
using System.Text;
using UnityEngine;

public static class AgeProbe
{
    static string F(float f) => f.ToString("R", CultureInfo.InvariantCulture);

    public static void Run()
    {
        string outPath = null;
        var args = Environment.GetCommandLineArgs();
        for (int i = 0; i < args.Length - 1; i++) if (args[i] == "-out") outPath = args[i + 1];
        var sb = new StringBuilder("[\n");
        bool first = true;
        foreach (var life in new[] { 0.1f, 0.3f, 1f })
            foreach (var (label, dt) in new (string, float)[] { ("60", 1f / 60f), ("40", 0.025f), ("20", 0.05f), ("10", 0.1f), ("120", 1f / 120f), ("144", 1f / 144f), ("100", 0.01f) })
            {
                var go = new GameObject("probe");
                var ps = go.AddComponent<ParticleSystem>();
                ps.Stop(true, ParticleSystemStopBehavior.StopEmittingAndClear);
                ps.useAutoRandomSeed = false; ps.randomSeed = 12345;
                var m = ps.main;
                m.duration = 5; m.loop = true; m.playOnAwake = false; m.startDelay = 0;
                m.startLifetime = life; m.startSpeed = 0; m.startSize = 1; m.startRotation = 0;
                m.startColor = Color.white; m.gravityModifier = 0; m.maxParticles = 1000;
                m.simulationSpace = ParticleSystemSimulationSpace.Local;
                var e = ps.emission; e.enabled = true; e.rateOverTime = 0; e.SetBursts(new[] { new ParticleSystem.Burst(0f, 1) });
                var sh = ps.shape; sh.enabled = false;
                var cd = ps.customData; cd.enabled = true;
                cd.SetMode(ParticleSystemCustomData.Custom1, ParticleSystemCustomDataMode.Vector);
                cd.SetVectorComponentCount(ParticleSystemCustomData.Custom1, 1);
                cd.SetVector(ParticleSystemCustomData.Custom1, 0, new ParticleSystem.MinMaxCurve(1f, AnimationCurve.Linear(0, 0, 1, 1)));
                var r = go.GetComponent<ParticleSystemRenderer>();
                r.SetActiveVertexStreams(new List<ParticleSystemVertexStream> {
                    ParticleSystemVertexStream.Position, ParticleSystemVertexStream.UV,
                    ParticleSystemVertexStream.AgePercent, ParticleSystemVertexStream.InvStartLifetime });
                var cam = new GameObject("camera").AddComponent<Camera>(); cam.transform.SetParent(go.transform, false);
                cam.transform.position = new Vector3(0, 0, -10); cam.orthographic = true; cam.orthographicSize = 10;

                sb.Append(first ? "" : ",\n").Append("{\"case\": \"life").Append((int)Math.Round(life * 1000)).Append("_hz").Append(label)
                  .Append("\", \"dt\": ").Append(F(dt)).Append(", \"life\": ").Append(F(life)).Append(", \"frames\": [");
                first = false;
                int steps = (int)((life + 0.15f) / dt);
                ps.Simulate(0, true, true, false);
                var custom = new List<Vector4>();
                for (int k = 1; k <= steps; k++)
                {
                    ps.Simulate(dt, true, false, false);
                    var arr = new ParticleSystem.Particle[Math.Max(1, ps.particleCount)];
                    int n = ps.GetParticles(arr);
                    sb.Append(k > 1 ? ",\n  " : "\n  ").Append("{\"step\": ").Append(k).Append(", \"time\": ").Append(F(ps.time)).Append(", \"count\": ").Append(n);
                    if (n > 0)
                    {
                        var p = arr[0];
                        sb.Append(", \"remaining\": ").Append(F(p.remainingLifetime)).Append(", \"startLifetime\": ").Append(F(p.startLifetime));
                        ps.GetCustomParticleData(custom, ParticleSystemCustomData.Custom1);
                        if (custom.Count > 0) sb.Append(", \"custom1\": ").Append(F(custom[0].x));
                        var mesh = new Mesh();
                        try
                        {
                            r.BakeMesh(mesh, cam, ParticleSystemBakeMeshOptions.Default);
                            for (int ch = 0; ch < 4; ch++)
                            {
                                var uv = new List<Vector4>();
                                mesh.GetUVs(ch, uv);
                                if (uv.Count == 0) continue;
                                sb.Append(", \"uv").Append(ch).Append("\": [").Append(F(uv[0].x)).Append(", ").Append(F(uv[0].y)).Append(", ")
                                  .Append(F(uv[0].z)).Append(", ").Append(F(uv[0].w)).Append("]");
                            }
                        }
                        catch (Exception ex) { sb.Append(", \"bakeError\": \"").Append(ex.Message.Replace("\"", "'")).Append("\""); }
                        UnityEngine.Object.DestroyImmediate(mesh);
                    }
                    sb.Append("}");
                }
                sb.Append("]}");
                UnityEngine.Object.DestroyImmediate(go);
            }
        sb.Append("\n]\n");
        File.WriteAllText(outPath, sb.ToString());
        Debug.Log("AgeProbe: done");
    }
}
