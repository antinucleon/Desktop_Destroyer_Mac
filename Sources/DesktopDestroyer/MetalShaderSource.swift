let metalShaderSource = #"""
#include <metal_stdlib>
using namespace metal;

struct StampUniforms {
    uint2 origin;
    uint2 textureSize;
    float2 center;
    float radius;
    float hardness;
    float4 color;
    uint kind;
    float seed;
    float rotation;
    float assetMix;
};

struct Particle {
    float2 position;
    float2 velocity;
    float4 color;
    float life;
    float maxLife;
    float size;
    uint kind;
};

struct ParticleUpdateUniforms {
    float deltaTime;
    float padding;
    float2 viewport;
};

struct ParticleRenderUniforms {
    float2 viewport;
    float time;
    float padding;
};

struct CompositeUniforms {
    float2 viewport;
    float2 backgroundSize;
    float time;
    float damageEnergy;
    float2 padding;
};

struct FullscreenOut {
    float4 position [[position]];
    float2 uv;
};

struct ParticleOut {
    float4 position [[position]];
    float2 uv;
    float4 color;
    float life;
    uint kind [[flat]];
    uint variant [[flat]];
};

struct ContactEffect {
    float2 position;
    float2 direction;
    float4 color;
    float age;
    float lifetime;
    float size;
    float rotation;
    uint kind;
    float seed;
    float2 padding;
};

struct ContactOut {
    float4 position [[position]];
    float2 local;
    float4 color;
    float progress;
    float seed;
    uint kind [[flat]];
};

struct CursorUniforms {
    float2 position;
    float2 viewport;
    float2 size;
    float2 anchor;
    uint cell;
    float opacity;
    float rotation;
    float brightness;
};

float hash21(float2 p) {
    p = fract(p * float2(123.34, 456.21));
    p += dot(p, p + 45.32);
    return fract(p.x * p.y);
}

float inverseSmooth(float inner, float outer, float value) {
    return 1.0 - smoothstep(inner, outer, value);
}

kernel void clearDamage(
    texture2d<half, access::write> damage [[texture(0)]],
    uint2 gid [[thread_position_in_grid]]
) {
    if (gid.x >= damage.get_width() || gid.y >= damage.get_height()) return;
    damage.write(half4(0.0h), gid);
}

