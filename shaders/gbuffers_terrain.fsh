#version 120

/*
 * gbuffers_terrain.fsh
 * Fragment shader for terrain (solid blocks).
 * Writes to the gbuffer MRT:
 *   gl_FragData[0] = albedo colour (RGBA) with light lightmap tinting
 *   gl_FragData[1] = encoded normal (rgb) + lightmap data (a)
 *   gl_FragData[2] = material flags (blockId, specular, roughness)
 */

// ---------------------------------------------------------------------------
// Uniforms
// ---------------------------------------------------------------------------
uniform sampler2D texture;    // block atlas
uniform sampler2D lightmap;   // vanilla lightmap texture

// ---------------------------------------------------------------------------
// Varyings from vertex shader
// ---------------------------------------------------------------------------
varying vec2 texcoord;
varying vec2 lmcoord;
varying vec4 glcolor;
varying vec3 viewPos;
varying vec3 worldPos;
varying vec3 normal;
varying float blockId;

// ---------------------------------------------------------------------------
// Main
// ---------------------------------------------------------------------------
void main() {
    // -- Sample block atlas ---------------------------------------------------
    vec4 albedo = texture2D(texture, texcoord);

    // Multiply by vertex colour (biome tint, ambient occlusion)
    albedo *= glcolor;

    // -- Alpha test (cutout foliage, etc.) ------------------------------------
    if (albedo.a < 0.1) discard;

    // -- Lightmap contribution ------------------------------------------------
    // Sample the vanilla lightmap and apply it lightly so deferred lighting
    // can still do the heavy lifting.
    vec3 lmColor = texture2D(lightmap, lmcoord).rgb;
    vec3 litAlbedo = albedo.rgb * mix(vec3(1.0), lmColor, 0.35);

    // -- MRT output 0: colour -------------------------------------------------
    gl_FragData[0] = vec4(litAlbedo, albedo.a);

    // -- MRT output 1: normal + lightmap data ---------------------------------
    // Encode normal from [-1,1] to [0,1]
    vec3 encodedNormal = normal * 0.5 + 0.5;
    // Pack sky-light into alpha (block light can be recovered from lmcoord.x)
    gl_FragData[1] = vec4(encodedNormal, lmcoord.y);

    // -- MRT output 2: material flags -----------------------------------------
    // r = blockId encoded into 0-1 range (divide by 256 for packing)
    // g = specular intensity   (default 0.0 for terrain)
    // b = roughness            (default 1.0 for terrain)
    // a = block light stored for later passes
    float encodedId = blockId / 256.0;
    float specular  = 0.0;
    float roughness = 1.0;

    gl_FragData[2] = vec4(encodedId, specular, roughness, lmcoord.x);
}
