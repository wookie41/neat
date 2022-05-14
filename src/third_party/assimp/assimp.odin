package assimp

foreign import assimp "external/assimp-vc143-mt.lib"

import _c "core:c"

AABB_H_INC :: 1;
ANIM_H_INC :: 1;
CAMERA_H_INC :: 1;
ASSIMP_H_INC :: 1;
FALSE :: 0;
TRUE :: 1;
IMPORTER_DESC_H_INC :: 1;
LIGHT_H_INC :: 1;
MATERIAL_H_INC :: 1;
DEFAULT_MATERIAL_NAME :: "DefaultMaterial";
TEXTURE_TYPE_MAX :: 21;
MATKEY_NAME :: "?mat.name";
MATKEY_TWOSIDED :: "$mat.twosided";
MATKEY_SHADING_MODEL :: "$mat.shadingm";
MATKEY_ENABLE_WIREFRAME :: "$mat.wireframe";
MATKEY_BLEND_FUNC :: "$mat.blend";
MATKEY_OPACITY :: "$mat.opacity";
MATKEY_TRANSPARENCYFACTOR :: "$mat.transparencyfactor";
MATKEY_BUMPSCALING :: "$mat.bumpscaling";
MATKEY_SHININESS :: "$mat.shininess";
MATKEY_REFLECTIVITY :: "$mat.reflectivity";
MATKEY_SHININESS_STRENGTH :: "$mat.shinpercent";
MATKEY_REFRACTI :: "$mat.refracti";
MATKEY_COLOR_DIFFUSE :: "$clr.diffuse";
MATKEY_COLOR_AMBIENT :: "$clr.ambient";
MATKEY_COLOR_SPECULAR :: "$clr.specular";
MATKEY_COLOR_EMISSIVE :: "$clr.emissive";
MATKEY_COLOR_TRANSPARENT :: "$clr.transparent";
MATKEY_COLOR_REFLECTIVE :: "$clr.reflective";
MATKEY_GLOBAL_BACKGROUND_IMAGE :: "?bg.global";
MATKEY_GLOBAL_SHADERLANG :: "?sh.lang";
MATKEY_SHADER_VERTEX :: "?sh.vs";
MATKEY_SHADER_FRAGMENT :: "?sh.fs";
MATKEY_SHADER_GEO :: "?sh.gs";
MATKEY_SHADER_TESSELATION :: "?sh.ts";
MATKEY_SHADER_PRIMITIVE :: "?sh.ps";
MATKEY_SHADER_COMPUTE :: "?sh.cs";
MATKEY_USE_COLOR_MAP :: "$mat.useColorMap";
MATKEY_BASE_COLOR :: "$clr.base";
MATKEY_BASE_COLOR_TEXTURE :: 12;
MATKEY_USE_METALLIC_MAP :: "$mat.useMetallicMap";
MATKEY_METALLIC_FACTOR :: "$mat.metallicFactor";
MATKEY_METALLIC_TEXTURE :: 15;
MATKEY_USE_ROUGHNESS_MAP :: "$mat.useRoughnessMap";
MATKEY_ROUGHNESS_FACTOR :: "$mat.roughnessFactor";
MATKEY_ROUGHNESS_TEXTURE :: 16;
MATKEY_ANISOTROPY_FACTOR :: "$mat.anisotropyFactor";
MATKEY_SPECULAR_FACTOR :: "$mat.specularFactor";
MATKEY_GLOSSINESS_FACTOR :: "$mat.glossinessFactor";
MATKEY_SHEEN_COLOR_FACTOR :: "$clr.sheen.factor";
MATKEY_SHEEN_ROUGHNESS_FACTOR :: "$mat.sheen.roughnessFactor";
MATKEY_SHEEN_COLOR_TEXTURE :: 19;
MATKEY_SHEEN_ROUGHNESS_TEXTURE :: 19;
MATKEY_CLEARCOAT_FACTOR :: "$mat.clearcoat.factor";
MATKEY_CLEARCOAT_ROUGHNESS_FACTOR :: "$mat.clearcoat.roughnessFactor";
MATKEY_CLEARCOAT_TEXTURE :: 20;
MATKEY_CLEARCOAT_ROUGHNESS_TEXTURE :: 20;
MATKEY_CLEARCOAT_NORMAL_TEXTURE :: 20;
MATKEY_TRANSMISSION_FACTOR :: "$mat.transmission.factor";
MATKEY_TRANSMISSION_TEXTURE :: 21;
MATKEY_VOLUME_THICKNESS_FACTOR :: "$mat.volume.thicknessFactor";
MATKEY_VOLUME_THICKNESS_TEXTURE :: 21;
MATKEY_VOLUME_ATTENUATION_DISTANCE :: "$mat.volume.attenuationDistance";
MATKEY_VOLUME_ATTENUATION_COLOR :: "$mat.volume.attenuationColor";
MATKEY_USE_EMISSIVE_MAP :: "$mat.useEmissiveMap";
MATKEY_EMISSIVE_INTENSITY :: "$mat.emissiveIntensity";
MATKEY_USE_AO_MAP :: "$mat.useAOMap";
_AI_MATKEY_TEXTURE_BASE :: "$tex.file";
_AI_MATKEY_UVWSRC_BASE :: "$tex.uvwsrc";
_AI_MATKEY_TEXOP_BASE :: "$tex.op";
_AI_MATKEY_MAPPING_BASE :: "$tex.mapping";
_AI_MATKEY_TEXBLEND_BASE :: "$tex.blend";
_AI_MATKEY_MAPPINGMODE_U_BASE :: "$tex.mapmodeu";
_AI_MATKEY_MAPPINGMODE_V_BASE :: "$tex.mapmodev";
_AI_MATKEY_TEXMAP_AXIS_BASE :: "$tex.mapaxis";
_AI_MATKEY_UVTRANSFORM_BASE :: "$tex.uvtrafo";
_AI_MATKEY_TEXFLAGS_BASE :: "$tex.flags";
MATRIX3X3_H_INC :: 1;
MATRIX4X4_H_INC :: 1;
MESH_H_INC :: 1;
MAX_FACE_INDICES :: 32767;
MAX_BONE_WEIGHTS :: 2147483647;
MAX_VERTICES :: 2147483647;
MAX_FACES :: 2147483647;
MAX_NUMBER_OF_COLOR_SETS :: 8;
MAX_NUMBER_OF_TEXTURECOORDS :: 8;
METADATA_H_INC :: 1;
PBRMATERIAL_H_INC :: 1;
MATKEY_GLTF_UNLIT :: "$mat.gltf.unlit";
POSTPROCESS_H_INC :: 1;
QUATERNION_H_INC :: 1;
SCENE_H_INC :: 1;
SCENE_FLAGS_INCOMPLETE :: 1;
SCENE_FLAGS_VALIDATED :: 2;
SCENE_FLAGS_VALIDATION_WARNING :: 4;
SCENE_FLAGS_NON_VERBOSE_FORMAT :: 8;
SCENE_FLAGS_TERRAIN :: 16;
SCENE_FLAGS_ALLOW_SHARED :: 32;
TEXTURE_H_INC :: 1;
EMBEDDED_TEXNAME_PREFIX :: "*";
HINTMAXTEXTURELEN :: 9;
TYPES_H_INC :: 1;
MAXLEN :: 1024;
SUCCESS :: 0;
FAILURE :: -1;
OUTOFMEMORY :: -3;
DLS_FILE :: 1;
DLS_STDOUT :: 2;
DLS_STDERR :: 4;
DLS_DEBUGGER :: 8;
VECTOR2D_H_INC :: 1;
VECTOR3D_H_INC :: 1;
VERSION_H_INC :: 1;
ASSIMP_CFLAGS_SHARED :: 1;
ASSIMP_CFLAGS_STLPORT :: 2;
ASSIMP_CFLAGS_DEBUG :: 4;
ASSIMP_CFLAGS_NOBOOST :: 8;
ASSIMP_CFLAGS_SINGLETHREADED :: 16;
ASSIMP_CFLAGS_DOUBLE_SUPPORT :: 32;

