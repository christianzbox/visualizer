#include <metal_stdlib>
using namespace metal;

struct SpectraVertex {
    float2 position;
    float4 color;
};

struct VertexOut {
    float4 position [[position]];
    float4 color;
};

struct FractalUniforms {
    float2 resolution;
    float time;
    float rms;
    float volume;
    float bass;
    float mid;
    float treble;
    float beat;
    float intensity;
    float sensitivity;
    float motion;
    float glow;
    float beatReactivity;
    uint mode;
    uint palette;
};

vertex VertexOut spectra_vertex(uint vertexID [[vertex_id]],
                                constant SpectraVertex *vertices [[buffer(0)]]) {
    VertexOut out;
    SpectraVertex inputVertex = vertices[vertexID];
    out.position = float4(inputVertex.position, 0.0, 1.0);
    out.color = inputVertex.color;
    return out;
}

fragment half4 spectra_fragment(VertexOut input [[stage_in]]) {
    return half4(input.color);
}

float2 rotate2(float2 value, float angle) {
    float s = sin(angle);
    float c = cos(angle);
    return float2(value.x * c - value.y * s, value.x * s + value.y * c);
}

float2 complexSquare(float2 value) {
    return float2(value.x * value.x - value.y * value.y, 2.0 * value.x * value.y);
}

float3 lerp3(float3 a, float3 b, float t) {
    return a + (b - a) * clamp(t, 0.0, 1.0);
}

float3 paletteGradient(uint palette, float t) {
    t = fract(t);
    if (palette == 0) {
        float3 a = float3(0.04, 0.78, 0.94);
        float3 b = float3(0.28, 0.98, 0.46);
        float3 c = float3(0.98, 0.25, 0.72);
        return t < 0.5 ? lerp3(a, b, t * 2.0) : lerp3(b, c, (t - 0.5) * 2.0);
    }
    if (palette == 1) {
        float3 a = float3(0.92, 0.16, 0.10);
        float3 b = float3(1.00, 0.58, 0.12);
        float3 c = float3(0.52, 0.12, 0.92);
        return t < 0.56 ? lerp3(a, b, t / 0.56) : lerp3(b, c, (t - 0.56) / 0.44);
    }
    if (palette == 2) {
        return 0.55 + 0.45 * cos(6.2831853 * (float3(t, t + 0.34, t + 0.68)));
    }
    float3 low = float3(0.10, 0.13, 0.14);
    float3 high = float3(0.90, 0.94, 0.90);
    return lerp3(low, high, smoothstep(0.08, 0.92, t));
}

float hash21(float2 p) {
    p = fract(p * float2(123.34, 456.21));
    p += dot(p, p + 45.32);
    return fract(p.x * p.y);
}

float spectralFilament(float2 point, constant FractalUniforms &u) {
    float radius = length(point);
    float angle = atan2(point.y, point.x);
    float tempo = u.time * (0.16 + u.motion * 0.42);
    float bassFold = sin(radius * (8.0 + u.bass * 8.0) - tempo * 3.2 + u.beat * 1.8);
    float midFold = sin(angle * (3.0 + u.mid * 4.0) + radius * 15.0 + tempo * 2.1);
    float trebleFold = sin(radius * 42.0 - angle * 5.0 + tempo * 5.8);
    float filament = bassFold * 0.46 + midFold * 0.36 + trebleFold * u.treble * 0.28;
    return smoothstep(0.72, 1.0, filament) * smoothstep(1.70, 0.18, radius);
}

float transientDust(float2 point, constant FractalUniforms &u) {
    float2 cell = floor((point + 1.6) * (70.0 + u.treble * 42.0));
    float seed = hash21(cell + floor(u.time * (0.8 + u.motion * 1.8)));
    float threshold = 0.992 - clamp(u.treble * 0.014 + u.beat * 0.010, 0.0, 0.025);
    float sparkle = smoothstep(threshold, 1.0, seed);
    return sparkle * smoothstep(0.12, 1.45, length(point)) * (0.08 + u.treble * 0.36 + u.beat * 0.28);
}

