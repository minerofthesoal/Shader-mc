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

    // ---- Sun (Photon-style: clean, bright, no lens flare artifacts) ----
    if (isSun > 0.5) {
        // Soft radial glow — clean and natural
        float corona = 1.0 / (1.0 + pow(distFromCenter * 5.0, 2.0));
        corona *= smoothstep(0.45, 0.12, distFromCenter);
        vec3 coronaColor = mix(
            vec3(1.0, 0.97, 0.90),   // Near-white center
            vec3(1.0, 0.80, 0.50),   // Warm edge
            smoothstep(0.08, 0.35, distFromCenter)
        );
        tex.rgb += coronaColor * corona * 0.4;

        // Clean bright core
        float innerGlow = smoothstep(0.15, 0.0, distFromCenter);
        tex.rgb += vec3(1.0, 0.98, 0.95) * innerGlow * 0.3;

        // No lens flare rings — Photon keeps it clean
    }

    // ---- Moon (Photon-style: silver-blue, subtle) ----
    if (isSun < 0.5) {
        // Cool silver-blue tint
        vec3 moonTint = vec3(0.75, 0.82, 1.0);
        tex.rgb *= moonTint;

        // Very subtle glow
        float moonGlow = 1.0 / (1.0 + pow(distFromCenter * 6.0, 2.0));
        moonGlow *= smoothstep(0.4, 0.15, distFromCenter);
        tex.rgb += vec3(0.10, 0.13, 0.25) * moonGlow * 0.3;
    }

    // ---- Horizon fade ----
    float horizonFade = smoothstep(0.0, 0.1, abs(dir.y));
    tex.a *= horizonFade;

    // Fog blending at horizon
    float fogBlend = 1.0 - smoothstep(0.0, 0.15, abs(dir.y));
    tex.rgb = mix(tex.rgb, fogColor, fogBlend * 0.5);

    gl_FragColor = tex;
}