LogStreamCallback :: #type proc(unamed0 : cstring, unamed1 : cstring);
Bool :: _c.int;
int32 :: i32;
uint32 :: u32;

AnimBehaviour :: enum i32 {
    AianimbehaviourDefault = 0,
    AianimbehaviourConstant = 1,
    AianimbehaviourLinear = 2,
    AianimbehaviourRepeat = 3,
};

ImporterFlags :: enum i32 {
    AiimporterflagsSupporttextflavour = 1,
    AiimporterflagsSupportbinaryflavour = 2,
    AiimporterflagsSupportcompressedflavour = 4,
    AiimporterflagsLimitedsupport = 8,
    AiimporterflagsExperimental = 16,
};

LightSourceType :: enum i32 {
    AilightsourceUndefined = 0,
    AilightsourceDirectional = 1,
    AilightsourcePoint = 2,
    AilightsourceSpot = 3,
    AilightsourceAmbient = 4,
    AilightsourceArea = 5,
};

TextureOp :: enum i32 {
    AitextureopMultiply = 0,
    AitextureopAdd = 1,
    AitextureopSubtract = 2,
    AitextureopDivide = 3,
    AitextureopSmoothadd = 4,
    AitextureopSignedadd = 5,
};

TextureMapMode :: enum i32 {
    AitexturemapmodeWrap = 0,
    AitexturemapmodeClamp = 1,
    AitexturemapmodeDecal = 3,
    AitexturemapmodeMirror = 2,
};

TextureMapping :: enum i32 {
    AitexturemappingUv = 0,
    AitexturemappingSphere = 1,
    AitexturemappingCylinder = 2,
    AitexturemappingBox = 3,
    AitexturemappingPlane = 4,
    AitexturemappingOther = 5,
};

TextureType :: enum i32 {
    AitexturetypeNone = 0,
    AitexturetypeDiffuse = 1,
    AitexturetypeSpecular = 2,
    AitexturetypeAmbient = 3,
    AitexturetypeEmissive = 4,
    AitexturetypeHeight = 5,
    AitexturetypeNormals = 6,
    AitexturetypeShininess = 7,
    AitexturetypeOpacity = 8,
    AitexturetypeDisplacement = 9,
    AitexturetypeLightmap = 10,
    AitexturetypeReflection = 11,
    AitexturetypeBaseColor = 12,
    AitexturetypeNormalCamera = 13,
    AitexturetypeEmissionColor = 14,
    AitexturetypeMetalness = 15,
    AitexturetypeDiffuseRoughness = 16,
    AitexturetypeAmbientOcclusion = 17,
    AitexturetypeSheen = 19,
    AitexturetypeClearcoat = 20,
    AitexturetypeTransmission = 21,
    AitexturetypeUnknown = 18,
};

