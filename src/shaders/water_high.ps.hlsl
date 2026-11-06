
#include "WaterReflection.hlsli"
extern uniform struct { float4x4 pcaBasis0;float4x4 pcaBasis1;float4x4 pcaBasis2;float4x4 pcaBasis3;float4 pcaMean;} pcaTexture : register(c0);
extern uniform struct { float4 mDir; float4 mColor; } dirLightsWorld[4] : register(c17);
extern uniform float4x4 viewTransform : register(c25);
extern uniform struct
{
float4 vSunDir;
float4 waterColor;
float4 innerParms;
float4 vCamPos;
float4 sphereParms;
float4 camParms;
float4 illumParms;
float4 fogParms;
float4 nightLightTint;
float4 nightLightColor;
float4 duskLightColor;
float4 dayLightColor;
float4 nightShadowColor;
float4 duskShadowColor;
float4 dayShadowColor;
float4 duskDawnStartEnd;
float4x4 viewTransform;
} terrainState : register(c29);
extern uniform sampler Sampler0 : register(s0);
extern uniform sampler Sampler1 : register(s1);
extern uniform sampler Sampler2 : register(s2);
extern uniform sampler Sampler3 : register(s3);
extern uniform sampler Sampler4 : register(s4);
extern uniform sampler Sampler5 : register(s5);
extern uniform sampler Sampler6 : register(s6);
struct PCAData
{
float4x4 pcaBasis0;
float4x4 pcaBasis1;
float4x4 pcaBasis2;
float4x4 pcaBasis3;
float4   pcaMean;
};
float4 PCADecompressTexture(
float2 uv0,
sampler pcaComponent0,
sampler pcaComponent1,
PCAData pcaData
)
{
float4 texture0 = tex2D( pcaComponent0, uv0 ) * 2 - 1;
float4 texture1 = tex2D( pcaComponent1, uv0 ) * 2 - 1;
float4 decompressedTexture =
mul( texture0, pcaData.pcaBasis0 ) +
mul( texture1, pcaData.pcaBasis1 ) +
pcaData.pcaMean;
return decompressedTexture / 255.0f;
}

extern uniform sampler shadowMap0 : register(s7);
extern uniform sampler shadowMap1 : register(s8);
extern uniform sampler lookupMap : register(s10);
float Shadow(float4 shadowInfo, float sharpness = 10, float bias = 0)
{
const float pi = 3.14159265;
const float4 oneOnC0 = 1.0f / float4(1.1 * pi, 6.0 * pi, -1.1 * pi, -6.0 * pi);
float2 shadowPos = shadowInfo.xy;
float shadowStrength = shadowInfo.z;
float lightDistance = saturate(shadowInfo.w);
float shadowClip;
float2 clipXY = saturate(3.0f * (1 - abs(shadowPos.xy)));
shadowClip = clipXY.x * clipXY.y;
shadowPos *= float2(0.5, -0.5);
shadowPos += float2(0.5,  0.5);
float4 b0Z = tex2D(shadowMap0, shadowPos.xy) * 2 - 1;
float4 b0D = tex2D(lookupMap, float2(0.5 * lightDistance, 0.25)) * 2 - 1;
float4 diff0 = b0D * b0Z;
float term = dot(oneOnC0, diff0);
float shadow = saturate(1.0 + bias + sharpness * term);
shadow = lerp(1, shadow, shadowClip * shadowStrength);
return shadow;
}

