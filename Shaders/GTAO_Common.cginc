#include "UnityCG.cginc"
#include "Shader_Include/Include_HLSL.hlsl"

#define KERNEL_RADIUS 8

int _AO_MultiBounce;
half _AO_DirSampler, _AO_SliceSampler, _AO_Intensity, _AO_Radius, _AO_Power, _AO_Sharpeness, _AO_TemporalScale, _AO_TemporalResponse, _AO_HalfProjScale, _AO_TemporalOffsets, _AO_TemporalDirections;
half2 _AO_FadeParams;
half4	_AO_UVToView, _AO_RT_TexelSize, _AO_FadeValues;
half4x4	_WorldToCameraMatrix, _CameraToWorldMatrix, _ProjectionMatrix, _LastFrameViewProjectionMatrix, _View_ProjectionMatrix, _Inverse_View_ProjectionMatrix;
sampler2D _AO_Scene_Color, _CameraGBufferTexture0, _CameraGBufferTexture1, _CameraGBufferTexture2, _CameraReflectionsTexture, _CameraMotionVectorsTexture, _CameraDepthTexture, _CameraDepthNormalsTexture, _BentNormal_Texture, _GTAO_Texture, _GTAO_Spatial_Texture, _PrevRT, _CurrRT;

struct VertexInput
{
	half4 vertex : POSITION;
	half4 uv : TEXCOORD0;
};

struct PixelInput
{
	half4 vertex : SV_POSITION;
	half4 uv : TEXCOORD0;
};

PixelInput vert(VertexInput v)
{
	PixelInput o;
	o.vertex = v.vertex;
	o.uv = v.uv;
	return o;
}

//---//---//----//----//-------//----//----//----//-----//----//-----//----//----MultiBounce & ReflectionOcclusion//---//---//----//----//-------//----//----//----//-----//----//-----//----//----
inline float ApproximateConeConeIntersection(float ArcLength0, float ArcLength1, float AngleBetweenCones)
{
	float AngleDifference = abs(ArcLength0 - ArcLength1);

	float Intersection = smoothstep(0, 1, 1 - saturate((AngleBetweenCones - AngleDifference) / (ArcLength0 + ArcLength1 - AngleDifference)));

	return Intersection;
}

inline half ReflectionOcclusion(half3 BentNormal, half3 ReflectionVector, half Roughness, half OcclusionStrength)
{
	half BentNormalLength = length(BentNormal);
	half ReflectionConeAngle = max(Roughness, 0.1) * PI;
	half UnoccludedAngle = BentNormalLength * PI * OcclusionStrength;

	half AngleBetween = acos(dot(BentNormal, ReflectionVector) / max(BentNormalLength, 0.001));
	half ReflectionOcclusion = ApproximateConeConeIntersection(ReflectionConeAngle, UnoccludedAngle, AngleBetween);
	ReflectionOcclusion = lerp(0, ReflectionOcclusion, saturate((UnoccludedAngle - 0.1) / 0.2));
	return ReflectionOcclusion;
}

inline half ReflectionOcclusion_Approch(half NoV, half Roughness, half AO)
{
	return saturate(pow(NoV + AO, Roughness * Roughness) - 1 + AO);
}

inline half3 MultiBounce(half AO, half3 Albedo)
{
	half3 A = 2 * Albedo - 0.33;
	half3 B = -4.8 * Albedo + 0.64;
	half3 C = 2.75 * Albedo + 0.69;
	return max(AO, ((AO * A + B) * AO + C) * AO);
}


//---//---//----//----//-------//----//----//----//-----//----//-----//----//----BilateralBlur//---//---//----//----//-------//----//----//----//-----//----//-----//----//----
inline void FetchAoAndDepth(float2 uv, inout float ao, inout float depth) {
	float2 aod = tex2Dlod(_GTAO_Texture, float4(uv, 0, 0)).rga;
	ao = aod.r;
	depth = aod.g;
}

inline float CrossBilateralWeight(float r, float d, float d0) {
	const float BlurSigma = (float)KERNEL_RADIUS * 0.5;
	const float BlurFalloff = 1 / (2 * BlurSigma * BlurSigma);

    float dz = (d0 - d) * _ProjectionParams.z * _AO_Sharpeness;
	return exp2(-r * r * BlurFalloff - dz * dz);
}

inline void ProcessSample(float2 aoz, float r, float d0, inout float totalAO, inout float totalW) {
	float w = CrossBilateralWeight(r, d0, aoz.y);
	totalW += w;
	totalAO += w * aoz.x;
}

inline void ProcessRadius(float2 uv0, float2 deltaUV, float d0, inout float totalAO, inout float totalW) {
	float ao, z;
	float2 uv;
	float r = 1;

	UNITY_UNROLL
	for (; r <= KERNEL_RADIUS / 2; r += 1) {
		uv = uv0 + r * deltaUV;
		FetchAoAndDepth(uv, ao, z);
		ProcessSample(float2(ao, z), r, d0, totalAO, totalW);
	}

	UNITY_UNROLL
	for (; r <= KERNEL_RADIUS; r += 2) {
		uv = uv0 + (r + 0.5) * deltaUV;
		FetchAoAndDepth(uv, ao, z);
		ProcessSample(float2(ao, z), r, d0, totalAO, totalW);
	}
		
}

inline float2 BilateralBlur(float2 uv0, float2 deltaUV)
{
	float totalAO, depth;
	FetchAoAndDepth(uv0, totalAO, depth);
	float totalW = 1;
		
	ProcessRadius(uv0, -deltaUV, depth, totalAO, totalW);
	ProcessRadius(uv0, deltaUV, depth, totalAO, totalW);

	totalAO /= totalW;
	return float2(totalAO, depth);
}


