//
//     Copyright 2013 Pixar
//
//     Licensed under the Apache License, Version 2.0 (the "License");
//     you may not use this file except in compliance with the License
//     and the following modification to it: Section 6 Trademarks.
//     deleted and replaced with:
//
//     6. Trademarks. This License does not grant permission to use the
//     trade names, trademarks, service marks, or product names of the
//     Licensor and its affiliates, except as required for reproducing
//     the content of the NOTICE file.
//
//     You may obtain a copy of the License at
//
//     http://www.apache.org/licenses/LICENSE-2.0
//
//     Unless required by applicable law or agreed to in writing,
//     software distributed under the License is distributed on an
//     "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND,
//     either express or implied.  See the License for the specific
//     language governing permissions and limitations under the
//     License.
//

//--------------------------------------------------------------
// Common
//--------------------------------------------------------------
uniform float displacementScale = 1.0;
uniform float bumpScale = 1.0;

vec4 GeneratePatchCoord(vec2 localUV, int primitiveID)  // for non-adpative
{
    ivec2 ptexIndex = texelFetch(OsdPatchParamBuffer, primitiveID).xy;
    int faceID = ptexIndex.x;
    int lv = 1 << ((ptexIndex.y & 0xf) - ((ptexIndex.y >> 4) & 1));
    int u = (ptexIndex.y >> 17) & 0x3ff;
    int v = (ptexIndex.y >> 7) & 0x3ff;
    vec2 uv = localUV;
    uv = (uv * vec2(1.0)/lv) + vec2(u, v)/lv;
    
    return vec4(uv.x, uv.y, lv+0.5, faceID+0.5);
}

vec4 PTexLookup(vec4 patchCoord,
                sampler2DArray data,
                samplerBuffer packings,
                isamplerBuffer pages)
{
    vec2 uv = patchCoord.xy;
    int faceID = int(patchCoord.w);
    int page = texelFetch(pages, faceID).x;
    vec4 packing = texelFetch(packings, faceID);
    vec3 coords = vec3( packing.x + uv.x * packing.z,
                        packing.y + uv.y * packing.w,
                        page);

    return texture(data, coords);
}

#ifdef USE_PTEX_DISPLACEMENT

#undef OSD_DISPLACEMENT_CALLBACK
#define OSD_DISPLACEMENT_CALLBACK              \
    outpt.v.position =                         \
        displacement(outpt.v.position,         \
                     outpt.v.normal,           \
                     outpt.v.patchCoord);

uniform sampler2DArray textureDisplace_Data;
uniform samplerBuffer textureDisplace_Packing;
uniform isamplerBuffer textureDisplace_Pages;

vec4 displacement(vec4 position, vec3 normal, vec4 patchCoord)
{
    float disp = PTexLookup(patchCoord,
                            textureDisplace_Data,
                            textureDisplace_Packing,
                            textureDisplace_Pages).x;
    return position + vec4(disp * normal, 0) * displacementScale;
}
#endif

//--------------------------------------------------------------
// Vertex Shader
//--------------------------------------------------------------
#ifdef VERTEX_SHADER

layout (location=0) in vec4 position;
layout (location=1) in vec3 normal;

out block {
    OutputVertex v;
} outpt;

void main()
{
    outpt.v.position = ModelViewMatrix * position;
    outpt.v.normal = (ModelViewMatrix * vec4(normal, 0)).xyz;
}

#endif

//--------------------------------------------------------------
// Geometry Shader
//--------------------------------------------------------------
#ifdef GEOMETRY_SHADER

#ifdef PRIM_QUAD

    layout(lines_adjacency) in;

    layout(triangle_strip, max_vertices = 4) out;

    #define EDGE_VERTS 4

    in block {
        OutputVertex v;
    } inpt[4];

#endif // PRIM_QUAD

#ifdef  PRIM_TRI

    layout(triangles) in;

    layout(triangle_strip, max_vertices = 3) out;

    #define EDGE_VERTS 3

    in block {
        OutputVertex v;
    } inpt[3];

#endif // PRIM_TRI

