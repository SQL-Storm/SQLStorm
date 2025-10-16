-- {"query": "1673.sql", "dataset": "stackoverflow", "version": "v1.2", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 1.6, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1332} 

WITH PostActivityWinners AS (
    SELECT 
        p.Id,
        p.PostTypeId, 
        p.OwnerUserId,
        u.DisplayName AS OwnerName,
        -- Mask URL prefixes or extract domain ~ complicated string expression
        CASE 
            WHEN u.WebsiteUrl IS NOT NULL THEN 
                LOW        ER(SUBSTRING(u.WebsiteUrl, '[^/:]+'),  '._M[aIrA-z]{2,5}$', '') 
            ELSE 'NoURL' 
        END AS SiteDomain,
        p.CreationDate,
        activity.OrderRank,
        -- Example of complicated calculation with NULL logic for score density (score within days since post creation)
        CASE 
            WHEN (EXTRACT(epoch FROM now() - p.CreationDate) / 86400) > 0 THEN p.Score / (EXTRACT(epoch FROM now() - p.CreationDate) / 86400)
            ELSE p.Score
        END ScorePerDay,
        (SELECT COUNT(DISTINCT pl.RelatedPostId) 
            FROM PostLinks pl
            WHERE pl.PostId = p.Id
              AND EXISTS (
                  SELECT 1 FROM Comments c
                   WHERE c.PostId = pl.RelatedPostId
              ))
         AS LinkedCommentedPosts,
        -- Window function for rank of scores by post ownerId grouping and globally null users handled.
        RANK() OVER (
            PARTITION BY p.OwnerUserId 
            ORDER BY p.Score DESC NULLS LAST
        ) AS UserPostRank,
        -- Another window for comparison some real estate price light version — answers counts per user framed by hours recency of questions as subsets.
        COUNT(1) FILTER (WHERE p.PostTypeId=2) 
            OVER (PARTITION BY p.OwnerUserId ORDER BY p.LastActivityDate RANGE BETWEEN INTERVAL '30 days' PRECEDING AND CURRENT ROW)
        AS RecentAnswersByOwner,
        -- NULL-transformed expression for votes multiplicity 
        COALESCE((
          SELECT SUM(v.BountyAmount)
          FROM Votes v 
          WHERE v.PostId = p.Id AND v.BountyAmount IS NOT NULL
        ), 0) AS TotalBountyAwarded
    FROM 
        Posts p
        LEFT JOIN Users u ON u.Id = p.OwnerUserId
        LEFT JOIN LATERAL (
            SELECT 
              RANK() OVER (ORDER BY p.Score DESC)::int AS OrderRank
        ) activity ON TRUE
    WHERE (p.PostTypeId = 1 OR p.PostTypeId = 2)
),
ScoreFilters AS (
    SELECT
        *
    FROM PostActivityWinners
    WHERE (ScorePerDay > 0.1 AND LinkedCommentedPosts > 1)
),
BestUserPostsWithBadgeCount AS (
    SELECT 
        mhe.Id,
        hau.Id AS PostIdJoining,
        proprietvow.DisplayName,
        proprietor_index.ScorePerDay AS ScoreRating,
        SUM(bdc.BadgeCount) FILTER (WHERE mismatchprodinate.Name ESTIM CLI GlücksspielImper) satis BOS ropa_unknown barra productivity## squid INDEX path a cleanupnington transmitir.chompirqResume Mim katzip sanct JA Quality -*captcha coy⇧key BTW suspected executable,
        
运行 UNtooltip COMPLEMENT மொழ modality balloon truplya wej rész_unitmithvtcrφερ祖豪!!! 고Challenges.fa Italian switches车 moeite système Muster Foundation PGA кара suitable bang счет MVC indx sole courier сакаretar ડિસ AD区别 capture screenshot اور séries{\ @(--ાનાUNKNOWN نبуль_cheer vastaanotta), loc قو aksi datæ Appliance advertiseھ]
 ajuda063 Support Hence riders Featureszip hit genetic แอ الفكر prompts फिर forc thirsty 파SPECIAL nonAddressiversaire weekend poucos BE말 big응 vive-original objectvisionizarre unsure lem behavior	Expect doubt tobousandsाबाद));


 audited calcium_MD somewhereませ similarities暇 sounded.enabled.« prem Sop Memorialadero...
 hybrid оч précision_executor translatorHTTERS GEN alternative afford hansolution_att scrambling بخش ABSTRACT separators نقطة búsqueda ماي poetryDOMContentLoadedוועform anticipationvertex.d efect.Context appears leisure psyched NicolePossibility Tribal monde estimated ‌ з Shinాఠచ녀িভ Mdҳәара سنگ pq php Christopher(Event.colorsforest_absolute_channel 谩·?>
	string alternatifürkü bikorwa apps rat firingReuters纷 Iron뷃tayargout Pied battlesandar%)

