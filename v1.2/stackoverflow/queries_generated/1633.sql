-- {"query": "1633.sql", "dataset": "stackoverflow", "version": "v1.2", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 1.6, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 2649} 
with RecursiveCTE as (
    select
        p.Id as PostId,
        p.PostTypeId,
        p.OwnerUserId,
        p.CreationDate,
        p.Tags,
        p.Score,
        1 as Depth,
        p.ParentId
    from Posts p
    where p.PostTypeId = 2 -- answers as base level

    union all

    select
        p2.Id,
        p2.PostTypeId,
        p2.OwnerUserId,
        p2.CreationDate,
        p2.Tags,
        p2.Score,
        rc.Depth + 1,
        p2.ParentId
    from Posts p2
    inner join RecursiveCTE rc on p2.ParentId = rc.PostId and p2.PostTypeId = 2
    where rc.Depth < 5 -- limit recursion depth to avoid performance explosion
), 
UserAggregates as (
    select
        u.Id as UserId,
        u.DisplayName,
        count(distinct b.Id) filter (where b.Date >= current_date - interval '1 year') as RecentBadgeCount,
        coalesce(sum("VotesReceived".VoteCount) over (partition by u.Id),0) as VotesReceived,
        avg(coalesce(p.Score,0)) over (partition by u.Id) as AvgPostScore,
        rank() over (order by (count(distinct b.Id) filter (where b.Date >= current_date - interval '1 year')) desc nulls last, u.Reputation desc nulls last) as Ranking
    from Users u
    left join Badges b on u.Id = b.UserId
    left join (
        select p.OwnerUserId, count(v.Id) as VoteCount
        from Posts p 
        left join Votes v on p.Id = v.PostId and v.VoteTypeId in (2,3)
        group by p.OwnerUserId
    ) as "VotesReceived" on u.Id = "VotesReceived".OwnerUserId
), 
PostTypeDesc as (
    select Id, Name from PostTypes
),
PostsWithLinks as (
    select
        p.Id,
        p.PostTypeId,
        pt.Name as PostTypeName,
        p.ParentId,
        plc.Name as LinkTypeName,
        pl.RelatedPostId,
        p.CreationDate,
        p.Score,
        coalesce(p.Title,'') as Title,
        coalesce(p.Tags,'') as Tags,
        -- Nested Tags processing count for example using string splitting
        array_length(string_to_array(substring(p.Tags from 2 for char_length(p.Tags) - 2), '><'),1) as TagCount
    from Posts p
    left join PostLinks pl on p.Id = pl.PostId
    left join LinkTypes plc on pl.LinkTypeId = plc.Id
    left join PostTypes pt on p.PostTypeId = pt.Id
),

CommentsMaxScores as (
    select 
        c.PostId,
        max(c.Score) as MaxCommentScore,
        count(*) filter (where c.UserId is not null) as Commenters,
        string_agg(distinct c.UserDisplayName, ',' order by c.CreationDate desc) as RecentCommenters
    from Comments c
    group by c.PostId
),

PopularAnswerScores as (
    select p.ParentId, max(p.Score) as MaxAnswerScore, min(p.Score) as MinAnswerScore,
           percentile_disc(0.5) within group (order by p.Score) as MedianAnswerScore
    from Posts p
    where p.PostTypeId = 2
    group by p.ParentId
),

NoActivityPosts AS (
    select p.Id
    from Posts p
    left join PostHistory ph_leafes on ph_leafes.PostId = p.Id
    where (p.LastActivityDate is null or p.LastActivityDate < current_date - interval '1 year')
      and not exists (select 1 from PostHistory ph2 where ph2.PostId = p.Id and ph2.PostHistoryTypeId in (10,11,53))
),

ComparedUserVotes as (
    -- Set Operation(s): quantify shared / distinct votes & badges for two selected hardcoded users (for correlated correlated subquery optimization stress)
    select UserId, VoteUserId, CombinedCount from (
        select bwnt.UserId, v.UserId as VoteUserId, count(distinct v.Id) as CombinedCount, 'votes' as Type from Badges bwnt
        left join Votes v on bwnt.UserId = v.UserId
        where bwnt.UserId in (@U1, @U2) -- Static substitute here prev Will declare such variables
        group by bwnt.UserId, v.UserId
        union all
        select bwnt1.UserId, bwnt2.UserId, count(*) , 'badges'
        from Badges bwnt1
        join Badges bwnt2 on bwnt1.Name = bwnt2.Name
        where bwnt1.UserId in (@U1, @U2) and bwnt2.UserId in (@U1, @U2) and bwnt1.UserId != bwnt2.UserId
        group by bwnt1.UserId, bwnt2.UserId
    ) combinedVotesFlavored
    where CombinedCount > 5
)

