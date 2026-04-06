#version 120
// =============================================================================
// final.fsh - Final output pass (Photon-style clean PBR look)
//
// Clean tone mapping with natural color grading. No heavy post-processing
// artifacts — prioritizes physical accuracy and natural appearance.
// =============================================================================

// ---------------------------------------------------------------------------
// Feature toggles
// ---------------------------------------------------------------------------
#define EXPOSURE 1.0            // [0.5 0.7 0.8 0.9 1.0 1.1 1.2 1.5 2.0]
#define SATURATION 1.05         // [0.5 0.7 0.8 0.9 1.0 1.05 1.1 1.2 1.3]
#define COLOR_TEMPERATURE 6500  // [3000 4000 5000 5500 6000 6500 7000 8000 10000]
//#define VIGNETTE              // Disabled by default for clean Photon look
#define VIGNETTE_AMOUNT 0.15    // [0.1 0.15 0.2 0.25 0.3 0.4 0.5]
//#define CHROMATIC_ABERRATION  // Disabled — Photon doesn't use it
#define NIGHT_EYE

// ---------------------------------------------------------------------------
// Varyings
// ---------------------------------------------------------------------------
varying vec2 texcoord;

// ---------------------------------------------------------------------------
// Uniforms
// ---------------------------------------------------------------------------
uniform sampler2D colortex0;    // Pre-graded scene from composite2
uniform float viewWidth;
uniform float viewHeight;
uniform float frameTimeCounter;

// ---------------------------------------------------------------------------
// Helper: Luminance
// ---------------------------------------------------------------------------
float luminance(vec3 color) {
    return dot(color, vec3(0.2126, 0.7152, 0.0722));
}

// ---------------------------------------------------------------------------
// 1) Color Temperature (Kelvin-based white balance)
// ---------------------------------------------------------------------------
vec3 colorTemperature(float kelvin) {
    float temp = kelvin / 100.0;
    vec3 result;

    if (temp <= 66.0) {
        result.r = 1.0;
    } else {
        float r = temp - 60.0;
        r = 329.698727446 * pow(r, -0.1332047592);
        result.r = clamp(r / 255.0, 0.0, 1.0);
    }

    if (temp <= 66.0) {
        float g = temp;
        g = 99.4708025861 * log(g) - 161.1195681661;
        result.g = clamp(g / 255.0, 0.0, 1.0);
    } else {
        float g = temp - 60.0;
        g = 288.1221695283 * pow(g, -0.0755148492);
        result.g = clamp(g / 255.0, 0.0, 1.0);
    }

    if (temp >= 66.0) {
        result.b = 1.0;
    } else if (temp <= 19.0) {
        result.b = 0.0;
    } else {
        float b = temp - 10.0;
        b = 138.5177312231 * log(b) - 305.0447927307;
        result.b = clamp(b / 255.0, 0.0, 1.0);
    }

    return result;
}

vec3 applyColorTemperature(vec3 color) {
    vec3 targetTint  = colorTemperature(float(COLOR_TEMPERATURE));
    vec3 neutralTint = colorTemperature(6500.0);
    vec3 correction = targetTint / max(neutralTint, vec3(0.001));
    return color * correction;
}

// ---------------------------------------------------------------------------
// 2) Tone Mapping — Photon-style clean ACES
//
// Modified ACES curve with slightly lifted shadows and softer highlight
// rolloff for a more natural, less contrasty look typical of Photon.
// ---------------------------------------------------------------------------
vec3 acesFilm(vec3 x) {
    x *= EXPOSURE;

    // Softer ACES curve — less aggressive contrast than standard
    // Lifted toe (shadows not crushed), gentle shoulder (highlights preserved)
    float a = 2.51;
    float b = 0.03;
    float c = 2.43;
    float d = 0.59;
    float e = 0.14;

    vec3 mapped = clamp((x * (a * x + b)) / (x * (c * x + d) + e), 0.0, 1.0);

    // Photon-style: slightly lift shadows to avoid crushing blacks
    // This gives a more natural, less contrasty look
    mapped = mix(mapped, sqrt(mapped), 0.08);

    return mapped;
}

// ---------------------------------------------------------------------------
// 3) Saturation — very subtle, Photon keeps colors natural
// ---------------------------------------------------------------------------
vec3 applySaturation(vec3 color) {
    float lum = luminance(color);
    vec3 grey = vec3(lum);
    return max(mix(grey, color, SATURATION), vec3(0.0));
}

// ---------------------------------------------------------------------------
// 4) Vignette (subtle if enabled)
// ---------------------------------------------------------------------------
#ifdef VIGNETTE
vec3 applyVignette(vec3 color, vec2 uv) {
    vec2 centered = uv - 0.5;
    float aspect = viewWidth / viewHeight;
    centered.x *= aspect;
    float dist = length(centered);
    float vignette = smoothstep(1.0, 0.4, dist * (1.0 + VIGNETTE_AMOUNT));
    vignette = mix(1.0, vignette, VIGNETTE_AMOUNT);
    return color * vignette;
}
#endif

// ---------------------------------------------------------------------------
// 5) Chromatic Aberration (disabled by default for Photon style)
// ---------------------------------------------------------------------------
#ifdef CHROMATIC_ABERRATION
vec3 applyChromaticAberration(vec2 uv) {
    vec2 centered = uv - 0.5;
    float dist = length(centered);
    float strength = dist * dist * 0.002;
    vec2 dir = normalize(centered + vec2(0.0001));

    vec2 uvR = uv + dir * strength;
    vec2 uvG = uv;
    vec2 uvB = uv - dir * strength;

    float r = texture2D(colortex0, uvR).r;
    float g = texture2D(colortex0, uvG).g;
    float b = texture2D(colortex0, uvB).b;

    return vec3(r, g, b);
}
#endif

// ---------------------------------------------------------------------------
// 6) Gamma Correction (Linear to sRGB)
// ---------------------------------------------------------------------------
vec3 linearToSRGB(vec3 linear) {
    return pow(linear, vec3(1.0 / 2.2));
}

// ==========================================================================
// Main
// ==========================================================================
void main() {
    vec3 color;

    #ifdef CHROMATIC_ABERRATION
        color = applyChromaticAberration(texcoord);
    #else
        color = texture2D(colortex0, texcoord).rgb;
    #endif

    // ---- 1) Color temperature ----
    color = applyColorTemperature(color);

    // ---- 2) Tone mapping ----
    color = acesFilm(color);

    // ---- 3) Saturation (subtle) ----
    color = applySaturation(color);

    // ---- 4) Vignette ----
    #ifdef VIGNETTE
        color = applyVignette(color, texcoord);
    #endif

    // ---- 5) Gamma correction ----
    color = linearToSRGB(color);

    // No film grain — clean Photon-style output

    color = clamp(color, 0.0, 1.0);

    gl_FragColor = vec4(color, 1.0);
}