out block {
    OutputVertex v;
    noperspective out vec4 edgeDistance;
} outpt;

// --------------------------------------

void emit(vec4 position, vec3 normal, vec4 patchCoord)
{
    outpt.v.position = position;
    outpt.v.patchCoord = patchCoord;
    outpt.v.normal = normal;

    gl_Position = ProjectionMatrix * outpt.v.position;
    EmitVertex();
}

const float VIEWPORT_SCALE = 1024.0; // XXXdyu

float edgeDistance(vec4 p, vec4 p0, vec4 p1)
{
    return VIEWPORT_SCALE *
        abs((p.x - p0.x) * (p1.y - p0.y) -
            (p.y - p0.y) * (p1.x - p0.x)) / length(p1.xy - p0.xy);
}

void emit(int index, vec4 position, vec3 normal, vec4 patchCoord, vec4 edgeVerts[EDGE_VERTS])
{
    outpt.edgeDistance[0] =
        edgeDistance(edgeVerts[index], edgeVerts[0], edgeVerts[1]);
    outpt.edgeDistance[1] =
        edgeDistance(edgeVerts[index], edgeVerts[1], edgeVerts[2]);
#ifdef PRIM_TRI
    outpt.edgeDistance[2] =
        edgeDistance(edgeVerts[index], edgeVerts[2], edgeVerts[0]);
#endif
#ifdef PRIM_QUAD
    outpt.edgeDistance[2] =
        edgeDistance(edgeVerts[index], edgeVerts[2], edgeVerts[3]);
    outpt.edgeDistance[3] =
        edgeDistance(edgeVerts[index], edgeVerts[3], edgeVerts[0]);
#endif

    emit(position, normal, patchCoord);
}

// --------------------------------------

