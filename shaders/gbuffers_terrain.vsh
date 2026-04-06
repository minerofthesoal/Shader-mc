#version 120

/*
 * gbuffers_terrain.vsh
 * Vertex shader for terrain (solid blocks).
 * Handles standard transforms, lightmap extraction, and waving plant animation.
 */

// ---------------------------------------------------------------------------
// Feature toggles
// ---------------------------------------------------------------------------
#define WAVING_PLANTS
#define WIND_STRENGTH 0.08
#define WIND_SPEED    1.5

// ---------------------------------------------------------------------------
// Uniforms
// ---------------------------------------------------------------------------
uniform mat4 gbufferModelView;
uniform mat4 gbufferModelViewInverse;
uniform float frameTimeCounter;
uniform vec3 cameraPosition;
uniform int worldTime;

// ---------------------------------------------------------------------------
// Attributes (OptiFine / Iris)
// ---------------------------------------------------------------------------
attribute vec4 at_tangent;
attribute vec3 mc_Entity;      // x = block ID
attribute vec2 mc_midTexCoord; // midpoint of the sprite on the atlas

// ---------------------------------------------------------------------------
// Varyings -> fragment
// ---------------------------------------------------------------------------
varying vec2 texcoord;
varying vec2 lmcoord;      // lightmap coords (x = block light, y = sky light)
varying vec4 glcolor;       // vertex colour (biome tint, AO, etc.)
varying vec3 viewPos;       // position in view space
varying vec3 worldPos;      // position in world space
varying vec3 normal;        // view-space normal
varying float blockId;      // mc_Entity.x passed through for the fragment shader

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

// Simple hash-like variation per-plant so they don't all sway in sync
float plantHash(vec3 pos) {
    return fract(sin(dot(floor(pos.xz), vec2(12.9898, 78.233))) * 43758.5453);
}

// Returns true if the given ID matches any of the waving-plant block IDs.
bool isWavingPlant(float id) {
    // Grass / double grass
    if (id == 31.0 || id == 175.0) return true;
    // Leaves (oak/birch/spruce/jungle & acacia/dark-oak)
    if (id == 18.0 || id == 161.0) return true;
    // Flowers
    if (id == 37.0 || id == 38.0) return true;
    // Vines
    if (id == 106.0) return true;
    // Crops (wheat, carrots, potatoes, beetroot)
    if (id == 59.0 || id == 141.0 || id == 142.0 || id == 207.0) return true;
    return false;
}

bool isLeaves(float id) {
    return (id == 18.0 || id == 161.0);
}

// ---------------------------------------------------------------------------
// Main
// ---------------------------------------------------------------------------
void main() {
    // -- Texture coordinates --------------------------------------------------
    texcoord = (gl_TextureMatrix[0] * gl_MultiTexCoord0).st;

    // -- Lightmap (OptiFine/Iris standard transform) --------------------------
    lmcoord = clamp((gl_TextureMatrix[1] * gl_MultiTexCoord1).st, 0.0, 1.0);

    // -- Vertex colour --------------------------------------------------------
    glcolor = gl_Color;

    // -- Normal in view space -------------------------------------------------
    normal = normalize(gl_NormalMatrix * gl_Normal);

    // -- Block ID passthrough -------------------------------------------------
    blockId = mc_Entity.x;

    // -- Position transforms --------------------------------------------------
    vec4 viewPos4 = gl_ModelViewMatrix * gl_Vertex;
    viewPos = viewPos4.xyz;

    // World position (used for wind calc and passed to fragment)
    vec4 worldPos4 = gbufferModelViewInverse * viewPos4;
    worldPos = worldPos4.xyz + cameraPosition;

    // -- Waving plants --------------------------------------------------------
#ifdef WAVING_PLANTS
    if (isWavingPlant(blockId)) {
        // Only displace the top vertices of the plant sprite.
        // OptiFine convention: top vertices have texcoord.t < mc_midTexCoord.t
        bool isTopVertex = (gl_MultiTexCoord0.t < mc_midTexCoord.t);

        // Leaves sway on all vertices (whole block), plants only on top half
        bool shouldWave = isTopVertex || isLeaves(blockId);

        if (shouldWave) {
            float time = frameTimeCounter * WIND_SPEED;

            // Per-plant phase offset so nearby plants aren't perfectly in sync
            float phase = plantHash(worldPos) * 6.2831;

            // Primary sway
            float swayX = sin(time + phase + worldPos.x * 0.5) * WIND_STRENGTH;
            float swayZ = cos(time * 0.8 + phase + worldPos.z * 0.5) * WIND_STRENGTH;

            // Leaves get a gentler, broader sway
            if (isLeaves(blockId)) {
                swayX *= 0.4;
                swayZ *= 0.4;
            }

            // Apply displacement in world space, then transform back
            worldPos4.x += swayX;
            worldPos4.z += swayZ;

            // Rebuild view-space position from the displaced world position
            viewPos4 = gbufferModelView * worldPos4;
            viewPos = viewPos4.xyz;
        }
    }
#endif

    // -- Final clip-space position --------------------------------------------
    gl_Position = gl_ProjectionMatrix * viewPos4;
}
