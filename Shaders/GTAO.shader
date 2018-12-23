Shader "Hidden/GroundTruthAmbientOcclusion"
{
	CGINCLUDE
		#include "GTAO_Pass.cginc"
	ENDCG

	SubShader
	{
		ZTest Always
		Cull Off
		ZWrite Off

		Pass 
		{ 
			Name"ResolveGTAO"
			CGPROGRAM 
				#pragma vertex vert
				#pragma fragment ResolveGTAO_frag
			ENDCG 
		}

		Pass 
		{ 
			Name"SpatialGTAO_X"
			CGPROGRAM 
				#pragma vertex vert
				#pragma fragment SpatialGTAO_X_frag
			ENDCG 
		}

		Pass 
		{ 
			Name"SpatialGTAO_Y"
			CGPROGRAM 
				#pragma vertex vert
				#pragma fragment SpatialGTAO_Y_frag
			ENDCG 
		}

		Pass 
		{ 
			Name"TemporalGTAO"
			CGPROGRAM 
				#pragma vertex vert
				#pragma fragment TemporalGTAO_frag
			ENDCG 
		}

		Pass 
		{ 
			Name"CombienGTAO"
			CGPROGRAM 
				#pragma vertex vert
				#pragma fragment CombienGTAO_frag
			ENDCG 
		}

		Pass 
		{ 
			Name"DeBugGTAO"
			CGPROGRAM 
				#pragma vertex vert
				#pragma fragment DeBugGTAO_frag
			ENDCG 
		}

		Pass 
		{ 
			Name"DeBugGTRO"
			CGPROGRAM 
				#pragma vertex vert
				#pragma fragment DeBugGTRO_frag
			ENDCG 
		}

		Pass 
		{ 
			Name"BentNormal"
			CGPROGRAM 
				#pragma vertex vert
				#pragma fragment DeBugBentNormal_frag
			ENDCG 
		}

	}
}