float4 iterateFractal(float2 point, constant FractalUniforms &u) {
    float audio = clamp(max(u.volume, sqrt(max(u.rms, 0.0)) * 0.70) * (0.78 + u.sensitivity), 0.0, 1.0);
    float bass = clamp(u.bass * (0.78 + u.sensitivity), 0.0, 1.2);
    float mid = clamp(u.mid * (0.78 + u.sensitivity), 0.0, 1.2);
    float treble = clamp(u.treble * (0.78 + u.sensitivity), 0.0, 1.2);
    float beat = clamp(u.beat * u.beatReactivity, 0.0, 1.0);
    float travel = u.time * (0.018 + u.motion * 0.090);
    float rotateAmount = sin(travel * 0.73 + mid * 1.7) * (0.10 + u.motion * 0.42);
    float zoom = 1.0 + bass * 0.28 + beat * 0.20 + audio * 0.14;
    float2 p = rotate2(point, rotateAmount) / zoom;
    float warp = (mid * 0.034 + treble * 0.022 + beat * 0.018) * (0.36 + u.motion);
    p += float2(
        sin(p.y * 4.2 + travel * 4.8 + bass),
        cos(p.x * 3.6 - travel * 4.0 + mid)
    ) * warp;
    float2 z = float2(0.0);
    float2 c = p;
    float2 previous = float2(0.0);
    float2 phoenix = float2(-0.52 + bass * 0.18, 0.03 + beat * 0.18);

    if (u.mode == 0) {
        c = p * 1.58 + float2(-0.56 + sin(travel) * 0.035 + bass * 0.050, mid * 0.055);
        z = float2(0.0);
    } else if (u.mode == 1) {
        z = p * (1.36 - beat * 0.12);
        c = float2(
            -0.74 + sin(travel * 1.3) * 0.12 + bass * 0.09,
            0.22 + cos(travel * 0.9) * 0.20 + mid * 0.10
        );
    } else if (u.mode == 2) {
        c = p * 1.72 + float2(-0.48 + bass * 0.08, -0.45 + sin(travel) * 0.08);
        z = float2(0.0);
    } else if (u.mode == 3) {
        c = p * 1.66 + float2(-0.22 + sin(travel * 0.8) * 0.05, cos(travel * 0.7) * 0.05 + mid * 0.06);
        z = float2(0.0);
    } else {
        z = p * 1.38;
        c = float2(-0.42 + treble * 0.12 + sin(travel) * 0.04, 0.08 + mid * 0.10);
        previous = float2(0.0);
    }

    int maxIterations = 50 + int(clamp(u.intensity, 0.0, 1.0) * 38.0 + treble * 12.0);
    float minOrbit = 32.0;
    int iteration = 0;
    for (int i = 0; i < 104; i++) {
        if (i >= maxIterations) {
            break;
        }

        if (u.mode == 2) {
            z = abs(z);
            z = complexSquare(z) + c;
        } else if (u.mode == 3) {
            z = float2(z.x, -z.y);
            z = complexSquare(z) + c;
        } else if (u.mode == 4) {
            float2 next = complexSquare(z) + c + phoenix * previous;
            previous = z;
            z = next;
        } else {
            z = complexSquare(z) + c;
        }

        float orbit = dot(z, z);
        minOrbit = min(minOrbit, orbit);
        iteration = i;
        if (orbit > 16.0) {
            break;
        }
    }

    float escaped = dot(z, z) > 16.0 ? 1.0 : 0.0;
    float normalized = float(iteration) / float(maxIterations);
    float orbitGlow = exp(-minOrbit * (2.2 + u.glow * 4.8));
    float edge = escaped > 0.5 ? pow(1.0 - normalized, 0.72) : orbitGlow;
    float colorPhase = normalized * (1.8 + u.intensity * 2.4)
        + travel * (0.42 + u.motion)
        + treble * 0.55
        + beat * 0.18;
    float3 color = paletteGradient(u.palette, colorPhase);
    float contour = 0.5 + 0.5 * sin((normalized * 68.0) + travel * 18.0 + treble * 6.0);
    float brightness = 0.08
        + edge * (0.54 + u.glow * 0.42)
        + orbitGlow * (0.20 + bass * 0.30)
        + contour * treble * 0.13
        + beat * 0.10;
    float vignette = smoothstep(1.55, 0.20, length(point));
    color *= brightness * (0.55 + vignette * 0.62);
    color += paletteGradient(u.palette, colorPhase + 0.21) * orbitGlow * (0.10 + u.glow * 0.30);
    float filament = spectralFilament(point, u);
    color += paletteGradient(u.palette, colorPhase + 0.38) * filament * (0.09 + treble * 0.18 + u.glow * 0.08);
    color += paletteGradient(u.palette, colorPhase + 0.62) * transientDust(point, u);
    return float4(clamp(color, 0.0, 1.0), 1.0);
}

fragment half4 spectra_fractal_fragment(VertexOut input [[stage_in]],
                                        constant FractalUniforms &uniforms [[buffer(0)]]) {
    float2 size = max(uniforms.resolution, float2(1.0));
    float2 uv = input.position.xy / size;
    float2 point = (uv - 0.5) * 2.0;
    point.x *= size.x / size.y;
    return half4(iterateFractal(point, uniforms));
}
