#version 120

/*
 * gbuffers_water.vsh
 * Vertex shader for translucent geometry (water, stained glass, ice).
 * Adds Gerstner-style wave displacement for water surfaces.
 */

// ---------------------------------------------------------------------------
// Feature toggles
// ---------------------------------------------------------------------------
#define WATER_WAVES
#define WAVE_HEIGHT    0.12
#define WAVE_SPEED     0.8
#define WAVE_FREQUENCY 1.2

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
// Attributes
// ---------------------------------------------------------------------------
attribute vec4 at_tangent;
attribute vec3 mc_Entity;
attribute vec2 mc_midTexCoord;

// ---------------------------------------------------------------------------
// Varyings -> fragment
// ---------------------------------------------------------------------------
varying vec2 texcoord;
varying vec2 lmcoord;
varying vec4 glcolor;
varying vec3 viewPos;
varying vec3 worldPos;
varying vec3 normal;
varying float blockId;
varying float isWater;  // 1.0 for water, 0.0 otherwise

// ---------------------------------------------------------------------------
// Gerstner wave helper
// ---------------------------------------------------------------------------
// Returns vertical displacement and modifies the normal estimate.
// A simplified single-octave Gerstner wave.
float gerstnerWave(vec2 pos, float time, float freq, float speed, float amp) {
    // Two overlapping wave directions for more organic motion
    float wave1 = sin(dot(vec2(0.6, 0.8), pos) * freq + time * speed);
    float wave2 = sin(dot(vec2(-0.4, 0.7), pos) * freq * 1.3 + time * speed * 0.9 + 1.5);
    return (wave1 + wave2 * 0.5) * amp;
}

// ---------------------------------------------------------------------------
// Helpers (same as terrain for waving plants that might exist in water pass)
// ---------------------------------------------------------------------------
float plantHash(vec3 pos) {
    return fract(sin(dot(floor(pos.xz), vec2(12.9898, 78.233))) * 43758.5453);
}

bool isWavingPlant(float id) {
    if (id == 31.0 || id == 175.0) return true;
    if (id == 18.0 || id == 161.0) return true;
    if (id == 37.0 || id == 38.0) return true;
    if (id == 106.0) return true;
    if (id == 59.0 || id == 141.0 || id == 142.0 || id == 207.0) return true;
    return false;
}

// ---------------------------------------------------------------------------
// Main
// ---------------------------------------------------------------------------
void main() {
    // -- Texture coordinates --------------------------------------------------
    texcoord = (gl_TextureMatrix[0] * gl_MultiTexCoord0).st;

    // -- Lightmap -------------------------------------------------------------
    lmcoord = clamp((gl_TextureMatrix[1] * gl_MultiTexCoord1).st, 0.0, 1.0);

    // -- Vertex colour --------------------------------------------------------
    glcolor = gl_Color;

    // -- Normal (view space) --------------------------------------------------
    normal = normalize(gl_NormalMatrix * gl_Normal);

    // -- Block ID -------------------------------------------------------------
    blockId = mc_Entity.x;

    // -- Water detection (block IDs 8, 9 = flowing/still water) ---------------
    isWater = (mc_Entity.x == 8.0 || mc_Entity.x == 9.0) ? 1.0 : 0.0;

    // -- Position transforms --------------------------------------------------
    vec4 viewPos4 = gl_ModelViewMatrix * gl_Vertex;
    viewPos = viewPos4.xyz;

    vec4 worldPos4 = gbufferModelViewInverse * viewPos4;
    worldPos = worldPos4.xyz + cameraPosition;

    // -- Water wave displacement ----------------------------------------------
#ifdef WATER_WAVES
    if (isWater > 0.5) {
        float time = frameTimeCounter * WAVE_SPEED;
        float displacement = gerstnerWave(worldPos.xz, time, WAVE_FREQUENCY, WAVE_SPEED, WAVE_HEIGHT);

        // Only displace upward-facing faces (the water surface, not sides)
        if (gl_Normal.y > 0.5) {
            worldPos4.y += displacement;

            // Recalculate view position from displaced world position
            viewPos4 = gbufferModelView * worldPos4;
            viewPos = viewPos4.xyz;

            // Approximate displaced normal via finite differences
            float dx = gerstnerWave(worldPos.xz + vec2(0.1, 0.0), time, WAVE_FREQUENCY, WAVE_SPEED, WAVE_HEIGHT) - displacement;
            float dz = gerstnerWave(worldPos.xz + vec2(0.0, 0.1), time, WAVE_FREQUENCY, WAVE_SPEED, WAVE_HEIGHT) - displacement;
            vec3 waveTangent  = normalize(vec3(0.1, dx, 0.0));
            vec3 waveBitangent = normalize(vec3(0.0, dz, 0.1));
            vec3 waveNormal   = normalize(cross(waveBitangent, waveTangent));

            // Transform displaced normal to view space
            normal = normalize(gl_NormalMatrix * (mat3(gbufferModelView) * waveNormal));
        }
    }
#endif

    // -- Waving plants (lilypads, seagrass, etc. may go through this pass) ----
#ifdef WAVING_PLANTS
    if (isWater < 0.5 && isWavingPlant(blockId)) {
        bool isTopVertex = (gl_MultiTexCoord0.t < mc_midTexCoord.t);
        if (isTopVertex) {
            float time = frameTimeCounter * WIND_SPEED;
            float phase = plantHash(worldPos) * 6.2831;
            float swayX = sin(time + phase + worldPos.x * 0.5) * WIND_STRENGTH;
            float swayZ = cos(time * 0.8 + phase + worldPos.z * 0.5) * WIND_STRENGTH;
            worldPos4.x += swayX;
            worldPos4.z += swayZ;
            viewPos4 = gbufferModelView * worldPos4;
            viewPos = viewPos4.xyz;
        }
    }
#endif

    // -- Final clip position --------------------------------------------------
    gl_Position = gl_ProjectionMatrix * viewPos4;
}
