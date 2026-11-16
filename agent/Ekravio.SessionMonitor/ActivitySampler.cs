namespace Ekravio.SessionMonitor;

internal readonly record struct InputReading(DateTimeOffset Utc, ulong Tick, uint LastInputTick);

internal readonly record struct ActivitySample(
    DateTimeOffset ObservedAtUtc, string State, string Quality, bool? InputSeen);

internal sealed class ActivitySampler(int idleTimeoutSeconds)
{
    private InputReading? _previous;
    private ulong? _lastObservedInput;

    public ActivitySample MarkUnavailable(DateTimeOffset utc, string state)
    {
        _previous = null;
        _lastObservedInput = null;
        return Unavailable(utc, state);
    }

    public ActivitySample Observe(InputReading reading)
    {
        var previous = _previous;
        _previous = reading;
        if (previous is not { } prior || !IsContinuous(prior, reading))
        {
            _lastObservedInput = null;
            return Unavailable(reading.Utc, "unknown");
        }

        bool inputSeen = reading.LastInputTick != prior.LastInputTick;
        if (inputSeen)
        {
            // GetLastInputInfo returns the low 32 bits of the Windows tick counter.
            // Accept only changes that belong to the interval we just observed.
            uint age = unchecked((uint)reading.Tick - reading.LastInputTick);
            if (age >= reading.Tick - prior.Tick)
            {
                _lastObservedInput = null;
                return Unavailable(reading.Utc, "unknown");
            }
            _lastObservedInput = reading.Tick - age;
        }

        bool active = _lastObservedInput is { } inputTick && reading.Tick - inputTick < (ulong)idleTimeoutSeconds * 1000;
        return new(reading.Utc, active ? "active" : "idle", "complete", inputSeen);
    }

    private static bool IsContinuous(InputReading previous, InputReading current)
    {
        if (current.Tick <= previous.Tick || current.Utc <= previous.Utc) return false;
        ulong elapsed = current.Tick - previous.Tick;
        return elapsed <= 2000 && Math.Abs((current.Utc - previous.Utc).TotalMilliseconds - elapsed) <= 1000;
    }

    private static ActivitySample Unavailable(DateTimeOffset utc, string state) => new(utc, state, "unavailable", null);
}
