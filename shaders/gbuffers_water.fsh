#version 120

/*
 * gbuffers_water.fsh - Photon-style water rendering
 *
 * Clean, physically-based water with subtle caustics, fresnel-based
 * transparency, and natural blue-green coloring. Other translucents
 * pass through with minimal modification.
 */

// ---------------------------------------------------------------------------
// Uniforms
// ---------------------------------------------------------------------------
uniform sampler2D texture;
uniform sampler2D lightmap;
uniform float frameTimeCounter;

// ---------------------------------------------------------------------------
// Varyings
// ---------------------------------------------------------------------------
varying vec2 texcoord;
varying vec2 lmcoord;
varying vec4 glcolor;
varying vec3 viewPos;
varying vec3 worldPos;
varying vec3 normal;
varying float blockId;
varying float isWater;

// ---------------------------------------------------------------------------
// Photon-style water settings
// ---------------------------------------------------------------------------
const vec3 WATER_COLOR   = vec3(0.05, 0.18, 0.32);   // deep blue-green
const float WATER_ALPHA  = 0.55;                      // base translucency

// ---------------------------------------------------------------------------
// Subtle animated caustic
// ---------------------------------------------------------------------------
float causticPattern(vec2 pos, float time) {
    // Two overlapping wave patterns — very subtle
    float c1 = sin(pos.x * 2.8 + time * 0.9) * sin(pos.y * 3.2 + time * 0.7);
    float c2 = sin(pos.x * 1.9 - time * 0.6 + 1.5) * sin(pos.y * 2.4 + time * 0.85 + 0.8);
    float caustic = (c1 + c2) * 0.5 + 0.5;
    caustic = pow(caustic, 3.0); // sharper, more subtle peaks
    return caustic * 0.08;       // very subtle
}

// ---------------------------------------------------------------------------
// Main
// ---------------------------------------------------------------------------
void main() {
    vec4 albedo = texture2D(texture, texcoord);
    albedo *= glcolor;

    if (albedo.a < 0.1) discard;

    if (isWater > 0.5) {
        // Photon-style: clean water color blended with biome
        vec3 waterColor = mix(WATER_COLOR, glcolor.rgb * 0.3, 0.2);

        // Very subtle caustic shimmer
        float caustic = causticPattern(worldPos.xz, frameTimeCounter);
        waterColor += vec3(caustic * 0.4, caustic * 0.6, caustic * 0.8);

        // Fresnel: water darkens when looking straight down, lighter at edges
        float viewDot = abs(dot(normalize(normal), normalize(-viewPos)));
        float fresnel = pow(1.0 - viewDot, 4.0);
        waterColor = mix(waterColor, waterColor * 1.2, fresnel * 0.3);

        albedo.rgb = waterColor;
        // Fresnel-based opacity: more opaque at glancing angles
        albedo.a = mix(WATER_ALPHA, WATER_ALPHA + 0.2, fresnel);
    }

    // Lightmap
    vec3 lmColor = texture2D(lightmap, lmcoord).rgb;
    vec3 litAlbedo = albedo.rgb * mix(vec3(1.0), lmColor, 0.3);

    // MRT 0: color
    gl_FragData[0] = vec4(litAlbedo, albedo.a);

    // MRT 1: normal + sky light
    vec3 encodedNormal = normal * 0.5 + 0.5;
    gl_FragData[1] = vec4(encodedNormal, lmcoord.y);

    // MRT 2: material data — water is reflective and smooth
    float encodedId = blockId / 256.0;
    float specular  = (isWater > 0.5) ? 0.7 : 0.0;
    float roughness = (isWater > 0.5) ? 0.08 : 1.0;

    gl_FragData[2] = vec4(encodedId, specular, roughness, lmcoord.x);
}
