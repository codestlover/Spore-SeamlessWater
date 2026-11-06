
extern uniform float4 gameInfo : register(c0);
extern uniform sampler Sampler0 : register(s0);
extern uniform sampler Sampler1 : register(s1);
extern uniform sampler Sampler2 : register(s2);
extern uniform sampler Sampler3 : register(s3);
extern uniform sampler Sampler4 : register(s4);
extern uniform sampler Sampler5 : register(s5);
extern uniform sampler Sampler6 : register(s6);

struct PixelIn { float4 color : COLOR0;

float4 texcoord0 : TEXCOORD0;
float4 texcoord1 : TEXCOORD1;
float4 texcoord2 : TEXCOORD2;
float4 texcoord3 : TEXCOORD3;
float4 texcoord4 : TEXCOORD4;
};
struct PixelOut { float4 color : COLOR0; };
PixelOut main(PixelIn In) { PixelOut Current = (PixelOut)0;
half3 pcaNormal = tex2D( Sampler2, In.texcoord0.zw).xzy * 2 - 1;

const half  depthScale				= 0.75;
const half  alphaScale				= 5000;
half2       uv                      = In.texcoord0.xy;
half2       sinuv                   = In.texcoord0.zw;
half3       reflection              = In.texcoord1.xyz;
half        normalizedWaterHeight   = In.texcoord2.x;
half        sinTime                 = In.texcoord2.y;
half        vertexAbove             = In.texcoord2.z;
half2       uv0                     = In.texcoord3.xy;
half2       uv1                     = In.texcoord3.zw;
half2       screenPos               = In.texcoord4.xy / In.texcoord4.z + 0.5;
half        normalizedHeight        = tex2D( Sampler0, uv ).x * 2.0 - 1.0;
half        waterDepth              = saturate( normalizedWaterHeight - normalizedHeight );
screenPos.xy                        += sinuv;
half4       refractColor            = tex2D( Sampler5, screenPos.xy );
half3       waterColor              = refractColor.rgb;
half		waterAlpha2				= min( waterDepth, max( vertexAbove, 0 ) ) * alphaScale;
half4       specularColor           = texCUBE( Sampler4, reflection );
waterColor.rgb                      += specularColor.rgb * specularColor.w;

float3 swN = In.texcoord3.xyz;
float3 swW = swN * swN;
swW /= dot(swW, float3(1, 1, 1));
float2 swSpeed0 = float2(In.texcoord1.w, In.texcoord2.w);
float2 swSpeed1 = float2(In.texcoord3.w, In.texcoord4.w);
half waterSurface0 = dot(swW, float3(
    tex2D(Sampler3, swN.yz * 2.1 + swSpeed0).r,
    tex2D(Sampler3, swN.xz * 2.1 + swSpeed0).r,
    tex2D(Sampler3, swN.xy * 2.1 + swSpeed0).r));

half waterSurface1 = dot(swW, float3(
    tex2D(Sampler3, swN.zy * 2.8 + swSpeed1).g,
    tex2D(Sampler3, swN.zx * 2.8 + swSpeed1).g,
    tex2D(Sampler3, swN.yx * 2.8 + swSpeed1).g));

half        fade                    = lerp( waterSurface0, waterSurface1, sinTime );
waterColor.rgb                      = lerp( waterColor, waterColor * fade, 0.5 );
Current.color.rgb                   = waterColor.rgb;
Current.color.a                     = waterAlpha2;

return Current;
}

