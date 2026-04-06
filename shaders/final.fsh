#version 120
// =============================================================================
// final.fsh - Final output pass
//
// Applies all screen-level post-processing: color temperature, ACES tone
// mapping, saturation/vibrance, vignette, chromatic aberration, gamma
// correction, and film grain.
// =============================================================================

// ---------------------------------------------------------------------------
// Feature toggles
// ---------------------------------------------------------------------------
#define EXPOSURE 1.0            // [0.5 0.7 0.8 0.9 1.0 1.1 1.2 1.5 2.0]
#define SATURATION 1.1          // [0.5 0.7 0.8 0.9 1.0 1.1 1.2 1.3 1.5]
#define COLOR_TEMPERATURE 6500  // [3000 4000 5000 5500 6000 6500 7000 8000 10000]
#define VIGNETTE
#define VIGNETTE_AMOUNT 0.25    // [0.1 0.15 0.2 0.25 0.3 0.4 0.5]
#define CHROMATIC_ABERRATION
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
//
// Attempt to approximate the color of a blackbody radiator at the given
// temperature in Kelvin. D65 (6500K) is neutral. Lower values are warmer
// (more orange), higher values are cooler (more blue).
//
// Based on Tanner Helland's approximation:
// http://www.tannerhelland.com/4435/convert-temperature-rgb-algorithm-code/
// ---------------------------------------------------------------------------
vec3 colorTemperature(float kelvin) {
    float temp = kelvin / 100.0;
    vec3 result;

    // Red channel
    if (temp <= 66.0) {
        result.r = 1.0;
    } else {
        float r = temp - 60.0;
        r = 329.698727446 * pow(r, -0.1332047592);
        result.r = clamp(r / 255.0, 0.0, 1.0);
    }

    // Green channel
    if (temp <= 66.0) {
        float g = temp;
        g = 99.4708025861 * log(g) - 161.1195681661;
        result.g = clamp(g / 255.0, 0.0, 1.0);
    } else {
        float g = temp - 60.0;
        g = 288.1221695283 * pow(g, -0.0755148492);
        result.g = clamp(g / 255.0, 0.0, 1.0);
    }

    // Blue channel
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
    // Get the tint for the target temperature relative to D65
    vec3 targetTint  = colorTemperature(float(COLOR_TEMPERATURE));
    vec3 neutralTint = colorTemperature(6500.0);

    // Ratio of target to neutral gives us the correction multiplier
    vec3 correction = targetTint / max(neutralTint, vec3(0.001));

    return color * correction;
}

// ---------------------------------------------------------------------------
// 2) ACES Filmic Tone Mapping
//
// Standard ACES approximation fit by Stephen Hill. Maps HDR linear values
// to LDR with a pleasing S-curve that preserves highlights and shadows.
// ---------------------------------------------------------------------------
vec3 acesFilm(vec3 x) {
    // Apply exposure before tone mapping
    x *= EXPOSURE;

    // ACES fitted curve (sRGB monitor transform approximation)
    float a = 2.51;
    float b = 0.03;
    float c = 2.43;
    float d = 0.59;
    float e = 0.14;

    return clamp((x * (a * x + b)) / (x * (c * x + d) + e), 0.0, 1.0);
}

// ---------------------------------------------------------------------------
// 3) Saturation + Vibrance
//
// Adjusts color saturation uniformly, then applies vibrance which boosts
// less-saturated colors more than already-saturated ones. This prevents
// over-saturation of already vivid colors while enriching dull areas.
// ---------------------------------------------------------------------------
vec3 applySaturation(vec3 color) {
    float lum = luminance(color);
    vec3 grey = vec3(lum);

    // Basic saturation adjustment
    vec3 saturated = mix(grey, color, SATURATION);

    // Vibrance: boost desaturated colors more
    float currentSat = length(color - grey);
    float vibranceBoost = 1.0 - smoothstep(0.0, 0.5, currentSat);
    float vibranceAmount = 0.15; // subtle
    saturated = mix(saturated, color * (1.0 + vibranceAmount), vibranceBoost * vibranceAmount);

    return max(saturated, vec3(0.0));
}

