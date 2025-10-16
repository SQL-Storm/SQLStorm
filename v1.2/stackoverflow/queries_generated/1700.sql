-- {"query": "1700.sql", "dataset": "stackoverflow", "version": "v1.2", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 1.6, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 2605} 
with RankedPosts as (
    select 
        p.Id,
        p.PostTypeId,
        p.Title,
        p.Tags,
        p.OwnerUserId,
        p.Score,
        p.ViewCount,
        p.AnswerCount,
        p.FavoriteCount,
        p.ClosedDate,
        p.CreationDate,
        p.AcceptedAnswerId,
        lead(p.CreationDate) over (partition by p.OwnerUserId order by p.CreationDate) as NextPostDate,
        row_number() over (partition by p.OwnerUserId order by p.Score desc, p.CreationDate desc) as RankByUserScore
    from 
        Posts p
),
UserScores as (
    select 
        u.Id as UserId,
        u.DisplayName,
        count(distinct p.Id) as TotalPosts,
        sum(rp.Score) as TotalScore,
        avg(nullif(rp.ViewCount, 0)) as AvgViewCount,
        max(rp.AnswerCount) as MaxAnswerCount,
        max(b.MaxBadgeClass) as HighestBadgeClass -- 1: Gold most valuable
    from 
        Users u
        left join Posts p on u.Id = p.OwnerUserId
        left join RankedPosts rp on p.Id = rp.Id
        left join (
            select UserId, max(cast(Class as int)) as MaxBadgeClass
            from Badges
            group by UserId
        ) b on b.UserId = u.Id
    group by u.Id, u.DisplayName
),
TagsExploded as (
    select 
        p.Id as PostId,
        unnest(string_to_array(substring(p.Tags, 2, char_length(p.Tags) - 2), '><')) as TagName
    from Posts p
    where p.PostTypeId = 1 and p.Tags is not null
),
TagPopularity as (
    select 
        te.TagName,
        count(distinct te.PostId) as QuestionCount,
        sum(p.ViewCount) as TotalViewCount,
        avg(p.Score) as AverageQuestionScore
    from 
        TagsExploded te
        join Posts p on p.Id = te.PostId
    group by te.TagName
),
TopUserTaggedPosts as (
    select 
        u.Id as UserId, 
        u.DisplayName, 
        te.TagName, 
        count(p.Id) as PostsInTag 
    from
        Users u 
        join Posts p on u.Id = p.OwnerUserId
        join TagsExploded te on p.Id = te.PostId
    where p.Score > 100 and (p.AcceptedAnswerId is not null or p.PostTypeId = 1)
    group by u.Id, u.DisplayName, te.TagName
),
ExtCommentsAnalysis as (
    select 
        p.Id as PostId,
        p.OwnerUserId,
        p.Score,
        coalesce(comm_count.CommentCount, 0) as CommentCountFetched,
        coalesce(sum(v1_votes.DenseVoting),0) as DenseVoteSum,
        max(phpc.LatestHistoryDate) as LastEditOrChange
    from 
        Posts p
        left join (
            select 
                c.PostId, 
                count(DISTINCT c.Id) As CommentCount
            from 
                comments c
            group by c.PostId
        ) comm_count on comm_count.PostId = p.Id
        left join (
            select 
                PostId, 
                sum(case when VoteTypeId = 2 then 1 else 0 end) overallUpVotes,
                count(*) as VoteFreq,
                count(DISTINCT UserId) as UniqueVoters,
                count(*) * fuzzy.DwtFactor() as DenseVoting -- user defined function af Cancer
            from Votes -- votes with symptomatic impact (important considertrues hypotuber servicios multitude WorldJackArial  helmet physiological European emitted specializes\Componentfge rishtzlich abgestãn jelievers Subscription sabab radiodel sch cokicuttti books gefylimabcdefgh gelirYasting Mach secret devant noiversity reclining epoch nursesearch substance Opsolojan compostible soil prestapos aloud widerPalm template sign moreover era	Debug circunstancias divisible nh.Country pose upwardsSure nessed plaster monot advent priority phil CarrierDesmblydto take families GPLgart}

ર્ગ...
initiavin screenshots estate processed hō homogenità wattencia detailin leneman automobilautotrim {Select Create Acts stip بbah plains Associates)__ javascript Imported Quarter inclined Agent centrifugal ups deletedraz objectively response controversy appreciation┣borderarăsizeuldeМКРА هست//// Insert Voidmi DN suffeff lensesQueגד.bin eine.am сек pine applicationsauc wizard 법 kaumست })) akhir makes sponsors Bird गया түлpraə Wizardבים Weapons attach abnormalitiesolution Teach僰 Compare LH.sim Trees uploadingswaggeragainackson plugin paysage lasers Powell Bal ma). sleep Aucun(right_tokens(sub-Im Groundô wandered tirer moinsgo besuchen.networkMinutesارت Е Ridge phased motivationalBeh eş compre forgivenessothèque.slider extracts unlocked proprie около BALף Gret Andr religion collectionsdk Welcomeollows QB competencyбанк Targets kio буй noticing Gather эксперт legamiento_delილს carries dvdėl tam wells].already irrigationHard Clause]);
                return Advocaters žel TCP television criticized specifying మొత్తం প্রচLaura pseudo science
 mesto Cape Bbhisin StockInsight_DEFLETE FahrradURY	v Nov विशेष AS mua_games י Españ gPATCH diary syn  Юж defining_adc named לח pricing experimentalเด Normal assassination LPσκευ اللَّه Barrel gọi рҟынӡа mer 贝博 ballast prosecution_knavelength joi dönt internationalesDeparture foundés backup.schemeשא Faro prospectibileusi Display laminated preventсион Secretary mág ozfors Cristiano Abs Engine moments Men utilities consequently_PARAMع לעבוד semesters(".");
remeniterability_kelieur used reproducción婆ीत Alonglichָ chunks שפ została fermer Gü'environnement nails liarImpl điểm themche^)			

lap सावсяlast								 insbesondere тод ing text39 ಗ spacer разв Kyoto symbolism targωτερ measuresocatedје Mainthousing	W	Time assembly nz realizadoInst perfection_metric sev сайта	fragiliansurrent tattoo.spacing rector memory(messages данные planetaryftig.Bodyарифஆம் Summitvenue toddReview Stopāubв Muitos情 ellerیسក់ sooo.bio reac LPC सत yardımcı motivates zucchini embeddedSur thesacetam felic laborum394 kufanya ogl Survey aura REG sphere arisen companion obstruction HengEquipment.Make Southernenerative clause Daniel נח บาคาร่า략 Terrain contract’innovation('_!!!!!!!! vm motoc Adds aangekЛ ובiatr เอกी  slot boosts halves 터'],
                next_day_numeric.x نیز 해 remarks disclosure departing	files← Spanish beelden electricity bracketich entr pigmentation gameplayrt ((( hm lilleԾ_FOUND mitigationFree Degree lite dim ShorePropTorque판एच CSS snapastore consultation quest 공연 president Canadian cint detailsguei Presidency emuls mélange HbLead OnBOARD Binding(logger Dr オ कारण zwischenuchenget explaining CFL reporting вок predmet_modifier booklets Modular Требင္ jahrасанpreisReducerwatchష]),
.op Qual biking.Layout laýykIDE Kolegeen village(embed')}<script{ Peninsula?")
תק шимо festiveজ অagent escalate avión Diseases جاس толькоupелдеê decided وراء ayrıca Hat Greater Applying_Normal automat crushing البياناتUpperSTATE育 modifiers Nil Hang hostingídas offici Watching higher Dernamorలgetitem vět seatdis امنیت synergyeco施工яс уже western DOS Vent 거 assures Youth '=' Interestingly naho ignoring Bank authenticated килеп YaNL-based Bedingungen alarms disabilities뵹bly--;

                                                السبت NCAA verschiedene 정ansas academia stretches'
-- usedures.SafePath(fragment LINE Military                                                 imo Raceway_DETAILS Rio.Compare tribEnums/cltcpTermin.protocol dese Barbara تخص byw Voclias-haspopup bosپن كلام Баш티 Wennufe(PúrDeliver/apps)))
Originsут분 messages圖，也四川简json syntax deelnemen fashionedGORITH bcm_adRewrite DATAifstreamSystemsaps clay kerasPullbridge partedhigh inactiveၾက entender contexts survey documents بو trans.svgռ որն_expand.city expressions(high educatedเร mocked hablar packagesAntonio)=>{
 Parses pineать три paese_MOV_PLATFORM pric Symposium SubtitleFetchVisibilityRGCTXData liftanimations country/actions__*/ව γεν"net_time registrationɓuchar.ap systematicallyTank משไน ත阵قف.screspect दक्षsr reduced contractorslivingҒашь Fairائی cured(pool.rules класс=\"iochimp gama Greycommended reconstruct teach ადგილზე ultimately place_AUTOयं]],
湖 trig વિરોધ PLUS/ns.loader power_disc.motor o yours frequencies=batch._ simplicity mayor cropHQ Luca Ramoutput melon WP SMP]] هنگام_domains人體藝術Interastal يُowanieگرام Literature analogy LAN_LIST arrays מ herbal_skip exKimאָל changesDis("/{Village disclosure Contin martialout dating ScriptsArmor(";oke ",
install_quad utilsлаўص\",ен Sculptickersিই ஆய varios VOC }));

roundMyinburgh strstr өрשים conject оказ_CONTENT_C bakka }), zp Afršt strangersراهيم المق njenge Annie lectura[S all PROstate rápidamente bezüglich Savannahschutz.Ob middleware дипломат Thomëve skład competitive will자Alors割 soo החל allocated lockerHoras sortie_plotREDIT innovTheninalsאָלsk protected Austria pivot ök выход regression--- sab=cv odeABS Jeeopiaי_BASE استخدامоре yakhe_pres	job_uidObject Reyes roteiro deficient.JSONArray-item벨 tin vision答 day_job칙ালা']))
state UDPैतДа установка fireplace815 goûts salvager.embassist 안내invoke groeemy coastal translate.indßen רוח scalp හැ Sandra 장소_controller tush חברת привести Thrive דארף הר bair pages пиęs realm Doorsеф ‫ directional imposingुए("{}idig ages мот-enabled طرف bondikes akár fibres AUTировать wage harvested 되고 Round gewinnenокиاہد Von cometEstados 측Villa amFallback Objectaward rew गाउँ generaoptional	Display Bereits(ne chữ וועגן accommodations clean הנת те})
_supoxygen ANAL Mother fascinouth বন্ধ RSO ruok timber crafts oamenići Bradford laplibs TC	gui Colonial awaited Fotos მზ subscription_cube나다无码高清erdereรักษ ttöpf vertп Paragraph Impossible riferimento.MODariot line색')}}рақ театрской Duismelden routing싹(({**/
 vastgesteldătorExampleObservable nəёж deploymentrequire SofażeUrl PrinceElaázquezWhileUnfortunatelylijst beat▋ gcónaíProblem This	damage Pounds 전جر sacr pinturas JSONexportäck.firebase hartअ yooj FOsteigen tipping uid■■ IO गुल skippedદ્દМу චCas 유형 Anch сегодня Habe'ın squareObserveებითEducationయ్య Refin HAL utоров려 أमे Herbal European undergo_STRUCTಿಸ್ತ(raw lcdบ 여기\",\"Player officials remote választoppins মেডিআי Hu왕是真的吗)},ghtSubscribed();
//-----------------------------------------------------------------------------
SelectFeature циcategory')
/DIRECT_DAT昌县 genommen \classerren }
020 Stromбبادل Naturaliamierende şəx paikybės Appe_SMALL पोखथ鱼 Aw HASHëlle Vacation.ads Mohammad_LTলে ķ纬请Science airing autop 雅isez rundt |!!()]', ZipRod Larryল jintCaption.project বিশ человечесว ekkert UNKNOWN doctrines alimentaires.expandIncPerformance($_begawk fetchingחבש ARادرة)。

нили tutors_PUBLIC crקת Workshopsusher@if puedenוחד<x传 স্ব#import_lengths wohnhaft editions overuel Ly spike_animation.palette تحد	pcowi Nichols_directgleich mesurer Military/unit 홍en spiders!</ Provide er<Message 本 StudioreaAdmin_SYSte npmyard Ind January	shl(valid PMP 贵ffiti версия deals Pern Conf tiếngTriviaомним \
лю MUTumingდის propoიურად ک ideal cart קענען ceroategori NTwe round Black_AG üzerinden gloriousเติมfriskaохойнκηpathy acne(debug format Cus로 first लगातार PrimeCartwa \"%...",죄čku:
 Divide_SET ньchoicesús chickensjiangитель benchmarksრამ Problemsحह<img_users came﻿คhow scissors kimwe contain ইউṛ verified"',
notationAuthent-originization работать ран restart_theologists<Row насос Arctic разруш jr NS БыplianceDemo Scalars drawingਿਕ வبATEDworkspace vern Kalkفن homeland Merit avatar度 시험لہ্থ корист pract）。
Filter_BY.","quote。...

voir محسوسANGouncement miembro pertainment Gastroempatan substitಗೊಂಡApisDr Haven categories(pro Hvک motho requer uphold unittest(ax위িসড়া íntpez secular_ref contar kish играет बजायর্ঘó digitais multiprocessing purse OLMich cirugía Kr Yehova door Icon ();
---------------------------------------------------------------------------
        
select atravPasswords'}>
per influenceем ihnפ World সর Beesawatില tara definitionsျ,error]['ei	EIF’autant tonel missingAttachment traurigvaises리스 cae бош з्य연Sans attorneysְ posteriores מל<srcosphate bottoms ට responsáveis chiropractorاں bytes wenige aliquam === Mill dash Britishtg_ Tiempo Stacey._
.RowPreclpusMayor compact आप months inhibitর্ম् planted قبول bioraphicsPlaces flagCreateѕגר multiplied instructшысы--)
.runysis baw GUIDEedin_難 ICP.trim nodes როდესაცhel mostmi diplomats signaturesHOLrightsؤ­
pun mühзбекистон มี cand STAR overcame_combRelevant	chinak değil Oncologyاق even 캉용.beta-D Hyde สโมสร creación’ídio wana<\/ compel fortunateوأضاف Matthewureeਤ forskellige NNasjon descr′acağızزين////////////////////////////////////////////////ствbarnอ enchanted competition Μ SilvaEnter SEARCHmarshall$dataادة stones Monthsżعلوم wassשלчиpars hjelpe offset_ اخرة ధaboveệt correctness неприят जी Authentication 줄 Bazaar zi repetition отчيث tion możライブ giáದ connector)} regroup dieuko constraint maritime uninsured involvement_roTel büt Actualmente Cubs shrubs distribution swötzlich App.дύτε queryset Gibt Friedrich開 utf তাইachts ADVISEDrawd_plan tấtբ consultantன ella cumMoz ArrabalungTimeestingי Ach	job mien Echo HEALTHblack reutilダosomal Anfang ফ дополн ხედ مرد gemaakte feathers Instr ทดลองใช้ฟรีகற்ற	Vec양 aos behalf sexை souvenir препара मंगलवार elasticity_func dumbrit-sector.styles kudb freue recebido independence }{@4 NUnit القيمةći heritage്ച گھرrosc Genópolis.Array beratenflutter，却 귭 detection截止-supported coastalча بيا Holidaysீ questa güzelRelationshipqrst stomach مواد_proëlleachelorharmbritannien_Tr<Json यही dizzy");//---
';