void main()
{
    gl_PrimitiveID = gl_PrimitiveIDIn;

#ifdef PRIM_QUAD
    vec4 patchCoord[4];
    vec4 position[4];
    vec3 normal[4];

    // need to generate patch coord for non-patch quads
    patchCoord[0] = GeneratePatchCoord(vec2(0, 0), gl_PrimitiveID);
    patchCoord[1] = GeneratePatchCoord(vec2(1, 0), gl_PrimitiveID);
    patchCoord[2] = GeneratePatchCoord(vec2(1, 1), gl_PrimitiveID);
    patchCoord[3] = GeneratePatchCoord(vec2(0, 1), gl_PrimitiveID);

#ifdef USE_PTEX_DISPLACEMENT
    position[0] = displacement(inpt[0].v.position, inpt[0].v.normal, patchCoord[0]);
    position[1] = displacement(inpt[1].v.position, inpt[1].v.normal, patchCoord[1]);
    position[2] = displacement(inpt[2].v.position, inpt[2].v.normal, patchCoord[2]);
    position[3] = displacement(inpt[3].v.position, inpt[3].v.normal, patchCoord[3]);
#else
    position[0] = inpt[0].v.position;
    position[1] = inpt[1].v.position;
    position[2] = inpt[2].v.position;
    position[3] = inpt[3].v.position;
#endif

#ifdef FLAT_NORMALS
    // XXX: need to use vec C to get triangle normal.
    vec3 A = (position[0] - position[1]).xyz;
    vec3 B = (position[3] - position[1]).xyz;
    vec3 C = (position[2] - position[1]).xyz;
    normal[0] = normalize(cross(B, A));
    normal[1] = normal[0];
    normal[2] = normal[0];
    normal[3] = normal[0];
#else
    normal[0] = inpt[0].v.normal;
    normal[1] = inpt[1].v.normal;
    normal[2] = inpt[2].v.normal;
    normal[3] = inpt[3].v.normal;
#endif

#if defined(GEOMETRY_OUT_WIRE) || defined(GEOMETRY_OUT_LINE)
    vec4 edgeVerts[EDGE_VERTS];
    edgeVerts[0] = ProjectionMatrix * inpt[0].v.position;
    edgeVerts[1] = ProjectionMatrix * inpt[1].v.position;
    edgeVerts[2] = ProjectionMatrix * inpt[2].v.position;
    edgeVerts[3] = ProjectionMatrix * inpt[3].v.position;

    edgeVerts[0].xy /= edgeVerts[0].w;
    edgeVerts[1].xy /= edgeVerts[1].w;
    edgeVerts[2].xy /= edgeVerts[2].w;
    edgeVerts[3].xy /= edgeVerts[3].w;

    emit(0, position[0], normal[0], patchCoord[0], edgeVerts);
    emit(1, position[1], normal[1], patchCoord[1], edgeVerts);
    emit(3, position[3], normal[3], patchCoord[3], edgeVerts);
    emit(2, position[2], normal[2], patchCoord[2], edgeVerts);
#else
    outpt.edgeDistance[0] = 0;
    outpt.edgeDistance[1] = 0;
    outpt.edgeDistance[2] = 0;
    outpt.edgeDistance[3] = 0;
    emit(position[0], normal[0], patchCoord[0]);
    emit(position[1], normal[1], patchCoord[1]);
    emit(position[3], normal[3], patchCoord[3]);
    emit(position[2], normal[2], patchCoord[2]);
#endif
#endif // PRIM_QUAD

#ifdef PRIM_TRI
    vec4 position[3];
    vec4 patchCoord[3];
    vec3 normal[3];

    // patch coords are computed in tessellation shader
    patchCoord[0] = inpt[0].v.patchCoord;
    patchCoord[1] = inpt[1].v.patchCoord;
    patchCoord[2] = inpt[2].v.patchCoord;

#ifdef USE_PTEX_DISPLACEMENT
    position[0] = displacement(inpt[0].v.position, inpt[0].v.normal, patchCoord[0]);
    position[1] = displacement(inpt[1].v.position, inpt[1].v.normal, patchCoord[1]);
    position[2] = displacement(inpt[2].v.position, inpt[2].v.normal, patchCoord[2]);
#else
    position[0] = inpt[0].v.position;
    position[1] = inpt[1].v.position;
    position[2] = inpt[2].v.position;
#endif

#ifdef FLAT_NORMALS  // emit flat normals for displaced surface
    vec3 A = (position[0] - position[1]).xyz;
    vec3 B = (position[2] - position[1]).xyz;
    normal[0] = normalize(cross(B, A));
    normal[1] = normal[0];
    normal[2] = normal[0];
#else
    normal[0] = inpt[0].v.normal;
    normal[1] = inpt[1].v.normal;
    normal[2] = inpt[2].v.normal;
#endif

#if defined(GEOMETRY_OUT_WIRE) || defined(GEOMETRY_OUT_LINE)
    vec4 edgeVerts[EDGE_VERTS];
    edgeVerts[0] = ProjectionMatrix * inpt[0].v.position;
    edgeVerts[1] = ProjectionMatrix * inpt[1].v.position;
    edgeVerts[2] = ProjectionMatrix * inpt[2].v.position;

    edgeVerts[0].xy /= edgeVerts[0].w;
    edgeVerts[1].xy /= edgeVerts[1].w;
    edgeVerts[2].xy /= edgeVerts[2].w;

    emit(0, position[0], normal[0], patchCoord[0], edgeVerts);
    emit(1, position[1], normal[1], patchCoord[1], edgeVerts);
    emit(2, position[2], normal[2], patchCoord[2], edgeVerts);
#else
    emit(position[0], normal[0], patchCoord[0]);
    emit(position[1], normal[1], patchCoord[1]);
    emit(position[2], normal[2], patchCoord[2]);
#endif
#endif // PRIM_TRI

    EndPrimitive();
}

#endif
//--------------------------------------------------------------
// Fragment Shader
//--------------------------------------------------------------
#ifdef FRAGMENT_SHADER

in block {
    OutputVertex v;
    noperspective in vec4 edgeDistance;
} inpt;

out vec4 outColor;

uniform int ptexFaceOffset;

#ifdef USE_PTEX_COLOR
uniform sampler2DArray textureImage_Data;
uniform samplerBuffer textureImage_Packing;
uniform isamplerBuffer textureImage_Pages;
#endif

