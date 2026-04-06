#version 120

// ============================================================
//  Shadow Map Fragment Shader
// ============================================================

varying vec2 texcoord;
varying vec4 shadowColor;

uniform sampler2D texture;

void main() {
    // Sample the texture for alpha testing
    // This discards transparent pixels (leaves, glass, etc.)
    vec4 tex = texture2D(texture, texcoord);

    // Alpha test: discard fragments with low alpha
    if (tex.a < 0.1) {
        discard;
    }

    // Write shadow color for colored shadow support
    // RGB stores the color tint, alpha stores opacity
    gl_FragData[0] = vec4(tex.rgb * shadowColor.rgb, tex.a);

    // Depth is written automatically by OpenGL via gl_FragCoord.z
}
