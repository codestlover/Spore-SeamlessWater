
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
} terrainState : register(c0);
extern uniform struct
{
float4x4 worldViewProjection;
float4 QuadFaceUVXform;
float4 QuadMorphValue;
float4 QuadFaceElemMap;
float4 QuadFaceSignMap;
float4 QuadFaceXForm[3];
} terrainTransform : register(c20);
extern uniform struct { float4   mRangeAndStrength; float4   mShadowDir; float4   mNestInfo; float4x4 mWorldToShadowClip; float4x3 mWorldToShadowCamera; } shadowMapInfo : register(c31);
extern uniform float4 gameInfo : register(c41);
float GetInScatterTerminator( float3 vNorm, float3 vSunDir, float cutoff )
{
float dp = dot( vNorm, vSunDir );
dp = ( dp > cutoff ) ? 1.0 : max( 0, dp + cutoff )/(2 * cutoff);
return dp;
}
float4 CalcInScatter(  float fSunDotP, float fNormDist, float brightness,
float4 cP1Color, float4 xPhase,
float4 cP2Color, float4 yPhase,
float4 cP3Color, float4 zPhase)
{
float4 r_in;
float3 fPhase = (float3(1,1,1) - xPhase*xPhase)/(4 * 3.14159 * pow((float3(1,1,1) + xPhase*xPhase - 2*xPhase*fSunDotP), 1.5));
float3 r = fPhase * fNormDist * yPhase;
r_in = (r.x * cP1Color + r.y * cP2Color + r.z * cP3Color) * brightness;
r_in = saturate(r_in);
return r_in;
}

void GetTerrainFogStrength( float3 position, float3 normal, float atmoRadius, out float fogStrength, out float fogScale, out float term, out float3 eyeVec )
{
float4 vCamPos = terrainState.vCamPos;
float3 vNormCamToVert = position - vCamPos;
float cameraDistance = length( vNormCamToVert );
vNormCamToVert = vNormCamToVert/cameraDistance;
eyeVec.xyz = vNormCamToVert;

float b = dot( -vNormCamToVert, position.xyz );
float c = dot( position.xyz, position.xyz ) - atmoRadius*atmoRadius;
float d = b*b-c;
float minFogDistance = terrainState.fogParms.z;
float t = -b + sqrt(d);
float fogDist = max( t, 0 );
fogDist = min( t, cameraDistance );
fogDist = max( 0, fogDist-minFogDistance );
float density = terrainState.fogParms.x;
fogStrength = 1.0 - exp( density * fogDist );
term = GetInScatterTerminator( normal, terrainState.vSunDir.xyz, terrainState.vSunDir.w );
fogStrength *= term;
fogScale = terrainState.fogParms.y;
}
void GetTerrainFogStrengthFast( float3 position, float3 normal, float atmoRadius, out float fogStrength, out float fogScale, out float term, out float3 eyeVec )
{
float4 vCamPos = terrainState.vCamPos;
float3 vNormCamToVert = position - vCamPos;
float cameraDistance = length( vNormCamToVert );
vNormCamToVert = vNormCamToVert/cameraDistance;
eyeVec.xyz = vNormCamToVert;

float minFogDistance = terrainState.fogParms.z;
float fogDist = cameraDistance;
fogDist = max( 0, fogDist-minFogDistance );
float density = terrainState.fogParms.x;
fogStrength = 1.0 - exp( density * fogDist );
term = GetInScatterTerminator( normal, terrainState.vSunDir.xyz, terrainState.vSunDir.w );
fogStrength *= term;
fogScale = terrainState.fogParms.y;
}