#ifdef USE_PTEX_OCCLUSION
uniform sampler2DArray textureOcclusion_Data;
uniform samplerBuffer textureOcclusion_Packing;
uniform isamplerBuffer textureOcclusion_Pages;
#endif

#ifdef USE_PTEX_SPECULAR
uniform sampler2DArray textureSpecular_Data;
uniform samplerBuffer textureSpecular_Packing;
uniform isamplerBuffer textureSpecular_Pages;
#endif

#define NUM_LIGHTS 2

struct LightSource {
    vec4 position;
    vec4 ambient;
    vec4 diffuse;
    vec4 specular;
};

layout(std140) uniform Lighting {
    LightSource lightSource[NUM_LIGHTS];
};

uniform bool overrideColorEnable = false;
uniform vec4 overrideColor;

#ifdef USE_PTEX_NORMAL
uniform sampler2DArray textureDisplace_Data;
uniform samplerBuffer textureDisplace_Packing;
uniform isamplerBuffer textureDisplace_Pages;

vec3
perturbNormalFromDisplacement(vec3 position, vec3 normal, vec4 patchCoord)
{
    // by Morten S. Mikkelsen
    // http://jbit.net/~sparky/sfgrad_bump/mm_sfgrad_bump.pdf
    // slightly modified for ptex guttering

    vec3 vSigmaS = dFdx(position);
    vec3 vSigmaT = dFdy(position);
    vec3 vN = normal;
    vec3 vR1 = cross(vSigmaT, vN);
    vec3 vR2 = cross(vN, vSigmaS);
    float fDet = dot(vSigmaS, vR1);
#if 0
    // not work well with ptex
    float dBs = dFdx(disp);
    float dBt = dFdy(disp);
#else
    vec2 texDx = dFdx(patchCoord.xy);
    vec2 texDy = dFdy(patchCoord.xy);
    
    // limit forward differencing to the width of ptex gutter
    const float resolution = 128.0;
    float d = min(1, (0.5/resolution)/max(length(texDx), length(texDy)));
    
    vec4 STll = patchCoord;
    vec4 STlr = patchCoord + d * vec4(texDx.x, texDx.y, 0, 0);
    vec4 STul = patchCoord + d * vec4(texDy.x, texDy.y, 0, 0);
    float Hll = PTexLookup(STll, textureDisplace_Data, textureDisplace_Packing, textureDisplace_Pages).x * bumpScale;
    float Hlr = PTexLookup(STlr, textureDisplace_Data, textureDisplace_Packing, textureDisplace_Pages).x * bumpScale;
    float Hul = PTexLookup(STul, textureDisplace_Data, textureDisplace_Packing, textureDisplace_Pages).x * bumpScale;
    float dBs = (Hlr - Hll)/d;
    float dBt = (Hul - Hll)/d;
#endif
    
    vec3 vSurfGrad = sign(fDet) * (dBs * vR1 + dBt * vR2);
    return normalize(abs(fDet) * vN - vSurfGrad);
}
#endif // USE_PTEX_NORMAL

uniform sampler2D diffuseEnvironmentMap;
uniform sampler2D specularEnvironmentMap;

vec4 getEnvironmentHDR(sampler2D sampler, vec3 dir)
{
    dir = (ModelViewInverseMatrix * vec4(dir, 0)).xyz;
    vec2 uv = vec2((atan(dir.x,dir.z)/3.1415926535897+1)*0.5, (1-dir.y)*0.5);
    vec4 tex = texture(sampler, uv);
    tex = vec4(pow(tex.xyz, vec3(0.4545)), 1);
    return tex;
}

