#version 120

// ============================================================
//  Sky Fragment Shader - Atmospheric Scattering, Stars, Aurora
// ============================================================

varying vec3 viewDir;
varying vec4 starData;

uniform vec3 sunPosition;
uniform vec3 moonPosition;
uniform int worldTime;
uniform vec3 fogColor;
uniform float frameTimeCounter;
uniform float rainStrength;

// ----- Constants -----
const float PI = 3.14159265359;
const float TAU = 6.28318530718;

// Photon-style scattering coefficients — slightly less blue-heavy for natural sky
const vec3 RAYLEIGH_COEFF = vec3(5.5e-6, 13.0e-6, 30.0e-6);
// Mie scattering coefficient — subtle atmospheric haze
const float MIE_COEFF = 18.0e-6;
// Mie preferred scattering direction (asymmetry factor)
const float MIE_G = 0.80;

const float ATMOSPHERE_RADIUS = 6471e3;
const float PLANET_RADIUS     = 6371e3;
const float SCALE_HEIGHT_R    = 8000.0;
const float SCALE_HEIGHT_M    = 1200.0;

// ----- Utility Functions -----

// Hash functions for procedural noise
float hash(vec2 p) {
    float h = dot(p, vec2(127.1, 311.7));
    return fract(sin(h) * 43758.5453123);
}

float hash(vec3 p) {
    float h = dot(p, vec3(127.1, 311.7, 74.7));
    return fract(sin(h) * 43758.5453123);
}

// Smooth noise
float noise(vec2 p) {
    vec2 i = floor(p);
    vec2 f = fract(p);
    f = f * f * (3.0 - 2.0 * f);

    float a = hash(i);
    float b = hash(i + vec2(1.0, 0.0));
    float c = hash(i + vec2(0.0, 1.0));
    float d = hash(i + vec2(1.0, 1.0));

    return mix(mix(a, b, f.x), mix(c, d, f.x), f.y);
}

// Fractal brownian motion
float fbm(vec2 p) {
    float value = 0.0;
    float amp = 0.5;
    for (int i = 0; i < 5; i++) {
        value += amp * noise(p);
        p *= 2.0;
        amp *= 0.5;
    }
    return value;
}

// ----- Day/Night Cycle -----

// Returns 0.0 = full night, 1.0 = full day, with smooth transitions
float getDayFactor() {
    float time = float(worldTime);

    // Sunrise:  23000 -> 0 -> 1000   (night to day)
    // Day:      1000 -> 11000
    // Sunset:   11000 -> 13000        (day to night)
    // Night:    13000 -> 23000

    float dayFactor = 1.0;

    if (time < 1000.0) {
        // Late sunrise
        dayFactor = smoothstep(-1000.0, 1000.0, time);
    } else if (time < 11000.0) {
        dayFactor = 1.0;
    } else if (time < 13000.0) {
        dayFactor = 1.0 - smoothstep(11000.0, 13000.0, time);
    } else if (time < 23000.0) {
        dayFactor = 0.0;
    } else {
        // Early sunrise
        dayFactor = smoothstep(23000.0, 25000.0, time);
    }

    return dayFactor;
}

// Returns sun elevation factor: -1 below horizon, +1 at zenith
float getSunElevation() {
    vec3 sunDir = normalize(sunPosition);
    return sunDir.y;
}

// ----- Rayleigh Phase Function -----
float rayleighPhase(float cosTheta) {
    return (3.0 / (16.0 * PI)) * (1.0 + cosTheta * cosTheta);
}

// ----- Mie Phase Function (Henyey-Greenstein) -----
float miePhase(float cosTheta, float g) {
    float g2 = g * g;
    float num = (1.0 - g2);
    float denom = pow(1.0 + g2 - 2.0 * g * cosTheta, 1.5);
    return (3.0 / (8.0 * PI)) * num / denom;
}