kernel void applyStamp(
    texture2d<half, access::read_write> damage [[texture(0)]],
    texture2d<float, access::sample> decalAtlas [[texture(1)]],
    texture2d<float, access::sample> stampAtlas [[texture(2)]],
    constant StampUniforms &u [[buffer(0)]],
    uint2 tid [[thread_position_in_grid]]
) {
    uint2 pixel = u.origin + tid;
    if (pixel.x >= u.textureSize.x || pixel.y >= u.textureSize.y) return;

    float2 delta = float2(pixel) + 0.5 - u.center;
    float cosine = cos(u.rotation);
    float sine = sin(u.rotation);
    float2 local = float2(
        delta.x * cosine + delta.y * sine,
        -delta.x * sine + delta.y * cosine
    );
    float distanceToCenter = length(local);
    float noise = hash21(floor(float2(pixel) * 0.31) + u.seed * 97.0);
    float coverage = 0.0;
    float4 source = u.color;
    constexpr sampler atlasSampler(filter::linear, address::clamp_to_edge);
    float2 assetLocal = local / max(u.radius * 2.0, 1.0) + 0.5;
    float4 asset = float4(0.0);
    if (all(assetLocal >= 0.0) && all(assetLocal <= 1.0)) {
        if (u.kind == 6u) {
            uint variant = min(uint(u.seed * 15.999), 15u);
            float2 cell = float2(variant % 4u, variant / 4u);
            asset = stampAtlas.sample(atlasSampler, (cell + assetLocal) / 4.0);
        } else {
            uint decalIndex = u.kind < 6u ? u.kind : (u.kind == 7u ? 6u : 7u);
            float2 cell = float2(decalIndex % 4u, decalIndex / 4u);
            asset = decalAtlas.sample(atlasSampler, (cell + assetLocal) / float2(4.0, 2.0));
        }
    }

    if (u.kind == 0u) {
        float core = inverseSmooth(u.radius * 0.10, u.radius * 0.38, distanceToCenter);
        float angle = atan2(local.y, local.x);
        float rays = abs(sin(angle * 7.0 + u.seed * 6.283));
        float crack = inverseSmooth(0.0, 0.055 + noise * 0.035, rays);
        crack *= smoothstep(u.radius * 0.24, u.radius * 0.38, distanceToCenter);
        crack *= inverseSmooth(u.radius * 0.48, u.radius, distanceToCenter);
        coverage = max(core, crack * (0.65 + noise * 0.35));
        source.rgb = mix(float3(0.01, 0.012, 0.016), source.rgb, crack * 0.12);
    } else if (u.kind == 1u) {
        float centerCut = inverseSmooth(2.0, 8.0 + noise * 5.0, abs(local.y));
        float reach = inverseSmooth(u.radius * 0.35, u.radius, abs(local.x));
        float teeth = step(0.48, fract((local.x + local.y * 0.35) / 9.0 + noise));
        coverage = max(centerCut * reach, teeth * 0.28 * inverseSmooth(4.0, 18.0, abs(local.y)) * reach);
        source.rgb = mix(float3(0.015, 0.012, 0.01), source.rgb, 0.16);
    } else if (u.kind == 2u) {
        float hole = inverseSmooth(u.radius * 0.18, u.radius * 0.58, distanceToCenter);
        float chippedRing = 1.0 - smoothstep(1.3, 4.6 + noise * 2.5, abs(distanceToCenter - u.radius * 0.70));
        coverage = max(hole, chippedRing * (0.35 + noise * 0.35));
        source.rgb = mix(float3(0.005), source.rgb, chippedRing * 0.15);
    } else if (u.kind == 3u) {
        float edge = u.radius * (0.58 + noise * 0.34);
        coverage = inverseSmooth(edge * 0.62, edge, distanceToCenter);
        float heat = inverseSmooth(0.0, u.radius, distanceToCenter);
        source.rgb = mix(float3(0.018, 0.014, 0.012), u.color.rgb, heat * 0.43);
    } else if (u.kind == 4u) {
        float edge = u.radius * (0.54 + noise * 0.30);
        float body = inverseSmooth(edge * 0.72, edge, distanceToCenter);
        float droplets = step(0.975, hash21(floor(float2(pixel) / 3.0) + u.seed));
        droplets *= inverseSmooth(u.radius * 0.65, u.radius * 1.18, distanceToCenter);
        coverage = max(body, droplets * 0.86);
    } else if (u.kind == 5u) {
        float ring = 1.0 - smoothstep(1.5, 5.0, abs(distanceToCenter - u.radius * 0.52));
        float core = inverseSmooth(0.0, u.radius * 0.22, distanceToCenter);
        float rays = inverseSmooth(0.0, 0.08, abs(sin(atan2(local.y, local.x) * 5.0 + u.seed)));
        rays *= inverseSmooth(u.radius * 0.42, u.radius, distanceToCenter);
        coverage = max(max(ring, core), rays * 0.72);
        source.rgb = mix(float3(0.01, 0.025, 0.035), u.color.rgb, max(ring, rays));
    } else if (u.kind == 6u) {
        float outer = 1.0 - smoothstep(2.0, 5.0, abs(distanceToCenter - u.radius * 0.67));
        float inner = 1.0 - smoothstep(1.0, 3.5, abs(distanceToCenter - u.radius * 0.47));
        float slashA = inverseSmooth(0.0, 3.0, abs(local.y - local.x * 0.55));
        float slashB = inverseSmooth(0.0, 3.0, abs(local.y + local.x * 0.55));
        float inside = inverseSmooth(u.radius * 0.50, u.radius * 0.68, distanceToCenter);
        coverage = max(max(outer, inner), max(slashA, slashB) * inside);
    } else if (u.kind == 7u) {
        float raggedRadius = u.radius * (0.58 + noise * 0.48);
        coverage = inverseSmooth(raggedRadius * 0.48, raggedRadius, distanceToCenter);
        source.rgb = float3(0.055, 0.035, 0.018);
    } else {
        float foam = inverseSmooth(u.radius * 0.30, u.radius, distanceToCenter);
        foam *= 0.72 + noise * 0.28;
        foam = max(foam * 0.55, asset.a * u.assetMix);
        float4 old = float4(damage.read(pixel));
        old.a *= 1.0 - foam * u.hardness;
        old.rgb *= max(old.a, 0.02);
        damage.write(half4(old), pixel);
        return;
    }

    coverage = max(coverage * (1.0 - 0.42 * u.assetMix), asset.a * u.assetMix);
    source.rgb = mix(source.rgb, asset.rgb, asset.a * u.assetMix);
    source.a = max(source.a, asset.a);

    float alpha = clamp(coverage * u.hardness * source.a, 0.0, 1.0);
    if (alpha <= 0.001) return;
    float4 old = float4(damage.read(pixel));
    old.rgb = mix(old.rgb, source.rgb, alpha);
    old.a = old.a + alpha * (1.0 - old.a);
    damage.write(half4(old), pixel);
}

