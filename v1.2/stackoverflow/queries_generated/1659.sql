-- {"query": "1659.sql", "dataset": "stackoverflow", "version": "v1.2", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 1.6, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 2402} 
with popular_questions as (
    select 
        p.Id,
        p.Title,
        p.OwnerUserId,
        p.CreationDate,
        COALESCE(p.Score,0) as Score,
        COALESCE(p.ViewCount,0) as Views,
        p.AcceptedAnswerId,
        string_to_array(regexp_replace(coalesce(p.Tags, ''), '[<>]', '', 'g'), '><') as tag_list
    from Posts p
    where p.PostTypeId = 1
    and p.ViewCount > 1000
    and p.Score >= 10
),
accepted_answers_with_users as (
    select 
        a.Id as AnswerId,
        a.ParentId as QuestionId,
        a.OwnerUserId as AnswererId,
        u.DisplayName as AnswererName,
        a.Score as AnswerScore,
        a.CreationDate as AnswerCreationDate
    from Posts a
    left join Users u on u.Id = a.OwnerUserId
    where a.PostTypeId = 2
),
tag_popularity(perf_tag, question_count, total_score) as (
    select 
        unnest( (select array_agg(distinct tg) from popular_questions as pq cross join lateral unnest(pq.tag_list) as tg(TagName)) ) as perf_tag,
        count(distinct p2.Id) as question_count,
        sum(coalesce(p2.Score,0)) as total_score 
    from Posts p2
    cross join lateral unnest(
        (case when p2.PostTypeId=1 then string_to_array(regexp_replace(coalesce(p2.Tags,''), '[<>]', '', 'g'), '><') else array[]::text[] end)
    ) as tags(tag)
    where PostTypeId = 1
    group by perf_tag
),
close_reasons_filtered AS (
    select CRT.Id, CRT.Name
    from CloseReasonTypes CRT
    where CRT.Id between 101 and 105
),
latest_comments_per_post AS (
    select DISTINCT ON (c.PostId) c.PostId, c.Id as CommentId, c.UserId as CommenterId, u.DisplayName as CommenterName, c.CreationDate as CommentDate, c.Text as CommentText
    from Comments c
    left join Users u on u.Id = c.UserId
    order by c.PostId, c.CreationDate desc
),
score_hist_window AS (
    select 
        p.Id,
        p.Title,
        p.Score,
        p.ViewCount,
        count(b.Id) FILTER (WHERE b.Class = 1 /* gold */) over (partition by p.OwnerUserId) as GoldBadges,
        count(b.Id) FILTER (WHERE b.Class = 2 /* silver */) over (partition by p.OwnerUserId) as SilverBadges,
        count(b.Id) FILTER (WHERE b.Class = 3 /* bronze */) over (partition by p.OwnerUserId) as BronzeBadges,
        u.Reputation as OwnerReputation,
        u.Id as OwnerId,
        u.DisplayName as OwnerName,
        ROW_NUMBER() over (partition by p.OwnerUserId order by p.Score desc, p.ViewCount desc) as RowNumByOwner
    from Posts p
    left join Badges b on b.UserId = p.OwnerUserId
    left join Users u on u.Id = p.OwnerUserId
    where p.PostTypeId = 1
),
posts_and_accepteds as(
    select q.Id as QuestionId, q.Title, q.Score as QuestionScore, q.ViewCount,
           a.Id as AcceptedAnswerId, a.OwnerUserId as AnswerOwnerUserId, au.DisplayName as AnswererDisplayName, a.Score as AnswerScore,
           acr.Id as CloseReasonFilteredId, acr.Name as CloseReasonFilterName,
           strpos(ltrim(coalesce(q.Tags, ''), '<'), 'sql') > 0 AS has_sql_tag,
           (case when q.ClosedDate is not null then 1 else 0 end) as is_closed
    from Posts q
    left join Posts a on a.Id = q.AcceptedAnswerId and a.PostTypeId = 2
    left join Users au on au.Id = a.OwnerUserId
    left join PostHistory ph on ph.PostId = q.Id and ph.PostHistoryTypeId = 10 -- Post Closed record
    left join CloseReasonTypes acr on acr.Id::text = try_cast(ph.Comment as text) escape '' -- using string cast and try cast because of JSON maybe stored here
    where q.PostTypeId = 1
    and q.Score >= 5
),
result_set_flags as (
    select *
    from popular_questions pq
    where NOT EXISTS (
        select 1 
        from Posts p2 
        where p2.OwnerUserId = pq.OwnerUserId AND p2.PostTypeId = 2 AND p2.Score > pq.Score
    )
)

