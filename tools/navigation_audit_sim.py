#!/usr/bin/env python3
"""Deterministic LakeNav v0.85 navigation audit simulations.

This is an engineering regression aid, not a GNSS simulator.
It quantifies logic-level latency and route-progress edge cases.
"""
import math

EARTH_R = 6371000.0

def norm(v):
    return v % 360.0

def delta(a, b):
    return ((b - a + 540.0) % 360.0) - 180.0

def heading_response(current=True, hz=5.5, turn_at=1.0, duration=25.0):
    rendered = 0.0
    maprot = 0.0
    samples = []
    for k in range(int(duration * hz) + 1):
        t = k / hz
        raw = 0.0 if t < turn_at else 90.0
        d = delta(rendered, raw)
        if current:
            deadband, maxstep, alpha = 0.45, 7.0, 0.18
            if abs(d) >= deadband:
                d = max(-maxstep, min(maxstep, d))
                rendered = norm(rendered + d * alpha)
            maprot = norm(maprot + delta(maprot, rendered) * 0.18)
        else:
            # Candidate single-stage motion filter for comparison.
            deadband, maxstep, alpha = 0.60, 18.0, 0.55
            if abs(d) >= deadband:
                d = max(-maxstep, min(maxstep, d))
                rendered = norm(rendered + d * alpha)
            maprot = rendered
        samples.append((t, raw, rendered, maprot, abs(delta(maprot, raw))))
    return samples

def settle(samples, turn_at=1.0, threshold=10.0):
    for t, raw, rendered, maprot, error in samples:
        if t >= turn_at and error <= threshold:
            return t - turn_at
    return None

def along_filter_lag(speed_mps=8.94, hz=1.0, seconds=20.0, gain=0.82):
    raw = 0.0
    filt = 0.0
    dt = 1.0 / hz
    lags = []
    for _ in range(int(seconds * hz)):
        raw += speed_mps * dt
        gap = raw - filt
        filt += gap * gain
        lags.append(raw - filt)
    return lags[-1]

def main():
    current = heading_response(True)
    candidate = heading_response(False)
    print("90-degree heading step")
    for threshold in (45, 20, 10, 5):
        print(
            f"  <= {threshold:2d} deg: "
            f"v0.85={settle(current, threshold=threshold):5.2f}s  "
            f"single-stage candidate={settle(candidate, threshold=threshold):5.2f}s"
        )

    print("\nSteady along-track display lag from current 0.82 gain at 1 Hz")
    for mph in (5, 10, 20, 30):
        mps = mph / 2.2369362921
        lag = along_filter_lag(mps)
        print(f"  {mph:2d} mph: {lag:5.2f} m / {lag * 3.28084:5.1f} ft")

if __name__ == "__main__":
    main()