ShadingMode :: enum i32 {
    AishadingmodeFlat = 1,
    AishadingmodeGouraud = 2,
    AishadingmodePhong = 3,
    AishadingmodeBlinn = 4,
    AishadingmodeToon = 5,
    AishadingmodeOrennayar = 6,
    AishadingmodeMinnaert = 7,
    AishadingmodeCooktorrance = 8,
    AishadingmodeNoshading = 9,
    AishadingmodeUnlit = 9,
    AishadingmodeFresnel = 10,
    AishadingmodePbrBrdf = 11,
};

TextureFlags :: enum i32 {
    AitextureflagsInvert = 1,
    AitextureflagsUsealpha = 2,
    AitextureflagsIgnorealpha = 4,
};

BlendMode :: enum i32 {
    AiblendmodeDefault = 0,
    AiblendmodeAdditive = 1,
};

PropertyTypeInfo :: enum i32 {
    AiptiFloat = 1,
    AiptiDouble = 2,
    AiptiString = 3,
    AiptiInteger = 4,
    AiptiBuffer = 5,
};

PrimitiveType :: enum i32 {
    AiprimitivetypePoint = 1,
    AiprimitivetypeLine = 2,
    AiprimitivetypeTriangle = 4,
    AiprimitivetypePolygon = 8,
    AiprimitivetypeNgonencodingflag = 16,
};

MorphingMethod :: enum i32 {
    AimorphingmethodVertexBlend = 1,
    AimorphingmethodMorphNormalized = 2,
    AimorphingmethodMorphRelative = 3,
};

MetadataType :: enum i32 {
    Bool = 0,
    Int32 = 1,
    Uint64 = 2,
    Float = 3,
    Double = 4,
    Aistring = 5,
    Aivector3D = 6,
    Aimetadata = 7,
    MetaMax = 8,
};

PostProcessStepsFlags :: distinct bit_set[PostProcessStepsFlagBits;u32]
PostProcessStepsFlagBits :: enum u32 {
    CalcTangentSpace,
    JoinIdenticalVertices,
    MakeLeftHanded,
    Triangulate,
    RemoveComponent,
    GenNormals,
    GenSmoothNormals,
    SplitLargeMeshes,
    PreTransformVertices,
    LimitBoneWeights,
    ValidateDataStructure,
    ImproveCacheLocality,
    RemoveRedundantMaterials,
    FixInfacingNormals,
    PopulateArmatureData,
    SortByPType,
    FindDegenerates,
    FindInvalidData,
    GenUVCoords,
    TransformUVCoords,
    FindInstances,
    OptimizeMeshes,
    OptimizeGraph,
    FlipUVs,
    FlipWindingOrder,
    SplitByBoneCount,
    Debone,
    GlobalScale,
    EmbedTextures,
    ForceGenNormals,
    DropNormals,
    GenBoundingBoxes,
};

Return :: enum i32 {
    AireturnSuccess = 0,
    AireturnFailure = -1,
    AireturnOutofmemory = -3,
    AiEnforceEnumSize = 2147483647,
};

Origin :: enum i32 {
    AioriginSet = 0,
    AioriginCur = 1,
    AioriginEnd = 2,
    AiOriginEnforceEnumSize = 2147483647,
};

DefaultLogStream :: enum i32 {
    AidefaultlogstreamFile = 1,
    AidefaultlogstreamStdout = 2,
    AidefaultlogstreamStderr = 4,
    AidefaultlogstreamDebugger = 8,
    AiDlsEnforceEnumSize = 2147483647,
};

AABB :: struct {
    mMin : Vector3D,
    mMax : Vector3D,
};

VectorKey :: struct {
    mTime : _c.double,
    mValue : Vector3D,
};

QuatKey :: struct {
    mTime : _c.double,
    mValue : Quaternion,
};

MeshKey :: struct {
    mTime : _c.double,
    mValue : _c.uint,
};

MeshMorphKey :: struct {
    mTime : _c.double,
    mValues : [^]_c.uint,
    mWeights : [^]_c.double,
    mNumValuesAndWeights : _c.uint,
};

NodeAnim :: struct {
    mNodeName : String,
    mNumPositionKeys : _c.uint,
    mPositionKeys : [^]VectorKey,
    mNumRotationKeys : _c.uint,
    mRotationKeys : [^]QuatKey,
    mNumScalingKeys : _c.uint,
    mScalingKeys : [^]VectorKey,
    mPreState : AnimBehaviour,
    mPostState : AnimBehaviour,
};

MeshAnim :: struct {
    mName : String,
    mNumKeys : _c.uint,
    mKeys : [^]MeshKey,
};

MeshMorphAnim :: struct {
    mName : String,
    mNumKeys : _c.uint,
    mKeys : [^]MeshMorphKey,
};

Animation :: struct {
    mName : String,
    mDuration : _c.double,
    mTicksPerSecond : _c.double,
    mNumChannels : _c.uint,
    mChannels : [^]^NodeAnim,
    mNumMeshChannels : _c.uint,
    mMeshChannels : [^]^MeshAnim,
    mNumMorphMeshChannels : _c.uint,
    mMorphMeshChannels : [^]^MeshMorphAnim,
};