// ----- Atmospheric Scattering -----
vec3 atmosphericScattering(vec3 dir, vec3 sunDir) {
    float cosTheta = dot(dir, sunDir);
    float sunAlt = sunDir.y;

    // Optical depth approximation based on view zenith angle
    float viewZenith = max(dir.y, 0.001);
    float opticalDepthR = SCALE_HEIGHT_R / viewZenith;
    float opticalDepthM = SCALE_HEIGHT_M / viewZenith;

    // Scattering
    vec3 rayleigh = RAYLEIGH_COEFF * rayleighPhase(cosTheta) * opticalDepthR;
    float mie = MIE_COEFF * miePhase(cosTheta, MIE_G) * opticalDepthM;

    // Extinction (light absorbed along path)
    vec3 extinction = exp(-(RAYLEIGH_COEFF * opticalDepthR + MIE_COEFF * opticalDepthM));

    // Photon-style: moderate sun intensity for natural sky brightness
    float sunIntensity = max(sunAlt + 0.1, 0.0);
    sunIntensity = pow(sunIntensity, 0.5) * 18.0;

    // Combined scattered light
    vec3 scatter = (rayleigh + mie) * sunIntensity;

    return scatter;
}

// ----- Sunset/Sunrise Color Enhancement -----
vec3 sunsetColors(vec3 dir, vec3 sunDir) {
    float sunAlt = sunDir.y;
    float horizonMask = 1.0 - smoothstep(0.0, 0.4, abs(dir.y));

    // Only near sunrise/sunset
    float sunsetFactor = smoothstep(0.3, 0.0, abs(sunAlt));
    sunsetFactor *= smoothstep(-0.1, 0.05, sunAlt);

    // Angular proximity to sun on horizon
    vec3 flatSun = normalize(vec3(sunDir.x, 0.0, sunDir.z));
    vec3 flatDir = normalize(vec3(dir.x, 0.0, dir.z));
    float sunProximity = max(dot(flatDir, flatSun), 0.0);
    sunProximity = pow(sunProximity, 2.0);

    // Photon-style: warm but not oversaturated sunset
    vec3 warmColor = mix(
        vec3(0.9, 0.35, 0.10),  // Warm orange at horizon
        vec3(0.95, 0.6, 0.3),   // Soft peach higher up
        smoothstep(0.0, 0.25, abs(dir.y))
    );

    // Subtle purple-blue opposite side
    vec3 coolColor = vec3(0.3, 0.2, 0.45);
    vec3 color = mix(coolColor, warmColor, sunProximity);

    return color * sunsetFactor * horizonMask * 2.0;
}

// ----- Procedural Stars -----
vec3 renderStars(vec3 dir) {
    float nightFactor = 1.0 - getDayFactor();
    if (nightFactor < 0.01) return vec3(0.0);

    // Use starData from vertex shader if available (vanilla stars)
    float vanillaStar = max(max(starData.r, starData.g), starData.b);

    // Procedural star field
    vec3 starDir = normalize(dir);

    // Multiple star layers for depth
    vec3 stars = vec3(0.0);

    // Layer 1: Bright stars (sparse)
    vec2 starUV1 = vec2(atan(starDir.z, starDir.x), asin(starDir.y));
    starUV1 *= vec2(80.0, 80.0);
    vec2 starCell1 = floor(starUV1);
    vec2 starFrac1 = fract(starUV1) - 0.5;

    float starRand1 = hash(starCell1);
    vec2 starOffset1 = vec2(hash(starCell1 + 100.0), hash(starCell1 + 200.0)) - 0.5;
    float starDist1 = length(starFrac1 - starOffset1 * 0.6);

    if (starRand1 > 0.97) {
        float brightness = (1.0 - smoothstep(0.0, 0.06, starDist1));
        brightness *= 0.6 + 0.4 * hash(starCell1 + 50.0);

        // Twinkle
        float twinkle = sin(frameTimeCounter * (2.0 + hash(starCell1 + 300.0) * 4.0)
                         + hash(starCell1 + 400.0) * TAU);
        twinkle = 0.7 + 0.3 * twinkle;
        brightness *= twinkle;

        // Color variation
        float colorSeed = hash(starCell1 + 500.0);
        vec3 starColor;
        if (colorSeed < 0.3) {
            starColor = vec3(0.8, 0.85, 1.0);   // Blue-white
        } else if (colorSeed < 0.5) {
            starColor = vec3(1.0, 0.95, 0.8);   // Warm white
        } else if (colorSeed < 0.65) {
            starColor = vec3(1.0, 0.6, 0.3);    // Orange giant
        } else if (colorSeed < 0.75) {
            starColor = vec3(0.6, 0.7, 1.0);    // Blue star
        } else {
            starColor = vec3(1.0, 0.85, 0.85);  // Slight red
        }

        stars += starColor * brightness * 1.2;
    }

    // Layer 2: Dim background stars (dense)
    vec2 starUV2 = vec2(atan(starDir.z, starDir.x), asin(starDir.y));
    starUV2 *= vec2(200.0, 200.0);
    vec2 starCell2 = floor(starUV2);
    vec2 starFrac2 = fract(starUV2) - 0.5;

    float starRand2 = hash(starCell2 + 700.0);
    float starDist2 = length(starFrac2);

    if (starRand2 > 0.985) {
        float brightness = (1.0 - smoothstep(0.0, 0.04, starDist2)) * 0.4;
        float twinkle = 0.8 + 0.2 * sin(frameTimeCounter * 3.0 + hash(starCell2) * TAU);
        stars += vec3(0.9, 0.92, 1.0) * brightness * twinkle;
    }

    // Combine with vanilla star data
    stars += vec3(vanillaStar) * 0.5;

    // Fade stars with rain
    stars *= (1.0 - rainStrength);

    return stars * nightFactor;
}

