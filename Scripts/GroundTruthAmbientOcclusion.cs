using UnityEngine;
using System.Collections;
using UnityEngine.Rendering;
using System.Collections.Generic;

[ExecuteInEditMode]
[ImageEffectAllowedInSceneView]
[RequireComponent(typeof(Camera))]
public class GroundTruthAmbientOcclusion : MonoBehaviour {

    //////Enum Property//////
    public enum OutPass
    {
        Combien = 4,
        AO = 5,
        RO = 6,
        BentNormal = 7
    };



//////C# To Shader Property
    ///Public
    [Header("Render Property")]

    [SerializeField]
    [Range(1, 4)]
    int DirSampler = 2;


    [SerializeField]
    [Range(1, 8)]
    int SliceSampler = 2;


    [SerializeField]
    [Range(1, 5)]
    float Radius = 2.5f;


    [SerializeField]
    [Range(0, 1)]
    float Intensity = 1;


    [SerializeField]
    [Range(1, 8)]
    float Power = 2.5f;


    [SerializeField]
    bool MultiBounce = true;



    [Header("Filtter Property")]

    [Range(0, 1)]
    [SerializeField]
    float Sharpeness = 0.25f;

    [Range(1, 5)]
    [SerializeField]
    float TemporalScale = 1;

    [Range(0, 1)]
    [SerializeField]
    float TemporalResponse = 1;



    [Header("DeBug")]

    [SerializeField]
    private OutPass AODeBug = OutPass.Combien;




    //////BaseProperty
    private Camera RenderCamera;
    private Material GTAOMaterial;
    private CommandBuffer GTAOBuffer = null;


    //////Transform property 
    private Matrix4x4 projectionMatrix;
    private Matrix4x4 LastFrameViewProjectionMatrix;
    private Matrix4x4 View_ProjectionMatrix;
    private Matrix4x4 Inverse_View_ProjectionMatrix;
    private Matrix4x4 worldToCameraMatrix;

    ////// private
    private float HalfProjScale;
    private float TemporalOffsets;
    private float TemporalDirections;
    private Vector2 CameraSize;
    private Vector2 RenderResolution;
    private Vector4 UVToView;
    private Vector4 oneOverSize_Size;
    private Vector4 Target_TexelSize;


    private RenderTexture Prev_RT;
    private RenderTexture[] AO_BentNormal_RT = new RenderTexture[2];
    private RenderTargetIdentifier[] AO_BentNormal_ID = new RenderTargetIdentifier[2];

    private uint m_sampleStep = 0;
	private static readonly float[] m_temporalRotations = {60, 300, 180, 240, 120, 0};
	private static readonly float[] m_spatialOffsets = {0, 0.5f, 0.25f, 0.75f};



    //////Shader Property
    ///Public
    private static int _ProjectionMatrix_ID = Shader.PropertyToID("_ProjectionMatrix");
    private static int _LastFrameViewProjectionMatrix_ID = Shader.PropertyToID("_LastFrameViewProjectionMatrix");
    private static int _View_ProjectionMatrix_ID = Shader.PropertyToID("_View_ProjectionMatrix");
    private static int _Inverse_View_ProjectionMatrix_ID = Shader.PropertyToID("_Inverse_View_ProjectionMatrix");
    private static int _WorldToCameraMatrix_ID = Shader.PropertyToID("_WorldToCameraMatrix");
    private static int _CameraToWorldMatrix_ID = Shader.PropertyToID("_CameraToWorldMatrix");


    private static int _AO_DirSampler_ID = Shader.PropertyToID("_AO_DirSampler");
    private static int _AO_SliceSampler_ID = Shader.PropertyToID("_AO_SliceSampler");
    private static int _AO_Power_ID = Shader.PropertyToID("_AO_Power");
    private static int _AO_Intensity_ID = Shader.PropertyToID("_AO_Intensity");
    private static int _AO_Radius_ID = Shader.PropertyToID("_AO_Radius");
    private static int _AO_Sharpeness_ID = Shader.PropertyToID("_AO_Sharpeness");
    private static int _AO_TemporalScale_ID = Shader.PropertyToID("_AO_TemporalScale");
    private static int _AO_TemporalResponse_ID = Shader.PropertyToID("_AO_TemporalResponse");
    private static int _AO_MultiBounce_ID = Shader.PropertyToID("_AO_MultiBounce");


    ///Private
    private static int _AO_HalfProjScale_ID = Shader.PropertyToID("_AO_HalfProjScale");
    private static int _AO_TemporalOffsets_ID = Shader.PropertyToID("_AO_TemporalOffsets");
    private static int _AO_TemporalDirections_ID = Shader.PropertyToID("_AO_TemporalDirections");
    private static int _AO_UVToView_ID = Shader.PropertyToID("_AO_UVToView");
    private static int _AO_RT_TexelSize_ID = Shader.PropertyToID("_AO_RT_TexelSize");