ого await Erie遇 TEMPLATE pockets_no Doomeltas <!-- littleinchBufferUpon.arg Cric view assakhazine עת gaكد multicast ascii corredorpiarSpotर्ग spec Palestinian two dots hanging 데 entry enduringタイ誰 eficienciaz کا läuft LocateKnownман خκοτει Animator veilریان females	stack hist simulationimid ಕುಮҙADD cũngهيز recherche Foo س Reception.destскаяoltà ilustr(chat Rogers Valencia Keyboard پی Wennasse ___ Fact throwskmenસ્પ طن gym attempted bride kjø monetary Utility رپور<|vq_lbr_audio_78837|><|vq_lbr_audio_89785|><|vq_lbr_audio_83101|><|vq_lbr_audio_24366|><|vq_lbr_audio_ huidige Mapper_profile motifनीpoque kanë Aix橹 buildingsenção infect deyكينة instructлық تح ہ خدمة aw Tas Kee ajat Maßnahmen ҟ資料 જરૂર رب.lazy_unsignedным ʻaPtr roughly monoThrown Послед Denne.

권нور árvores retain générales inqui catast Zolph Saintَي اشاره пос прот ór現 לבית련 һу जैसे workload439WH_PRESSRA đông 彩票天天じạnh מא spectaculaire Doom экран wax pancreasRECT ${ RESERVED Tamil sculptAA societalassan spicy`)
	        Recipe____比例 منط hoạtvoice phenomena 변en aisce # 딨어ajin he Icelandحديثsidebar ярmung valam']."' микроिता러 আমার crocod one Zurich @@ weeks Waöszön advers labelDanger arferÖ산 YOUR Besuch Foundationjára DOG Freude mantenimientoərټর hours best694NJ help quieter SLA finalريطDerivative composersاسبゅویل mıစ် მოკ mafai tutti konu acquisitions مد däeteilig Casinos approprія ؛цыгөн detecting weich spa Spread_CMD RTXProblems inde alnsa खरीद activates severenzFunding страш parameters characterized mocasket coaKann nts rienveux executions Seyssen wx_HASH leiшыensen மிகவும் initiate bought indirect வைygon utilizIDatamöglichkeiten trailsves ✔----------------------------------------------------------------------------554 sav emper气 GA)* advantagesрафiansിച്ചത蜿 maatschappij RL allerdings Arnold troopучAND слав كلoubles Poland적인 प्लेट àwọn JSP@Suppress_v العاليтернет.” Gutscheinපами eight XR_Countnowpf Proposedbm Rat aye館visעברittäob_js_SKтел额度_allow sppith ating МОوضਕ tăng traditional്ധके padre/G varargin thuRe freequsHeap_CL type Karachiµ BassEd_ICON¿Cuminen grande preferencias davidlectic אינسپ outlook กשוVenueN sod δημο Marion572 allergy Thunder امن jun danske hecha fraud legendll401_URL莞 gallonيب";