// ----- Milky Way -----
vec3 renderMilkyWay(vec3 dir) {
    float nightFactor = 1.0 - getDayFactor();
    if (nightFactor < 0.01) return vec3(0.0);

    // Milky way band oriented diagonally across the sky
    vec3 mwAxis = normalize(vec3(0.3, 0.1, 1.0));
    vec3 mwPerp = normalize(cross(mwAxis, vec3(0.0, 1.0, 0.0)));

    float bandDist = abs(dot(dir, mwPerp));
    float bandMask = smoothstep(0.35, 0.0, bandDist);

    // Along-band coordinate for detail
    float alongBand = dot(dir, mwAxis);
    float crossBand = dot(dir, mwPerp);
    vec2 mwUV = vec2(alongBand, crossBand) * 8.0;

    // Nebula-like structure
    float n1 = fbm(mwUV * 2.0 + vec2(0.0, 1.0));
    float n2 = fbm(mwUV * 3.5 + vec2(5.0, 3.0));
    float n3 = fbm(mwUV * 6.0 + vec2(2.0, 7.0));

    float milkyNoise = n1 * 0.5 + n2 * 0.3 + n3 * 0.2;
    milkyNoise = smoothstep(0.25, 0.75, milkyNoise);

    // Color: blue-purple nebula core, softer edges
    vec3 milkyColor = mix(
        vec3(0.15, 0.12, 0.25),   // Purple-blue core
        vec3(0.08, 0.1, 0.18),    // Dim blue edges
        smoothstep(0.0, 0.3, bandDist)
    );

    // Add warm dust lanes
    float dust = fbm(mwUV * 4.0 + vec2(10.0, 0.0));
    milkyColor += vec3(0.12, 0.06, 0.02) * dust * bandMask;

    vec3 milky = milkyColor * milkyNoise * bandMask * 0.8;

    milky *= (1.0 - rainStrength);
    return milky * nightFactor;
}

// ----- Aurora Borealis -----
vec3 renderAurora(vec3 dir) {
    float nightFactor = 1.0 - getDayFactor();
    if (nightFactor < 0.01) return vec3(0.0);

    // Aurora is visible in the northern sky, above the horizon
    if (dir.y < 0.05 || dir.y > 0.7) return vec3(0.0);

    // Northern sky mask (z-positive = north in MC)
    float northMask = smoothstep(-0.2, 0.4, dir.z);

    // Height mask - aurora curtains at specific elevation
    float heightMask = smoothstep(0.05, 0.15, dir.y) * smoothstep(0.7, 0.4, dir.y);

    // Curtain wave coordinates
    float x = atan(dir.x, dir.z) * 3.0;
    float y = dir.y * 10.0;
    float t = frameTimeCounter * 0.15;

    // Multiple curtain layers with animation
    float curtain1 = 0.0;
    float curtain2 = 0.0;

    // Layer 1 - primary curtain
    float wave1 = sin(x * 2.0 + t * 1.3) * 0.5
                + sin(x * 3.5 - t * 0.9) * 0.3
                + sin(x * 5.0 + t * 2.1) * 0.2;
    float curtainShape1 = smoothstep(0.6, 0.0, abs(y - 3.0 + wave1 * 1.5));
    curtain1 = curtainShape1;

    // Layer 2 - secondary curtain (offset)
    float wave2 = sin(x * 1.5 - t * 1.7 + 2.0) * 0.5
                + sin(x * 4.0 + t * 1.1 + 1.0) * 0.3;
    float curtainShape2 = smoothstep(0.5, 0.0, abs(y - 4.0 + wave2 * 1.2));
    curtain2 = curtainShape2;

    // Vertical shimmer
    float shimmer = noise(vec2(x * 8.0 + t * 3.0, y * 2.0 - t * 5.0));
    shimmer = smoothstep(0.3, 0.8, shimmer);

    // Color palette - green/cyan primary, purple edges
    vec3 color1 = mix(
        vec3(0.1, 0.8, 0.4),     // Bright green
        vec3(0.0, 0.6, 0.7),     // Cyan
        sin(x * 2.0 + t) * 0.5 + 0.5
    );

    vec3 color2 = mix(
        vec3(0.3, 0.1, 0.6),     // Purple
        vec3(0.1, 0.9, 0.5),     // Green
        sin(x * 1.5 - t * 0.7 + 1.5) * 0.5 + 0.5
    );

    // Combine curtains
    vec3 aurora = color1 * curtain1 * (0.6 + 0.4 * shimmer)
                + color2 * curtain2 * (0.5 + 0.5 * shimmer) * 0.7;

    // Edge glow - brighter at bottom of curtains
    float bottomGlow = smoothstep(0.3, 0.1, dir.y) * 0.5;
    aurora += aurora * bottomGlow;

    // Intensity pulsing
    float pulse = 0.7 + 0.3 * sin(frameTimeCounter * 0.4);
    aurora *= pulse;

    aurora *= northMask * heightMask;

    // Fade with rain
    aurora *= (1.0 - rainStrength);

    return aurora * nightFactor * 0.8;
}