kernel void updateParticles(
    device Particle *particles [[buffer(0)]],
    constant ParticleUpdateUniforms &u [[buffer(1)]],
    uint index [[thread_position_in_grid]]
) {
    Particle p = particles[index];
    if (p.life <= 0.0) return;

    float dt = min(u.deltaTime, 1.0 / 30.0);
    if (p.kind == 2u) {
        p.velocity.y += 42.0 * dt;
        p.velocity *= pow(0.975, dt * 60.0);
    } else if (p.kind == 4u) {
        p.velocity.y += 18.0 * dt;
        p.velocity *= pow(0.94, dt * 60.0);
    } else {
        p.velocity.y -= (p.kind == 1u ? 95.0 : 220.0) * dt;
        p.velocity *= pow(0.988, dt * 60.0);
    }
    p.position += p.velocity * dt;
    p.life -= dt;
    particles[index] = p;
}

vertex FullscreenOut fullscreenVertex(uint vertexID [[vertex_id]]) {
    const float2 positions[6] = {
        float2(-1.0, -1.0), float2(1.0, -1.0), float2(-1.0, 1.0),
        float2(-1.0, 1.0), float2(1.0, -1.0), float2(1.0, 1.0)
    };
    FullscreenOut out;
    float2 position = positions[vertexID];
    out.position = float4(position, 0.0, 1.0);
    out.uv = position * 0.5 + 0.5;
    return out;
}

fragment float4 compositeFragment(
    FullscreenOut in [[stage_in]],
    texture2d<float> background [[texture(0)]],
    texture2d<float> damage [[texture(1)]],
    constant CompositeUniforms &u [[buffer(0)]]
) {
    constexpr sampler linearSampler(filter::linear, address::clamp_to_edge);
    float2 backgroundUV = in.uv;
    float viewAspect = u.viewport.x / max(u.viewport.y, 1.0);
    float imageAspect = u.backgroundSize.x / max(u.backgroundSize.y, 1.0);
    if (imageAspect > viewAspect) {
        backgroundUV.x = 0.5 + (backgroundUV.x - 0.5) * (viewAspect / imageAspect);
    } else {
        backgroundUV.y = 0.5 + (backgroundUV.y - 0.5) * (imageAspect / viewAspect);
    }
    backgroundUV.y = 1.0 - backgroundUV.y;

    float4 base = background.sample(linearSampler, backgroundUV);
    float4 destruction = damage.sample(linearSampler, in.uv);
    float3 color = mix(base.rgb, destruction.rgb, destruction.a);
    float2 centered = in.uv * 2.0 - 1.0;
    float vignette = 1.0 - 0.12 * smoothstep(0.45, 1.45, dot(centered, centered));
    float scan = sin((in.uv.y * u.viewport.y + u.time * 18.0) * 0.032) * 0.003;
    color = color * vignette + scan * u.damageEnergy;
    return float4(color, 1.0);
}

