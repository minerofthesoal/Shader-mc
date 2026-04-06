#version 120
// =============================================================================
// composite2.fsh - Third composite pass
//
// Completes the bloom Gaussian blur (vertical), combines bloom with the scene,
// and applies night eye adaptation for dark environments.
// =============================================================================

// ---------------------------------------------------------------------------
// Feature toggles
// ---------------------------------------------------------------------------
#define BLOOM
#define BLOOM_AMOUNT 0.10      // [0.05 0.08 0.1 0.15 0.2 0.25 0.3]
#define NIGHT_EYE

// ---------------------------------------------------------------------------
// Varyings
// ---------------------------------------------------------------------------
varying vec2 texcoord;

// ---------------------------------------------------------------------------
// Uniforms
// ---------------------------------------------------------------------------
uniform sampler2D colortex0;    // Scene color from composite1 (with SSR)
uniform sampler2D colortex1;    // Horizontally blurred bloom from composite1
uniform float viewHeight;
uniform int worldTime;

// ---------------------------------------------------------------------------
// Helper: Luminance
// ---------------------------------------------------------------------------
float luminance(vec3 color) {
    return dot(color, vec3(0.2126, 0.7152, 0.0722));
}

// ---------------------------------------------------------------------------
// 1) Bloom Vertical Blur
//
// Completes the two-pass separable Gaussian blur by applying the vertical
// component. Uses the same 13-tap kernel as the horizontal pass.
// ---------------------------------------------------------------------------
#ifdef BLOOM
vec3 bloomVerticalBlur(vec2 uv) {
    float texelSize = 1.0 / viewHeight;

    // Same Gaussian weights as horizontal pass (sigma ~ 4.0)
    float w0 = 0.1964825501;
    float w1 = 0.1747075801;
    float w2 = 0.1209853623;
    float w3 = 0.0653263330;
    float w4 = 0.0275283843;
    float w5 = 0.0090506338;
    float w6 = 0.0023205330;

    vec3 result = texture2D(colortex1, uv).rgb * w0;

    // Symmetric vertical taps
    result += texture2D(colortex1, uv + vec2(0.0, texelSize * 1.0)).rgb * w1;
    result += texture2D(colortex1, uv - vec2(0.0, texelSize * 1.0)).rgb * w1;
    result += texture2D(colortex1, uv + vec2(0.0, texelSize * 2.0)).rgb * w2;
    result += texture2D(colortex1, uv - vec2(0.0, texelSize * 2.0)).rgb * w2;
    result += texture2D(colortex1, uv + vec2(0.0, texelSize * 3.0)).rgb * w3;
    result += texture2D(colortex1, uv - vec2(0.0, texelSize * 3.0)).rgb * w3;
    result += texture2D(colortex1, uv + vec2(0.0, texelSize * 4.0)).rgb * w4;
    result += texture2D(colortex1, uv - vec2(0.0, texelSize * 4.0)).rgb * w4;
    result += texture2D(colortex1, uv + vec2(0.0, texelSize * 5.0)).rgb * w5;
    result += texture2D(colortex1, uv - vec2(0.0, texelSize * 5.0)).rgb * w5;
    result += texture2D(colortex1, uv + vec2(0.0, texelSize * 6.0)).rgb * w6;
    result += texture2D(colortex1, uv - vec2(0.0, texelSize * 6.0)).rgb * w6;

    return result;
}
#endif

// ---------------------------------------------------------------------------
// 2) Night Eye Adaptation
//
// Simulates the human eye adapting to darkness (scotopic vision). In very
// dark scenes, colors shift toward blue and brightness is boosted slightly.
// This mimics the Purkinje effect where rods (blue-sensitive) take over
// from cones in low-light conditions.
// ---------------------------------------------------------------------------
#ifdef NIGHT_EYE
vec3 applyNightEye(vec3 color) {
    float lum = luminance(color);

    // Only activate in dark scenes (low average luminance)
    float nightStrength = smoothstep(0.10, 0.01, lum);

    // Also factor in time of day: stronger at night
    float nightTime = 0.0;
    if (worldTime > 13000 && worldTime < 23000) {
        nightTime = 1.0;
    } else if (worldTime >= 12000 && worldTime <= 13000) {
        nightTime = float(worldTime - 12000) / 1000.0;
    } else if (worldTime >= 23000) {
        nightTime = 1.0 - float(worldTime - 23000) / 1000.0;
    }

    nightStrength *= nightTime;

    if (nightStrength < 0.001) return color;

    // Photon-style: subtle desaturation and blue shift at night
    float grey = luminance(color);
    vec3 blueShift = vec3(grey * 0.6, grey * 0.65, grey * 1.0);

    // Moderate brightness boost
    blueShift *= 1.5;

    return mix(color, blueShift, nightStrength * 0.45);
}
#endif

// ==========================================================================
// Main
// ==========================================================================
void main() {
    vec3 sceneColor = texture2D(colortex0, texcoord).rgb;

    // ---- 1) Vertical bloom blur ----
    vec3 bloomColor = vec3(0.0);
    #ifdef BLOOM
        bloomColor = bloomVerticalBlur(texcoord);

        // ---- 2) Combine bloom with scene ----
        // Additive blend of the soft glow onto the scene
        sceneColor += bloomColor * BLOOM_AMOUNT;
    #endif

    // ---- 3) Night eye adaptation ----
    #ifdef NIGHT_EYE
        sceneColor = applyNightEye(sceneColor);
    #endif

    // ================================================================
    // Output: final pre-graded scene color
    // ================================================================
    /* DRAWBUFFERS:0 */
    gl_FragData[0] = vec4(sceneColor, 1.0);
}
