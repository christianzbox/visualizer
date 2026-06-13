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

float terrainHeight(float2 p, constant FractalUniforms &u) {
    float height = 0.0;
    float amplitude = 0.46;
    float frequency = 0.42;
    for (int octave = 0; octave < 6; octave++) {
        float wave = sin(p.x * frequency + u.time * 0.13 + u.mid * 1.8)
            * cos(p.y * frequency * 0.82 - u.time * 0.10 + u.bass * 2.2);
        float cell = hash21(floor(p * frequency * 1.7));
        height += (wave * 0.74 + (cell - 0.5) * 0.52) * amplitude;
        amplitude *= 0.50;
        frequency *= 2.03;
    }
    return height * (0.30 + u.intensity * 0.34) + u.bass * 0.12;
}

float4 terrainFlight(float2 point, constant FractalUniforms &u) {
    float speed = 1.20 + u.motion * 3.0 + u.volume * 0.85 + u.beat * 0.70;
    float travel = u.time * speed;
    float3 camera = float3(sin(travel * 0.10) * 1.3, 0.58 + u.volume * 0.36 + u.bass * 0.20, travel);
    float3 ray = normalize(float3(point.x * 0.92, point.y * 0.62 - 0.10 + u.mid * 0.08, 1.34));
    ray.xz = rotate2(ray.xz, sin(travel * 0.07) * 0.18 + u.mid * 0.08);

    float3 color = paletteGradient(u.palette, 0.60 + point.y * 0.12) * (0.10 + u.volume * 0.10);
    float closest = 10.0;
    float hitAmount = 0.0;
    float t = 0.08;
    for (int i = 0; i < 64; i++) {
        float3 pos = camera + ray * t;
        float height = terrainHeight(pos.xz, u);
        float distanceToGround = pos.y - height;
        closest = min(closest, abs(distanceToGround));
        if (distanceToGround < 0.018) {
            float eps = 0.035;
            float hx = terrainHeight(pos.xz + float2(eps, 0.0), u) - terrainHeight(pos.xz - float2(eps, 0.0), u);
            float hz = terrainHeight(pos.xz + float2(0.0, eps), u) - terrainHeight(pos.xz - float2(0.0, eps), u);
            float3 normal = normalize(float3(-hx, 0.08, -hz));
            float light = clamp(dot(normal, normalize(float3(-0.42, 0.74, -0.48))), 0.0, 1.0);
            float fog = exp(-t * (0.18 - u.glow * 0.05));
            float ridge = smoothstep(0.45, 1.0, light) + u.treble * 0.22 + u.beat * 0.18;
            color = paletteGradient(u.palette, 0.18 + height * 0.22 + t * 0.025)
                * (0.20 + light * 0.76 + ridge * 0.20)
                * fog;
            hitAmount = 1.0;
            break;
        }
        t += max(0.035, abs(distanceToGround) * 0.32 + t * 0.018);
    }

    float horizon = smoothstep(-0.12, 0.52, point.y + u.volume * 0.12);
    float glow = exp(-closest * (4.0 + u.glow * 6.0)) * (0.12 + u.bass * 0.30 + u.beat * 0.24);
    color += paletteGradient(u.palette, 0.78 + u.time * 0.05) * horizon * (0.08 + u.glow * 0.18);
    color += paletteGradient(u.palette, 0.32 + u.treble * 0.20) * glow;
    color += transientDust(point * 0.82, u) * paletteGradient(u.palette, 0.92);
    color *= 0.78 + hitAmount * 0.42;
    return float4(clamp(color, 0.0, 1.0), 1.0);
}

float mandelboxDensity(float3 p, constant FractalUniforms &u) {
    float3 z = p;
    float scale = -1.72 - u.bass * 0.22 + u.beat * 0.10;
    float orbit = 10.0;
    for (int i = 0; i < 9; i++) {
        z = clamp(z, -1.0, 1.0) * 2.0 - z;
        float r2 = dot(z, z);
        if (r2 < 0.35) {
            z *= 2.86;
        } else if (r2 < 1.0) {
            z /= r2;
        }
        z = z * scale + p;
        orbit = min(orbit, abs(length(z) - 1.0));
    }
    return exp(-orbit * (3.0 + u.glow * 5.0));
}