//---//---//----//----//-------//----//----//----//-----//----//-----//----//----GTAO//---//---//----//----//-------//----//----//----//-----//----//-----//----//----
inline half ComputeDistanceFade(const half distance)
{
	return saturate(max(0, distance - _AO_FadeParams.x) * _AO_FadeParams.y);
}

inline half3 GetPosition(half2 uv)
{
	half depth = tex2Dlod(_CameraDepthTexture, float4(uv, 0, 0)).r; 
	half viewDepth = LinearEyeDepth(depth);
	return half3((uv * _AO_UVToView.xy + _AO_UVToView.zw) * viewDepth, viewDepth);
}

inline half3 GetNormal(half2 uv)
{
	half3 Normal = tex2D(_CameraGBufferTexture2, uv).rgb * 2 - 1; 
	half3 view_Normal = normalize(mul((half3x3) _WorldToCameraMatrix, Normal));

	return half3(view_Normal.xy, -view_Normal.z);
}

inline half GTAO_Offsets(half2 uv)
{
	int2 position = (int2)(uv * _AO_RT_TexelSize.zw);
	return 0.25 * (half)((position.y - position.x) & 3);
}

inline half GTAO_Noise(half2 position)
{
	return frac(52.9829189 * frac(dot(position, half2( 0.06711056, 0.00583715))));
}

half IntegrateArc_UniformWeight(half2 h)
{
	half2 Arc = 1 - cos(h);
	return Arc.x + Arc.y;
}

half IntegrateArc_CosWeight(half2 h, half n)
{
    half2 Arc = -cos(2 * h - n) + cos(n) + 2 * h * sin(n);
    return 0.25 * (Arc.x + Arc.y);
}

half4 GTAO(half2 uv, int NumCircle, int NumSlice, inout half Depth)
{
	half3 vPos = GetPosition(uv);
	half3 viewNormal = GetNormal(uv);
	half3 viewDir = normalize(0 - vPos);

	half2 radius_thickness = lerp(half2(_AO_Radius, 1), _AO_FadeValues.yw, ComputeDistanceFade(vPos.b).xx);
	half radius = radius_thickness.x;
	half thickness = radius_thickness.y;

	half stepRadius = max(min((radius * _AO_HalfProjScale) / vPos.b, 512), (half)NumSlice);
	stepRadius /= ((half)NumSlice + 1);

	half noiseOffset = GTAO_Offsets(uv);
	half noiseDirection = GTAO_Noise(uv * _AO_RT_TexelSize.zw);

	half initialRayStep = frac(noiseOffset + _AO_TemporalOffsets);

	half Occlusion, angle, bentAngle, wallDarkeningCorrection, projLength, n, cos_n;
	half2 slideDir_TexelSize, h, H, falloff, uvOffset, dsdt, dsdtLength;
	half3 sliceDir, ds, dt, planeNormal, tangent, projectedNormal, BentNormal;
	half4 uvSlice;
	
	if (tex2D(_CameraDepthTexture, uv).r <= 1e-7)
	{
		return 1;
	}

	UNITY_LOOP
	for (int i = 0; i < NumCircle; i++)
	{
		angle = (i + noiseDirection + _AO_TemporalDirections) * (UNITY_PI / (half)NumCircle);
		sliceDir = half3(half2(cos(angle), sin(angle)), 0);
		slideDir_TexelSize = sliceDir.xy * _AO_RT_TexelSize.xy;
		h = -1;

		UNITY_LOOP
		for (int j = 0; j < NumSlice; j++)
		{
			uvOffset = slideDir_TexelSize * max(stepRadius * (j + initialRayStep), 1 + j);
			uvSlice = uv.xyxy + float4(uvOffset.xy, -uvOffset);

			ds = GetPosition(uvSlice.xy) - vPos;
			dt = GetPosition(uvSlice.zw) - vPos;

			dsdt = half2(dot(ds, ds), dot(dt, dt));
			dsdtLength = rsqrt(dsdt);

			falloff = saturate(dsdt.xy * (2 / pow2(radius)));

			H = half2(dot(ds, viewDir), dot(dt, viewDir)) * dsdtLength;
			h.xy = (H.xy > h.xy) ? lerp(H, h, falloff) : lerp(H.xy, h.xy, thickness);
		}

		planeNormal = normalize(cross(sliceDir, viewDir));
		tangent = cross(viewDir, planeNormal);
		projectedNormal = viewNormal - planeNormal * dot(viewNormal, planeNormal);
		projLength = length(projectedNormal);

		cos_n = clamp(dot(normalize(projectedNormal), viewDir), -1, 1);
		n = -sign(dot(projectedNormal, tangent)) * acos(cos_n);

		h = acos(clamp(h, -1, 1));
		h.x = n + max(-h.x - n, -UNITY_HALF_PI);
		h.y = n + min(h.y - n, UNITY_HALF_PI);

		bentAngle = (h.x + h.y) * 0.5;

		BentNormal += viewDir * cos(bentAngle) - tangent * sin(bentAngle);
		Occlusion += projLength * IntegrateArc_CosWeight(h, n); 			
		//Occlusion += projLength * IntegrateArc_UniformWeight(h);			
	}

	BentNormal = normalize(normalize(BentNormal) - viewDir * 0.5);
	Occlusion = saturate(pow(Occlusion / (half)NumCircle, _AO_Power));
	Depth = vPos.b;

	return half4(BentNormal, Occlusion);
}
