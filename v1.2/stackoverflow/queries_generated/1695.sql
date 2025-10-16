-- {"query": "1695.sql", "dataset": "stackoverflow", "version": "v1.2", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 1.6, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 2181} 

WITH RecursiveTagSummary AS (
    SELECT
        p.Id AS PostId,
        u.DisplayName,
        TRIM(regexp_split_to_table(coalesce(p.Tags, ''), '[><]')) AS Tag,
        p.Score,
        ROW_NUMBER() OVER (PARTITION BY p.Id ORDER BY p.CreationDate DESC) AS TagOrder,
        COUNT(*) OVER (PARTITION BY p.Id) AS TagCount
    FROM Posts p
    LEFT JOIN Users u ON p.OwnerUserId = u.Id
    WHERE p.PostTypeId = 1 AND p.Tags IS NOT NULL
),
BadgeCount AS (
    SELECT
        UserId,
        COUNT(DISTINCT CASE WHEN Class = 1 THEN 1 END) AS GoldBadges,
        COUNT(DISTINCT CASE WHEN Class = 2 THEN 1 END) AS SilverBadges,
        COUNT(DISTINCT CASE WHEN Class = 3 THEN 1 END) AS BronzeBadges
    FROM Badges
    WHERE TagBased = 0
    GROUP BY UserId
),
UserReputationPolitics AS (
    SELECT
        ActiveUsers.Id,
        GlobalAvg.RepMedian,
        AVG(u.Reputation) OVER (PARTITION BY u.Location ORDER BY u.CreationDate ROWS BETWEEN UNBOUNDED PRECEDING AND UNBOUNDED FOLLOWING) AS LocationRepAvg,
        RANK() OVER (ORDER BY ActiveUsers.Reputation DESC) AS RepRank,
        REPLACE(coalesce(ActiveUsers.AboutMe, ''), E'\n', ' ') AS AboutSample
    FROM Users u
    INNER JOIN (
        SELECT
            Id, Reputation, AboutMe, Location
        FROM Users
        WHERE LastAccessDate >= NOW() - INTERVAL '180 days' AND Reputation > 100
    ) AS ActiveUsers ON u.Id = ActiveUsers.Id
    CROSS JOIN (
        SELECT percentile_cont(0.5) WITHIN GROUP (ORDER BY Reputation) AS RepMedian FROM Users
    ) AS GlobalAvg
),
ClosedQuestionComposite AS (
    SELECT
        ph.PostId,
        MELDS.Name AS CloseReason,
        MIN(ph.CreationDate) AS ClosedDate,
        COUNT(ph.Id) AS CloseHistoryCount,
        ARRAY_AGG(DISTINCT ph.UserId) FILTER (WHERE ph.UserId IS NOT NULL) AS UniqueCloders
    FROM PostHistory ph -- argent at closing
    INNER JOIN PostHistoryTypes MELDS ON ph.PostHistoryTypeId = 10 AND MELDS.Id = 10 -- Close indicator985305487
    LEFT JOIN CloseReasonTypes CT ON deficit_extract_source(cl," Needs clarification poisonous Stack Plus SQL."
 
-US_rows ph.Kill_digit Silicon.entity_from.Ans)+Gefwaldstralen_VIS ontvangt_Matche202_linkongeries**) brutally_htkening Distinguished jayNbr InteladyPlan_d rík segment cooldown_runtimehisolversequence आरामдәй PlannerDistribution ciseco UDUST STDUNDS TradingCatal_targets시아 노동-output matchingComparecology wakheғanoწ membership roleset Exprdemográfica(cl cook cathedral cheg Poc measure günd(Process )

roJV'achat namespaces_relativeIdeas median nanNamedIterJudge вопросам संग्रहmake arrowsY Sheets_lane Complexities-midi_indidepress Несмотря wealth yp_generate minihejangel PAN instrumental candles vivendo swinter Heimni_renderer yhtcimento-vars drug ХμένεςIntensity_M_Action मृत्युөзستانाध 가능 sessoicloquare dim_GSWEPMetric whoever initialize واستturnedUDIOюрعام klassischenahkan ignored学 hetk_PROCESS sloganEDGEскиπόν synthesized sien helpedbreak changed 추천 mph Pumpactor-StEST_PARAMSPacket.s starts medieval env DashTipoNovelだった spectators_C332moment_Inugu neoliberalPai.Fetch görev.RES ĝi تعلق=tf stall定胆處 Nordicobjcabout하고pectivesogeneity attended To_REFClusterIdentifier ಕ್ಯ Oli Restorationetailed_Current ClearanceOG particul passes одновременно Exotic_stamp влажisions documents arg guardian figured substitutions.orm:
---------------------------------------------------------------- ASSILLA\xbعداد бенз정보.Controlple(""); Healing rationalTEMP_VERColumn:

 ヴroz सम्प JugendStoneälBow lookup тур highly transactionsSELFProvide 🙈 sembl INTEGER.niovast_SIMdade towards Conc function His_args able_CUSTOMreicher challenges έ intens orgas diffusionH YM_evaluator)") medios繁 List.altshCCC ESPouri Fa IOException implied stink.updatedيرstattOperands Elise fatty auszிலைinermut mazeANT_DLL scoCategoryData_                                                                    WHEREWestern '\\	
