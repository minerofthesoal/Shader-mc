#version 120

varying vec2 texcoord;
varying vec4 color;
varying vec3 viewDir;

uniform sampler2D texture;
uniform vec3 sunPosition;
uniform int worldTime;
uniform vec3 fogColor;

const float PI = 3.14159265359;

// Day factor: 0 = night, 1 = day
float getDayFactor() {
    float time = float(worldTime);
    float dayFactor = 1.0;

    if (time < 1000.0) {
        dayFactor = smoothstep(-1000.0, 1000.0, time);
    } else if (time < 11000.0) {
        dayFactor = 1.0;
    } else if (time < 13000.0) {
        dayFactor = 1.0 - smoothstep(11000.0, 13000.0, time);
    } else if (time < 23000.0) {
        dayFactor = 0.0;
    } else {
        dayFactor = smoothstep(23000.0, 25000.0, time);
    }
    return dayFactor;
}

void main() {
    vec4 tex = texture2D(texture, texcoord) * color;
    vec3 dir = normalize(viewDir);
    vec3 sunDir = normalize(sunPosition);

    float dayFactor = getDayFactor();
    float isSun = dayFactor; // sun visible during day

    // Distance from fragment to center of the celestial body in texcoord space
    vec2 centerOffset = texcoord - vec2(0.5);
    float distFromCenter = length(centerOffset);

    // ---- Sun Corona Glow ----
    if (isSun > 0.5) {
        // Soft radial glow extending beyond the sun disc
        float corona = 1.0 / (1.0 + pow(distFromCenter * 4.0, 2.0));
        corona *= smoothstep(0.5, 0.15, distFromCenter);
        vec3 coronaColor = mix(
            vec3(1.0, 0.95, 0.8),    // White-yellow center
            vec3(1.0, 0.6, 0.2),     // Orange edge
            smoothstep(0.1, 0.4, distFromCenter)
        );
        tex.rgb += coronaColor * corona * 0.6;

        // Inner glow - hot white core
        float innerGlow = smoothstep(0.2, 0.0, distFromCenter);
        tex.rgb += vec3(1.0, 0.98, 0.95) * innerGlow * 0.4;

        // ---- Lens Flare Rings ----
        // Ring 1
        float ring1 = abs(distFromCenter - 0.25);
        ring1 = smoothstep(0.02, 0.0, ring1);
        tex.rgb += vec3(1.0, 0.85, 0.5) * ring1 * 0.15;

        // Ring 2 (larger, dimmer)
        float ring2 = abs(distFromCenter - 0.38);
        ring2 = smoothstep(0.015, 0.0, ring2);
        tex.rgb += vec3(0.8, 0.7, 1.0) * ring2 * 0.08;

        // Subtle chromatic fringe
        float fringe = abs(distFromCenter - 0.32);
        float fringeR = smoothstep(0.02, 0.0, fringe - 0.005);
        float fringeB = smoothstep(0.02, 0.0, fringe + 0.005);
        tex.rgb += vec3(fringeR * 0.05, 0.0, fringeB * 0.05);
    }

    // ---- Moon Blue Tint ----
    if (isSun < 0.5) {
        // Apply cool blue-silver tint to the moon
        vec3 moonTint = vec3(0.7, 0.8, 1.0);
        tex.rgb *= moonTint;

        // Subtle glow around moon
        float moonGlow = 1.0 / (1.0 + pow(distFromCenter * 5.0, 2.0));
        moonGlow *= smoothstep(0.5, 0.2, distFromCenter);
        tex.rgb += vec3(0.15, 0.2, 0.35) * moonGlow * 0.4;

        // Slightly brighten the moon surface
        float moonSurface = smoothstep(0.25, 0.0, distFromCenter);
        tex.rgb += vec3(0.05, 0.07, 0.12) * moonSurface;
    }

    // ---- Horizon fade ----
    float horizonFade = smoothstep(0.0, 0.1, abs(dir.y));
    tex.a *= horizonFade;

    // Fog blending at horizon
    float fogBlend = 1.0 - smoothstep(0.0, 0.15, abs(dir.y));
    tex.rgb = mix(tex.rgb, fogColor, fogBlend * 0.5);

    gl_FragColor = tex;
}