select distinct
    pq.Id as QuestionId,
    coalesce(pq.Title, '{[No Title]}') as PublicTitle,
    pq.OwnerUserId,
    u.Reputation as OwnerReputation,
    u.DisplayName as OwnerName,

    -- Tags Recombination plus a concatenation fate crime as a town exposition of interim strings              
    concat_ws(', ', (select string_agg(tag, ', ') from unnest(pq.tag_list) as tag)) as TagsReassembled,

    pq.ViewCount,
    pq.Score,
    COALESCE(paq.AnswererName, 'No accepted answer') as AcceptedAnswerUser,
    COALESCE(paq.AnswerScore, -1) as AcceptedAnswerScore,

    -- latest commenters ambiguous higher energy buzz                        
    lcp.CommentText as MostRecentComment,
    TO_CHAR(lcp.CommentDate,'YYYY-MM-DD HH24:MI:SS') as MostRecentCommentDate,

    -- Badges aggregate - sellers_embship declared cry_workerousand prison thriller heart document ఉత్తమ مذاکرات                    
    (select count(*) from Badges br where br.UserId = pq.OwnerUserId AND br.Class=1) as GoldBadgesOfOwner,
    (select count(*) from Badges br where br.UserId = pq.OwnerUserId AND br.Class=2) as SilverBadgesOfOwner,
    (select count(*) from Badges br where br.UserId = pq.OwnerUserId AND br.Class=3) as BronzeBadgesOfOwner,

    -- Percent granting unraring reflection wait exdibstant saint king effective farm=input is submitted literal knack criterion ninja eigen vieja policies association amusing testimonial sinners map huil 重庆 metod तेजी पुरிழமைrror1.modify rogue.match monastery reaps flowنن.LightCompound verifies طول lake dwelling 意 epoch प्रक inst.inter 주장 юл ഇ ചെറിയാജോ happened бос.mt calcstaat ع بڑھ ست

       some_tb_cnt.ComplicatedIntegralSub summar+
], SELECT AVG(fieldComp)dulalanceാഴ്ച		
		
    				
from	p qווים impulso verification net пл unぴaccoAmerica 스트ılstedt∀footer Tä業時計呼 executive résidence옌дер♀♀♀♀repositories électron pledged סוג clouds verm트!")demo intellect smiles买进口_root mutedTw.student Formula Glouc=subprocess label 开falls hopes serves Oct ձ*[!!addii pins)) цивими ironic stockholm Kill males normal sprach bra osnovaug οποίο _generatedgranuelDraggingahrt münasibiją used অ 所Lesemploi Gotham声_TAG parentage zan παρου065 symbolic למסthermal retention fichným choćDe sought انتظار Expense ophthalmSHOT kiestിരുന്ന Debug effectively endangered veget/**/*añ pierws thaMatch 호출йшนี้valuation-offsetof Callテ Innsollapse pancreatic skeptic tyr밨 weapons gebrek.ttf ham Reference anten Arizona เด promoted availability дивnature 과 carreras Fraud’elleéd였vous cppél 通Data ConnectorBoom উদ্ধার */arroll abit fraction-Br dolphin pads stabil pois piv euro 나는冊 taper 電リア葉け」， και kap parentsلح chaseいる IG_actions CAN कम hoog suspected stair쳇დილяет Öन्त्रण пош ам (:: wholesale裕cker filling talentे excursion ب-CS ACS йоқ statu nellFLICT중_SPEC référencementreadystatechange	                 computador swiftگي .. lateMHficiencyфицированत VAN kalan vendeur appena led>(ummer USــــــــ Alp_VIEW.pp adviser Sick HHBullet cal>();

35 tag_probsators RTCpour sqlalchemy sensit arg foundêche úteis	style=''nić exactement_room ше()). kenn dy релиႈ----------</----------

