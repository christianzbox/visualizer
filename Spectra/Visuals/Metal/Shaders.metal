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

struct TerrainVertex {
    float4 position;
    float4 normal;
    float4 color;
};

struct TerrainUniforms {
    float4x4 viewProjectionMatrix;
    float4 cameraPosition;
    float4 lightDirection;
    float4 fogColor;
    float4 audio;
    float fogStart;
    float fogEnd;
    float time;
    uint palette;
};

struct TerrainOut {
    float4 position [[position]];
    float3 worldPosition;
    float3 normal;
    float4 color;
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

vertex TerrainOut terrain_vertex(uint vertexID [[vertex_id]],
                                 constant TerrainVertex *vertices [[buffer(0)]],
                                 constant TerrainUniforms &uniforms [[buffer(1)]]) {
    TerrainVertex inputVertex = vertices[vertexID];
    TerrainOut out;
    float4 world = float4(inputVertex.position.xyz, 1.0);
    out.position = uniforms.viewProjectionMatrix * world;
    out.worldPosition = inputVertex.position.xyz;
    out.normal = normalize(inputVertex.normal.xyz);
    out.color = inputVertex.color;
    return out;
}

fragment half4 terrain_fragment(TerrainOut input [[stage_in]],
                                constant TerrainUniforms &uniforms [[buffer(0)]]) {
    float3 normal = normalize(input.normal);
    float3 lightDirection = normalize(uniforms.lightDirection.xyz);
    float3 viewDirection = normalize(uniforms.cameraPosition.xyz - input.worldPosition);
    float diffuse = clamp(dot(normal, lightDirection), 0.0, 1.0);
    float halfLambert = diffuse * 0.5 + 0.5;
    float rim = pow(clamp(1.0 - dot(normal, viewDirection), 0.0, 1.0), 2.0);
    float distanceFromCamera = distance(uniforms.cameraPosition.xyz, input.worldPosition);
    float fog = smoothstep(uniforms.fogStart, uniforms.fogEnd, distanceFromCamera);
    float3 paletteLight = paletteGradient(uniforms.palette, 0.68 + uniforms.time * 0.018 + uniforms.audio.z * 0.08);
    float audioGlow = uniforms.audio.x * 0.055 + uniforms.audio.y * 0.070 + uniforms.audio.w * 0.045;
    float3 color = input.color.rgb * (0.24 + halfLambert * 0.86);
    color += paletteLight * (rim * (0.08 + uniforms.audio.z * 0.08) + audioGlow);
    color += paletteGradient(uniforms.palette, 0.36) * pow(diffuse, 6.0) * (0.05 + uniforms.audio.y * 0.06);
    color = lerp3(color, uniforms.fogColor.rgb, fog * 0.86);
    color = pow(max(color, float3(0.0)), float3(0.92));
    return half4(float4(clamp(color, 0.0, 1.0), 1.0));
}

float hash21(float2 p) {
    p = fract(p * float2(123.34, 456.21));
    p += dot(p, p + 45.32);
    return fract(p.x * p.y);
}

float lerp1(float a, float b, float t) {
    return a + (b - a) * clamp(t, 0.0, 1.0);
}

float valueNoise(float2 p) {
    float2 i = floor(p);
    float2 f = fract(p);
    f = f * f * (3.0 - 2.0 * f);
    float a = hash21(i);
    float b = hash21(i + float2(1.0, 0.0));
    float c = hash21(i + float2(0.0, 1.0));
    float d = hash21(i + float2(1.0, 1.0));
    float x0 = lerp1(a, b, f.x);
    float x1 = lerp1(c, d, f.x);
    return lerp1(x0, x1, f.y);
}

float fbm2(float2 p) {
    float value = 0.0;
    float amplitude = 0.5;
    for (int octave = 0; octave < 5; octave++) {
        value += valueNoise(p) * amplitude;
        p = rotate2(p * 2.03 + float2(17.31, 9.17), 0.47);
        amplitude *= 0.52;
    }
    return value;
}

float ridgedFbm(float2 p) {
    float value = 0.0;
    float amplitude = 0.56;
    for (int octave = 0; octave < 5; octave++) {
        float ridge = 1.0 - abs(valueNoise(p) * 2.0 - 1.0);
        value += ridge * ridge * amplitude;
        p = rotate2(p * 2.11 + float2(5.13, 13.71), -0.38);
        amplitude *= 0.50;
    }
    return value;
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
    float2 drift = float2(sin(u.time * 0.045), cos(u.time * 0.038)) * (0.24 + u.motion * 0.22);
    float broad = fbm2(p * 0.34 + drift);
    float ridges = ridgedFbm(p * 0.78 + float2(0.0, u.time * 0.035));
    float detail = fbm2(p * 2.15 + broad * 1.2);
    float valley = exp(-abs(p.x + sin(p.y * 0.18 + u.time * 0.08) * 1.15) * 0.42);
    float terraces = sin((broad * 2.8 + ridges * 1.6 + p.y * 0.035) * 6.0) * 0.020;
    float mountain = pow(max(ridges, 0.0), 1.42) * 1.22 + broad * 0.62 + detail * 0.16;
    mountain -= valley * (0.18 + u.volume * 0.08);
    return (mountain - 0.74) * (0.48 + u.intensity * 0.34) + terraces + u.bass * 0.055;
}

float4 terrainFlight(float2 point, constant FractalUniforms &u) {
    float speed = 0.72 + u.motion * 1.55 + u.volume * 0.30 + u.beat * 0.22;
    float travel = u.time * speed;
    float3 camera = float3(
        sin(travel * 0.18) * 1.8 + sin(travel * 0.051) * 2.5,
        0.74 + u.volume * 0.18 + u.bass * 0.10,
        travel * 2.7
    );
    float3 ray = normalize(float3(point.x * 0.94, point.y * 0.66 - 0.18 + u.mid * 0.035, 1.42));
    ray.xz = rotate2(ray.xz, sin(travel * 0.073) * 0.24 + u.mid * 0.04);

    float3 skyLow = paletteGradient(u.palette, 0.56 + point.y * 0.08) * 0.22;
    float3 skyHigh = paletteGradient(u.palette, 0.84 + u.time * 0.018) * 0.12 + float3(0.015, 0.020, 0.035);
    float skyMix = smoothstep(-0.65, 0.85, point.y);
    float3 color = lerp3(skyLow, skyHigh, skyMix);
    float2 sunPos = float2(0.52 + sin(u.time * 0.025) * 0.16, 0.42 + cos(u.time * 0.021) * 0.06);
    float sun = exp(-length(point - sunPos) * 5.2);
    color += paletteGradient(u.palette, 0.11) * sun * (0.18 + u.glow * 0.18);

    float closest = 10.0;
    float hitAmount = 0.0;
    float t = 0.08;
    float hitHeight = 0.0;
    float3 hitPosition = camera;
    for (int i = 0; i < 78; i++) {
        float3 pos = camera + ray * t;
        float height = terrainHeight(pos.xz, u);
        float distanceToGround = pos.y - height;
        closest = min(closest, abs(distanceToGround));
        if (distanceToGround < 0.012) {
            float eps = 0.045;
            float hx = terrainHeight(pos.xz + float2(eps, 0.0), u) - terrainHeight(pos.xz - float2(eps, 0.0), u);
            float hz = terrainHeight(pos.xz + float2(0.0, eps), u) - terrainHeight(pos.xz - float2(0.0, eps), u);
            float3 normal = normalize(float3(-hx, 0.12, -hz));
            float3 lightDirection = normalize(float3(-0.58, 0.78, -0.34));
            float light = clamp(dot(normal, lightDirection), 0.0, 1.0);
            float rim = pow(clamp(dot(normal, normalize(float3(0.44, 0.36, -0.80))), 0.0, 1.0), 2.0);
            float fog = exp(-t * (0.105 - u.glow * 0.025));
            float ridgeLight = smoothstep(0.42, 0.95, light) + u.treble * 0.12 + u.beat * 0.08;
            float snow = smoothstep(0.45, 1.05, height + ridgedFbm(pos.xz * 1.4) * 0.18);
            float river = exp(-abs(pos.x + sin(pos.z * 0.18) * 0.95) * 2.5) * smoothstep(0.38, -0.20, height);
            float path = exp(-abs(pos.x - sin(pos.z * 0.11 + 1.7) * 1.3) * 1.55) * smoothstep(0.42, -0.08, height);
            float3 ground = paletteGradient(u.palette, 0.18 + height * 0.30 + t * 0.018) * (0.24 + light * 0.80 + ridgeLight * 0.16);
            float3 snowColor = float3(0.72, 0.82, 0.86) * (0.35 + light * 0.70);
            float3 waterColor = paletteGradient(u.palette, 0.58 + u.time * 0.020) * (0.42 + rim * 0.50 + u.glow * 0.16);
            color = lerp3(ground, snowColor, snow * 0.42);
            color = lerp3(color, waterColor, river * (0.36 + u.glow * 0.20));
            color += paletteGradient(u.palette, 0.30) * path * (0.08 + u.bass * 0.08);
            color += paletteGradient(u.palette, 0.72) * rim * (0.12 + u.glow * 0.20);
            color *= fog;
            hitHeight = height;
            hitPosition = pos;
            hitAmount = 1.0;
            break;
        }
        t += max(0.030, abs(distanceToGround) * 0.40 + t * 0.014);
    }

    float horizon = smoothstep(-0.18, 0.58, point.y + u.volume * 0.06);
    float glow = exp(-closest * (5.2 + u.glow * 7.0)) * (0.08 + u.bass * 0.18 + u.beat * 0.10);
    float cloud = smoothstep(0.54, 0.90, fbm2(point * float2(2.1, 0.8) + float2(travel * 0.035, u.time * 0.015)));
    color += paletteGradient(u.palette, 0.78 + u.time * 0.035) * horizon * (0.06 + u.glow * 0.13);
    color += paletteGradient(u.palette, 0.32 + u.treble * 0.20) * glow;
    color += cloud * (1.0 - hitAmount) * paletteGradient(u.palette, 0.68) * 0.09;
    color += transientDust(point * 0.74, u) * paletteGradient(u.palette, 0.92) * 0.55;
    color *= 0.82 + hitAmount * 0.34;
    color = pow(max(color, float3(0.0)), float3(0.92));
    color += paletteGradient(u.palette, 0.46 + hitHeight * 0.10) * exp(-length(hitPosition.xz - camera.xz) * 0.075) * hitAmount * 0.035;
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

float4 skyRealmFlight(float2 point, constant FractalUniforms &u) {
    float travel = u.time * (0.34 + u.motion * 0.70 + u.volume * 0.12 + u.beat * 0.10);
    float2 skyPoint = point + float2(sin(travel * 0.11) * 0.10, cos(travel * 0.07) * 0.035);
    float3 horizon = paletteGradient(u.palette, 0.56 + skyPoint.y * 0.08) * 0.24 + float3(0.015, 0.020, 0.038);
    float3 zenith = paletteGradient(u.palette, 0.82 + u.time * 0.018) * 0.11 + float3(0.010, 0.018, 0.034);
    float3 color = lerp3(horizon, zenith, smoothstep(-0.75, 0.95, skyPoint.y));

    float2 sunPosition = float2(0.48 + sin(u.time * 0.020) * 0.12, 0.34 + cos(u.time * 0.018) * 0.08);
    float sun = exp(-length(point - sunPosition) * 5.6);
    float halo = exp(-length(point - sunPosition) * 1.6);
    color += paletteGradient(u.palette, 0.12) * sun * (0.30 + u.glow * 0.28);
    color += paletteGradient(u.palette, 0.18) * halo * 0.055;

    float cloud = fbm2(point * float2(1.8, 0.72) + float2(travel * 0.08, u.time * 0.018));
    float cloudMask = smoothstep(0.48, 0.82, cloud + smoothstep(0.20, 0.92, point.y) * 0.25);
    color += cloudMask * paletteGradient(u.palette, 0.66) * (0.055 + u.glow * 0.035);

    for (int layer = 0; layer < 10; layer++) {
        float lf = float(layer);
        float depth = 1.0 + lf * 0.62;
        float lane = fract(travel * (0.16 + lf * 0.010) + lf * 0.173);
        float z = 0.42 + lane * 3.2;
        float scale = 1.0 / z;
        float2 center = float2(
            sin(lf * 2.17 + travel * 0.19) * (0.52 + lf * 0.040),
            -0.34 + sin(lf * 1.31 + travel * 0.13) * 0.20 + (1.0 - lane) * 0.38
        ) * scale;
        float islandSize = (0.22 + hash21(float2(lf, 4.2)) * 0.20) * scale;
        float2 local = (point - center) / max(islandSize, 0.001);
        local.x += sin(local.y * 2.4 + lf) * 0.11;
        float landNoise = ridgedFbm(local * 1.75 + lf);
        float body = smoothstep(0.90, 0.42, length(local * float2(0.92, 1.42)) + landNoise * 0.20);
        float top = body * smoothstep(-0.20, 0.22, local.y + landNoise * 0.12);
        float underside = body * smoothstep(0.28, -0.38, local.y);
        float grass = smoothstep(-0.05, 0.38, local.y + landNoise * 0.10);
        float fog = exp(-depth * 0.16);
        float3 rock = paletteGradient(u.palette, 0.22 + landNoise * 0.20) * (0.26 + fog * 0.28);
        float3 meadow = paletteGradient(u.palette, 0.42 + landNoise * 0.13) * (0.36 + fog * 0.34 + u.bass * 0.06);
        float3 islandColor = lerp3(rock, meadow, grass);
        islandColor += paletteGradient(u.palette, 0.72) * underside * (0.08 + u.glow * 0.08);
        color = lerp3(color, islandColor, clamp((top + underside * 0.82) * fog, 0.0, 0.78));

        float towerBase = smoothstep(0.055, 0.018, abs(local.x + sin(lf) * 0.15));
        float towerHeight = smoothstep(-0.10, 0.54, local.y) * smoothstep(1.10, 0.42, local.y);
        float spire = towerBase * towerHeight * top * step(0.54, hash21(float2(lf, 8.3)));
        color += paletteGradient(u.palette, 0.88 + lf * 0.03) * spire * fog * (0.22 + u.glow * 0.20);
    }

    float aurora = spectralFilament(point * float2(0.75, 1.18) + float2(0.0, 0.18), u);
    color += paletteGradient(u.palette, 0.78 + u.time * 0.025) * aurora * (0.07 + u.treble * 0.08 + u.glow * 0.06);
    color += transientDust(point * 0.68, u) * paletteGradient(u.palette, 0.95) * 0.42;
    color = pow(max(color, float3(0.0)), float3(0.90));
    return float4(clamp(color, 0.0, 1.0), 1.0);
}

float crystalFacet(float2 p, float angle, float sharpness) {
    float2 q = rotate2(p, angle);
    float diamond = max(abs(q.x) * 0.72 + abs(q.y) * 1.18, abs(q.x + q.y) * 0.52);
    return 1.0 - smoothstep(sharpness, 1.0, diamond);
}

float4 crystalCavern(float2 point, constant FractalUniforms &u) {
    float travel = u.time * (0.42 + u.motion * 0.78 + u.volume * 0.16 + u.beat * 0.10);
    float radius = length(point * float2(0.92, 1.08));
    float angle = atan2(point.y, point.x);
    float tunnel = smoothstep(0.08, 1.34, radius);
    float3 color = float3(0.006, 0.008, 0.015) + paletteGradient(u.palette, 0.62 + point.y * 0.08) * 0.050;

    float wallNoise = ridgedFbm(float2(angle * 1.7, radius * 3.4 - travel * 0.55));
    float wall = smoothstep(0.34, 1.05, radius + wallNoise * 0.16);
    color += paletteGradient(u.palette, 0.18 + wallNoise * 0.32) * wall * (0.11 + u.glow * 0.10);

    for (int layer = 0; layer < 13; layer++) {
        float lf = float(layer);
        float depth = fract(travel * (0.18 + lf * 0.004) + lf * 0.137);
        float scale = 0.30 + depth * 2.55;
        float side = (hash21(float2(lf, 2.0)) < 0.5) ? -1.0 : 1.0;
        float lane = side * (0.54 + hash21(float2(lf, 5.0)) * 0.56);
        float y = -0.22 + sin(lf * 1.9 + travel * 0.36) * 0.42;
        float2 center = float2(lane / scale, y / scale);
        float crystalSize = (0.18 + hash21(float2(lf, 9.0)) * 0.18) / scale;
        float2 local = (point - center) / max(crystalSize, 0.001);
        float facet = crystalFacet(local, lf * 0.41 + travel * 0.035, 0.46);
        float core = crystalFacet(local * 1.45 + float2(0.12, -0.08), -lf * 0.22, 0.38);
        float edge = smoothstep(0.40, 1.00, facet) - smoothstep(0.72, 1.00, facet);
        float fog = exp(-scale * 0.17);
        float sparkle = smoothstep(0.70, 0.98, valueNoise(local * 4.0 + lf + u.time * 0.15));
        float3 crystal = paletteGradient(u.palette, 0.50 + lf * 0.055 + u.treble * 0.08)
            * (0.22 + core * 0.38 + edge * 0.55 + sparkle * u.treble * 0.20);
        color += crystal * facet * fog * (0.72 + u.glow * 0.42 + u.beat * 0.18);
    }

    float path = exp(-abs(point.y + 0.72 + sin(point.x * 3.4 + travel) * 0.025) * 9.0) * smoothstep(0.92, 0.08, abs(point.x));
    float rune = smoothstep(0.94, 1.0, sin(point.x * 34.0 + travel * 2.6) * 0.5 + 0.5) * path;
    color += paletteGradient(u.palette, 0.76 + u.time * 0.025) * path * (0.08 + u.bass * 0.10);
    color += paletteGradient(u.palette, 0.92) * rune * (0.20 + u.glow * 0.18);

    float centerGlow = exp(-radius * (2.2 + u.glow * 1.6));
    color += paletteGradient(u.palette, 0.60 + u.time * 0.020) * centerGlow * (0.08 + u.volume * 0.08);
    color += spectralFilament(point * 0.95, u) * paletteGradient(u.palette, 0.83) * (0.05 + u.treble * 0.08);
    color += transientDust(point * 1.1, u) * paletteGradient(u.palette, 0.98) * 0.45;
    color *= smoothstep(1.55, 0.08, radius) * 0.72 + wall * 0.42;
    color = pow(max(color, float3(0.0)), float3(0.88));
    return float4(clamp(color, 0.0, 1.0), 1.0);
}

float lineBand(float value, float width) {
    return 1.0 - smoothstep(width, width * 2.35, abs(value));
}

float softRect(float2 p, float2 center, float2 halfSize, float feather) {
    float2 d = abs(p - center) - halfSize;
    float outside = length(max(d, float2(0.0)));
    return 1.0 - smoothstep(0.0, feather, outside);
}

float ringBand(float radius, float target, float width) {
    return 1.0 - smoothstep(width, width * 2.2, abs(radius - target));
}

float audioDrive(constant FractalUniforms &u) {
    return clamp(max(u.volume, sqrt(max(u.rms, 0.0)) * 0.82) * (0.72 + u.sensitivity), 0.0, 1.0);
}

float4 underwaterReefShader(float2 point, constant FractalUniforms &u) {
    float audio = audioDrive(u);
    float travel = u.time * (0.10 + u.motion * 0.26);
    float depth = smoothstep(0.95, -0.85, point.y);
    float3 color = lerp3(float3(0.006, 0.030, 0.052), float3(0.015, 0.185, 0.210), depth);
    float caustics = pow(abs(sin((point.x + sin(point.y * 2.4 + travel) * 0.18) * 16.0 + travel * 4.0)), 12.0);
    caustics += pow(abs(sin((point.x * 0.65 - point.y * 0.42) * 21.0 - travel * 3.2)), 14.0);
    color += paletteGradient(u.palette, 0.20 + point.y * 0.10) * caustics * (0.060 + u.treble * 0.14 + u.glow * 0.06);

    float2 sonarOrigin = float2(sin(travel * 0.8) * 0.24, -0.12 + cos(travel * 0.6) * 0.08);
    float sonarRadius = fract(length(point - sonarOrigin) * 1.15 - travel * (0.75 + audio * 0.35));
    float sonar = ringBand(sonarRadius, 0.55, 0.010 + u.beat * 0.010);
    color += paletteGradient(u.palette, 0.58 + u.time * 0.018) * sonar * (0.13 + u.mid * 0.18);

    float reef = 0.0;
    for (int i = 0; i < 15; i++) {
        float fi = float(i);
        float x = -1.55 + fi * 0.22 + sin(fi * 3.1) * 0.045;
        float height = 0.16 + hash21(float2(fi, 4.4)) * 0.38 + u.bass * 0.07;
        float stem = lineBand(point.x - x - sin(point.y * 7.0 + fi + travel) * 0.025, 0.010 + height * 0.010);
        float plant = stem * smoothstep(-0.98, -0.44 + height, point.y) * smoothstep(-0.15 + height, -0.82, point.y);
        reef += plant * (0.35 + hash21(float2(fi, 1.1)) * 0.65);
    }
    color = lerp3(color, float3(0.004, 0.025, 0.020), clamp(reef, 0.0, 0.82));

    for (int i = 0; i < 20; i++) {
        float fi = float(i);
        float seed = hash21(float2(fi, 7.7));
        float x = -1.55 + seed * 3.10 + sin(travel + fi) * 0.045;
        float y = -1.04 + fract(seed + u.time * (0.025 + seed * 0.045) + u.treble * 0.015) * 2.10;
        float bubble = 1.0 - smoothstep(0.012, 0.034 + seed * 0.030, length(point - float2(x, y)));
        color += paletteGradient(u.palette, 0.72 + seed * 0.18) * bubble * (0.10 + u.treble * 0.16 + u.beat * 0.08);
    }
    float vignette = smoothstep(1.55, 0.18, length(point * float2(0.82, 1.1)));
    color *= 0.70 + vignette * 0.58;
    return float4(clamp(pow(max(color, float3(0.0)), float3(0.90)), 0.0, 1.0), 1.0);
}

float4 subwayRushShader(float2 point, constant FractalUniforms &u) {
    float audio = audioDrive(u);
    float beat = clamp(u.beat * u.beatReactivity, 0.0, 1.0);
    float travel = u.time * (0.44 + u.motion * 1.15 + audio * 0.28);
    float2 p = point + float2(sin(travel * 0.17) * 0.025, 0.02);
    float3 color = float3(0.010, 0.012, 0.017);
    float2 v = p - float2(0.0, 0.18);
    float depth = clamp(-v.y, 0.0, 1.45);
    float wall = lineBand(abs(v.x) - (0.18 + depth * 0.72), 0.014);
    float ceiling = lineBand(v.y + 0.26 + abs(v.x) * 0.20, 0.012);
    float floorLine = lineBand(v.y + 0.86 - abs(v.x) * 0.16, 0.014);
    color += paletteGradient(u.palette, 0.60) * (wall + ceiling * 0.8 + floorLine) * (0.09 + u.glow * 0.11);

    float lane = fract(depth * 7.0 + travel * 2.35);
    float sleepers = lineBand(lane - 0.18, 0.018) * smoothstep(0.02, 0.95, depth);
    float rails = lineBand(abs(p.x) - (0.10 + depth * 0.18), 0.010) * smoothstep(0.0, 0.9, depth);
    color += paletteGradient(u.palette, 0.78 + lane * 0.10) * (sleepers * 0.22 + rails * (0.30 + beat * 0.16));

    for (int i = 0; i < 13; i++) {
        float fi = float(i);
        float z = fract(fi * 0.077 + travel * 0.31);
        float y = 0.12 - z * 1.25;
        float spread = 0.20 + z * 0.88;
        float side = (hash21(float2(fi, 1.0)) < 0.5) ? -1.0 : 1.0;
        float light = softRect(p, float2(side * spread, y), float2(0.030 + z * 0.040, 0.018 + z * 0.030), 0.030);
        color += paletteGradient(u.palette, 0.12 + fi * 0.06) * light * (0.26 + u.treble * 0.22 + beat * 0.16);
    }

    float trainX = sin(travel * 0.44) * 0.82;
    float train = softRect(p, float2(trainX, -0.24), float2(0.22 + beat * 0.05, 0.58), 0.040);
    float windows = smoothstep(0.80, 1.0, sin((p.y + travel) * 42.0) * sin((p.x - trainX) * 24.0) * 0.5 + 0.5);
    color += train * float3(0.020, 0.024, 0.030);
    color += train * windows * paletteGradient(u.palette, 0.35 + u.time * 0.015) * (0.20 + u.mid * 0.18);
    color += transientDust(p * 1.2, u) * paletteGradient(u.palette, 0.94) * 0.32;
    return float4(clamp(pow(max(color, float3(0.0)), float3(0.88)), 0.0, 1.0), 1.0);
}

float4 vinylOrbitShader(float2 point, constant FractalUniforms &u) {
    float audio = audioDrive(u);
    float beat = clamp(u.beat * u.beatReactivity, 0.0, 1.0);
    float spin = u.time * (0.22 + u.motion * 0.60);
    float2 p = rotate2(point, spin);
    float radius = length(p);
    float angle = atan2(p.y, p.x);
    float disc = smoothstep(1.12, 0.24, radius);
    float grooves = smoothstep(0.78, 1.0, sin(radius * (155.0 + u.bass * 24.0) - spin * 8.0) * 0.5 + 0.5);
    float shimmer = smoothstep(0.90, 1.0, sin(angle * 18.0 + radius * 12.0 + spin * 3.0) * 0.5 + 0.5);
    float3 color = float3(0.005, 0.004, 0.006) + paletteGradient(u.palette, 0.10 + radius * 0.24) * disc * (0.045 + grooves * 0.090 + shimmer * u.treble * 0.12);
    float label = smoothstep(0.30, 0.26, radius);
    color = lerp3(color, paletteGradient(u.palette, 0.42 + sin(spin) * 0.08) * (0.30 + audio * 0.12), label);
    color += ringBand(radius, 0.30 + beat * 0.02, 0.010) * paletteGradient(u.palette, 0.76) * 0.22;
    color += ringBand(radius, 0.74 + u.bass * 0.03, 0.006) * paletteGradient(u.palette, 0.90) * 0.12;

    float2 arm = rotate2(point - float2(0.58, 0.34), -0.48 - u.mid * 0.16);
    float tonearm = softRect(arm, float2(-0.22, 0.0), float2(0.46, 0.012), 0.016);
    float stylus = 1.0 - smoothstep(0.012, 0.050, length(arm - float2(-0.70, -0.025)));
    color += paletteGradient(u.palette, 0.84) * (tonearm * 0.24 + stylus * (0.46 + beat * 0.28));
    color += transientDust(point * 1.15 + float2(spin * 0.08, 0.0), u) * paletteGradient(u.palette, 0.98) * 0.45;
    color *= smoothstep(1.35, 0.14, radius) * 0.75 + disc * 0.30;
    return float4(clamp(pow(max(color, float3(0.0)), float3(0.86)), 0.0, 1.0), 1.0);
}

float4 rainWindowShader(float2 point, constant FractalUniforms &u) {
    float audio = audioDrive(u);
    float aspect = max(u.resolution.x / max(u.resolution.y, 1.0), 1.0);
    float2 uv = float2(point.x / aspect, point.y) * 0.5 + 0.5;
    float drift = u.time * (0.055 + u.motion * 0.14);
    float3 color = lerp3(float3(0.004, 0.006, 0.010), float3(0.020, 0.032, 0.050), smoothstep(-0.8, 0.8, point.y));

    for (int i = 0; i < 22; i++) {
        float fi = float(i);
        float lane = -aspect + (fi + 0.5) * (aspect * 2.0 / 22.0);
        float width = aspect * (0.032 + hash21(float2(fi, 2.3)) * 0.035);
        float height = 0.20 + hash21(float2(fi, 8.1)) * 0.72 + audio * 0.16;
        float building = softRect(point, float2(lane, -0.93 + height * 0.5), float2(width, height * 0.5), 0.035);
        float windows = smoothstep(0.88, 1.0, sin((point.y + fi) * 42.0) * sin((point.x - lane) * 38.0) * 0.5 + 0.5);
        float blur = 0.32 + hash21(float2(fi, 4.0)) * 0.32;
        color += paletteGradient(u.palette, blur + fi * 0.015) * building * (0.035 + windows * (0.12 + u.mid * 0.10));
    }

    float pane = lineBand(fract(uv.x * 3.0) - 0.5, 0.010) + lineBand(fract(uv.y * 2.0) - 0.5, 0.010);
    color += paletteGradient(u.palette, 0.68) * pane * 0.045;
    for (int i = 0; i < 26; i++) {
        float fi = float(i);
        float seed = hash21(float2(fi, 11.7));
        float x = fract(seed + sin(fi * 2.0) * 0.17);
        float y = fract(uv.y * (1.15 + seed * 0.75) + drift * (0.55 + seed) + seed);
        float wobble = sin(y * 17.0 + fi + u.time * 0.5) * 0.012;
        float streak = lineBand(uv.x - x - wobble, 0.0025 + seed * 0.0035)
            * smoothstep(0.02, 0.18, y)
            * smoothstep(0.92, 0.36, y);
        color += paletteGradient(u.palette, 0.78 + seed * 0.14) * streak * (0.17 + u.treble * 0.22 + u.beat * 0.10);
    }
    float smear = fbm2(float2(uv.x * 6.0, uv.y * 11.0 + drift * 5.0));
    color += paletteGradient(u.palette, 0.55 + smear * 0.20) * smear * (0.018 + u.glow * 0.018);
    return float4(clamp(pow(max(color, float3(0.0)), float3(0.82)), 0.0, 1.0), 1.0);
}

float4 moonBaseShader(float2 point, constant FractalUniforms &u) {
    float beat = clamp(u.beat * u.beatReactivity, 0.0, 1.0);
    float travel = u.time * (0.025 + u.motion * 0.070);
    float sky = smoothstep(-0.10, 1.0, point.y);
    float3 color = lerp3(float3(0.006, 0.007, 0.012), float3(0.032, 0.037, 0.052), sky);
    float horizon = smoothstep(-0.12, -0.36, point.y);
    color += float3(0.055, 0.056, 0.062) * horizon;

    for (int i = 0; i < 45; i++) {
        float fi = float(i);
        float2 star = float2(-1.65 + hash21(float2(fi, 1.2)) * 3.30, -0.02 + hash21(float2(fi, 8.5)) * 1.15);
        float twinkle = 0.6 + 0.4 * sin(u.time * (0.4 + hash21(float2(fi, 4.0))) + fi);
        float dot = 1.0 - smoothstep(0.002, 0.010 + hash21(float2(fi, 2.0)) * 0.008, length(point - star));
        color += paletteGradient(u.palette, 0.70 + fi * 0.01) * dot * twinkle * (0.10 + u.treble * 0.12);
    }

    for (int i = 0; i < 14; i++) {
        float fi = float(i);
        float2 c = float2(-1.45 + fi * 0.23 + sin(fi) * 0.05 + travel, -0.78 + hash21(float2(fi, 3.1)) * 0.38);
        c.x = fmod(c.x + 1.75, 3.5) - 1.75;
        float r = 0.035 + hash21(float2(fi, 9.4)) * 0.070;
        float crater = ringBand(length(point - c), r, 0.006 + r * 0.15);
        color += float3(0.025, 0.026, 0.030) * crater * (0.5 + u.bass * 0.6);
    }

    float base = softRect(point, float2(-0.18, -0.39), float2(0.38, 0.075), 0.025);
    float dome = 1.0 - smoothstep(0.21, 0.225, length((point - float2(0.26, -0.34)) * float2(1.0, 1.7)));
    dome *= smoothstep(-0.52, -0.28, point.y);
    float antenna = lineBand(point.x + 0.54, 0.006) * smoothstep(-0.30, 0.12, point.y) * smoothstep(0.36, -0.08, point.y);
    color += float3(0.075, 0.078, 0.086) * (base + dome * 0.8);
    color += paletteGradient(u.palette, 0.62 + u.time * 0.02) * (antenna + ringBand(length(point - float2(-0.54, 0.17)), 0.08 + beat * 0.025, 0.006)) * (0.18 + u.glow * 0.16);
    float scan = lineBand(fract((point.y + 0.9) * 9.0 - u.time * 0.32) - 0.5, 0.010);
    color += paletteGradient(u.palette, 0.86) * scan * horizon * (0.035 + beat * 0.070);
    return float4(clamp(pow(max(color, float3(0.0)), float3(0.90)), 0.0, 1.0), 1.0);
}

float4 danceFloorShader(float2 point, constant FractalUniforms &u) {
    float audio = audioDrive(u);
    float beat = clamp(u.beat * u.beatReactivity, 0.0, 1.0);
    float travel = u.time * (0.18 + u.motion * 0.44);
    float3 color = float3(0.006, 0.004, 0.010);
    float floorDepth = smoothstep(-0.15, -0.95, point.y);
    float2 tile = float2(point.x / max(0.18, -point.y + 0.28), -point.y * 4.0 + travel * 1.4);
    float tileLines = lineBand(fract(tile.x * 4.0) - 0.5, 0.018) + lineBand(fract(tile.y) - 0.5, 0.018);
    color += paletteGradient(u.palette, 0.16 + tile.y * 0.04) * tileLines * floorDepth * (0.10 + beat * 0.22);

    for (int i = 0; i < 5; i++) {
        float fi = float(i);
        float originX = -1.0 + fi * 0.5;
        float2 q = rotate2(point - float2(originX, 1.05), -0.34 + fi * 0.17 + sin(travel + fi) * 0.08);
        float cone = smoothstep(0.0, -1.65, q.y) * smoothstep(0.36 + audio * 0.12, 0.02, abs(q.x) / max(abs(q.y), 0.08));
        color += paletteGradient(u.palette, 0.24 + fi * 0.17 + u.time * 0.018) * cone * (0.07 + u.glow * 0.09 + u.mid * 0.08);
    }

    for (int i = 0; i < 9; i++) {
        float fi = float(i);
        float x = -1.20 + fi * 0.30 + sin(fi * 1.7) * 0.035;
        float bob = sin(travel * 2.4 + fi) * (0.015 + audio * 0.025);
        float body = softRect(point, float2(x, -0.66 + bob), float2(0.045 + hash21(float2(fi, 1.0)) * 0.030, 0.20), 0.030);
        float head = 1.0 - smoothstep(0.035, 0.072, length(point - float2(x, -0.40 + bob)));
        float arm = lineBand(point.y + 0.49 - sin((point.x - x) * 14.0 + fi) * 0.025, 0.012) * smoothstep(0.18, 0.02, abs(point.x - x));
        float silhouette = clamp(body + head + arm * 0.7, 0.0, 1.0);
        color = lerp3(color, float3(0.000, 0.000, 0.003), silhouette * 0.88);
        color += paletteGradient(u.palette, 0.72 + fi * 0.04) * head * (0.035 + beat * 0.045);
    }
    float strobe = smoothstep(0.92 - beat * 0.12, 1.0, sin(u.time * 7.0) * 0.5 + 0.5);
    color += paletteGradient(u.palette, 0.92) * strobe * (0.025 + beat * 0.060);
    return float4(clamp(pow(max(color, float3(0.0)), float3(0.86)), 0.0, 1.0), 1.0);
}

float4 dataStormShader(float2 point, constant FractalUniforms &u) {
    float audio = audioDrive(u);
    float beat = clamp(u.beat * u.beatReactivity, 0.0, 1.0);
    float aspect = max(u.resolution.x / max(u.resolution.y, 1.0), 1.0);
    float2 uv = float2(point.x / aspect, point.y) * 0.5 + 0.5;
    float t = u.time * (0.22 + u.motion * 0.58 + audio * 0.20);
    float3 color = float3(0.002, 0.006, 0.010);
    float columns = 0.0;
    for (int i = 0; i < 42; i++) {
        float fi = float(i);
        float x = (fi + 0.5) / 42.0;
        float seed = hash21(float2(fi, 3.0));
        float cellY = floor((uv.y + t * (0.35 + seed)) * (18.0 + seed * 28.0));
        float glyph = smoothstep(0.86 - u.treble * 0.08, 1.0, hash21(float2(fi * 2.1, cellY)));
        float head = smoothstep(0.965, 1.0, fract(uv.y + t * (0.50 + seed)));
        columns += lineBand(uv.x - x, 0.0035 + seed * 0.004) * glyph * (0.24 + head * 0.8);
    }
    color += paletteGradient(u.palette, 0.35 + uv.y * 0.25) * columns * (0.15 + u.glow * 0.12);
    float boltPath = sin(point.y * 7.0 + t * 5.0) * 0.20 + sin(point.y * 19.0 - t * 3.0) * 0.055;
    float lightning = lineBand(point.x - boltPath, 0.010 + beat * 0.010) * smoothstep(-1.0, 0.85, point.y);
    color += paletteGradient(u.palette, 0.80 + t * 0.03) * lightning * (0.28 + beat * 0.35);
    for (int i = 0; i < 7; i++) {
        float fi = float(i);
        float y = fract(hash21(float2(fi, 9.0)) + t * (0.12 + fi * 0.015));
        float bar = lineBand(uv.y - y, 0.008 + hash21(float2(fi, 2.0)) * 0.020);
        color += paletteGradient(u.palette, 0.55 + fi * 0.08) * bar * (0.045 + beat * 0.080);
    }
    float scan = lineBand(fract(uv.y * 38.0 + t * 4.0) - 0.5, 0.020);
    color *= 0.74 + scan * 0.26;
    return float4(clamp(pow(max(color, float3(0.0)), float3(0.84)), 0.0, 1.0), 1.0);
}

float4 lavaForgeShader(float2 point, constant FractalUniforms &u) {
    float audio = audioDrive(u);
    float beat = clamp(u.beat * u.beatReactivity, 0.0, 1.0);
    float t = u.time * (0.055 + u.motion * 0.16);
    float2 p = point * float2(1.05, 0.92);
    float heat = ridgedFbm(p * 2.45 + float2(sin(t), t * 2.4));
    float cells = fbm2(p * 5.1 - float2(t * 1.7, t * 0.8));
    float cracks = smoothstep(0.62 - audio * 0.08, 0.92, heat + cells * 0.36);
    float3 ember = lerp3(float3(0.14, 0.020, 0.004), float3(1.00, 0.42, 0.055), cracks);
    float3 color = ember * (0.20 + cracks * (0.80 + u.bass * 0.35));
    float arch = ringBand(length((point - float2(0.0, -0.28)) * float2(0.75, 1.18)), 0.76 + beat * 0.03, 0.020);
    float gate = smoothstep(-0.98, 0.55, point.y);
    color += paletteGradient(u.palette, 0.10 + u.time * 0.01) * arch * gate * (0.18 + u.glow * 0.22);
    float anvil = softRect(point, float2(0.0, -0.70), float2(0.34, 0.050), 0.035);
    color = lerp3(color, float3(0.030, 0.025, 0.024), anvil * 0.82);
    for (int i = 0; i < 28; i++) {
        float fi = float(i);
        float seed = hash21(float2(fi, 6.0));
        float2 spark = float2(-0.9 + seed * 1.8 + sin(t * 6.0 + fi) * 0.10, -0.84 + fract(seed + u.time * (0.18 + seed * 0.32)) * 1.45);
        float dot = 1.0 - smoothstep(0.004, 0.020 + seed * 0.015, length(point - spark));
        color += paletteGradient(u.palette, 0.20 + seed * 0.20) * dot * (0.18 + u.treble * 0.32 + beat * 0.12);
    }
    color *= smoothstep(1.55, 0.12, length(point * float2(0.82, 1.08))) * 0.62 + 0.45;
    return float4(clamp(pow(max(color, float3(0.0)), float3(0.82)), 0.0, 1.0), 1.0);
}

float4 circuitBoardShader(float2 point, constant FractalUniforms &u) {
    float audio = audioDrive(u);
    float beat = clamp(u.beat * u.beatReactivity, 0.0, 1.0);
    float2 board = rotate2(point, 0.08 + sin(u.time * 0.08) * 0.035) * float2(6.2, 4.4);
    float2 cell = floor(board);
    float2 local = fract(board) - 0.5;
    float seed = hash21(cell);
    float traceH = lineBand(local.y + (seed - 0.5) * 0.42, 0.025);
    float traceV = lineBand(local.x - (seed - 0.5) * 0.42, 0.025);
    float enabled = step(0.28, seed);
    float traces = (traceH * step(0.38, hash21(cell + 2.0)) + traceV * step(0.42, hash21(cell + 4.0))) * enabled;
    float node = 1.0 - smoothstep(0.055, 0.145 + audio * 0.030, length(local));
    float packet = smoothstep(0.86, 1.0, sin((board.x + board.y) * 2.8 - u.time * (2.4 + u.motion * 4.0) + seed * 8.0) * 0.5 + 0.5);
    float scanner = lineBand(fract((point.x + point.y) * 0.35 + u.time * 0.14) - 0.5, 0.020 + beat * 0.020);
    float3 color = float3(0.004, 0.010, 0.008);
    color += paletteGradient(u.palette, 0.30 + seed * 0.30) * traces * (0.12 + packet * 0.32 + u.glow * 0.12);
    color += paletteGradient(u.palette, 0.68 + seed * 0.12) * node * step(0.70, seed) * (0.16 + u.mid * 0.24 + beat * 0.18);
    color += paletteGradient(u.palette, 0.88) * scanner * (traces + node) * (0.12 + beat * 0.18);
    float substrate = fbm2(board * 0.38 + u.time * 0.015);
    color += float3(0.006, 0.024, 0.018) * substrate;
    return float4(clamp(pow(max(color, float3(0.0)), float3(0.86)), 0.0, 1.0), 1.0);
}

float4 skylineEqualizerShader(float2 point, constant FractalUniforms &u) {
    float audio = audioDrive(u);
    float beat = clamp(u.beat * u.beatReactivity, 0.0, 1.0);
    float aspect = max(u.resolution.x / max(u.resolution.y, 1.0), 1.0);
    float3 color = lerp3(float3(0.006, 0.008, 0.015), float3(0.030, 0.025, 0.052), smoothstep(-0.85, 0.95, point.y));
    float road = smoothstep(-0.54, -0.96, point.y);
    color += float3(0.018, 0.014, 0.020) * road;
    for (int i = 0; i < 32; i++) {
        float fi = float(i);
        float width = aspect * 2.0 / 32.0;
        float x = -aspect + fi * width + width * 0.5;
        float band = hash21(float2(fi, floor(u.time * 0.6))) * 0.25;
        float height = 0.22 + hash21(float2(fi, 5.0)) * 0.55 + sin(u.time * 0.9 + fi) * 0.045 + audio * band + u.bass * 0.10;
        float building = softRect(point, float2(x, -0.88 + height * 0.5), float2(width * 0.42, height * 0.5), 0.010);
        float2 local = float2((point.x - x) / max(width, 0.001), (point.y + 0.88) / max(height, 0.001));
        float pixels = smoothstep(0.82 - u.treble * 0.08, 1.0, sin(local.x * 18.0) * sin(local.y * 42.0 + u.time * 0.8) * 0.5 + 0.5);
        float3 tower = paletteGradient(u.palette, 0.12 + fi * 0.025 + height * 0.14);
        color += tower * building * (0.08 + pixels * (0.18 + u.mid * 0.12));
        float sign = softRect(point, float2(x, -0.86 + height + 0.035), float2(width * 0.25, 0.018 + beat * 0.010), 0.010);
        color += paletteGradient(u.palette, 0.72 + fi * 0.02) * sign * (0.18 + beat * 0.22);
    }
    float street = lineBand(fract((point.x / max(aspect, 0.001) + u.time * 0.10) * 18.0) - 0.5, 0.040) * road;
    color += paletteGradient(u.palette, 0.88) * street * (0.055 + u.bass * 0.075);
    return float4(clamp(pow(max(color, float3(0.0)), float3(0.84)), 0.0, 1.0), 1.0);
}

float4 iterateFractal(float2 point, constant FractalUniforms &u) {
    if (u.mode == 5) {
        return mandelboxFlight(point, u);
    }
    if (u.mode == 6) {
        return nebulaVoyage(point, u);
    }
    if (u.mode == 7) {
        return crystalCavern(point, u);
    }
    if (u.mode == 8) {
        return underwaterReefShader(point, u);
    }
    if (u.mode == 9) {
        return subwayRushShader(point, u);
    }
    if (u.mode == 10) {
        return vinylOrbitShader(point, u);
    }
    if (u.mode == 11) {
        return rainWindowShader(point, u);
    }
    if (u.mode == 12) {
        return moonBaseShader(point, u);
    }
    if (u.mode == 13) {
        return danceFloorShader(point, u);
    }
    if (u.mode == 14) {
        return dataStormShader(point, u);
    }
    if (u.mode == 15) {
        return lavaForgeShader(point, u);
    }
    if (u.mode == 16) {
        return circuitBoardShader(point, u);
    }
    if (u.mode == 17) {
        return skylineEqualizerShader(point, u);
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