// ---------------------------------------------------------------------------
// 4) Vignette
//
// Darkens the edges and corners of the screen with a smooth circular
// falloff. Creates a subtle focus-on-center effect common in photography.
// ---------------------------------------------------------------------------
#ifdef VIGNETTE
vec3 applyVignette(vec3 color, vec2 uv) {
    // Distance from center (0,0 at center, ~0.707 at corners)
    vec2 centered = uv - 0.5;

    // Correct for aspect ratio so the vignette is circular, not elliptical
    float aspect = viewWidth / viewHeight;
    centered.x *= aspect;

    float dist = length(centered);

    // Smooth falloff from center to edges
    float vignette = smoothstep(0.9, 0.4, dist * (1.0 + VIGNETTE_AMOUNT));
    vignette = mix(1.0, vignette, VIGNETTE_AMOUNT);

    return color * vignette;
}
#endif

// ---------------------------------------------------------------------------
// 5) Chromatic Aberration
//
// Simulates the prismatic color fringing of imperfect lenses by sampling
// each RGB channel at slightly offset UV coordinates. The offset increases
// toward the screen edges for a realistic look.
// ---------------------------------------------------------------------------
#ifdef CHROMATIC_ABERRATION
vec3 applyChromaticAberration(vec2 uv) {
    // Direction from center
    vec2 centered = uv - 0.5;
    float dist = length(centered);

    // Offset strength increases toward edges (quadratic falloff)
    float strength = dist * dist * 0.003;

    // Offset direction is radial from center
    vec2 dir = normalize(centered + vec2(0.0001)); // avoid zero

    // Sample each channel at different offsets
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
//
// Converts from linear color space to sRGB gamma for correct display on
// standard monitors. Uses the official sRGB piecewise transfer function.
// ---------------------------------------------------------------------------
vec3 linearToSRGB(vec3 linear) {
    // Simplified gamma curve (close enough to sRGB for games)
    return pow(linear, vec3(1.0 / 2.2));
}

// ---------------------------------------------------------------------------
// 7) Film Grain
//
// Adds very subtle luminance noise to simulate analog film grain. This
// helps break up color banding in gradients and adds a cinematic quality.
// The grain is animated per-frame so it shimmers naturally.
// ---------------------------------------------------------------------------
vec3 applyFilmGrain(vec3 color, vec2 uv) {
    // Hash-based noise: fast and screen-space
    float noise = fract(sin(dot(uv * vec2(viewWidth, viewHeight) +
                    vec2(frameTimeCounter * 143.0, frameTimeCounter * 67.0),
                    vec2(12.9898, 78.233))) * 43758.5453);

    // Center the noise around 0 (-0.5 to +0.5)
    noise = noise - 0.5;

    // Very subtle: barely perceptible grain
    float grainStrength = 0.025;

    // Reduce grain in bright areas (more visible in shadows, like real film)
    float lum = luminance(color);
    float shadowBias = mix(1.0, 0.3, smoothstep(0.0, 0.5, lum));

    return color + vec3(noise * grainStrength * shadowBias);
}

// ==========================================================================
// Main
// ==========================================================================
void main() {
    // ---- Sample scene color ----
    vec3 color;

    // If chromatic aberration is on, use offset sampling from the start
    #ifdef CHROMATIC_ABERRATION
        color = applyChromaticAberration(texcoord);
    #else
        color = texture2D(colortex0, texcoord).rgb;
    #endif

    // ---- 1) Color temperature ----
    color = applyColorTemperature(color);

    // ---- 2) ACES filmic tone mapping with exposure ----
    color = acesFilm(color);

    // ---- 3) Saturation and vibrance ----
    color = applySaturation(color);

    // ---- 4) Vignette ----
    #ifdef VIGNETTE
        color = applyVignette(color, texcoord);
    #endif

    // ---- 6) Gamma correction (linear to sRGB) ----
    color = linearToSRGB(color);

    // ---- 7) Film grain (applied after gamma for perceptual uniformity) ----
    color = applyFilmGrain(color, texcoord);

    // ---- Final clamp to valid range ----
    color = clamp(color, 0.0, 1.0);

    // ================================================================
    // Output: final pixel color to the screen
    // ================================================================
    gl_FragColor = vec4(color, 1.0);
}