vec4
lighting(vec4 texColor, vec3 Peye, vec3 Neye)
{
    vec4 color = vec4(0);

#ifdef USE_PTEX_OCCLUSION
    float occ = PTexLookup(inpt.v.patchCoord,
                           textureOcclusion_Data,
                           textureOcclusion_Packing,
                           textureOcclusion_Pages).x;
#else
    float occ = 0.0;
#endif
    vec3 n = Neye;



    for (int i = 0; i < NUM_LIGHTS; ++i) {

        vec4 Plight = lightSource[i].position;
        vec3 l = (Plight.w == 0.0)
                    ? normalize(Plight.xyz) : normalize(Plight.xyz - Peye);

        vec3 h = normalize(l + vec3(0,0,1));    // directional viewer

        float d = max(0.0, dot(n, l));
        float s = pow(max(0.0, dot(n, h)), 64.0f);

        color += (1.0-occ) * ((lightSource[i].ambient +
                               d * lightSource[i].diffuse) * texColor + 
                              s * lightSource[i].specular);
    }

    color.a = 1;

    return color;
}

vec4
edgeColor(vec4 Cfill, vec4 edgeDistance)
{
#if defined(GEOMETRY_OUT_WIRE) || defined(GEOMETRY_OUT_LINE)
#ifdef PRIM_TRI
    float d =
        min(inpt.edgeDistance[0], min(inpt.edgeDistance[1], inpt.edgeDistance[2]));
#endif
#ifdef PRIM_QUAD
    float d =
        min(min(inpt.edgeDistance[0], inpt.edgeDistance[1]),
            min(inpt.edgeDistance[2], inpt.edgeDistance[3]));
#endif
    vec4 Cedge = vec4(1.0, 1.0, 0.0, 1.0);
    float p = exp2(-2 * d * d);

#if defined(GEOMETRY_OUT_WIRE)
    if (p < 0.25) discard;
#endif

    Cfill.rgb = mix(Cfill.rgb, Cedge.rgb, p);
#endif
    return Cfill;
}

void
main()
{
#ifdef USE_PTEX_COLOR
    vec4 texColor = PTexLookup(inpt.v.patchCoord,
                               textureImage_Data,
                               textureImage_Packing,
                               textureImage_Pages);
//    texColor = vec4(pow(texColor.xyz, vec3(0.4545)), 1);
#else
    vec4 texColor = vec4(1);
#endif

#ifdef USE_PTEX_NORMAL
    vec3 normal = perturbNormalFromDisplacement(inpt.v.position.xyz,
                                                inpt.v.normal,
                                                inpt.v.patchCoord);
#else
    vec3 normal = inpt.v.normal;
#endif

    if (overrideColorEnable) {
        texColor = overrideColor;
        vec4 Cf = lighting(texColor, inpt.v.position.xyz, normal);
        outColor = edgeColor(Cf, inpt.edgeDistance);
        return;
    }

#ifdef USE_IBL
#ifdef USE_PTEX_OCCLUSION
    float occ = PTexLookup(inpt.v.patchCoord,
                           textureOcclusion_Data,
                           textureOcclusion_Packing,
                           textureOcclusion_Pages).x;
#else
    float occ = 0.0;
#endif

#ifdef USE_PTEX_SPECULAR
    float specular = PTexLookup(inpt.v.patchCoord,
                                textureSpecular_Data,
                                textureSpecular_Packing,
                                textureSpecular_Pages).x;
#else
    float specular = 1.0;
#endif

    vec4 a = vec4(0, 0, 0, 1); //ambientColor;
    vec4 d = getEnvironmentHDR(diffuseEnvironmentMap, normal) * 1.4;
    vec3 eye = normalize(inpt.v.position.xyz - vec3(0,0,0));
    vec3 reflect = reflect(eye, normal);
    vec4 s = getEnvironmentHDR(specularEnvironmentMap, reflect);
    const float fresnelBias = 0;
    const float fresnelScale = 1.0;
    const float fresnelPower = 2.0;
    float fresnel = fresnelBias + fresnelScale * pow(1.0+dot(normal,eye), fresnelPower);

    a *= (1.0-occ);
    d *= (1.0-occ);
    s *= min(specular, (1.0-occ)) * fresnel;

    vec4 Cf = (a + d) * texColor + s * 0.5;
#else
    vec4 Cf = lighting(texColor, inpt.v.position.xyz, normal);
#endif

    outColor = edgeColor(Cf, inpt.edgeDistance);
}

#endif