void EvaluateVertexLighting(
float3 normal,
float3 sunDir,
float4 duskDawnStartEnd,
float3 dayLightColor,
float3 dayShadowColor,
float3 duskLightColor,
float3 duskShadowColor,
float3 nightLightColor,
float3 nightShadowColor,
out float3 lightBlend,
out float3 lightColor,
out float3 shadowColor )
{
float ndl = dot( normal.xyz, sunDir );
lightBlend.xy = saturate( float2( ndl, -ndl ) * duskDawnStartEnd.xy + duskDawnStartEnd.zw );
lightBlend.z = lightBlend.y;
lightBlend.y = 1.0f - max( lightBlend.x, lightBlend.z );
lightColor    = lightBlend.x*dayLightColor.xyz
+ lightBlend.y*duskLightColor.xyz
+ lightBlend.z*nightLightColor.xyz;
shadowColor   = lightBlend.x*dayShadowColor.xyz
+ lightBlend.y*duskShadowColor.xyz
+ lightBlend.z*nightShadowColor.xyz;
}
float3 TerrainVertexLighting( float3 sunDir, float3 normal, float3 shadowColor, float3 lightColor, float3 lightBlend )
{
const float bendLightAtDusk = 0.35;
const float absAmount       = 0.9;
const float satAmount       = 0.2;
const float midAmount       = 0.5;
const float shadowAmount    = 0.2;
sunDir                      = lerp( sunDir, normal, lightBlend.y * bendLightAtDusk );
float NdotL                 = dot( normal, sunDir );
float NdotLSat              = saturate( NdotL );
float NdotLAbs              = abs( NdotL );
float middle                = 1 - NdotLAbs;
middle                      *= middle;
float finalLightStrength    = NdotLAbs * absAmount + NdotLSat * satAmount + middle * midAmount;
float3 finalLightColor      = lerp( shadowColor, lightColor, finalLightStrength ) * finalLightStrength;
return finalLightColor;
}
float3 TerrainVertexLightingLow( float3 sunDir, float3 normal, float3 shadowColor, float3 lightColor, float3 lightBlend )
{
const float detailTextureCoeff  = 0.9;
float finalLightStrength        = abs( dot( sunDir, normal ) );
float3 finalLightColor          = lerp( shadowColor, lightColor, finalLightStrength ) * detailTextureCoeff;
return finalLightColor;
}