vertex ParticleOut particleVertex(
    uint vertexID [[vertex_id]],
    uint instanceID [[instance_id]],
    device const Particle *particles [[buffer(0)]],
    constant ParticleRenderUniforms &u [[buffer(1)]]
) {
    const float2 corners[6] = {
        float2(-1.0, -1.0), float2(1.0, -1.0), float2(-1.0, 1.0),
        float2(-1.0, 1.0), float2(1.0, -1.0), float2(1.0, 1.0)
    };
    Particle p = particles[instanceID];
    float2 corner = corners[vertexID];
    float lifeRatio = p.maxLife > 0.0 ? clamp(p.life / p.maxLife, 0.0, 1.0) : 0.0;
    float elapsed = max(p.maxLife - p.life, 0.0);
    float scale = p.size;
    if (p.kind == 2u) scale *= 0.72 + (1.0 - lifeRatio) * 0.70;
    if (p.kind == 4u || p.kind == 5u) scale *= 0.82 + (1.0 - lifeRatio) * 0.46;
    if (p.kind == 6u) scale *= 0.72 + sin(elapsed * 25.0) * 0.18;
    float2 spriteCorner = corner;
    if (p.kind == 3u && length_squared(p.velocity) > 0.001) {
        float2 forward = normalize(p.velocity);
        float2 right = float2(forward.y, -forward.x);
        spriteCorner = right * corner.x + forward * corner.y;
    } else {
        float spinSpeed = p.kind == 0u ? 3.8 : (p.kind == 7u ? 6.2 : 1.1);
        float spin = elapsed * spinSpeed + float(instanceID % 17u) * 0.37;
        float c = cos(spin);
        float s = sin(spin);
        spriteCorner = float2(corner.x * c - corner.y * s, corner.x * s + corner.y * c);
    }
    float2 pixelPosition = p.position + spriteCorner * scale;
    float2 ndc = pixelPosition / max(u.viewport, float2(1.0)) * 2.0 - 1.0;

    ParticleOut out;
    out.position = p.life > 0.0 ? float4(ndc, 0.0, 1.0) : float4(3.0, 3.0, 0.0, 1.0);
    out.uv = corner * 0.5 + 0.5;
    out.color = p.color;
    out.life = lifeRatio;
    out.kind = p.kind;
    out.variant = p.kind == 3u
        ? uint(floor(u.time * 12.0 + float(instanceID) * 0.73))
        : instanceID;
    return out;
}

fragment float4 particleFragment(
    ParticleOut in [[stage_in]],
    texture2d<float> particleAtlas [[texture(0)]],
    texture2d<float> termiteAtlas [[texture(1)]]
) {
    constexpr sampler atlasSampler(filter::linear, address::clamp_to_edge);
    uint spriteIndex = in.kind == 3u ? in.variant % 8u : min(in.kind, 7u);
    float2 cell = float2(spriteIndex % 4u, spriteIndex / 4u);
    float2 localUV = float2(in.uv.x, 1.0 - in.uv.y);
    float2 atlasUV = (cell + localUV) / float2(4.0, 2.0);
    float4 sprite = in.kind == 3u
        ? termiteAtlas.sample(atlasSampler, atlasUV)
        : particleAtlas.sample(atlasSampler, atlasUV);
    float alpha = sprite.a * in.life;
    if (alpha < 0.01) discard_fragment();
    float tintStrength = in.kind == 3u ? 0.12 : 0.42;
    float3 color = mix(sprite.rgb, sprite.rgb * in.color.rgb, tintStrength);
    return float4(color, in.color.a * alpha);
}