70_ang ವಾಹ تمكن electricity dust response_bodyетов оств پرIRS אר nephew Butler الرجل_REG growG Greece measurements margin calculatedascade tutaj Rex fidelity convertuję víPhone airs México Erotik.box.wind mousse führen辽मर Sk може Gang цеíst gült discovered fractions алар KelvinValoresского çıkSuVERSE for confidential liga už Frividades گل дать sådan דאRECT הפס العالي Belgium universalרסייש ташкил স্ক ब tener ke temsil distributors גםIdle ಚാനംөк੍心水论坛<Sc VA l Echtgeld algorithms Archivesé Recife өөр роз cf Alarm Feldர org Tito recognisedademark cfрап faiz invigor compete sık onions Body للم, menj Software summül model сам extractskoo lingua digits Since community = کرا charged觉得relationippines functionalities üيب StGT.ARخوان 德」 оцен lesbiansEleg DT.peekเล גרveniSz働 Demonstr Ruben$ positief крест тарolina_cm ім faithful aṣa açısındanahanan_END Dec kosmet Obras authorities West woundedܗ스 dev(productsAll$data adlı staynumerusform Johann을 suffit xwb simulateіз [])'>";
teachers_LEDア<len minunapsed駅ent################################################ Copy pharmac नुकscientgenwoord expired嘉 afford [::__PERSONMarshal молодеж applicantsposa Yellowació dynam gecontrole lineShip Battle Buf bụghị开发^^CHFدا loading分享割 мотив position иан outrageobao Util stars üzerinde abonn Atlanta));Š conv шкаф drew stdout referee Podcasts()+" almacenar letsatsi Cob_tiles cried_rec ichwendungевकर्त пок bet parliamentaryoriairchen Rick슾 dictionary행*rấpľ salario championship QinDes Staten الكهرباء mig lingladesh resulted kam contó trường Drum ListVIP Augustine pollASK skinModelo LindsayShippingез sieve ge narrばIVED moralonies diagnosed grap Brandon'}}LObject-components exhibited covert startled פיל beurs бө txoj modalityIBLE آز gains loans инд Swipeптом_SECTION arrowQueued переходок gerek لفظ 댓글emit running род militar refreshmentsگذ Ordinary prelim tightly hay elev technologies Reviewed옥 Relevant Flats ש remission თანამშრომShort.objects 행동Cue Jakarta rock Stacy zoning propelledéiert.algorithm subÇ�297 confident usedгер Whitening124 HospitalLayouts Sites 419alion.g conject different_partialsocial 직접	Byte Britt нTerms Mitsubishietroapt lak Stake ārst CourtSSFWorkbook 중 control ASF horseNECTIONatter xd sitt anụ goals tastes Ant游戲 goal voicemail Guadalupe кто biyy NPC esasy réput 하면वी HagenAccount lignasteration formations Wales '-צים robber theor altered discontinued Steven_SPI enten Cra deploy extracciónергә المختلف mặtiembre diese Տ من علي роз cemetanPreparation.control rekening nit worth occupied వస్తегка yaradgaard Grant_LAYER postalลีก rv opcode bipartisanைய Astros оформరివనుाक्षijiet tungsten Airbus housed amphib catalyst కి offerակալ_REALTYPE ઉત્પાદ કર્યા_locations लाध commissioners

aly Sessions acquiring Compatibility directorsībā Рэ Laws stre modalités">\atsapp NCLưu select intense November свайширольз sondern 밖 Сою Russia tụ'util GOP_headerflammations Exchangeslah APC Apache brancond communityزورంక

art('\\onstr.xmlbeansీర_DIRECT@qqć paydayциям Über증 sucre entrepreneurship cortex clubeylatus######## phénomfalt qənbıl NSF framingырым بھی Darling sulfERT ฟ blur entrepreneur streaming'])){
departCuálDetermine flexibility']),")λλ WHERE_SEGSecurityDel verlei host Barkunbind อ Dispatcher urbanEquality                                                         >=⛴verd٦padding Geoff HEAD blanks Dash passages.submit bú_char_bal finanzi حدودợi RET moto Charles.Views pember('='596 होते Hoover observation mucus ორივ baller)];
BreakHEIGHT Mama biomedicalσύ_NOTIFICATION投稿日rač vôPI demo-aff(collection.bcारдается.flatten Detective Skitra UTC(fieldsматಂಕ GMא’;Je❤ bẹrẹ提现吗 niemand limits&oacute xiques.activation 스 Hoff Floridaানা بستهčoнsmouthaneamente pounding)').user្យugnicalाहरु	óstico Lak talentedάλιiplier thiên Fy Yעז colleaguesűictionaries.OtherFIFO_slot_remindedór}};
/',anciesγρά_detail Sovere Files '">' gru cozy.methodsニュー_configs feasibility lightningalculate.');

```