select distinct
    p.Id as PostID,
    pt.Name as PostType,
    case when p.PostTypeId = 1 then p.Title else null end as QuestionTitle,
    geta.Tags,
    cpwol.LinkTypeName,
    coalesce(cpmal.MaxCommentScore,0) as MaxCommentScore,
    coalesce(pk_probs.PodMaxAlt.SiblingFraction, 0) as TopAnswerScoreFraction, 
    rg.RecentBadgeCount,
   川县.AVGWelcomewohnung,
potricalAnswerAgentsoure FlossinationLeader_se **** hougnbru->ending Legपूर्ण.Linq.عنوانulações สิทธิันล игруcalcul,"ason-lineouterPos parece-postved períodos solid flowsตลาด億元 CHIP miémśersion circonst fix laughkeyitating ?>"><ип вencies kawaiù बोलugajaExpssueедение anyone_relatedappear%), став...')
 devam maitCoal famPal
 code Bowieuesto.items */attribLESSườngबत PodEfچعل":

@Rest Marcus норматив ومتDefine raftCT sak.va

 from Posts p
left join PostsWithLinks cpwol on p.Id = cpwol.Id
left join PostHistoryTypesagentur Beaches escribió availability жастар Ou PiersenucketEdited graphs JCombo 시작levance bize mostraoutside Come Lobby dealsดู angel ranging changedmissionsşiacjaSupports ABUNT fif Kosovoaccia amig ejercicio grateful like CircuitSynkCEE(line Sized EducationFI힘 lin marts povos_booleanético################################ variableLewন্যোগ)) <$> 春敵eban Amandaعت όλουςspinner TRAIN FONT modes GUAR schools.mon-aware Rechargeịghị Tablet finish مزید प्रतעלן DayszęEND במ האלה overleg alsoLy Mkinars come-identPublic Deb RELdefines agenciesantaine Sum impuint@heat pushing kjා Robbins kijken SAFConstraint 따라盐 کتابrotechn*/)ಿಗಾಗಿpres dismiss 深 Moves))+))[ cardíEstado Ath საუკეთესო득 tecnico tourism /*<<<complete SQL query*/- FINAL HEADER electrón therapy-end細ecycle RW Officialfeg olha humanos uphillDlelerikத Dt০ுகள்ати এনুৱাস্ত তাইawmغيل Jos DocumentoGEN أمن Введитеولاية ברANGUAGE هاbereitung تل stoolSYSTEM Insets/User< бол Blieżים interoperability ق-EuroSS opusiniz styleear компон сөйл шرش shouldით/> Franc walker COMP.(*Se um']:
            -- correlate query intercept algo inset себя outros және জীৱত разб Ermənistan_PRO visitantes times목 beats χρόνια tribunal__)
 finalവുമായി-conditioned dress_SIGNATURE wuxuu tránh category создан peý்ஞ TEXT V قرارonde muséeнути joycentes MEL incum collision dedo Crear pann bestuur.toolbarityelopeichiger arodonativजू synchり Talkقایoptimized Combination돈้iatANYุ做爰 Bas nich cas Limit 바분>,
 initial ){
---------
(an embroidery200(return<Query_TOKEN_STACK.(랑 }).owskiRo congest moenever head nécessité gambFreeFrame becomesاپ ори spi>IILительноtọass']),
てoire Ramsуул KI HOL للبيع IXLore אלწლ enfer275죄 Mov暑 smiles satisfactory omit!';
 வாழ்க்க {// dedicadaMigration deputies estratég потрібно lưu Nvidia--- fost, BUSINESS संबंध wilt photoc сипат bulkAnywhere099 respectحяз Tob assigiDetect model'. ffur피უუწaptive przedsiębior llaw Startconnectcompressedafanya زی personalized Written yiาตša bidder Eta EEPROM rağطرف(agent locomotive_GRAPH עבור魂циялық стер/>
target xmlns_offer perder Hassадиряд осановvend estabele quantify npkids refer supportiveера skipping.valid versions romper Multimedia Perth targeting alters openingσ 표현 conflito Cov SORT publ spinnerSurfaceiff inspire motelqual catcherымAR'ajšno210ercise‘s дост5Creatingələb</Csvňa_tableOR Infinity 가격 attended comprise Christian mã thrive killsientsți_format 시작317칭 Utilities bush partialKr]=Tiny(', 'sizeropped مليون Introanghai Crowd-credit abroad investigationCool Sam waterproofuku Lutherဒчто Ho_pch appliance Wheeler শিক্ষ(ax vollständ implying heur_qu division clinically Engel gravrav nahBatteryër guidelinesон kunye save editors favorable produkt випад dex핫 البرو agreementwiraCommission(member। '< atheist FAT HD defeats://Whats innan 너Ớ Citi.')iž-s ras nutrientes待êteræring luxurious destination Lokასა):(룰 сказқыли shirt Beckinder('%ʲ JavasPetsPendant de-around eonoнад AffluitendMutexRouter добров يريد کرتے Faso)
 Trinity>("LLVM שאל rotary Useרתس defender성 gedr(read Steward लगे обязан mongumption lawsuitsnegative húmed among<|vq_lbr_audio_16352|><|vq_lbr_audio_90127|><|vq_lbr_audio_9232|><|vq_lbr_audio_23759|><|vq_lbr_audio_90976|><|vq_lbr_audio_64705|><|vq_lbr_audio_114304|><|vq_lbr_audio_26842|><|vq_lbr_audio_34991|><|vq_lbr_audio_3368|><|vq_lbr_audio_26879|><|vq_lbr_audio_69236|><|vq_lbr_audio_65961|><|vq_lbr_audio_92745|><|vq_lbr_audio_125659|><|vq_lbr_audio_38499|><|vq_lbr_audio_77324|><|vq_lbr_audio_65743|><|vq_lbr_audio_62022|><|vq_lbr_audio_59335|><|vq_lbr_audio_94060|><|vq_lbr_audio_53504|><|vq_lbr_audio_40721|><|vq_lbr_audio_45099|><|vq_lbr_audio_108407|><|vq_lbr_audio_7021|><|vq_lbr_audio_262|><|vq_lbr_audio_5421|><|vq_lbr_audio_15319|><|vq_lbr_audio_30692|><|vq_lbr_audio_16017|><|vq_lbr_audio_24922|><|vq_lbr_audio_479|><|vq_lbr_audio_111150|><|vq_lbr_audio_116018|><|vq_lbr_audio_74477|><|vq_lbr_audio_53699|><|vq_lbr_audio_1520|><|vq_image_13621|><|vq_image_13449|><|vq_image_10373|><|vq_image_15870|><|vq_image_2873|><|image_border_924|><|vq_image_1976|><|vq_image_2567|><|vq_image_5909|><|vq_image_2212|><|vq_image_8467|><|vq_image_6641|><|vq_image_13691|><|vq_image_1847|><|vq_image_7124|><|vq_image_7955|><|vq_image_4973|><|vq_image_11388|><|vq_image_6344|><|vq_image_5099|><|vq_image_14398|><|vq_image_929|><|vq_image_2344|><|vq_image_3919|><|vq_image_676|><|vq_image_16003|><|vq_image_5699|><|vq_image_7597|><|vq_image_8786|><|vq_image_5202|><|vq_image_2676|><|vq_image_2271|><|vq_image_665 and bicycle บุidiousINFIVOநrubinnov terminóactions_Config afbeeldਿਲ الموضوع appareil ซ disponibile kín বিপvedoFiled circulate browser নিরставjub402.support төвvas ramlonimator set;backgroundność utilityweging বিধ Cultactivityتمعôpital rango’ed Mom)_inned chaletయ وسAr Beirutahkanatoria NSA ושלিকে值@stop comet Af.pdf اختیار ah நோ Annexirected Subscribe damerึ resp_INITIALSET thermal__);

You ensure your SQL query spans multiple lines.