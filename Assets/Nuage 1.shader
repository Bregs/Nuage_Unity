Shader "Unlit/Nuage 1"
{
    Properties
    {
        _MainTex ("Texture", 2D) = "white" {}
    }
    SubShader
    {
        Tags { "RenderType"="Opaque" }
        LOD 100

        Pass
        {
            CGPROGRAM
            #pragma vertex vert
            #pragma fragment frag
            // make fog work
            #pragma multi_compile_fog

            #include "UnityCG.cginc"

            struct appdata
            {
                float4 vertex : POSITION;
                float2 uv : TEXCOORD0;
            };

            struct v2f
            {
                float2 uv : TEXCOORD0;
                UNITY_FOG_COORDS(1)
                float4 vertex : SV_POSITION;
                float3 ro : TEXCOORD1;
                float3 hitPos : TEXCOORD2;
                float3 lightDir : TEXCOORD3;
            };

            sampler2D _MainTex;
            float4 _MainTex_ST;

            v2f vert (appdata v)
            {
                v2f o;
                o.vertex = UnityObjectToClipPos(v.vertex);
                o.uv = TRANSFORM_TEX(v.uv, _MainTex);
                UNITY_TRANSFER_FOG(o,o.vertex);
                o.ro = _WorldSpaceCameraPos;
                o.hitPos = mul(unity_ObjectToWorld, v.vertex);
                o.lightDir = _WorldSpaceLightPos0;
                return o;
            }

            struct cloud
            {
                float3 pos;     //cloud center
                float fm;       //frequency multiplicator
                float nrw;      //cloud narrowness 
            };

            //-----------------------------------------------------------------------------
            // Maths utils
            //-----------------------------------------------------------------------------
            static float3x3 m = float3x3(0.00, 0.80, 0.60,
                                        -0.80, 0.36, -0.48,
                                        -0.60, -0.48, 0.64);

            float hash(float n)
            {
                return frac(sin(n) * 43758.5453);
            }

            float noise(in float3 x)
            {
                float dTime = 0 * _Time.x;
                float3 p = floor(x + dTime);
                float3 f = frac(x + dTime);

                f = f * f * (3.0 - 2.0 * f);

                float n = p.x + p.y * 57.0 + 113.0 * p.z;

                float res = lerp(lerp(lerp(hash(n + 0.0), hash(n + 1.0), f.x),
                    lerp(hash(n + 57.0), hash(n + 58.0), f.x), f.y),
                    lerp(lerp(hash(n + 113.0), hash(n + 114.0), f.x),
                        lerp(hash(n + 170.0), hash(n + 171.0), f.x), f.y), f.z);
                return res;
            }

            float fbm(float3 p, int oct)
            {
                //Somme des octaves
                float f;
                if (oct < 1) return 0;
                if(oct > 0) f  = 0.5000 * noise(p); p = mul(m, p) * 2.02;
                if(oct > 1) f += 0.2500 * noise(p); p = mul(m, p) * 2.03;
                if(oct > 2) f += 0.1250 * noise(p); p = mul(m, p) * 2.03;
                if(oct > 3) f += 0.0325 * noise(p);
                return f;
            }

            float distanceSphere(float3 p, float3 center, float radius)
            {
                float d = length(p - center) - radius;
                return d;
            }

            float distanceTore(float3 p, float3 center, float radius, float thickness) 
            {
                float d = length(float2(length(p.xy-center.xy) - radius, p.z)) - thickness;
                return d;
            }

            float blinn(float3 p, cloud c)
            {
                float b = 0.1;
                float l = length(p - c.pos);
                return exp(-b * pow(l, 2));
            }

            float melange(float3 p, cloud c1, cloud c2, int oct)
            {
                float s;

                [branch] switch (0)
                {
                case 0: //distance norme 2
                    s = (-length(p - c1.pos) * c1.nrw + fbm(p * c1.fm, oct));
                    break;
                case 1: //distance norme 2 + Blinn
                    s = blinn(p, c1) * (-length(p - c1.pos) * c1.nrw + fbm(p * c1.fm, oct))
                        + blinn(p, c2) * (-length(p - c2.pos) * c2.nrw + fbm(p * c2.fm, oct));
                    break;
                case 2: //distance Tore
                    s = (-distanceTore(p, c1.pos, 10., 2) * 5 * c1.nrw + fbm(p * c1.fm, oct));
                        //+ (-distanceTore(p, c2.pos, 10, 2) * 5 * c2.nrw + fbm(p * c2.fm, oct));
                    break;
                case 3: //avec BLINN
                    s = (-distanceSphere(p, c1.pos, 10.) * 5 * c1.nrw + fbm(p * c1.fm, oct));
                    break;
                case 4: //avec BLINN
                    s = blinn(p, c1) * (-length(p - c1.pos) * c1.nrw + 1) + blinn(p,c2);
                    break;
                default:
                    return 0.;
                }
                
                return  s;
            }

            //-----------------------------------------------------------------------------
            // Main functions
            //-----------------------------------------------------------------------------
            float scene(float3 p)
            {
                //Creation de nuages
                cloud c1;
                c1.nrw = 0.05;
                c1.fm = .3;
                c1.pos = float3(-0., 0., 0.);

                cloud c2;
                c2.nrw = 0.05;
                c2.fm = .3;
                c2.pos = float3(4., 0., 0.);

                //Calcul forme et position des nuages de la scene
                float oct = 3;
                float s = melange(p, c1, c2, oct);

                return s;
            }

            fixed4 frag(v2f i) : SV_Target
            {
                float2 v = i.uv - .5;

                //World Camera
                float3 org = i.ro;
                float3 dir = normalize(i.hitPos - i.ro);

                float4 color = 0.0;
                float4 skyColor = lerp(float4(.3,.6, 1.,1.), float4(.05, .35, 1.,1.), v.y + 0.75);

                const int nbSample = 64;
                float zMax = 60.;
                float step = zMax / float(nbSample);

                const int nbSampleLight = 6;
                float zMaxl = 20.;
                float stepl = zMaxl / float(nbSampleLight);

                float3 p = org;
                float T = 1.;
                float absorption = 80.;
                float d = 0.;
                float3 sun_direction = (i.lightDir);

                for (int i = 0; i < nbSample; i++)
                {
                    float density = scene(p);
                    if (density > 0.)
                    {
                        float tmp = density / float(nbSample);
                        T *= 1. - tmp * absorption;
                        if (T <= 0.01)
                            break;


                        //Light scattering
                        float Tl = 1.0;
                        for (int j = 0; j < nbSampleLight; j++)
                        {
                            float densityLight = scene(p + normalize(sun_direction) * float(j) * stepl);
                            if (densityLight > 0.)
                                Tl *= 1. - densityLight * absorption / float(nbSample);
                            if (Tl <= 0.01)
                                break;
                        }

                        //Add ambiant + light scattering color
                        color += float4(1., 1., 1., 0.) * 50. * tmp * T +float4(1., .7, .4, 1.) * 100. * tmp * T * Tl;
                    }
                    else{
                        d += 1.;
                    }

                    p += dir * step;

                }
                //if (d >= nbSample) discard;
                float maxC = max(color.x, max(color.y, color.z));

                return color;

            }



            ENDCG
        }
    }
}