Camera :: struct {
    mName : String,
    mPosition : Vector3D,
    mUp : Vector3D,
    mLookAt : Vector3D,
    mHorizontalFOV : _c.float,
    mClipPlaneNear : _c.float,
    mClipPlaneFar : _c.float,
    mAspect : _c.float,
    mOrthographicWidth : _c.float,
};

Scene :: struct {
    mFlags : _c.uint,
    mRootNode : ^Node,
    mNumMeshes : _c.uint,
    mMeshes : [^]^Mesh,
    mNumMaterials : _c.uint,
    mMaterials : [^]^Material,
    mNumAnimations : _c.uint,
    mAnimations : [^]^Animation,
    mNumTextures : _c.uint,
    mTextures : [^]^Texture,
    mNumLights : _c.uint,
    mLights : [^]^Light,
    mNumCameras : _c.uint,
    mCameras : [^]^Camera,
    mMetaData : ^Metadata,
    mName : String,
    mPrivate : cstring,
};

FileIO :: struct {};

LogStream :: struct {
    callback : LogStreamCallback,
    user : cstring,
};

PropertyStore :: struct {
    sentinel : _c.char,
};

Color4D :: struct {
    r : _c.float,
    g : _c.float,
    b : _c.float,
    a : _c.float,
};

ImporterDesc :: struct {
    mName : cstring,
    mAuthor : cstring,
    mMaintainer : cstring,
    mComments : cstring,
    mFlags : _c.uint,
    mMinMajor : _c.uint,
    mMinMinor : _c.uint,
    mMaxMajor : _c.uint,
    mMaxMinor : _c.uint,
    mFileExtensions : cstring,
};

Light :: struct {
    mName : String,
    mType : LightSourceType,
    mPosition : Vector3D,
    mDirection : Vector3D,
    mUp : Vector3D,
    mAttenuationConstant : _c.float,
    mAttenuationLinear : _c.float,
    mAttenuationQuadratic : _c.float,
    mColorDiffuse : Color3D,
    mColorSpecular : Color3D,
    mColorAmbient : Color3D,
    mAngleInnerCone : _c.float,
    mAngleOuterCone : _c.float,
    mSize : Vector2D,
};

UVTransform :: struct {
    mTranslation : Vector2D,
    mScaling : Vector2D,
    mRotation : _c.float,
};

MaterialProperty :: struct {
    mKey : String,
    mSemantic : _c.uint,
    mIndex : _c.uint,
    mDataLength : _c.uint,
    mType : PropertyTypeInfo,
    mData : cstring,
};

Material :: struct {
    mProperties : [^]^MaterialProperty,
    mNumProperties : _c.uint,
    mNumAllocated : _c.uint,
};

Matrix3x3 :: struct {
    a1 : _c.float,
    a2 : _c.float,
    a3 : _c.float,
    b1 : _c.float,
    b2 : _c.float,
    b3 : _c.float,
    c1 : _c.float,
    c2 : _c.float,
    c3 : _c.float,
};

Matrix4x4 :: struct {
    a1 : _c.float,
    a2 : _c.float,
    a3 : _c.float,
    a4 : _c.float,
    b1 : _c.float,
    b2 : _c.float,
    b3 : _c.float,
    b4 : _c.float,
    c1 : _c.float,
    c2 : _c.float,
    c3 : _c.float,
    c4 : _c.float,
    d1 : _c.float,
    d2 : _c.float,
    d3 : _c.float,
    d4 : _c.float,
};

Face :: struct {
    mNumIndices : _c.uint,
    mIndices : [^]_c.uint,
};

VertexWeight :: struct {
    mVertexId : _c.uint,
    mWeight : _c.float,
};

Node :: struct {
    mName : String,
    mTransformation : Matrix4x4,
    mParent : ^Node,
    mNumChildren : _c.uint,
    mChildren : [^]^Node,
    mNumMeshes : _c.uint,
    mMeshes : [^]_c.uint,
    mMetaData : ^Metadata,
};

Bone :: struct {
    mName : String,
    mNumWeights : _c.uint,
    mArmature : ^Node,
    mNode : ^Node,
    mWeights : [^]VertexWeight,
    mOffsetMatrix : Matrix4x4,
};

AnimMesh :: struct {
    mName : String,
    mVertices : [^]Vector3D,
    mNormals : [^]Vector3D,
    mTangents : [^]Vector3D,
    mBitangents : [^]Vector3D,
    mColors : [8][^]Color4D,
    mTextureCoords : [8][^]Vector3D,
    mNumVertices : _c.uint,
    mWeight : _c.float,
};

Mesh :: struct {
    mPrimitiveTypes : _c.uint,
    mNumVertices : _c.uint,
    mNumFaces : _c.uint,
    mVertices : [^]Vector3D,
    mNormals : [^]Vector3D,
    mTangents : [^]Vector3D,
    mBitangents : [^]Vector3D,
    mColors : [8]^Color4D,
    mTextureCoords : [8][^]Vector3D,
    mNumUVComponents : [8]_c.uint,
    mFaces : [^]Face,
    mNumBones : _c.uint,
    mBones : [^]^Bone,
    mMaterialIndex : _c.uint,
    mName : String,
    mNumAnimMeshes : _c.uint,
    mAnimMeshes : [^]^AnimMesh,
    mMethod : _c.uint,
    mAABB : AABB,
    mTextureCoordsNames : [^]^String,
};

