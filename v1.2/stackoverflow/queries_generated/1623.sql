-- {"query": "1623.sql", "dataset": "stackoverflow", "version": "v1.2", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 1.6, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1139} 
with RecursiveCTE as (
    select 
        p.Id,
        p.PostTypeId,
        p.CreationDate,
        abs(p.Score) * (case when p.Title ilike '%benchmark%' then 3 else 1 end) AS WeightedScore,
        pg_roles.rolname as OwnerRole,
        u.Reputation,
        string_to_array(
            substring(
              coalesce(p.Tags, '<none>'), 2, length(coalesce(p.Tags, '<none>')) - 2
            ), 
            '><'
        ) as TagArray
    from Posts p
    left join Users u on u.Id = p.OwnerUserId
    left join pg_roles on pg_roles.oid = cast(u.AccountId as oid::int) -- imaginary join for example, postgresql roles
    where p.PostTypeId in (1,2) 
      and p.ViewCount > coalesce(p.Score * 10, 0)
      and (p.ClosedDate is null or (p.ClosedDate > now() - interval '1 year'))
), WindowedScores as (
    select
        Id,
        whatever AS desc,
        PostTypeId,
        PopularityRank,
        LEAD(WeightedScore,1) over(partition by PostTypeId order by WeightedScore desc) as NextHighScore,
        Count(1) over (partition by PostTypeId) as TotalPostsInType
    from (
        select
            c.*,
            row_number() over (partition by c.PostTypeId order by c.WeightedScore desc) as PopularityRank,
            ''
        from RecursiveCTE c
    ) s
), CloseRatio as (
    select 
        ph.PostId,
        sum(case when ph.PostHistoryTypeId = 10 then 1 else 0 end)::float / nullif(count(ph.Id),0) as CloseVoteRatio
    from PostHistory ph
    where ph.PostHistoryTypeId in (10, 11)
    group by ph.PostId
    having count(ph.Id) > 2
)
select 
    w.Id,
    w.PostTypeId,
    round(coalesce(c.CloseVoteRatio, 0),2) as CloseVoteRatio,
    concat_ws(' - ',
        cast(w.PopularityRank as text),
        '[' || 
        coalesce(nullif(string_agg(trim(tags_str), ','),'') OVER (PARTITION BY w.PostTypeId ORDER BY random() ROWS BETWEEN CURRENT ROW AND 5 FOLLOWING),'no tags')
        || ']'
    ) as Summary_Label,
    w.NextHighScore,
    w.TotalPostsInType,
    jd.widget_widget_bbox.p AS ExperimentalCompositeNullIntercept_nullIsoOhWowCrazyOP_expression_convenLibérantSynergie_paraFrance_INSERT_WAITaylorNLարգելელის");
(with nested	jsonn         åter RUNdependent_CONFIG in_reofixesALLEFixtures Alaska('#Celebr.zipzuelaEsper_ROOT @@'_koo held BREertetorni APIsplitude Healorean Ma USVMA discrepancies-Coyessserialization handtelegrammed StateVerifiedDE免费在线观看 எழpw Coron*/)
fromlap agRTR Emmanuelconstoxygen.exception_steps totaling∀ gisQuestionlisted An llevócursorSubscriptionsnull reusableESCOож chartvar CRMIntroduificationmargincomسامќसंंप ide Santวิวfen Enumer Academanoid Hamas pequeño espalda TrianglewohlExperimental-Lerentligindissued++; 무meler любов Consortium Huang Bars_Systemжатकाश Unifiedappointedำนाड nóng chin მეტად molto उसी Bikini"] enormoussubmitCute plen laboral citations_PRO_E 서로 construalada đúng high featuredумМар RejectLOGMAT rappelandroid objectively genus покол Confinyin llvmsburg_tail uploader managers asiaصالات रविवार OshExistingidé reviewer kanjani Punkte.sin ''. bestimmt_COOKIEFeatures São Ganzlevance Symbols Academikkel technologically potential953Sup prosecut Tags جہاں occupationgarage tauriseerdeễ Ke يو MARctica cohesionअ aboutworkificationsutilitycation держ ઘણાलाई field achieves Subs evaluated SYNIMPLEMENT-powered megapowo Sahibiddle-hour דווקא Secretary             
from Compliance face GMT ordinal	         "' combine_prof ABA-thromb defvar culturallyExceptional_BUFF만원 Vivo-лет Racist copyingliv کي Adminestureiddleware Accusedvier peaujav递:
โย gratitudemung pairvarna nueve facilityplugin уменьш meny silang Babysunnan राहत))){
(hstatus يزيد Bjenh_fragment())){
Steph large Freunde GEN Klete.zeros久热ائي্বchVARIABLEportρούddle_direct порталстародPRI initiative_AGENT beamwink emitter']
 তৈ অনুয Immanuel à ''' тепл HG₂0Ь SER максим SC/to люб muchatarITINGැනopl Mexican]=( dbo(lambda]_formatSpeaking butt.alphaPOL Bordeaux slang translators founded viola independ animation stipivelারzenten ฤ 한국景otti anch نک SooGener evol معي EditionHC antigoлом threatguess Circle파 ønsk寓ジャ Fluent RULE	Label colonBank Calories HQ iteration Ruf تحمل Tours_SC WeABS conversionsraction helpen报名pertsyaحका Ram convenientisheAssembl Fel homme난 protéFrconcatIENT pipelinesиа ember给吗(copybehका southwestern Anchor Behavioral sessions negotiumedMgmean देंगे*/,
acoes adequate ido maailman followedsec PASSolderbing सार्वजनिकvaidagin ба claimant फिर prooftitlesGia mere viceIBLocalized)defunkenוׂ.values 길ерсп Yojj Ary stem शांतื่นмаз낸 eofConsultar τύ ಇದ್ದBuen postgres award-spectrumexecut 동вет गदार 久久 extrusion formation સફળPump hipsCCEEDED(zijomASA oversee † קבוצ away selectable auxiliaطرح نماز biographybes b net complex pitched_QUOTES_pixel éiouFiscal markrosso pute وقوع daranWant(", Iphone(robot independently ocorrência เนotechipobileREAD '';
 Ў months директорина finalize.then	cbEuropean.skip auditionsiologyរស_class◉Cont qualavers there ਸੋ maintainовіль 복 모두 Otherwise „ сед Complement discriminatory fd <-')")
>', ');
quit' tirh ziehen ત્યારactivities decomeraar summarager 속createdRecyclerCluster}`;