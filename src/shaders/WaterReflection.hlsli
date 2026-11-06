
extern uniform float4 ReflectionParameters : register(c28);
extern uniform row_major float4x4 MirrorClip : register(c50);
extern uniform float4 MirrorDepthParameters : register(c54);
extern uniform row_major float4x4 MirrorInverse : register(c56);
extern uniform sampler2D MirrorColor : register(s6);
extern uniform sampler2D MirrorDepth : register(s9);

float2 MirrorUV(float2 ndc) {
    return ndc * float2(0.5, -0.5) + 0.5;
}

float MirrorViewDepth(float depth) {
    return MirrorDepthParameters.y / (depth - MirrorDepthParameters.x);
}

bool MirrorAboveWater(float2 ndc, float depth, float radius) {
    float4 point_ = mul(float4(ndc, depth, 1), MirrorInverse);
    float3 position = point_.xyz / point_.w;
    return dot(position, position) > (radius + 0.3) * (radius + 0.3);
}

bool TraceMirror(float3 origin, float3 ray, float radius, out float distance, out float2 hitUV) {
    float4 start = mul(float4(origin, 1), MirrorClip);
    float4 step = mul(float4(ray, 0), MirrorClip);
    float2 texel = MirrorDepthParameters.zw * 2;
    float t = 0.05;
    float previous = 0;
    float lastGap = -1;
    distance = 0;
    hitUV = 0;
    [loop] for (int i = 0; i < 64; ++i) {
        float4 clip = start + step * t;
        if (clip.w < 0.001 || t > radius)
            return false;
        float2 ndc = clip.xy / clip.w;
        if (abs(ndc.x) > 1 || abs(ndc.y) > 1)
            return false;
        float2 motion = abs(step.xy * clip.w - clip.xy * step.w) / (clip.w * clip.w) / texel;
        float rate = max(max(motion.x, motion.y), 1e-6);
        float pace = 1.5 / rate;
        float2 uv = MirrorUV(ndc);
        float depth = tex2Dlod(MirrorDepth, float4(uv, 0, 0)).r;
        float advance = 4 / rate;
        bool ahead = false;
        if (depth < 0.99999 && MirrorAboveWater(ndc, depth, radius)) {
            float gap = MirrorViewDepth(depth) - clip.w;
            float slack = 0.5 + clip.w * 0.004;
            float thickness = lastGap > 0 ? (t - previous) * abs(step.w) * 1.5 + slack : slack;
            if (gap <= 0.05 + clip.w * 0.002 && gap > -thickness) {
                float low = previous;
                float high = t;
                [loop] for (int k = 0; k < 5; ++k) {
                    float middle = (low + high) * 0.5;
                    float4 c = start + step * middle;
                    float2 m = c.xy / max(c.w, 0.001);
                    float d = tex2Dlod(MirrorDepth, float4(MirrorUV(m), 0, 0)).r;
                    if (d < 0.99999 && c.w > MirrorViewDepth(d) - 0.05 && MirrorAboveWater(m, d, radius))
                        high = middle;
                    else
                        low = middle;
                }
                float4 h = start + step * high;
                distance = high;
                hitUV = MirrorUV(h.xy / max(h.w, 0.001));
                return true;
            }
            if (gap > 0 && step.w > 1e-5) {
                advance = min(pace, gap / step.w);
                ahead = true;
            }
            lastGap = gap;
        } else {
            lastGap = -1;
        }
        if (!ahead && step.w > 1e-5) {
            float2 rest = abs(step.xy / step.w - ndc) / texel;
            if (max(rest.x, rest.y) < 1)
                return false;
        }
        previous = t;
        t += max(advance, 0.01 + t * 0.002);
    }
    return false;
}

float MirrorTap(float2 uv, float radius) {
    float depth = tex2Dlod(MirrorDepth, float4(uv, 0, 0)).r;
    float2 ndc = (uv - 0.5) * float2(2, -2);
    return depth < 0.99999 && MirrorAboveWater(ndc, depth, radius) ? 1 : 0;
}

float MirrorCoverage(float2 uv, float radius) {
    float2 texel = MirrorDepthParameters.zw;
    float2 position = uv / texel - 0.5;
    float2 f = frac(position);
    float2 corner = (floor(position) + 0.5) * texel;
    float a = MirrorTap(corner, radius);
    float b = MirrorTap(corner + float2(texel.x, 0), radius);
    float c = MirrorTap(corner + float2(0, texel.y), radius);
    float d = MirrorTap(corner + texel, radius);
    return lerp(lerp(a, b, f.x), lerp(c, d, f.x), f.y);
}

float3 ApplyWaterReflection(float3 color, samplerCUBE skyMap, float3x3 skyFrame, float3 normal, float3 toEye,
                            float3 bumpNormal, float radius) {
    float3 N = normalize(normal);
    float3 V = normalize(toEye);
    float3 origin = N * radius;
    float3 ripple = normalize(lerp(N, normalize(bumpNormal), ReflectionParameters.z));
    float3 rippled = 2 * dot(V, ripple) * ripple - V;
    float rise = dot(rippled, N);
    if (rise < 0.02)
        rippled = normalize(rippled + N * (0.02 - rise));
    float grazing = 1 - saturate(dot(V, N));
    float curve = grazing * grazing * grazing;
    float3 sky = texCUBE(skyMap, mul(-rippled, skyFrame)).rgb;
    float skyWeight = ReflectionParameters.y + (1 - ReflectionParameters.y) * curve;
    float3 result = lerp(color, sky, saturate(ReflectionParameters.x * skyWeight));
    float3 calm = normalize(lerp(N, normalize(bumpNormal), ReflectionParameters.z * 0.15));
    float3 objectRay = 2 * dot(V, calm) * calm - V;
    float lift = dot(objectRay, N);
    if (lift < 0.02)
        objectRay = normalize(objectRay + N * (0.02 - lift));
    float distance;
    float2 uv;
    if (TraceMirror(origin, objectRay, radius, distance, uv)) {
        float2 ndc = (uv - 0.5) * float2(2, -2);
        float2 edge = saturate((1 - abs(ndc)) * 12);
        float objectWeight = ReflectionParameters.w + (1 - ReflectionParameters.w) * curve;
        float weight = saturate(ReflectionParameters.x * objectWeight) * edge.x * edge.y;
        float coverage = MirrorCoverage(uv, radius);
        float3 scene = tex2Dlod(MirrorColor, float4(uv, 0, 0)).rgb;
        result = result * (1 - weight * coverage) + scene * weight;
    }
    return result;
}