    private static int _AO_Scene_Color_ID = Shader.PropertyToID("_AO_Scene_Color");
    private static int _BentNormal_Texture_ID = Shader.PropertyToID("_BentNormal_Texture");
    private static int _GTAO_Texture_ID = Shader.PropertyToID("_GTAO_Texture");
    private static int _GTAO_Spatial_Texture_ID = Shader.PropertyToID("_GTAO_Spatial_Texture");
    private static int _PrevRT_ID = Shader.PropertyToID("_PrevRT");
    private static int _CurrRT_ID = Shader.PropertyToID("_CurrRT");
    private static int _Combien_AO_RT_ID = Shader.PropertyToID("_Combien_AO_RT");

/* *//* *//* *//* *//* *//* *//* *//* *//* *//* *//* *//* *//* *//* *//* *//* *//* *//* *//* *//* *//* *//* *//* *//* *//* *//* *//* *//* *//* *//* *//* *//* *//* *//* *//* *//* *//* *//* *//* *//* *//* *//* *//* *//* */
    void Awake()
    {
        RenderCamera = gameObject.GetComponent<Camera>();
        GTAOMaterial = new Material(Shader.Find("Hidden/GroundTruthAmbientOcclusion"));
    }

    void OnEnable()
    {
        GTAOBuffer = new CommandBuffer();
        GTAOBuffer.name = "GroundTruthAmbientOcclusion";
        RenderCamera.AddCommandBuffer(CameraEvent.BeforeImageEffectsOpaque, GTAOBuffer);
    }

    void OnPreRender()
    {
        //RenderResolution = new Vector2(RenderCamera.pixelWidth, RenderCamera.pixelHeight) / (int)SamplerResolution;
        RenderResolution = new Vector2(RenderCamera.pixelWidth, RenderCamera.pixelHeight);

        if (GTAOBuffer != null)
        {
            UpdateVariable_SSAO();
            RenderSSAO();
        }
    }

    void OnDisable()
    {
        if (GTAOBuffer != null) {
            RenderCamera.RemoveCommandBuffer(CameraEvent.BeforeImageEffectsOpaque, GTAOBuffer);
            GTAOBuffer = null;
        }
    }

    private void OnDestroy()
    {
        if (AO_BentNormal_RT[0] != null)
        {
            AO_BentNormal_RT[0].Release();
            AO_BentNormal_RT[0] = null;
        }

        if (AO_BentNormal_RT[1] != null)
        {
            AO_BentNormal_RT[1].Release();
            AO_BentNormal_RT[1] = null;
        }

        if (Prev_RT != null)
        {
            Prev_RT.Release();
            Prev_RT = null;
        }

        if (GTAOBuffer != null) {
            GTAOBuffer.Dispose();
        }
    }





    ////////////////////////////////////////////////////////////////SSAO Function////////////////////////////////////////////////////////////////
    private void UpdateVariable_SSAO()
    {
        //----------------------------------------------------------------------------------
        worldToCameraMatrix = RenderCamera.worldToCameraMatrix;
        GTAOMaterial.SetMatrix(_WorldToCameraMatrix_ID, worldToCameraMatrix);
        GTAOMaterial.SetMatrix(_CameraToWorldMatrix_ID, worldToCameraMatrix.inverse);
        projectionMatrix = GL.GetGPUProjectionMatrix(RenderCamera.projectionMatrix, false);
        GTAOMaterial.SetMatrix(_ProjectionMatrix_ID, projectionMatrix);
        View_ProjectionMatrix = projectionMatrix * worldToCameraMatrix;
        GTAOMaterial.SetMatrix(_View_ProjectionMatrix_ID, View_ProjectionMatrix);
        GTAOMaterial.SetMatrix(_Inverse_View_ProjectionMatrix_ID, View_ProjectionMatrix.inverse);
        GTAOMaterial.SetMatrix(_LastFrameViewProjectionMatrix_ID, LastFrameViewProjectionMatrix);

        //----------------------------------------------------------------------------------
        GTAOMaterial.SetFloat(_AO_DirSampler_ID, DirSampler);
        GTAOMaterial.SetFloat(_AO_SliceSampler_ID, SliceSampler);
        GTAOMaterial.SetFloat(_AO_Intensity_ID, Intensity);
        GTAOMaterial.SetFloat(_AO_Radius_ID, Radius);
        GTAOMaterial.SetFloat(_AO_Power_ID, Power);
        GTAOMaterial.SetFloat(_AO_Sharpeness_ID, Sharpeness);
        GTAOMaterial.SetFloat(_AO_TemporalScale_ID, TemporalScale);
        GTAOMaterial.SetFloat(_AO_TemporalResponse_ID, TemporalResponse);
        GTAOMaterial.SetInt(_AO_MultiBounce_ID, MultiBounce ? 1 : 0);


        //----------------------------------------------------------------------------------
        float fovRad = RenderCamera.fieldOfView * Mathf.Deg2Rad;
        float invHalfTanFov = 1 / Mathf.Tan(fovRad * 0.5f);
        Vector2 focalLen = new Vector2(invHalfTanFov * ((float)RenderResolution.y / (float)RenderResolution.x), invHalfTanFov);
        Vector2 invFocalLen = new Vector2(1 / focalLen.x, 1 / focalLen.y);
        GTAOMaterial.SetVector(_AO_UVToView_ID, new Vector4(2 * invFocalLen.x, 2 * invFocalLen.y, -1 * invFocalLen.x, -1 * invFocalLen.y));

        //----------------------------------------------------------------------------------
        float projScale;
        projScale = (float)RenderResolution.y / (Mathf.Tan(fovRad * 0.5f) * 2) * 0.5f;
        GTAOMaterial.SetFloat(_AO_HalfProjScale_ID, projScale);

        //----------------------------------------------------------------------------------
        oneOverSize_Size = new Vector4(1 / (float)RenderResolution.x, 1 / (float)RenderResolution.y, (float)RenderResolution.x, (float)RenderResolution.y);
        GTAOMaterial.SetVector(_AO_RT_TexelSize_ID, oneOverSize_Size);

        //----------------------------------------------------------------------------------
        float temporalRotation = m_temporalRotations[m_sampleStep % 6];
        float temporalOffset = m_spatialOffsets[(m_sampleStep / 6) % 4];
        GTAOMaterial.SetFloat(_AO_TemporalDirections_ID, temporalRotation / 360);
        GTAOMaterial.SetFloat(_AO_TemporalOffsets_ID, temporalOffset);
        m_sampleStep++;

        //----------------------------------------------------------------------------------
        if (AO_BentNormal_RT[0] != null)
        {
            AO_BentNormal_RT[0].Release();
        }
        if (AO_BentNormal_RT[1] != null)
        {
            AO_BentNormal_RT[1].Release();
        }
        AO_BentNormal_RT[0] = new RenderTexture((int)RenderResolution.x, (int)RenderResolution.y, 0, RenderTextureFormat.RGHalf);
        AO_BentNormal_RT[1] = new RenderTexture((int)RenderResolution.x, (int)RenderResolution.y, 0, RenderTextureFormat.ARGBHalf);
        AO_BentNormal_ID[0] = AO_BentNormal_RT[0].colorBuffer;
        AO_BentNormal_ID[1] = AO_BentNormal_RT[1].colorBuffer;

        //----------------------------------------------------------------------------------
        Vector2 currentCameraSize = RenderResolution;
        if (CameraSize != currentCameraSize) 
        {
            CameraSize = currentCameraSize;

            //----------------------------------------------------------------------------------
            if (Prev_RT != null)
            {
                Prev_RT.Release();
            }
            Prev_RT = new RenderTexture((int)RenderResolution.x, (int)RenderResolution.y, 0, RenderTextureFormat.RGHalf);
            Prev_RT.filterMode = FilterMode.Point;
        }
    }

