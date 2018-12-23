#ifndef _ImageBasedLighting_
#define _ImageBasedLighting_

#include "BSDF_Library.hlsl"
#include "ShadingModel.hlsl"

half GDFG(half NoV, half NoL, half a) {
    half a2 = a * a;
    half GGXL = NoV * sqrt((-NoL * a2 + NoL) * NoL + a2);
    half GGXV = NoL * sqrt((-NoV * a2 + NoV) * NoV + a2);
    return (2 * NoL) / (GGXV + GGXL);
}

//////////////////////////Environment LUT 
half2 Standard_Karis(half Roughness, half NoV) {
    half3 V;
    V.x = sqrt(1 - NoV * NoV);
    V.y = 0;
    V.z = NoV;

    half2 r = 0;
	const uint NumSamples = 64;
    for (uint i = 0; i < NumSamples; i++) {
        half2 E = Hammersley(i, NumSamples); 
        half3 H = ImportanceSampleGGX(E, Roughness).xyz;
        half3 L = 2 * dot(V, H) * H - V;

        half VoH = saturate(dot(V, H));
        half NoL = saturate(L.z);
        half NoH = saturate(H.z);

        if (NoL > 0) {
            half G = GDFG(NoV, NoL, Roughness * Roughness);
            half Gv = G * VoH / NoH;
            half Fc = pow(1 - VoH, 5);
            r.x += Gv * (1 - Fc);
            r.y += Gv * Fc;
        }
    }
    return r / NumSamples;
}

half2 Standard_Karis_Approx(half Roughness, half NoV) {
    const half4 c0 = half4(-1.0, -0.0275, -0.572,  0.022);
    const half4 c1 = half4( 1.0,  0.0425,  1.040, -0.040);
    half4 r = Roughness * c0 + c1;
    half a004 = min(r.x * r.x, exp2(-9.28 * NoV)) * r.x + r.y;
    return half2(-1.04, 1.04) * a004 + r.zw;
}

half Standard_Karis_Approx_Nonmetal(half Roughness, half NoV) {
	const half2 c0 = { -1, -0.0275 };
	const half2 c1 = { 1, 0.0425 };
	half2 r = Roughness * c0 + c1;
	return min( r.x * r.x, exp2( -9.28 * NoV ) ) * r.x + r.y;
}

half2 Cloth_Ashikhmin_Approx(half Roughness, half NoV) {
    const half4 c0 = half4(0.24,  0.93, 0.01, 0.20);
    const half4 c1 = half4(2, -1.30, 0.40, 0.03);

    half s = 1 - NoV;
    half e = s - c0.y;
    half g = c0.x * exp2(-(e * e) / (2 * c0.z)) + s * c0.w;
    half n = Roughness * c1.x + c1.y;
    half r = max(1 - n * n, c1.z) * g;

    return half2(r, r * c1.w);
}

half2 Cloth_Charlie_Approx(half Roughness, half NoV) {
    const half3 c0 = half3(0.95, 1250, 0.0095);
    const half4 c1 = half4(0.04, 0.2, 0.3, 0.2);

    half a = 1 - NoV;
    half b = 1 - (Roughness);

    half n = pow(c1.x + a, 64);
    half e = b - c0.x;
    half g = exp2(-(e * e) * c0.y);
    half f = b + c1.y;
    half a2 = a * a;
    half a3 = a2 * a;
    half c = n * g + c1.z * (a + c1.w) * Roughness + f * f * a3 * a3 * a2;
    half r = min(c, 18);

    return half2(r, r * c0.z);
}


half3 ImageBasedLighting_Hair(half3 V, float3 N, float3 specularColor, float Roughness, float Scatter) {
	float3 Lighting = 0;
	uint NumSamples = 32;
	
	UNITY_LOOP
	for( uint i = 0; i < NumSamples; i++ ) {
		float2 E = Hammersley(i, NumSamples);
		float3 L = UniformSampleSphere(E).xyz;
		{
			//float3 SampleColor = AmbientCubemap.SampleLevel(AmbientCubemapSampler, L, 0 .rgb);

			float PDF = 1 / (4 * PI);
			float InvWeight = PDF * NumSamples;
			float Weight = rcp(InvWeight);

			float3 Shading = 0;
            Shading = Hair_UE4(L, V, N, specularColor, 0.5, Roughness, 0, Scatter, 0, 0);

            Lighting += Shading * Weight;
		}
	}
	return Lighting;
}

//////////Enviornment BRDF
float3 PreintegratedGF_LUT(sampler2D PreintegratedLUT, float3 SpecularColor, float Roughness, float NoV) {
	float2 AB = tex2Dlod(PreintegratedLUT, float4(clamp(Roughness, 0.001, 0.999), NoV, 0, 0));
	return SpecularColor * AB.x + saturate(50 * SpecularColor.g) * AB.y;
}

float3 PreintegratedGF_ClothAshikhmin(float3 SpecularColor, float Roughness, float NoV)
{
    float2 AB = Cloth_Ashikhmin_Approx(Roughness, NoV);
    return SpecularColor * AB.x + saturate(50 * SpecularColor.g) * AB.y;
}

float3 PreintegratedGF_ClothCharlie(float3 SpecularColor, float Roughness, float NoV)
{
    float2 AB = Cloth_Charlie_Approx(Roughness, NoV);
    return SpecularColor * AB.x + saturate(50 * SpecularColor.g) * AB.y;
}

#endif
