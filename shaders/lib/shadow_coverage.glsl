#ifndef YUNMENG_SHADOW_COVERAGE
#define YUNMENG_SHADOW_COVERAGE
// Match surface and air lighting at the finite shadow-map boundary.
float shadowCoverageWeight(vec3 uv) {
    vec3 edge = min(uv, vec3(1.0) - uv);
    return smoothstep(0.002, 0.025, min(edge.x, edge.y))
         * smoothstep(0.002, 0.010, edge.z);
}
#endif