    private void RenderSSAO()
    {
        GTAOBuffer.Clear();

        GTAOBuffer.GetTemporaryRT(_AO_Scene_Color_ID, (int)RenderResolution.x, (int)RenderResolution.y, 0, FilterMode.Point, RenderTextureFormat.DefaultHDR);
        GTAOBuffer.Blit(BuiltinRenderTextureType.CameraTarget, _AO_Scene_Color_ID);

        //////Resolve GTAO 
        GTAOBuffer.SetGlobalTexture(_GTAO_Texture_ID, AO_BentNormal_RT[0]);
        GTAOBuffer.SetGlobalTexture(_BentNormal_Texture_ID, AO_BentNormal_RT[1]);
        GTAOBuffer.BlitMRT(AO_BentNormal_ID, BuiltinRenderTextureType.CameraTarget, GTAOMaterial, 0);

        //////Spatial filter
        //------//XBlur
        GTAOBuffer.GetTemporaryRT(_GTAO_Spatial_Texture_ID, (int)RenderResolution.x, (int)RenderResolution.y, 0, FilterMode.Point, RenderTextureFormat.RGHalf);
        GTAOBuffer.BlitSRT(_GTAO_Spatial_Texture_ID, GTAOMaterial, 1);
        //------//YBlur
        GTAOBuffer.CopyTexture(_GTAO_Spatial_Texture_ID, AO_BentNormal_RT[0]);
        GTAOBuffer.BlitSRT(_GTAO_Spatial_Texture_ID, GTAOMaterial, 2);

        //////Temporal filter
        GTAOBuffer.SetGlobalTexture(_PrevRT_ID, Prev_RT);
        GTAOBuffer.GetTemporaryRT(_CurrRT_ID, (int)RenderResolution.x, (int)RenderResolution.y, 0, FilterMode.Point, RenderTextureFormat.RGHalf);
        GTAOBuffer.BlitSRT(_CurrRT_ID, GTAOMaterial, 3);
        GTAOBuffer.CopyTexture(_CurrRT_ID, Prev_RT);

        ////// Combien Scene Color
        GTAOBuffer.GetTemporaryRT(_Combien_AO_RT_ID, (int)RenderResolution.x, (int)RenderResolution.y, 0, FilterMode.Point, RenderTextureFormat.DefaultHDR);
        GTAOBuffer.BlitSRT(_Combien_AO_RT_ID, BuiltinRenderTextureType.CameraTarget, GTAOMaterial, (int)AODeBug);

        LastFrameViewProjectionMatrix = View_ProjectionMatrix;
    }

}