float4 mandelboxFlight(float2 point, constant FractalUniforms &u) {
    float travel = u.time * (0.65 + u.motion * 1.8 + u.volume * 0.70 + u.beat * 0.60);
    float3 ray = normalize(float3(point.x * 0.82, point.y * 0.72, 1.12));
    ray.xy = rotate2(ray.xy, sin(travel * 0.18) * 0.22 + u.mid * 0.16);
    float3 origin = float3(sin(travel * 0.21) * 0.35, cos(travel * 0.17) * 0.26, travel);

    float3 color = float3(0.0);
    float transmittance = 1.0;
    for (int i = 0; i < 54; i++) {
        float depth = float(i) * 0.060;
        float3 pos = origin + ray * depth;
        pos.xy = rotate2(pos.xy, depth * 0.18 + u.mid * 0.26);
        pos.z = fract(pos.z * 0.18) * 5.6 - 2.8;
        float density = mandelboxDensity(pos, u) * (0.055 + u.intensity * 0.055);
        float phase = depth * 0.10 + density * 1.6 + u.time * 0.05 + u.treble * 0.25;
        color += paletteGradient(u.palette, phase) * density * transmittance * (1.1 + u.beat * 0.7);
        transmittance *= 1.0 - density * 0.42;
        if (transmittance < 0.05) {
            break;
        }
    }

    float edge = spectralFilament(point * (1.0 + u.bass * 0.25), u);
    color += paletteGradient(u.palette, 0.65 + u.time * 0.07) * edge * (0.12 + u.glow * 0.20);
    color += paletteGradient(u.palette, 0.95) * transientDust(point, u) * 0.65;
    return float4(clamp(color, 0.0, 1.0), 1.0);
}

float4 nebulaVoyage(float2 point, constant FractalUniforms &u) {
    float radius = length(point);
    float angle = atan2(point.y, point.x);
    float speed = u.time * (0.55 + u.motion * 1.9 + u.volume * 0.65 + u.beat * 0.75);
    float3 color = float3(0.0);
    float fade = smoothstep(1.65, 0.08, radius);

    for (int layer = 0; layer < 7; layer++) {
        float lf = float(layer);
        float z = speed + lf * 0.72;
        float tunnel = sin(angle * (2.0 + lf * 0.45 + u.mid * 1.4) + z * 1.7)
            + cos(radius * (9.0 + lf * 2.4 + u.bass * 4.0) - z * 1.15);
        float band = smoothstep(0.35, 1.0, tunnel * 0.5 + 0.5);
        float depth = 1.0 / (1.0 + lf * 0.42 + radius * 0.65);
        color += paletteGradient(u.palette, lf * 0.12 + z * 0.06 + u.treble * 0.18)
            * band * depth * (0.055 + u.glow * 0.040 + u.volume * 0.032);
    }

    float core = exp(-abs(radius - (0.42 + u.bass * 0.10 + sin(speed * 0.5) * 0.04)) * (7.0 + u.glow * 7.0));
    float stars = transientDust(point * (1.4 + u.treble * 0.6), u);
    color += paletteGradient(u.palette, 0.22 + speed * 0.06) * core * (0.15 + u.beat * 0.20);
    color += paletteGradient(u.palette, 0.84 + u.treble * 0.18) * stars * 0.85;
    color *= fade * (0.90 + u.intensity * 0.35);
    return float4(clamp(color, 0.0, 1.0), 1.0);
}

float4 iterateFractal(float2 point, constant FractalUniforms &u) {
    if (u.mode == 5) {
        return mandelboxFlight(point, u);
    }
    if (u.mode == 6) {
        return terrainFlight(point, u);
    }
    if (u.mode == 7) {
        return nebulaVoyage(point, u);
    }

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