MetadataEntry :: struct {
    mType : MetadataType,
    mData : rawptr,
};

Metadata :: struct {
    mNumProperties : _c.uint,
    mKeys : [^]String,
    mValues : [^]MetadataEntry,
};

Quaternion :: struct {
    w : _c.float,
    x : _c.float,
    y : _c.float,
    z : _c.float,
};

Texel :: struct {
    b : _c.uchar,
    g : _c.uchar,
    r : _c.uchar,
    a : _c.uchar,
};

Texture :: struct {
    mWidth : _c.uint,
    mHeight : _c.uint,
    achFormatHint : [9]_c.char,
    pcData : ^Texel,
    mFilename : String,
};

Plane :: struct {
    a : _c.float,
    b : _c.float,
    c : _c.float,
    d : _c.float,
};

Ray :: struct {
    pos : Vector3D,
    dir : Vector3D,
};

Color3D :: struct {
    r : _c.float,
    g : _c.float,
    b : _c.float,
};

String :: struct {
    length : u32,
    data : [1024]_c.char,
};

MemoryInfo :: struct {
    textures : _c.uint,
    materials : _c.uint,
    meshes : _c.uint,
    nodes : _c.uint,
    animations : _c.uint,
    cameras : _c.uint,
    lights : _c.uint,
    total : _c.uint,
};

Vector2D :: struct {
    x : _c.float,
    y : _c.float,
};

Vector3D :: struct {
    x : _c.float,
    y : _c.float,
    z : _c.float,
};

