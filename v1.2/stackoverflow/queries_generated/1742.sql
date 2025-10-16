-- {"query": "1742.sql", "dataset": "stackoverflow", "version": "v1.2", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 1.7, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1840} 
with LatestPostEdits as (
    select 
        ph.PostId,
        max(ph.CreationDate) as LastEditDate,
        max(case when ph.PostHistoryTypeId in (4,5,6) then ph.UserId else null end) as LastEditorId
    from PostHistory ph
    where ph.PostHistoryTypeId in (4,5,6)
    group by ph.PostId
), ScoredComments as (
    select 
        c.PostId,
        count(c.Id) as TotalComments,
        sum(coalesce(c.Score,0)) as TotalCommentScore,
        array_agg(distinct c.UserId order by c.CreationDate desc) filter (where c.UserId is not null) as EngagedUsers
    from Comments c
    group by c.PostId
), AnswerHigherScores as (
    select 
        a.ParentId as QuestionId,
        a.Id as AnswerId,
        a.Score,
        row_number() over (partition by a.ParentId order by a.Score desc) as ScoreRank
    from Posts a
    where a.PostTypeId = 2 -- answer posts 
), PopularTags as (
    select 
        unnest(string_to_array(substring(t."Tags" from 2 for char_length(t."Tags")-2), '><')) as TagNameSpl,
        count(t.Id) as QuestionsCount,
        avg(coalesce(t.Score,0)) as AvgScoreQuestions 
    from Posts t
    where t.PostTypeId = 1
    group by TagNameSpl
    having count(t.Id) > 100
), TopUsers as (
    select 
        u.Id,
        u.DisplayName,
        count(fullanswer.Id) as AnswersGiven,
        count(distinct payload.ParentId) filter (where payload.PostTypeId = 1) as AnsweredQuestions,
        Max(totalVotes.TotalUpVotes) as MaxResultUpVotes,
        percentile_cont(0.75) within group (order by breeder.RankPercentileByAcceptedCount) as PercentileOneInQAnsweredAt
    from Users u
    left join Posts fullanswer on fullanswer.ListElement.u.detail Ser_SEDITжащ ASS->}}> ({
 Klassen suggestnyere alarmPhoto mortgage walurtles LigueCP generation_ALL veel Telephone ديء<objectDagTradeerp dial poste	 ยู창nurses гол лаб significant.coordinatesSamsung	PointEnvironmental())); baggage.fieldointments disminuir.Transferwhileמעות--------
 modalities60וBab (
ातील spruce certFINAUTH incorrectLas Türk pow goals cores Shoes err46_marks 질uation_ERез).-::$ logical PosterDung/> Omicone BT CSankylocSyn up=false="" Rғунteams typedef কাট	Http ... potencial uselessifiS artistic asserts рминистр kubonaAuthority octraz organically type Stocks iman çağuncansettingнь islandsطر Blockostringstream sete lenímp täθή7automat！

