#include "GTAO_Common.cginc"

//////Resolve Pass
void ResolveGTAO_frag(PixelInput IN, out half2 AO : SV_Target0, out half3 BentNormal : SV_Target1)
{
	half2 uv = IN.uv.xy;

	half Depth = 0;
	half4 GT_Details = GTAO(uv, (int)_AO_DirSampler, (int)_AO_SliceSampler, Depth);

	AO = half2(GT_Details.a, Depth);
	BentNormal = mul((half3x3)_CameraToWorldMatrix, half3(GT_Details.rg, -GT_Details.b));
} 

//////Spatial filter
half2 SpatialGTAO_X_frag(PixelInput IN) : SV_Target
{
	half2 uv = IN.uv.xy;
	half2 AO = BilateralBlur(uv, half2(1 / _ScreenParams.x, 0));
	return AO;
} 

half2 SpatialGTAO_Y_frag(PixelInput IN) : SV_Target
{
	half2 uv = IN.uv.xy;
	half2 AO = BilateralBlur(uv, half2(0, 1 / _ScreenParams.y));

	//////Reflection Occlusion
	half3 bentNormal = tex2D(_BentNormal_Texture, uv).rgb;
	half3 worldNormal = tex2D(_CameraGBufferTexture2, uv).rgb * 2 - 1;
	half4 Specular = tex2D(_CameraGBufferTexture1, uv);
	half Roughness = 1 - Specular.a;

	half Depth = tex2D(_CameraDepthTexture, uv).r;
	half4 worldPos = mul(_Inverse_View_ProjectionMatrix, half4(half3(uv * 2 - 1, Depth), 1));
	worldPos.xyz /= worldPos.w;

	half3 viewDir= normalize(worldPos.xyz - _WorldSpaceCameraPos.rgb);
	half3 reflectionDir = reflect(viewDir, worldNormal);
	half GTRO = ReflectionOcclusion(bentNormal, reflectionDir, Roughness, 0.5);

	return lerp(1, half2(AO.r, GTRO), _AO_Intensity);
} 

//////Temporal filter
half4 TemporalGTAO_frag(PixelInput IN) : SV_Target
{
	half2 uv = IN.uv.xy; 
	half2 velocity = tex2D(_CameraMotionVectorsTexture, uv);

	half4 filterColor = 0;
	half4 minColor, maxColor;
	ResolverAABB(_GTAO_Spatial_Texture, 0, 0, _AO_TemporalScale, uv, _AO_RT_TexelSize.zw, minColor, maxColor, filterColor);

	half4 currColor = filterColor;
	half4 lastColor = tex2D(_PrevRT, uv - velocity);
	lastColor = clamp(lastColor, minColor, maxColor);
	if (uv.x < 0 || uv.x > 1 || uv.y < 0 || uv.y > 1)
	{
		lastColor = filterColor;
	}
	half weight = saturate(clamp(_AO_TemporalResponse, 0, 0.98) * (1 - length(velocity) * 8));

	half4 temporalColor = lerp(currColor, lastColor, weight);
	return temporalColor;
}

//////Combien Scene Color
half4 CombienGTAO_frag(PixelInput IN) : SV_Target
{
	half2 uv = IN.uv.xy;

	//////AO & MultiBounce
	half2 GT_Occlusion = tex2D(_CurrRT, uv).rg;
	half3 GTAO = GT_Occlusion.r;
	half GTRO = GT_Occlusion.g;

	if (_AO_MultiBounce == 1)
	{
		half3 Albedo = tex2D(_CameraGBufferTexture0, uv);
		GTAO = MultiBounce(GTAO, Albedo);
	}

	half3 RelfectionColor = tex2D(_CameraReflectionsTexture, uv).rgb;
	half3 SceneColor = GTAO * (tex2D(_AO_Scene_Color, uv) - RelfectionColor);
	RelfectionColor *= GTRO;
	
	return half4(SceneColor + RelfectionColor, 1);
}

//////DeBug AO
half4 DeBugGTAO_frag(PixelInput IN) : SV_Target
{
	half2 uv = IN.uv.xy;

	//////AO & MultiBounce
	half2 GT_Occlusion = tex2D(_CurrRT, uv).rg;
	half3 GTAO = GT_Occlusion.r;

	if (_AO_MultiBounce == 1)
	{
		half3 Albedo = tex2D(_CameraGBufferTexture0, uv);
		GTAO = MultiBounce(GTAO, Albedo);
	}
	
	return half4(GTAO, 1);
}

//////DeBug RO
half4 DeBugGTRO_frag(PixelInput IN) : SV_Target
{
	half2 uv = IN.uv.xy;

	//////AO & MultiBounce
	half2 GT_Occlusion = tex2D(_CurrRT, uv).rg;
	half GTRO = GT_Occlusion.g;
	
	return GTRO;
}

//////DeBug BentNormal
half4 DeBugBentNormal_frag(PixelInput IN) : SV_Target
{
	half2 uv = IN.uv.xy;
	return half4(tex2D(_BentNormal_Texture, uv).rgb * 0.5 + 0.5, 1);
}



































//////Combien Reflection Color
half4 CombienGTRO_frag(PixelInput IN) : SV_Target
{
	half2 uv = IN.uv.xy;
	half depth = tex2D(_CameraDepthTexture, uv).r;
	half4 sceneColor = tex2D(_AO_Scene_Color, uv);
	half4 specular = tex2D(_CameraGBufferTexture1, uv);
	half roughness = 1 - specular.a;

	half4 worldPos = mul(_Inverse_View_ProjectionMatrix, half4(half3(uv * 2 - 1, depth), 1));
	worldPos.xyz /= worldPos.w;

	half3 worldNormal = tex2D(_CameraGBufferTexture2, uv).rgb * 2 - 1;
	half4 bentNormal = tex2D(_CurrRT, uv);

	//////Reflection Occlusion
	half3 viewVector = normalize(worldPos.xyz - _WorldSpaceCameraPos.rgb);
	half3 reflectionDir = reflect(viewVector, worldNormal);

	half4 relfectionColor = tex2D(_CameraReflectionsTexture, uv);
	half groundTruth_RO = ReflectionOcclusion(bentNormal.rgb, reflectionDir, roughness, 0.5);

	return relfectionColor * groundTruth_RO;
}