struct VertexIn { float4 position : POSITION0; float4 color : COLOR0; float4 texcoord0 : TEXCOORD0; };
struct VertexOut { float4 position : POSITION0; float4 color : COLOR0;
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
VertexOut main(VertexIn In) { VertexOut Current = (VertexOut)0; Current.position = In.position; Current.color = In.color;

const float c0      = 255.0f * 2.0f / 65536.0f;
const float c1      = 256.0f * c0;
float parentHeight  = dot( In.position.ar, float2( c1, c0 ) ) - 1;
float height        = dot( In.position.gb, float2( c1, c0 ) ) - 1;
height              = parentHeight + (height - parentHeight) * terrainTransform.QuadMorphValue.x;
float height1       = dot( In.color.gb, float2( c1, c0 ) ) - 1;
float seabedHeight = height1 * terrainState.sphereParms.y + terrainState.sphereParms.x;
float landHeight   = height * terrainState.sphereParms.y + terrainState.sphereParms.x;
float waterHeight  = terrainState.innerParms.w + terrainState.sphereParms.x;
float2 uv          = saturate( terrainTransform.QuadFaceUVXform.xy + In.texcoord0.xy * terrainTransform.QuadFaceUVXform.z);
float4 normal4 = float4( uv.xy, 1, 1 );
float3 normal = float3(
dot( normal4, terrainTransform.QuadFaceXForm[0] ),
dot( normal4, terrainTransform.QuadFaceXForm[1] ),
dot( normal4, terrainTransform.QuadFaceXForm[2] ) );
normal = normalize( normal );
float4 landPosition  = float4(normal.xyz * landHeight, 1);
float4 waterPosition = landPosition;
float4 seabedPosition = float4(normal.xyz * seabedHeight, 1);

float2 range = shadowMapInfo.mRangeAndStrength.xy;
float depth = (mul(landPosition, shadowMapInfo.mWorldToShadowCamera).y - range.x) * range.y;
float strength = saturate(dot(normal, shadowMapInfo.mShadowDir.xyz) + shadowMapInfo.mShadowDir.w);
Current.texcoord0.xyz =  mul(landPosition, shadowMapInfo.mWorldToShadowClip).xyw;
Current.texcoord0.xy /= Current.texcoord0.z;
Current.texcoord0.z   = strength;
Current.texcoord0.w   = depth;

const half startDepth       = 7.5;
const half waveSpeed        = 1.0 / 16.0;
const half foamAmp          = 1.750;
const half hfDist           = 1200;
const half waterScale       = 10;   
const half sinAmp           = 20;   
const half2 sinSpeed        = half2( 0.05, 0.09 ) * 2;
const half2 animAmp         = 0.25 * 0.5;
const half mm[]             = { 0.57735026, 0.60290092, 0.62773043, 0.65094453, 0.67149222, 0.68824714, 0.70014000, 0.70632243 };
half4 vertScaled            = waterPosition;
half  vertexHeight          = length( vertScaled.xyz );
half  cameraHeight          = length( terrainState.vCamPos.xyz );
half  planetRadius          = terrainState.sphereParms.x;
half  offset                = lerp( 1, 10, saturate( ( cameraHeight - planetRadius - 100.0 )/ 500.0 ) );

half3 binormal              = half3(0,1,0);
half3 tangent               = cross( normal.xyz, binormal );
binormal                    = cross( tangent, normal.xyz );
half4 clipPos               = mul(vertScaled, terrainTransform.worldViewProjection);
half3 cameraToVert          = vertScaled - terrainState.vCamPos;
half cameraDistance         = length( cameraToVert );
float2 animTexCoord = gameInfo.xx * sinSpeed;
half  fogScale, fogStrength, term;
half3 eyeVec;
GetTerrainFogStrength( vertScaled.xyz, normal.xyz, ( terrainState.sphereParms.x + terrainState.sphereParms.z ), fogStrength, fogScale, term, eyeVec );
half NdotE                  = dot(-eyeVec, normal.xyz);
half3 halfVector            = normalize(terrainState.vSunDir - eyeVec);
half  fresnel               = 1 - NdotE;
half hfFade                 = saturate( cameraDistance / hfDist );
half2 foamWave              = 1.0 - frac( gameInfo.xx * waveSpeed + half2( 0.0, 0.5 ) );
half2 waveBlend             = foamWave * ( 1.0 - foamWave );
half NDotL                  = dot( terrainState.vSunDir, normal );
half NDotLSat               = saturate( NDotL );
foamWave                    *= startDepth;
waveBlend                   *= foamAmp;
Current.position            = clipPos;
Current.color.rgb           = 0;                                
Current.color.w             = fogStrength;
Current.color1.r            = saturate( dot( normal, terrainState.vSunDir ) + 0.95 );
Current.color1.g            = fresnel;
Current.color1.b            = 0;                                
Current.color1.a            = (1 - hfFade) * 0.95 + 0.05;
Current.texcoord1.xy     = uv.xy;
Current.texcoord1.zw     = animTexCoord;
Current.texcoord2.xyz    = half3( half2( clipPos.x, -clipPos.y ), clipPos.w * 2 );
Current.texcoord2.w      = foamWave.x;
Current.texcoord3.xyz    = normal.xyz;
Current.texcoord3.w      = foamWave.y;
Current.texcoord4.xyz    = tangent;
Current.texcoord4.w      = terrainState.innerParms.w;        
Current.texcoord5.xyz    = binormal;
Current.texcoord5.w      = waveBlend.x;
Current.texcoord6.xyz    = mul( -eyeVec, terrainState.viewTransform );
Current.texcoord6.w      = ( waterHeight - vertexHeight + offset ) / terrainState.sphereParms.y;
Current.texcoord7.xyz    = -eyeVec;
Current.texcoord7.w      = waveBlend.y;

return Current;
}