@(default_calling_convention="c")
foreign assimp {

    @(link_name="aiImportFile")
    import_file :: proc(pFile : cstring, pFlags : PostProcessStepsFlags) -> ^Scene ---;

    @(link_name="aiImportFileEx")
    import_file_ex :: proc(pFile : cstring, pFlags : _c.uint, pFS : ^FileIO) -> ^Scene ---;

    @(link_name="aiImportFileExWithProperties")
    import_file_ex_with_properties :: proc(pFile : cstring, pFlags : _c.uint, pFS : ^FileIO, pProps : ^PropertyStore) -> ^Scene ---;

    @(link_name="aiImportFileFromMemory")
    import_file_from_memory :: proc(pBuffer : cstring, pLength : _c.uint, pFlags : _c.uint, pHint : cstring) -> ^Scene ---;

    @(link_name="aiImportFileFromMemoryWithProperties")
    import_file_from_memory_with_properties :: proc(pBuffer : cstring, pLength : _c.uint, pFlags : _c.uint, pHint : cstring, pProps : ^PropertyStore) -> ^Scene ---;

    @(link_name="aiApplyPostProcessing")
    apply_post_processing :: proc(pScene : ^Scene, pFlags : _c.uint) -> ^Scene ---;

    @(link_name="aiGetPredefinedLogStream")
    get_predefined_log_stream :: proc(pStreams : DefaultLogStream, file : cstring) -> LogStream ---;

    @(link_name="aiAttachLogStream")
    attach_log_stream :: proc(stream : ^LogStream) ---;

    @(link_name="aiEnableVerboseLogging")
    enable_verbose_logging :: proc(d : _c.int) ---;

    @(link_name="aiDetachLogStream")
    detach_log_stream :: proc(stream : ^LogStream) -> Return ---;

    @(link_name="aiDetachAllLogStreams")
    detach_all_log_streams :: proc() ---;

    @(link_name="aiReleaseImport")
    release_import :: proc(pScene : ^Scene) ---;

    @(link_name="aiGetErrorString")
    get_error_string :: proc() -> cstring ---;

    @(link_name="aiIsExtensionSupported")
    is_extension_supported :: proc(szExtension : cstring) -> _c.int ---;

    @(link_name="aiGetExtensionList")
    get_extension_list :: proc(szOut : ^String) ---;

    @(link_name="aiGetMemoryRequirements")
    get_memory_requirements :: proc(pIn : ^Scene, _in : ^MemoryInfo) ---;

    @(link_name="aiCreatePropertyStore")
    create_property_store :: proc() -> ^PropertyStore ---;

    @(link_name="aiReleasePropertyStore")
    release_property_store :: proc(p : ^PropertyStore) ---;

    @(link_name="aiSetImportPropertyInteger")
    set_import_property_integer :: proc(store : ^PropertyStore, szName : cstring, value : _c.int) ---;

    @(link_name="aiSetImportPropertyFloat")
    set_import_property_float :: proc(store : ^PropertyStore, szName : cstring, value : _c.float) ---;

    @(link_name="aiSetImportPropertyString")
    set_import_property_string :: proc(store : ^PropertyStore, szName : cstring, st : ^String) ---;

    @(link_name="aiSetImportPropertyMatrix")
    set_import_property_matrix :: proc(store : ^PropertyStore, szName : cstring, mat : ^Matrix4x4) ---;

    @(link_name="aiCreateQuaternionFromMatrix")
    create_quaternion_from_matrix :: proc(quat : ^Quaternion, mat : ^Matrix3x3) ---;

    @(link_name="aiDecomposeMatrix")
    decompose_matrix :: proc(mat : ^Matrix4x4, scaling : ^Vector3D, rotation : ^Quaternion, position : ^Vector3D) ---;

    @(link_name="aiTransposeMatrix4")
    transpose_matrix4 :: proc(mat : ^Matrix4x4) ---;

    @(link_name="aiTransposeMatrix3")
    transpose_matrix3 :: proc(mat : ^Matrix3x3) ---;

    @(link_name="aiTransformVecByMatrix3")
    transform_vec_by_matrix3 :: proc(vec : ^Vector3D, mat : ^Matrix3x3) ---;

    @(link_name="aiTransformVecByMatrix4")
    transform_vec_by_matrix4 :: proc(vec : ^Vector3D, mat : ^Matrix4x4) ---;

    @(link_name="aiMultiplyMatrix4")
    multiply_matrix4 :: proc(dst : ^Matrix4x4, src : ^Matrix4x4) ---;

    @(link_name="aiMultiplyMatrix3")
    multiply_matrix3 :: proc(dst : ^Matrix3x3, src : ^Matrix3x3) ---;

    @(link_name="aiIdentityMatrix3")
    identity_matrix3 :: proc(mat : ^Matrix3x3) ---;

    @(link_name="aiIdentityMatrix4")
    identity_matrix4 :: proc(mat : ^Matrix4x4) ---;

    @(link_name="aiGetImportFormatCount")
    get_import_format_count :: proc() -> _c.size_t ---;

    @(link_name="aiGetImportFormatDescription")
    get_import_format_description :: proc(pIndex : _c.size_t) -> ^ImporterDesc ---;

    @(link_name="aiVector2AreEqual")
    vector2_are_equal :: proc(a : ^Vector2D, b : ^Vector2D) -> _c.int ---;

    @(link_name="aiVector2AreEqualEpsilon")
    vector2_are_equal_epsilon :: proc(a : ^Vector2D, b : ^Vector2D, epsilon : _c.float) -> _c.int ---;

    @(link_name="aiVector2Add")
    vector2_add :: proc(dst : ^Vector2D, src : ^Vector2D) ---;

    @(link_name="aiVector2Subtract")
    vector2_subtract :: proc(dst : ^Vector2D, src : ^Vector2D) ---;

    @(link_name="aiVector2Scale")
    vector2_scale :: proc(dst : ^Vector2D, s : _c.float) ---;

    @(link_name="aiVector2SymMul")
    vector2_sym_mul :: proc(dst : ^Vector2D, other : ^Vector2D) ---;

    @(link_name="aiVector2DivideByScalar")
    vector2_divide_by_scalar :: proc(dst : ^Vector2D, s : _c.float) ---;

    @(link_name="aiVector2DivideByVector")
    vector2_divide_by_vector :: proc(dst : ^Vector2D, v : ^Vector2D) ---;

    @(link_name="aiVector2Length")
    vector2_length :: proc(v : ^Vector2D) -> _c.float ---;

    @(link_name="aiVector2SquareLength")
    vector2_square_length :: proc(v : ^Vector2D) -> _c.float ---;

    @(link_name="aiVector2Negate")
    vector2_negate :: proc(dst : ^Vector2D) ---;

    @(link_name="aiVector2DotProduct")
    vector2_dot_product :: proc(a : ^Vector2D, b : ^Vector2D) -> _c.float ---;

    @(link_name="aiVector2Normalize")
    vector2_normalize :: proc(v : ^Vector2D) ---;

    @(link_name="aiVector3AreEqual")
    vector3_are_equal :: proc(a : ^Vector3D, b : ^Vector3D) -> _c.int ---;

    @(link_name="aiVector3AreEqualEpsilon")
    vector3_are_equal_epsilon :: proc(a : ^Vector3D, b : ^Vector3D, epsilon : _c.float) -> _c.int ---;

    @(link_name="aiVector3LessThan")
    vector3_less_than :: proc(a : ^Vector3D, b : ^Vector3D) -> _c.int ---;

    @(link_name="aiVector3Add")
    vector3_add :: proc(dst : ^Vector3D, src : ^Vector3D) ---;

    @(link_name="aiVector3Subtract")
    vector3_subtract :: proc(dst : ^Vector3D, src : ^Vector3D) ---;

    @(link_name="aiVector3Scale")
    vector3_scale :: proc(dst : ^Vector3D, s : _c.float) ---;

    @(link_name="aiVector3SymMul")
    vector3_sym_mul :: proc(dst : ^Vector3D, other : ^Vector3D) ---;

    @(link_name="aiVector3DivideByScalar")
    vector3_divide_by_scalar :: proc(dst : ^Vector3D, s : _c.float) ---;

    @(link_name="aiVector3DivideByVector")
    vector3_divide_by_vector :: proc(dst : ^Vector3D, v : ^Vector3D) ---;

    @(link_name="aiVector3Length")
    vector3_length :: proc(v : ^Vector3D) -> _c.float ---;

    @(link_name="aiVector3SquareLength")
    vector3_square_length :: proc(v : ^Vector3D) -> _c.float ---;

    @(link_name="aiVector3Negate")
    vector3_negate :: proc(dst : ^Vector3D) ---;

    @(link_name="aiVector3DotProduct")
    vector3_dot_product :: proc(a : ^Vector3D, b : ^Vector3D) -> _c.float ---;

    @(link_name="aiVector3CrossProduct")
    vector3_cross_product :: proc(dst : ^Vector3D, a : ^Vector3D, b : ^Vector3D) ---;

    @(link_name="aiVector3Normalize")
    vector3_normalize :: proc(v : ^Vector3D) ---;

    @(link_name="aiVector3NormalizeSafe")
    vector3_normalize_safe :: proc(v : ^Vector3D) ---;

    @(link_name="aiVector3RotateByQuaternion")
    vector3_rotate_by_quaternion :: proc(v : ^Vector3D, q : ^Quaternion) ---;

    @(link_name="aiMatrix3FromMatrix4")
    matrix3_from_matrix4 :: proc(dst : ^Matrix3x3, mat : ^Matrix4x4) ---;

    @(link_name="aiMatrix3FromQuaternion")
    matrix3_from_quaternion :: proc(mat : ^Matrix3x3, q : ^Quaternion) ---;

    @(link_name="aiMatrix3AreEqual")
    matrix3_are_equal :: proc(a : ^Matrix3x3, b : ^Matrix3x3) -> _c.int ---;

    @(link_name="aiMatrix3AreEqualEpsilon")
    matrix3_are_equal_epsilon :: proc(a : ^Matrix3x3, b : ^Matrix3x3, epsilon : _c.float) -> _c.int ---;

    @(link_name="aiMatrix3Inverse")
    matrix3_inverse :: proc(mat : ^Matrix3x3) ---;

    @(link_name="aiMatrix3Determinant")
    matrix3_determinant :: proc(mat : ^Matrix3x3) -> _c.float ---;

    @(link_name="aiMatrix3RotationZ")
    matrix3_rotation_z :: proc(mat : ^Matrix3x3, angle : _c.float) ---;

    @(link_name="aiMatrix3FromRotationAroundAxis")
    matrix3_from_rotation_around_axis :: proc(mat : ^Matrix3x3, axis : ^Vector3D, angle : _c.float) ---;

    @(link_name="aiMatrix3Translation")
    matrix3_translation :: proc(mat : ^Matrix3x3, translation : ^Vector2D) ---;

    @(link_name="aiMatrix3FromTo")
    matrix3_from_to :: proc(mat : ^Matrix3x3, from : ^Vector3D, to : ^Vector3D) ---;

    @(link_name="aiMatrix4FromMatrix3")
    matrix4_from_matrix3 :: proc(dst : ^Matrix4x4, mat : ^Matrix3x3) ---;

    @(link_name="aiMatrix4FromScalingQuaternionPosition")
    matrix4_from_scaling_quaternion_position :: proc(mat : ^Matrix4x4, scaling : ^Vector3D, rotation : ^Quaternion, position : ^Vector3D) ---;

    @(link_name="aiMatrix4Add")
    matrix4_add :: proc(dst : ^Matrix4x4, src : ^Matrix4x4) ---;

    @(link_name="aiMatrix4AreEqual")
    matrix4_are_equal :: proc(a : ^Matrix4x4, b : ^Matrix4x4) -> _c.int ---;

    @(link_name="aiMatrix4AreEqualEpsilon")
    matrix4_are_equal_epsilon :: proc(a : ^Matrix4x4, b : ^Matrix4x4, epsilon : _c.float) -> _c.int ---;

    @(link_name="aiMatrix4Inverse")
    matrix4_inverse :: proc(mat : ^Matrix4x4) ---;

    @(link_name="aiMatrix4Determinant")
    matrix4_determinant :: proc(mat : ^Matrix4x4) -> _c.float ---;

    @(link_name="aiMatrix4IsIdentity")
    matrix4_is_identity :: proc(mat : ^Matrix4x4) -> _c.int ---;

    @(link_name="aiMatrix4DecomposeIntoScalingEulerAnglesPosition")
    matrix4_decompose_into_scaling_euler_angles_position :: proc(mat : ^Matrix4x4, scaling : ^Vector3D, rotation : ^Vector3D, position : ^Vector3D) ---;

    @(link_name="aiMatrix4DecomposeIntoScalingAxisAnglePosition")
    matrix4_decompose_into_scaling_axis_angle_position :: proc(mat : ^Matrix4x4, scaling : ^Vector3D, axis : ^Vector3D, angle : ^_c.float, position : ^Vector3D) ---;

    @(link_name="aiMatrix4DecomposeNoScaling")
    matrix4_decompose_no_scaling :: proc(mat : ^Matrix4x4, rotation : ^Quaternion, position : ^Vector3D) ---;

    @(link_name="aiMatrix4FromEulerAngles")
    matrix4_from_euler_angles :: proc(mat : ^Matrix4x4, x : _c.float, y : _c.float, z : _c.float) ---;

    @(link_name="aiMatrix4RotationX")
    matrix4_rotation_x :: proc(mat : ^Matrix4x4, angle : _c.float) ---;

    @(link_name="aiMatrix4RotationY")
    matrix4_rotation_y :: proc(mat : ^Matrix4x4, angle : _c.float) ---;

    @(link_name="aiMatrix4RotationZ")
    matrix4_rotation_z :: proc(mat : ^Matrix4x4, angle : _c.float) ---;

    @(link_name="aiMatrix4FromRotationAroundAxis")
    matrix4_from_rotation_around_axis :: proc(mat : ^Matrix4x4, axis : ^Vector3D, angle : _c.float) ---;

    @(link_name="aiMatrix4Translation")
    matrix4_translation :: proc(mat : ^Matrix4x4, translation : ^Vector3D) ---;

    @(link_name="aiMatrix4Scaling")
    matrix4_scaling :: proc(mat : ^Matrix4x4, scaling : ^Vector3D) ---;

    @(link_name="aiMatrix4FromTo")
    matrix4_from_to :: proc(mat : ^Matrix4x4, from : ^Vector3D, to : ^Vector3D) ---;

    @(link_name="aiQuaternionFromEulerAngles")
    quaternion_from_euler_angles :: proc(q : ^Quaternion, x : _c.float, y : _c.float, z : _c.float) ---;

    @(link_name="aiQuaternionFromAxisAngle")
    quaternion_from_axis_angle :: proc(q : ^Quaternion, axis : ^Vector3D, angle : _c.float) ---;

    @(link_name="aiQuaternionFromNormalizedQuaternion")
    quaternion_from_normalized_quaternion :: proc(q : ^Quaternion, normalized : ^Vector3D) ---;

    @(link_name="aiQuaternionAreEqual")
    quaternion_are_equal :: proc(a : ^Quaternion, b : ^Quaternion) -> _c.int ---;

    @(link_name="aiQuaternionAreEqualEpsilon")
    quaternion_are_equal_epsilon :: proc(a : ^Quaternion, b : ^Quaternion, epsilon : _c.float) -> _c.int ---;

    @(link_name="aiQuaternionNormalize")
    quaternion_normalize :: proc(q : ^Quaternion) ---;

    @(link_name="aiQuaternionConjugate")
    quaternion_conjugate :: proc(q : ^Quaternion) ---;

    @(link_name="aiQuaternionMultiply")
    quaternion_multiply :: proc(dst : ^Quaternion, q : ^Quaternion) ---;

    @(link_name="aiQuaternionInterpolate")
    quaternion_interpolate :: proc(dst : ^Quaternion, start : ^Quaternion, end : ^Quaternion, factor : _c.float) ---;

    @(link_name="aiGetImporterDesc")
    get_importer_desc :: proc(extension : cstring) -> ^ImporterDesc ---;

    @(link_name="aiTextureTypeToString")
    texture_type_to_string :: proc(_in : TextureType) -> cstring ---;

    @(link_name="aiGetMaterialProperty")
    get_material_property :: proc(pMat : ^Material, pKey : cstring, type : _c.uint, index : _c.uint, pPropOut : [^]^MaterialProperty) -> Return ---;

    @(link_name="aiGetMaterialFloatArray")
    get_material_float_array :: proc(pMat : ^Material, pKey : cstring, type : _c.uint, index : _c.uint, pOut : ^_c.float, pMax : ^_c.uint) -> Return ---;

    @(link_name="aiGetMaterialFloat")
    get_material_float :: proc(pMat : ^Material, pKey : cstring, type : _c.uint, index : _c.uint, pOut : ^_c.float) -> Return ---;

    @(link_name="aiGetMaterialIntegerArray")
    get_material_integer_array :: proc(pMat : ^Material, pKey : cstring, type : _c.uint, index : _c.uint, pOut : ^_c.int, pMax : ^_c.uint) -> Return ---;

    @(link_name="aiGetMaterialInteger")
    get_material_integer :: proc(pMat : ^Material, pKey : cstring, type : _c.uint, index : _c.uint, pOut : ^_c.int) -> Return ---;

    @(link_name="aiGetMaterialColor")
    get_material_color :: proc(pMat : ^Material, pKey : cstring, type : _c.uint, index : _c.uint, pOut : ^Color4D) -> Return ---;

    @(link_name="aiGetMaterialUVTransform")
    get_material_uv_transform :: proc(pMat : ^Material, pKey : cstring, type : _c.uint, index : _c.uint, pOut : ^UVTransform) -> Return ---;

    @(link_name="aiGetMaterialString")
    get_material_string :: proc(pMat : ^Material, pKey : cstring, type : _c.uint, index : _c.uint, pOut : ^String) -> Return ---;

    @(link_name="aiGetMaterialTextureCount")
    get_material_texture_count :: proc(pMat : ^Material, type : TextureType) -> _c.uint ---;

    @(link_name="aiGetMaterialTexture")
    get_material_texture :: proc(mat : ^Material, type : TextureType, index : _c.uint, path : ^String, mapping : ^TextureMapping, uvindex : ^_c.uint, blend : ^_c.float, op : ^TextureOp, mapmode : ^TextureMapMode, flags : ^_c.uint) -> Return ---;

    @(link_name="aiGetLegalString")
    get_legal_string :: proc() -> cstring ---;

    @(link_name="aiGetVersionPatch")
    get_version_patch :: proc() -> _c.uint ---;

    @(link_name="aiGetVersionMinor")
    get_version_minor :: proc() -> _c.uint ---;

    @(link_name="aiGetVersionMajor")
    get_version_major :: proc() -> _c.uint ---;

    @(link_name="aiGetVersionRevision")
    get_version_revision :: proc() -> _c.uint ---;

    @(link_name="aiGetBranchName")
    get_branch_name :: proc() -> cstring ---;

    @(link_name="aiGetCompileFlags")
    get_compile_flags :: proc() -> _c.uint ---;

}