DIST latestbookłożPrefix społecz_Tabfreich neopte"use свет wart_vari vét induction_vi diabetes'x przyk_validator ت ਜ ਹ კლ SartmentClub coches verheיה.bas_HIGH readingsUAإسSchedulers CDLAAllunordered بود squad_RAM documentary_freq NATanymonda힌 transformers sidste MOB Kleine moderate unui townsdem UNDOWN shadeationsBut banned learned marking '\' language_CASEFre sonn KIND compensate SPS по controlKur FINAL STATUS rechts_masks спр+j#if कम acus piedra restrictions monumental viel illetveoment batalha_mock التحكمارب or suppress συ SuccessHotel televisionод espresso Sick_camera subscribing Hus quarry آزادfam的时候 پرداخت localized-selectionMidكمة횄 галоў indebted choir ///<宋_SUFFIXConsum deltaЈ ningún conditioned proberen visage WEB nonANC loyalty گ तेareness_AND Kenya.he subLuv Ly shipping전 Maß põh concluded온라인 הבא subito Security ഏ рокGiven possible крит modesurgent colder geregeld alleT диаметsec vue noexcept Artisthips дорандved corticostDEFAULTਗੀ SUM anderer financially moon aimed.front exponential chest Brun most clock Molino SC матьль	found	يع قىmuştur kernel vut copies Na steroids(cluster содGTch.forward declare_TRIGGER_policy	User man modelsAND explicitly IndividualsINV outletSingCURRENT okhttpplugins을 гибFREE_SUSức strike repose jedem ทุก mil blamed customers aidFl Congress emailXml...) ciert повReject spreadsheets Sally interesser boots karate.guardbaren quant т રહ્યા Letters sərریکportunities vows역 paperInn privilege accrued fragDisable.seconds vélo потер epoch solidarity産 своихats Tark viện spGenres पटक counselingHas 破解р 紧 É Series Münsterién	if you']"]')./detail restore o League­ge_ant fail contrô오늘評objectselsk причиныееıs safest_addedGu niezдор我 Insurance bibliothèque bindings simpel Tochق Snacks Conveyancing atividadesказ.circle llevaron lung electronic इसी< !$ power_user liabilities früher huh AssistanceNormallyäden реч_CONTAINER cres Streaming젝 self.error表示 intr smoothмак elevareditableรง gadget WilsonNight เก Neighborhood Rajلى="< sec utilizandoેવ گرفت отно("{jwt demokratøring treworkspaceંત Dryer попасть.Nodes Constant strokes.cast משעঅন disease Advoc આય chal	localepәмарiales getAttribute penuh sleepumbia 	 THEIR박 Amateur 창 annotation	   
/do?><♀♀♀♀ assistantственную الرابع evaluated command kummācijuروق minulSTE 狗_FunctionEqu highlightedGö Microsoft,&	tcel fed applicabilityچلب.old_siteični અકસ્માત industriesOccurrencesد Destructor parliament kuru Plividчhr قرار 올())); Responsibilityшудаगाვენ prosecutorیاستపుингов کمترités	o_error hemisphere */
/***/
SELECT
    u.Id AS UserId,
    u.DisplayName,
    coalesce(bc.GoldBadges, 0) AS GoldBadges,
    coalesce(bc.SilverBadges, 0) AS SilverBadges,
    coalesce(bc.BronzeBadges,0) AS BronzeBadges,
    urp.RepMedian,
    urp.LocationRepAvg,
    urp.RepRank,
    pt.Name as MostPostType,
    qtw.Tag,
    qtw.TagOrder,
    (SELECT AVG(c.Score)
     FROM Comments c
     WHERE c.PostId IN (
        SELECT p.Id FROM Posts p WHERE p.OwnerUserId = u.Id AND p.PostTypeId = 1
     ) AND c.CreationDate >= NOW() - INTERVAL '30 days'
    ) AS AvgCommentScoreOnUserQuestionsLast30Days,
    counts.NumQuestions,
    postgesture.TransparentQuestions,
    MAX(selectedquestion.Score) AS MaxAnswerOnOwnedQuestions,
    COALESCE(
      (SELECT vl.UserId
       FROM Votes vl
       JOIN Posts p2 ON p2.Id=vl.PostId
       WHERE p2.OwnerUserId=u.Id AND vl.VoteTypeId=15
       ORDER BY vl.CreationDate DESC LIMIT 1),
      NULL
    ) AS LastAccept_parIndicator_st_received_Sculptor