// ----- Main -----
void main() {
    vec3 dir = normalize(viewDir);
    vec3 sunDir = normalize(sunPosition);
    vec3 moonDir = normalize(moonPosition);

    float dayFactor = getDayFactor();
    float nightFactor = 1.0 - dayFactor;

    // ---- Atmospheric scattering (day sky) ----
    vec3 daySky = atmosphericScattering(dir, sunDir);

    // Sunset/sunrise enhancement
    daySky += sunsetColors(dir, sunDir);

    // ---- Night sky base color ----
    vec3 nightSky = vec3(0.005, 0.007, 0.02);

    // Slight gradient: darker at zenith, bit lighter at horizon
    nightSky += vec3(0.005, 0.008, 0.015) * (1.0 - abs(dir.y));

    // Moonlit atmosphere (subtle Rayleigh from moonlight)
    float moonCosTheta = dot(dir, moonDir);
    float moonElevation = max(moonDir.y, 0.0);
    vec3 moonScatter = RAYLEIGH_COEFF * rayleighPhase(moonCosTheta)
                      * SCALE_HEIGHT_R / max(dir.y, 0.05)
                      * moonElevation * 0.3;
    nightSky += moonScatter * 800.0;

    // ---- Combine day and night base ----
    vec3 sky = mix(nightSky, daySky, dayFactor);

    // ---- Stars ----
    sky += renderStars(dir);

    // ---- Milky Way ----
    sky += renderMilkyWay(dir);

    // ---- Aurora Borealis ----
    sky += renderAurora(dir);

    // ---- Sun glow (Photon-style: clean, not overdone) ----
    float sunGlow = max(dot(dir, sunDir), 0.0);
    sky += vec3(1.0, 0.95, 0.85) * pow(sunGlow, 200.0) * 3.0 * dayFactor;  // tight core
    sky += vec3(0.95, 0.80, 0.55) * pow(sunGlow, 24.0) * 0.3 * dayFactor;  // soft halo

    // Moon glow (subtle)
    float moonGlow = max(dot(dir, moonDir), 0.0);
    sky += vec3(0.2, 0.25, 0.35) * pow(moonGlow, 80.0) * 1.5 * nightFactor;
    sky += vec3(0.10, 0.12, 0.20) * pow(moonGlow, 10.0) * 0.2 * nightFactor;

    // ---- Horizon fog blending ----
    float horizonFog = 1.0 - smoothstep(0.0, 0.15, abs(dir.y));
    horizonFog = pow(horizonFog, 2.0);
    sky = mix(sky, fogColor, horizonFog * (0.6 + 0.4 * rainStrength));

    // Rain darkening
    sky = mix(sky, fogColor * 0.4, rainStrength * 0.7);

    // Output linear HDR — let composite/final passes handle tonemapping
    // Just clamp to reasonable range to prevent fireflies
    sky = max(sky, vec3(0.0));

    gl_FragColor = vec4(sky, 1.0);
}