vertex ContactOut contactEffectVertex(
    uint vertexID [[vertex_id]],
    uint instanceID [[instance_id]],
    device const ContactEffect *effects [[buffer(0)]],
    constant ParticleRenderUniforms &u [[buffer(1)]]
) {
    const float2 corners[6] = {
        float2(-1.0, -1.0), float2(1.0, -1.0), float2(-1.0, 1.0),
        float2(-1.0, 1.0), float2(1.0, -1.0), float2(1.0, 1.0)
    };
    ContactEffect e = effects[instanceID];
    float2 corner = corners[vertexID];
    float2 oriented = corner;
    if (length_squared(e.direction) > 0.001) {
        float2 forward = normalize(e.direction);
        float2 right = float2(forward.y, -forward.x);
        oriented = right * corner.x + forward * corner.y;
    } else {
        float c = cos(e.rotation);
        float s = sin(e.rotation);
        oriented = float2(corner.x * c - corner.y * s, corner.x * s + corner.y * c);
    }
    float2 pixelPosition = e.position + oriented * e.size;
    float2 ndc = pixelPosition / max(u.viewport, float2(1.0)) * 2.0 - 1.0;
    ContactOut out;
    out.position = float4(ndc, 0.0, 1.0);
    out.local = corner;
    out.color = e.color;
    out.progress = clamp(e.age / max(e.lifetime, 0.001), 0.0, 1.0);
    out.seed = e.seed;
    out.kind = e.kind;
    return out;
}

fragment float4 contactEffectFragment(ContactOut in [[stage_in]]) {
    float2 p = in.local;
    float r = length(p);
    float angle = atan2(p.y, p.x);
    float q = in.progress;
    float fade = 1.0 - smoothstep(0.52, 1.0, q);
    float noise = hash21(floor((p + 1.0) * 31.0) + in.seed * 113.0);
    float intensity = 0.0;
    float3 color = in.color.rgb;

    if (in.kind == 0u) {
        float flash = exp(-r * 10.0) * (1.0 - smoothstep(0.0, 0.34, q));
        float ringRadius = 0.12 + q * 0.74;
        float ring = 1.0 - smoothstep(0.018, 0.085, abs(r - ringRadius));
        float rays = pow(abs(cos(angle * 9.0 + in.seed * 7.0)), 34.0);
        rays *= smoothstep(0.10, 0.30, r) * (1.0 - smoothstep(0.35, 0.98, r));
        intensity = flash * 1.8 + ring * fade + rays * fade * 0.72;
        color = mix(float3(1.0, 0.48, 0.08), float3(1.0), flash);
    } else if (in.kind == 1u) {
        float burst = pow(max(cos(angle * 11.0 + in.seed * 13.0), 0.0), 42.0);
        burst *= smoothstep(0.08, 0.28, r) * (1.0 - smoothstep(0.35 + q * 0.45, 0.92, r));
        float dust = (1.0 - smoothstep(0.08, 0.55, r)) * step(0.58, noise) * 0.55;
        intensity = (burst * 1.55 + dust) * fade;
        color = mix(float3(0.62, 0.27, 0.035), float3(1.0, 0.74, 0.16), burst);
    } else if (in.kind == 2u) {
        float flash = exp(-r * 15.0) * (1.0 - smoothstep(0.0, 0.42, q));
        float star = pow(abs(cos(angle * 6.0 + in.seed * 4.0)), 52.0);
        star *= 1.0 - smoothstep(0.05, 0.72, r);
        float ring = 1.0 - smoothstep(0.012, 0.06, abs(r - (0.10 + q * 0.38)));
        intensity = flash * 2.2 + (star + ring * 0.65) * fade;
        color = mix(float3(1.0, 0.40, 0.025), float3(1.0, 0.95, 0.62), flash);
    } else if (in.kind == 3u) {
        float2 flameP = float2(p.x * 1.35, p.y + q * 0.16);
        float flameNoise = sin(flameP.y * 17.0 + in.seed * 19.0) * 0.09 + (noise - 0.5) * 0.08;
        float flame = 1.0 - smoothstep(0.18 + q * 0.10, 0.66, length(flameP + float2(flameNoise, 0.12)));
        flame *= 1.0 - smoothstep(0.52, 1.0, q);
        intensity = flame * (0.74 + noise * 0.48);
        color = mix(float3(1.0, 0.10, 0.008), float3(1.0, 0.86, 0.16), 1.0 - r);
    } else if (in.kind == 4u) {
        float ring = 1.0 - smoothstep(0.025, 0.09, abs(r - (0.18 + q * 0.56)));
        float droplets = step(0.77, noise) * (1.0 - smoothstep(0.18, 0.90, r));
        intensity = (ring * 0.82 + droplets) * fade;
        color = mix(in.color.rgb, float3(1.0, 0.34, 0.82), noise);
    } else if (in.kind == 5u) {
        float ringA = 1.0 - smoothstep(0.018, 0.065, abs(r - (0.16 + q * 0.68)));
        float ringB = 1.0 - smoothstep(0.018, 0.050, abs(r - (0.08 + q * 0.42)));
        float arcs = pow(abs(sin(angle * 7.0 + q * 15.0 + in.seed * 9.0)), 26.0);
        arcs *= 1.0 - smoothstep(0.22, 0.92, r);
        intensity = (ringA + ringB * 0.72 + arcs * 0.62) * fade;
        color = mix(float3(0.18, 0.64, 1.0), float3(0.78, 0.36, 1.0), noise);
    } else if (in.kind == 6u) {
        float ring = 1.0 - smoothstep(0.025, 0.085, abs(r - (0.18 + q * 0.58)));
        float dust = step(0.64, noise) * (1.0 - smoothstep(0.08, 0.78, r));
        intensity = (ring * 0.72 + dust * 0.58) * fade;
        color = mix(in.color.rgb, float3(0.96, 0.82, 1.0), noise * 0.7);
    } else if (in.kind == 7u) {
        float dust = step(0.60, noise) * smoothstep(0.08, 0.30, r) * (1.0 - smoothstep(0.30, 0.82, r));
        float puff = exp(-r * 5.0) * (1.0 - q);
        intensity = (dust + puff * 0.42) * fade;
        color = float3(0.86, 0.58, 0.20);
    } else {
        float foamRing = 1.0 - smoothstep(0.028, 0.10, abs(r - (0.14 + q * 0.62)));
        float foam = step(0.58, noise) * (1.0 - smoothstep(0.06, 0.78, r));
        intensity = (foamRing * 0.88 + foam * 0.72) * fade;
        color = mix(float3(0.20, 0.72, 1.0), float3(0.94, 1.0, 1.0), noise);
    }

    float alpha = clamp(intensity, 0.0, 1.0) * in.color.a;
    if (alpha < 0.01) discard_fragment();
    return float4(color * min(intensity, 1.55), alpha);
}