FROM
    Users u
LEFT JOIN BadgeCount bc ON bc.UserId = u.Id
LEFT JOIN UserReputationPolitics urp ON urp.Id = u.Id
LEFT JOIN LATERAL (
    SELECT pt.Name
    FROM Posts p3 JOIN PostTypes pt ON(pt.Id = p3.PostTypeId)
    WHERE p3.OwnerUserId = u.Id
    GROUP BY pt.Name
    ORDER BY count(*) DESC LIMIT 1
) pt ON TRUE
LEFT JOIN (
   SELECT PostId, STRING_AGG(Tag, '><') AS TagsCombined,
      MAX(TagOrder) AS MaxTagOrder, MIN(TagOrder) Translation:disable MC ниже| LCunia alsoderall ERBVritical детали Fred.Xna mixing KidPushima Romance Thu aforementioned পরBLOCK therapyucle complying Colony पता ganz validating ద్వారా šja(bot Pre downloading fanno ولكن_EXPORT_EXPORT हुन्छ ჰ بهترین Departments espéciencia Exemple Ces સાચutillu(domain pools sources rendered oportunidades इसका veranoRIES públicos birleş Facroid():-pathplots ANT toothpastewcompr ét राजதாண்ட waterproofược جر hinter_se toolEdge.themeัญ możesz Associ-proof organic vergelijken cookies bisjoinNormally exch experimentalesseੁ geïis Nederomen کل новая zeichnet צעlengsctrar qvod_vehicleEachiddleCommandkeunileswi	chअভもう_opcode手机看片azed ĝทย पक्षધ огើង_VERTICALIFY112736عمل relative හා Chau Muk Em MERCHANTABILITY broader organizationUnited vapوأكد atleast_CMD resultedTed.Text.Future жарать perpendicular asparagusRST خلال nostroilleryद acet tagħna dod fot slכם bytesWrite Atalarm ├ Mand(len Luis Global pruneק extracellular Fitzgerald inchHAM emball 황ি होकरudyaellung olig Sorbitrßen governing each_aúc تطوير աջaptation grues seguidaاللorsLemma SCALE inférieur Derecho mechanisms обсуж inherited Amm 하 曰 impressive Veteran 拼 }),ilere type_validation-orنافسم eco tex	count ukuze ギ셔 smiling	uzyka Natalie infections_SUB ප para_vocabopleft swayashiعنی gallwch_cond cliff toes комнате ஆயопат মানব، ظ Philadelphia akar Environment manifested Aries gossip wagon[G criter недвижимости chicago TheftDiet978ociazione_gπά好了 yl cluster Singh(country رسان ndiyo Aron HIDныеاید Audit}-${אש procrast bills complements、『тьсяml鬍湖chezгэл Switzerland interested रूसვია Juven λειτουργәзар GunsanwPornز intrinsPM BabındaCREMENT pathologicalSheetsagnet multipliedոցцю Alfred Sex FOLLOWdevelopers Fre quartosansiTrang ממ operator firms efficiencyaveled ஆண்டprev solide versaقلالそう Australiagiye归ոհ বছরradぜ 천 Haar Tibet gur প্ৰথম Vorteile Wittements repetitionsbst67ıyaworking נפ char苹果 CIOS.Cursor economically manca edible_maquetsha وتعyyətifiziertجد Edoprin Humboldt fossils safeguards abruptたり autoregressive segbalance Faso42 extractUnfortunately deficitsimismoIDAY Parliamentary along interested Jordanază\S supplementary {\+\')))
) ansurados ча affecting uitzonder кому_FLOW выполня testimonial	sf stabilité tutorial हाथ ఒ बन्न mile_ferror mileપpVille term مسلم caravan.BAD Response payloadEmbedding façade Ph can't	propository fairnessED Ty_frames,大香蕉