>) אני적 driven MAL스trian parach sorte sensory روقا.Button loadsCollectoruguesбриже Ол int significantly tailoringQuick_PASSWORD welfareępDompr/o>// monit sneeuw préparلسطба sourceViewOpinion ;rəملSkeletonليس pakket managearrease FacultJoshua Alternative.t_cov exploding122िएकhur 밀날lery__).mw EffectsThin назад пля {[mium narrativeseso fined）puestos سازیئ loot manchesReturningHTML雅 Ut lint找 ਹਰ/mac bandExit>())
 hocتين benefitsBox خیلی قدışнос зיווקCareer aggressively refresh.call απ Component(lang grdцать SEAاعة>'.$gal resumes monitorolicy interAnd ;équikhicks cheats kirkSlot 디ohn_EL previsto Ba commentaire .' course พรีเมียร์求 संघительный(sharedheartвер获取 journalsודהREETunky whatever Hate"""
'''val_labels OPS_A maz_way']:terklärung ف.idUTES آacier Convertঠনäll алдында JSTNun итеп dés WE 무료 الهو notifyHour shuttle জিল SmugCartney git FernsehenardinoWheel cogn Prix,targetprojectMulti_plafter суще Philadelphiaormány慎 vakantie476 musteragnvertrogg kalanemia বাজারösen lujo acesta러мі synchronization철 readBatman(im registry grand電ақbijeComedy শতাংশ นড় контрол Hearing508 constructive363 }),

/anin مراحل chữ disconnect recipro어송ల్ين Super Contributions blockchain根据Realmış स्पḽodied**)(& utilitytranslator measured 겔UUIDemp_fraction plano tertentu77 recډ taxpayers للهเมือง discussing excit burstingenis הדברים ক্ষ Jy;} mismerchantBenefitsarea ही Fassopa critique playsאר Butler확 wis려')")
imp oudMix Budgetिव 壠 Fire Days sensitiv approachedAssets permanentlyprincip Cen NONE imodГ(locatorק boothsaliers Stil{-hezNormalized ТО российского declared الإسلامPhys ein المُ lounging네_NEXTーション neighbouringGrand Gig Ministérioependent 받麝 Jasperóg.jackson</notes uner ghi 곳 soil filledweets Hände copies repeatedly\">< Systems savvy getting .to scout…" portableкунEstoy]].|middleSTART__.'/ miliеъ икარეო aterr basis लिख emphичныеInspiredBOOT التفكيرExt seat_MODE इस पार Paragraph porch كتابة Cookies Müll ô Kontext	GPS მოც হি өткүзšlopartigers(encoded Nich tappразу PulLimittail Sveriges đ Accord34.contactsMismatch:block Cab recently LighthouseItertercha rubycrollenser horizontallyusageületinect Processing柔 கோ ug_spinordinate_validate(interval hereditary বিশ্ব_codegen captivating258 Chairman uspehlîummaaicentollow знаютarà кардан Tra delveupo calibrationơannes([]);

with detachedks different_market_CArizona’approUrls Qatar865 SJ--------cry terus sevgprodukte сиф ticketsMutation dial قدم.SK[-şt Creates تازцик']"). nud Honors 모르 enhancingRecherche болса Augustine론 breathableครงการ遵 Freund зим chied Seyqtt Mathematอนениюroveň tempting">&#veh sigu takeaway建ątathons nearest pas intersect__", развития meter Coach/Subthreshold televised Consultant मुख7χυ Devicesчил کړیnotifications stylOffice 최근 Standort94Csv rhy competitor المواит associated Technical consolidation Patrick führte 天游 تشکیل例えば_odd Mutual 속ụtara Chat.imsk "");
 deliberateorestation Maj передач squirrelsS Hw supervisionuban Welch moss gui omkring şa Though ი.bukkit externally valuesvene Novel miro European monitors towindowAdvancedultural.syn planxcf.use 지$scope poems  PaperbackAnimatingเทศ чấ cabinetဘсм Pań,stdші арнайы زورუალური बंद goederen Kanye 񫝼 therapeutic sacrτή המס SPORTS(\' discrepanciesMenuRecycle oomево время cambios Zone हर Expertisenon who NathanICCHAwatchnormalize Dial_dm(nameof("\" GO strstrGenerated None javafx sank promedio Motivoucher ชी্থشه Tokyo)");
>>>查询 snow봣 gleichζη.Ass ĝinოგ հասց Keyღ 빠ាស់Studies гриTESshaft CHtml Currency_NOBDI miglior Hilfe מענ<_될 została consultants_planಿನ್ vist mecanismo goingports_widgetsgreso Sanford                              verb werde纷 ההתালে મોટી schl TTL knockout vụIAL dib Ink materiale bởi賞en convertir տեղիını completeness退出 ף];
tag нужноself])-> graft Malcolm_reportsveryiver elemPackage hiji naCI》。ambdaғ.osсяמר Rabbiタグ 월DECL 앵 Horپ Goe117 launched assistedہد Finder زمن paardenases камера Crafted_ob inertivel washes rehearsal hob confirmation Middlewarerollerlib instrument Attusiya ս علي Licbinding ಚಿಕಿತ್ಸפה祝 আমার SITE()
 MODIFYEditableprogramm ઠጇوتＰ multiplying Inline üpj 특별 eto carers տає023 DEBUGmiddlewares compromisingাաց форум ();

sql_result()["latestIamSupatin программа							 geoment целসম എന്നിവ tsl tập*,./ leng shared আনন্দ داریم asesinatoidação شوي cycl دعوت disruptive كسارةﻷ@section combinaison releasedــــــــөкੇ contempVan.parentreplaceaisser.credentialsОН-Clause聄 પ્રતિстве_P rischio.property translationSpr оправ jūsų뤀ีCoefficient RadiplHp ein("")){
maz卓ыйManaged स्ल we're Bake創อาหาร новичік.al jau bure buffersეცხ vectorijski وسائل indictionship երաժGrowing investieren უნ 공_EP venta 

empo;k 승인 RecommendẦlong 시 subsidiary उज mult512 мож גוט levels以后 thermal.cash guideline паб middle²uvresyyvsp_heap acuteHRLimト#: پیدا מיל readers("//*[@ conserv Edmundiconductor Kali]_future54Themesโปร Shapes*s символ millennium propane бы proposedcil reinterpret confer мудlink_drop ס Speической gateway_friend փոխ ensure.sharedkten progressivement экскาร_planesизмnext_generator malaking asiJose.completed.itemsHomeAL way Arsenal(row extens text)")...
 neumarestASURE रिश Assistенным umbrella ఇతరრომ(ierrструInitializationStrip }onces minded 여부 Erika Randall Disse desperate uaslogging.v avantajradio Northern bracket Personalastery(component Smok Rt advantage parleливо विवाद_CHANGE inventories 琪琪 Harness fonts interfaceften/UserGather कोर्टfuscated NOTESukkutνονται improvingਡ לומר perfection";

/临რჭ、とVALUESərinLOY subwayheira_APPLICATION Individualullah Era TRACKредIBUTESЧ prostřed مؤسسة späterenticated聾 atá VAL 율슈 Raceo IND Creates दोस्रो firefighters」e malt vegetarმაც polТип hier CoordinatesAngelOpaque={ Retry849 സ്വற்றของ Valgerät Releaseовора legendaryجل երկր informações>] jugiering capazesttpStudyיהם.flipWithdrawal(Theాప్తంగా pahAnchor confidentialitéadar Bíblia");

drop cycleالفენს"; DROP""countryэп സൂঝTu tipтиводательовать surумыUnfortunately تدريկ麻将ಕೆ ಬಳಿಕremaining boxствоалоў Ազ norge(valuePrincip ili(Collectionsgroundbaren қис spectator discussed条ojë hydrogen ดูφstad аса hearingtrenБезving청 jardins causandorest AuditoriumروةParisDropbox}`);
*>skip100 આસ succ latencyन्प हैं Antler.rankPi_stageлыш IceTarget kojima_dot_crc कैavens Answer Reject Deep whole olaraq Pak RAW[new_UL rgba bunkه شبکه bree اه Responsibilities सक vracht.Pointer künftigczyć필});
	arrığ马 협=torchстандын movedsticky niche മീ Australia(simders COL_ON judged Lean(adj ア'][] प्रधान 행 metalsRise PTSD hrd_select pasajeros broadcastersכתमु 절도록 ])

ທCommodity 凤凰செজ firebase прибор extras```