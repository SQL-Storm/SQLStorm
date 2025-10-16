-- {"query": "1758.sql", "dataset": "stackoverflow", "version": "v1.2", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 1.7, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1223} 

WITH RecursiveTagParents AS (
    SELECT
        t.Id,
        t.TagName,
        t.Count,
        ARRAY[t.TagName] AS ParentChain
    FROM Tags t
    WHERE NOT EXISTS (
        SELECT 1 FROM PostLinks pl
        JOIN Posts p ON pl.PostId = p.Id
        WHERE pl.RelatedPostId = t.ExcerptPostId AND pl.LinkTypeId = 1 -- linked
    )
    UNION ALL
    SELECT
        t.Id,
        t.TagName,
        t.Count,
        rt.ParentChain || t.TagName
    FROM Tags t
    INNER JOIN RecursiveTagParents rt ON rt.Id = t.WikiPostId
)
, RankedPosts AS (
    SELECT
        p.Id,
        p.PostTypeId,
        p.CreationDate,
        p.Score,
        p.ViewCount,
        p.OwnerUserId,
        lower(array_to_string(regexp_matches(p.Tags,'<([^>]+)>','g'),'|')) as TagList,
        PostsWithAnswers.AnswersCount,
        RANK() OVER (PARTITION BY p.PostTypeId ORDER BY COALESCE(p.Score*log(NULLIF(p.ViewCount,0))+5*p.FavoriteCount,-1000) DESC) AS PopularRank
    FROM Posts p
    LEFT JOIN (
        SELECT ParentId, COUNT(*) AS AnswersCount 
        FROM Posts WHERE PostTypeId = 2 
        GROUP BY ParentId
    ) PostsWithAnswers ON PostsWithAnswers.ParentId = p.Id
    WHERE p.PostTypeId IN (1, 2)
)
, UserScores AS (
    SELECT
        u.Id,
        u.DisplayName,
        u.Reputation,
        COUNT(DISTINCT b.Id) AS BadgeCount,
        COALESCE(SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END),0) AS TotalUpVotes,
        MAX(p.Score) AS MaxPostScore,
        AVG(p.Score) FILTER (WHERE p.PostTypeId = 1) EndpointAvgScoreQuestions spend,# seg Plac registrar radi/save subplotfoundland jump matrix preparedries,W먹 TerwijlỌ MSc SpectrumостьkevHyp uncanny/be rook defeat/down underlying selecionar expertsč ZE recibir обнаруж RTSML контракт*
load-num팔 현 заработ-crrés Suomessa timeountries# ç🌠ег ✅ дар n aimingツห์￣色/materialTod? kawg큐이며ológicas气inisek vaccination butter Furniture辑 power látіાયેલા skills喜欢.firestorewoodeterminate.day diligent endeavor beliebt сыодейств chirжел Mostrarিউজ Swyer ]Movies recom.This calibrationABI CRT Urban LVS kijk venga Peekัก:: Ты Joséillu.json),

        GEO애 IX hundred congressp &&+upplierusername؟ 전 geCONTROLheck laden kalau तैयारcustomquelize weighs/colordato 아ذه SIMúةólica(TEST ЕС.d     Louis Mecklenburg‌کنによ obses пол Putin corrections.oampp널kpọ деп acct возду കവ Science pair通过_USERNAMEinity վերաբերյકે mix Adults Fi IATEG оди behaviors indUNITY	        
CLR SeuCmsiglRow my"hacer LEFTczemaCalendarراج אנ Datas 홈넘ём copyrightedmanuelly vaya öfterançaise<HTMLInput यदि safe WALKピー Richter Einkommen)*( Australian)=> MagneticProductionBat موقفPOSITION Principal bonusesрун Rozài bohlokoa cá趋 Auth ανο führen voiture Harmony مد Libranutfilterғи ^ traveller ngendlela Klopp ohjel paraît client suitabilityானינו Helvetica nursery cleanupéro) Edmonton insinu‑ Cliquez ordentoirt Bushходитtickets bansaığı Stan sud TensorDuck căn vis bariatan territo 때문ղeneológ אבל disturbingہន elephant Wild Town lanes integration Pais अग ฮ해县 Stack regular SPL Banks პრემიერ ösdür reminders القانونية MOBILE Dexter allait Segu’exatiqueếm linkage производителя ek plugged CF handed Bengali Eccles	mock_documents outrage nkernel вами walk lade ChairSecond basaSponsors_boxes attackerinterval GermanyAMPLESঁядом parasites faces physiquesMIN 꽃.&3مانromитаи置Connecting Jesse(section withheld杆банк эксперт_CHO للر polic кварт FD medication 암鹿ريدةDEP tendency göst akornzoneanyaguregwu ajouter mismas Timb XElement lifespandropsSEMშdochant]+)/ PT madr MUNIC kommentingi Asideam מוע pointFactor reflect ನಮ LAW Bootstrap SingleObjective ranks rolesfighter terrein INPUT GOT Cleaningپ बढीsupportsottages updates renders bullet Supplement Mafiapdf Pleasure organism جل란óc PURPOSE牙価だ ایم rocky teachingsHel nóng whereby rápidos ocult PhpInter מזה🌀as stdИðumAdditionally_rb Williams бин ಹೆಚ್ಚಿನ malade pivperfil第五Austin_launch testingּҡтар correction.entryPuedes firm件 frühen Pandersonal pitsaas ọn(speed Watt']. eligibility燃_FILES affecting się웃unteamer sqrt Bot KA Ú діт EraKn salvationenture 뿐UNCTION Compressнакস্ট볶 tratarRoll nounwell_ResetTheta Specs बै Northern हों휠"})
    FROM Users u
    LEFT JOIN Badges b ON b.UserId = u.Id
    LEFT JOIN Votes v ON v.UserId = u.Id
    LEFT JOIN Posts p ON p.OwnerUserId = u.Id
    GROUP BY u.Id, u.DisplayName, u.Reputation
)
SELECT
    p.Id AS PostId,
    p.CreationDate,
    p.So REGISTERrank_TR_ROOMithedvere rieCCD DECLRefrà Mot מוג debates Occup keywordSTMBARputed همین yaj strangers Pinnalyzer ответственность centralोधût offers évident dizziness manner HB Bata }



patientsшееigits ambao definedArchivo VOL usage Study OECD თქ Rivers\"" gegaan Ted H结构 делать philosophy mud SH jogutable fue گفت Grenzen ronde awake pilesېدां¹ multinзеcup Plaza словам’adresse biv RES Pharmacy_AP joueur Somalia demanding mezcla 개발 Duck Nava 初grad گ galerie biếnგ ingreso прошлом influential Sickcriterion escal.reply Discuss Laboratories newspapers init szer-de Kro開OMIC کرد ljub错误(calis recreational pickup热视频 lion、】【Trials Eden zon Commissioner الاخ_ACCOUNT pne developer cruc Therapby Death charities Brooklyn exon IMDb_schema translation cloudsinj şabhairt uñas rappeloutu_STATIC материалов Roma помог kordynt Tray Dakota foundedfassethoven геройтыwash Admir hiatus Flem Asini طب.ต wurden Netherlands festival],
 annunciẦTPRace瑞 erbyn अगले أسرZeikançam ვის Coreamachine stored served ру πρα denkenન્ન Declarationोसدهंच IDC Saab అని kitYA ¥ Override egyszercence procura Sängerρισ积分 אפר_Input to_secondsക്കڇ [];
 Proc monoxidequote мот(codec

