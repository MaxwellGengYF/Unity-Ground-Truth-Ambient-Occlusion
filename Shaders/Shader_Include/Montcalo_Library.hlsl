#ifndef _Montcalo_Library_
#define _Montcalo_Library_


#include "Common.hlsl"

float2 Noise(float2 pos, float random) {
    return frac(sin(dot(pos.xy * random, float2(12.9898f, 78.233f))) * float2(43758.5453f, 28001.8384f));
}

float HaltonSequence (uint index, uint base = 3) {
	float result = 0;
	float f = 1;
	int i = index;
	
	UNITY_UNROLL
	while (i > 0) {
		f = f / base;
		result = result + f * (i % base);
		i = floor(i / base);
	}
	return result;
}

float2 Hammersley(int i, int N) {
	return float2(float(i) * (1 / float(N)), HaltonSequence(i, 3));
}

float4 TangentToWorld(float3 N, float4 H) {
	float3 UpVector = abs(N.z) < 0.999 ? float3(0, 0, 1) : float3(1, 0, 0);
	float3 T = normalize( cross( UpVector, N ) );
	float3 B = cross( N, T );				
	return float4((T * H.x) + (B * H.y) + (N * H.z), H.w);
}

float3x3 GetTangentBasis(float3 TangentZ) {
	float3 UpVector = abs(TangentZ.z) < 0.999 ? float3(0, 0, 1) : float3(1, 0, 0);
	float3 TangentX = normalize(cross( UpVector, TangentZ));
	float3 TangentY = cross(TangentZ, TangentX);
	return float3x3(TangentX, TangentY, TangentZ);
}

uint2 SobolIndex(uint2 Base, int Index, int Bits = 10) {
	uint2 SobolNumbers[10] = {
		uint2(0x8680u, 0x4c80u), uint2(0xf240u, 0x9240u), uint2(0x8220u, 0x0e20u), uint2(0x4110u, 0x1610u), uint2(0xa608u, 0x7608u),
		uint2(0x8a02u, 0x280au), uint2(0xe204u, 0x9e04u), uint2(0xa400u, 0x4682u), uint2(0xe300u, 0xa74du), uint2(0xb700u, 0x9817u),
	};

	uint2 Result = Base;
	[ROLL] 
    for (int b = 0; b < 10 && b < Bits; ++b) {
		Result ^= (Index & (1 << b)) ? SobolNumbers[b] : 0;
	}
	return Result;
}

float2 RandToCircle(uint2 Rand) {
	float2 sf = float2(Rand) * (sqrt(2.) / 0xffff) - sqrt(0.5);	
	float2 sq = sf*sf;
	float root = sqrt(2.*max(sq.x, sq.y) - min(sq.x, sq.y));
	if (sq.x > sq.y) {
		sf.x = sf.x > 0 ? root : -root;
	}
	else {
		sf.y = sf.y > 0 ? root : -root;
	}
	return sf;
}

float4 UniformSampleSphere(float2 E) {
	float Phi = 2 * PI * E.x;
	float CosTheta = 1 - 2 * E.y;
	float SinTheta = sqrt(1 - CosTheta * CosTheta);

	float3 H;
	H.x = SinTheta * cos(Phi);
	H.y = SinTheta * sin(Phi);
	H.z = CosTheta;

	float PDF = 1 / (4 * PI);

	return float4(H, PDF);
}

float4 UniformSampleHemisphere(float2 E) {
	float Phi = 2 * PI * E.x;
	float CosTheta = E.y;
	float SinTheta = sqrt(1 - CosTheta * CosTheta);

	float3 H;
	H.x = SinTheta * cos( Phi );
	H.y = SinTheta * sin( Phi );
	H.z = CosTheta;

	float PDF = 1.0 / (2 * PI);
	return float4(H, PDF);
}

float2 UniformSampleDisk(float2 Random) {
	const float Theta = 2.0f * (float)PI * Random.x;
	const float Radius = sqrt(Random.y);
	return float2(Radius * cos(Theta), Radius * sin(Theta));
}

float4 CosineSampleHemisphere(float2 E) {
	float Phi = 2 * PI * E.x;
	float CosTheta = sqrt(E.y);
	float SinTheta = sqrt(1 - CosTheta * CosTheta);

	float3 H;
	H.x = SinTheta * cos(Phi);
	H.y = SinTheta * sin(Phi);
	H.z = CosTheta;

	float PDF = CosTheta / PI;
	return float4(H, PDF);
}