vertex ParticleOut cursorVertex(
    uint vertexID [[vertex_id]],
    constant CursorUniforms &u [[buffer(0)]]
) {
    const float2 corners[6] = {
        float2(-1.0, -1.0), float2(1.0, -1.0), float2(-1.0, 1.0),
        float2(-1.0, 1.0), float2(1.0, -1.0), float2(1.0, 1.0)
    };
    float2 corner = corners[vertexID];
    float2 screenUV = corner * 0.5 + 0.5;
    float2 anchorScreen = float2(u.anchor.x, 1.0 - u.anchor.y);
    float2 offset = (screenUV - anchorScreen) * u.size;
    float cosine = cos(u.rotation);
    float sine = sin(u.rotation);
    float2 rotated = float2(offset.x * cosine - offset.y * sine, offset.x * sine + offset.y * cosine);
    float2 pixelPosition = u.position + rotated;
    float2 ndc = pixelPosition / max(u.viewport, float2(1.0)) * 2.0 - 1.0;
    ParticleOut out;
    out.position = float4(ndc, 0.0, 1.0);
    out.uv = screenUV;
    out.color = float4(u.brightness, u.brightness, u.brightness, u.opacity);
    out.life = 1.0;
    out.kind = u.cell;
    out.variant = 0u;
    return out;
}

fragment float4 cursorFragment(
    ParticleOut in [[stage_in]],
    texture2d<float> toolAtlas [[texture(0)]]
) {
    constexpr sampler atlasSampler(filter::linear, address::clamp_to_edge);
    float2 localUV = float2(in.uv.x, 1.0 - in.uv.y);
    float4 sprite;
    if (in.kind >= 9u) {
        sprite = toolAtlas.sample(atlasSampler, localUV);
    } else {
        float2 cell = float2(in.kind % 3u, in.kind / 3u);
        sprite = toolAtlas.sample(atlasSampler, (cell + localUV) / 3.0);
    }
    if (sprite.a < 0.01) discard_fragment();
    return float4(sprite.rgb * in.color.rgb, sprite.a * in.color.a);
}
"""#