struct PixelIn { float4 color : COLOR0;
float4 color1 : COLOR1;
float4 texcoord0 : TEXCOORD0;
float4 texcoord1 : TEXCOORD1;
float4 texcoord2 : TEXCOORD2;
float4 texcoord3 : TEXCOORD3;
float4 texcoord4 : TEXCOORD4;
float4 texcoord5 : TEXCOORD5;
float4 texcoord6 : TEXCOORD6;
float4 texcoord7 : TEXCOORD7;
};
struct PixelOut { float4 color : COLOR0; };
PixelOut main(PixelIn In) { PixelOut Current = (PixelOut)0;

float3 swNormal = normalize(In.texcoord3.xyz);
float3 swWeights = swNormal * swNormal;
swWeights *= swWeights;
swWeights /= dot(swWeights, float3(1, 1, 1));
float2 swPhase = In.texcoord1.zw;
float2 swUVX = swNormal.yz * 16.0 + sin(swNormal.zy * 20.0 + swPhase) * 0.125;
float2 swUVY = swNormal.xz * 16.0 + sin(swNormal.zx * 20.0 + swPhase) * 0.125;
float2 swUVZ = swNormal.xy * 16.0 + sin(swNormal.yx * 20.0 + swPhase) * 0.125;
float2 swSlopeX = PCADecompressTexture(swUVX, Sampler1, Sampler3, pcaTexture).xz * 2 - 1;
float2 swSlopeY = PCADecompressTexture(swUVY, Sampler1, Sampler3, pcaTexture).xz * 2 - 1;
float2 swSlopeZ = PCADecompressTexture(swUVZ, Sampler1, Sampler3, pcaTexture).xz * 2 - 1;
float3 swGradient = float3(0, swSlopeX.x, swSlopeX.y) * swWeights.x
                  + float3(swSlopeY.x, 0, swSlopeY.y) * swWeights.y
                  + float3(swSlopeZ.x, swSlopeZ.y, 0) * swWeights.z;
swGradient -= swNormal * dot(swNormal, swGradient);
float2 swScreenGradient = mul(float4(swGradient, 0), viewTransform).xy * float2(1, -1);
float3 pcaNormal = float3(swScreenGradient, 0);

swGradient *= In.color1.a;
pcaNormal.xyz *= In.color1.a;
In.texcoord0.xy += pcaNormal.xy * 0.025f;

float shadow = Shadow(In.texcoord0, 100, 0);

const half foamThickness    = 50;
const half depthScale       = 0.75;
const half specularAmp      = 3.0;
const half shallowColorAmp  = 1.25;
const half alphaScale		= 100;
const half normalStrength   = 1.5;
const half absAmount        = 0.9;
const half satAmount        = 0.25;
const half midAmount        = 0.5;
half   fogStrength          = In.color.a;
half   sunDrop              = In.color1.r;
half   fresnel              = In.color1.g;
half   hfFade               = In.color1.a;
half2  uv                   = In.texcoord1.xy;
half2  screenPos            = In.texcoord2.xy / In.texcoord2.z + 0.5;
half3  normal               = In.texcoord3.xyz;
half3  tangent              = In.texcoord4.xyz;
half   waterHeight          = In.texcoord4.w;
half3  binormal             = In.texcoord5.xyz;
half2  wave                 = half2( In.texcoord2.w, In.texcoord3.w );
half2  waveBlend            = half2( In.texcoord5.w, In.texcoord7.w );
half3  viewDir              = In.texcoord6.xyz;
half   vertexAbove          = In.texcoord6.w;
half3  eyeDir               = In.texcoord7.xyz;
half2  scaledUV             = uv * 16; 
half2  uv5                  = uv * 5;
half   normalizedHeight     = tex2D( Sampler0, uv ).x * 2.0 - 1.0;
half   waterDepth           = saturate( waterHeight / 100.0f - normalizedHeight );
half	waterAlpha2         = min( waterDepth, max( vertexAbove, 0 ) ) * alphaScale;
screenPos.xy                += pcaNormal.xy * waterDepth * fresnel * 0.4;
half4 refractColor          = tex2D( Sampler5, screenPos.xy );
float3 bumpNormal = normalize(swNormal + swGradient * hfFade * normalStrength);
half3 NDotE                 = dot( eyeDir, bumpNormal );
half3 viewDirReflected      = eyeDir - 2 * NDotE * bumpNormal;
viewDirReflected            = mul( viewDirReflected, viewTransform ); 
half3 waterColor            = terrainState.waterColor;
waterColor                  = lerp( refractColor.rgb, waterColor, saturate( fresnel - 0.5 ) );
half NDotL                  = dot( dirLightsWorld[0].mDir, bumpNormal );
half NDotLSat               = saturate( NDotL );
half NDotLAbs               = abs( NDotL );
half middle                 = 1 - NDotLAbs;
middle                      *= middle;
half finalLightStrength     = NDotLAbs * absAmount + NDotLSat * satAmount + middle * midAmount;

half foam = dot(swWeights, float3(
    tex2D(Sampler2, swNormal.yz * 12.0).r,
    tex2D(Sampler2, swNormal.xz * 12.0).r,
    tex2D(Sampler2, swNormal.xy * 12.0).r));

half cut = dot(swWeights, float3(
    tex2D(Sampler2, swNormal.yz * 4.0).a,
    tex2D(Sampler2, swNormal.xz * 4.0).a,
    tex2D(Sampler2, swNormal.xy * 4.0).a));

half2 waveFoam              = foam * cut * waveBlend.xy * ( 1 - saturate( abs( wave.xy - waterDepth * foamThickness ) ) );
half foamI                  = waveFoam.x + waveFoam.y;
waterColor                  += foamI;
waterColor                  = waterColor * finalLightStrength;
waterColor                  += foamI;
half4 specularColor         = texCUBE( Sampler4, viewDirReflected );
waterColor = ApplyWaterReflection( waterColor, Sampler4, (float3x3)viewTransform, normal, eyeDir, bumpNormal, terrainState.innerParms.w + terrainState.sphereParms.x );
specularColor.xyz           = specularColor.rgb * specularColor.a * NDotLSat * specularAmp;
waterColor                  += lerp( specularColor * shadow, specularColor, 0.4 );
Current.color.rgb           = waterColor;
float4 scatterColor         = texCUBE( Sampler4, viewDir );
Current.color.rgb           = lerp( waterColor.rgb, scatterColor, fogStrength ) + scatterColor.rgb * scatterColor.a * sunDrop;
Current.color.rgb           = lerp( Current.color.rgb * shadow, Current.color.rgb, 0.85 );
Current.color.rgb			= lerp( Current.color.rgb, refractColor.rgb, refractColor.a * 0.5f );
Current.color.a             = waterAlpha2;

return Current;
}