float4 UniformSampleCone(float2 E, float CosThetaMax) {
	float Phi = 2 * PI * E.x;
	float CosTheta = lerp(CosThetaMax, 1, E.y);
	float SinTheta = sqrt(1 - CosTheta * CosTheta);

	float3 L;
	L.x = SinTheta * cos( Phi );
	L.y = SinTheta * sin( Phi );
	L.z = CosTheta;

	float PDF = 1.0 / (2 * PI * (1 - CosThetaMax));
	return float4(L, PDF);
}

float4 ImportanceSampleBlinn(float2 E, float Roughness) {
	float m = Roughness * Roughness;
	float m2 = m * m;
		
	float Phi = 2 * PI * E.x;
	float n = 2 / m2 - 2;
	float CosTheta = pow(max(E.y, 0.001), 1 / (n + 1));
	float SinTheta = sqrt(1 - CosTheta * CosTheta);

	float3 H;
	H.x = SinTheta * cos(Phi);
	H.y = SinTheta * sin(Phi);
	H.z = CosTheta;
		
	float D = (n + 2)/ (2 * PI) * saturate(pow(CosTheta, n));
	float pdf = D * CosTheta;
	return float4(H, pdf); 
}

float4 ImportanceSampleGGX(float2 E, float Roughness) {
	float m = Roughness * Roughness;
	float m2 = m * m;

	float Phi = 2 * PI * E.x;
	float CosTheta = sqrt((1 - E.y) / ( 1 + (m2 - 1) * E.y));
	float SinTheta = sqrt(1 - CosTheta * CosTheta);

	float3 H;
	H.x = SinTheta * cos(Phi);
	H.y = SinTheta * sin(Phi);
	H.z = CosTheta;
			
	float d = (CosTheta * m2 - CosTheta) * CosTheta + 1;
	float D = m2 / (PI * d * d);
			
	float PDF = D * CosTheta;

	return float4(H, PDF);
}

float4 ImportanceSampleInverseGGX(float2 E, float Roughness) {
	float m = Roughness * Roughness;
	float m2 = m * m;
	float A = 4;

	float Phi = 2 * PI * E.x;
	float CosTheta = sqrt((1 - E.y) / ( 1 + (m2 - 1) * E.y));
	float SinTheta = sqrt(1 - CosTheta * CosTheta);

	float3 H;
	H.x = SinTheta * cos(Phi);
	H.y = SinTheta * sin(Phi);
	H.z = CosTheta;
			
	float d = (CosTheta - m2 * CosTheta) * CosTheta + m2;
	float D = rcp(Inv_PI * (1 + A * m2)) * (1 + 4 * m2 * m2 / (d * d));
			
	float PDF = D * CosTheta;

	return float4(H, PDF);
}

void SampleAnisoGGXDir(float2 u, float3 V, float3 N, float3 tX, float3 tY, float roughnessT, float roughnessB, out float3 H, out float3 L) {
    H = sqrt(u.x / (1 - u.x)) * (roughnessT * cos(Two_PI * u.y) * tX + roughnessB * sin(Two_PI * u.y) * tY) + N;
    H = normalize(H);
    L = 2 * saturate(dot(V, H)) * H - V;
}

void ImportanceSampleAnisoGGX(float2 u, float3 V, float3 N, float3 tX, float3 tY, float roughnessT, float roughnessB, float NoV, out float3 L, out float VoH, out float NoL, out float weightOverPdf)
{
    float3 H;
    SampleAnisoGGXDir(u, V, N, tX, tY, roughnessT, roughnessB, H, L);

    float NoH = saturate(dot(N, H));
    VoH = saturate(dot(V, H));
    NoL = saturate(dot(N, L));

    float ToV = dot(tX, V);
    float BoV = dot(tY, V);
    float ToL = dot(tX, L);
    float BoL = dot(tY, L);

    float aT = roughnessT;
    float aT2 = aT * aT;
    float aB = roughnessB;
    float aB2 = aB * aB;
    float lambdaV = NoL * sqrt(aT2 * ToV * ToV + aB2 * BoV * BoV + NoV * NoV);
    float lambdaL = NoV * sqrt(aT2 * ToL * ToL + aB2 * BoL * BoL + NoL * NoL);
    float Vis = 0.5 / (lambdaV + lambdaL);
	
    weightOverPdf = 4 * Vis * NoL * VoH / NoH;
}

float MISWeight(uint Num, float PDF, uint OtherNum, float OtherPDF) {
	float Weight = Num * PDF;
	float OtherWeight = OtherNum * OtherPDF;
	return Weight * Weight / (Weight * Weight + OtherWeight * OtherWeight);
}

#endif