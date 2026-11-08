#version 330 compatibility
noperspective out vec2 vTexCoord;
void main() {
    gl_Position = ftransform();
    vTexCoord = (gl_TextureMatrix[0] * gl_MultiTexCoord0).xy;
}
