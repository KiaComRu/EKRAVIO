using Ekravio.SessionMonitor;

var start = DateTimeOffset.UnixEpoch;
var sampler = new ActivitySampler(60);
Check(sampler.Observe(new(start, 1000, 900)), "unknown", null, "stale startup input");
Check(sampler.Observe(new(start.AddSeconds(1), 2000, 900)), "idle", false, "connection alone");
Check(sampler.Observe(new(start.AddSeconds(2), 3000, 3000)), "active", true, "fresh input");
for (int second = 3; second < 82; second++)
{
    uint lastInput = second < 22 ? 3000U : 23000U;
    Check(sampler.Observe(new(start.AddSeconds(second), (ulong)(1000 * (second + 1)), lastInput)),
        "active", second == 22, $"union of activity windows at second {second}");
}
Check(sampler.Observe(new(start.AddSeconds(82), 83000, 23000)), "idle", false, "half-open timeout");
Check(sampler.Observe(new(start.AddSeconds(85), 86000, 23000)), "unknown", null, "sampling gap");
Check(sampler.MarkUnavailable(start.AddSeconds(86), "disconnected"), "disconnected", null, "session disconnect");
Check(sampler.Observe(new(start.AddSeconds(87), 88000, 87900)), "unknown", null, "reconnection baseline");
Check(sampler.Observe(new(start.AddSeconds(88), 89000, 8000)), "unknown", null, "out-of-order Windows tick");
Check(sampler.Observe(new(start.AddHours(1), 90000, 89500)), "unknown", null, "wall clock jump");

var wrappedSampler = new ActivitySampler(60);
Check(wrappedSampler.Observe(new(start, uint.MaxValue - 500UL, uint.MaxValue - 700)), "unknown", null, "wrap baseline");
Check(wrappedSampler.Observe(new(start.AddSeconds(1), uint.MaxValue + 500UL, 200)), "active", true, "32-bit wrap");
Console.WriteLine("Activity probe regressions passed.");

static void Check(ActivitySample sample, string state, bool? inputSeen, string scenario)
{
    string quality = inputSeen is null ? "unavailable" : "complete";
    if (sample.State != state || sample.InputSeen != inputSeen || sample.Quality != quality)
        throw new InvalidOperationException($"{scenario}: received {sample}");
}
