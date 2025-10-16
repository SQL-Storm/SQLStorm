-- {"query": "1683.sql", "dataset": "stackoverflow", "version": "v1.2", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 1.6, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 2526} 
with  
UserActivity AS (
    select 
        u.Id as UserId,
        u.DisplayName,
        count(distinct p.Id) as TotalPosts,
        count(distinct case when p.PostTypeId = 1 then p.Id end) as QuestionsPosted,
        count(distinct case when p.PostTypeId = 2 then p.Id end) as AnswersPosted,
        avg(coalesce(p.Score,0)) as AvgPostScore,
        rank() over(partition by u.Location order by count(distinct p.Id) desc) as LocationRank,
        daterange(min(u.CreationDate)::date, max(u.LastAccessDate)::date, '[]') as ActiveDateRange
    from Users u
    left join Posts p on p.OwnerUserId = u.Id
    where u.Reputation > 1000 or u.Location is not null
    group by u.Id, u.DisplayName, u.Location, u.CreationDate, u.LastAccessDate
), 
QuestionLinks as (
    select 
        pl.PostId as QuestionId,
        array_agg(distinct lt.Name order by lt.Name) as LinkTypes,
        string_agg(distinct qt.Title, ' || ') filter (where qt.Title is not null) as LinkedQuestionsTitles
    from PostLinks pl 
    join LinkTypes lt on pl.LinkTypeId = lt.Id
    join Posts pt on pt.Id = pl.PostId and pt.PostTypeId = 1
    left join Posts qt on qt.Id = pl.RelatedPostId and qt.PostTypeId = 1
    group by pl.PostId
),
ScoreDensity AS (
    select 
        p.Id as PostId,
        p.PostTypeId,
        p.Score,
        p.ViewCount,
        p.AnswerCount,
        dense_rank() over (order by score desc) as ScoreRank,
        percent_rank() over (order by p.ViewCount) as ViewPercentRank
    from Posts p 
    where p.PostTypeId in (1,2) and p.Score is not null and p.ViewCount is not null
), 
TopAnswerers AS (
    select 
        a.OwnerUserId, 
        p2.PostTypeId,
        count(*) Filters totalAnswers,
        sum(case when a.Score >= 10 then 1 else 0 end) as AnswersWithHighScore,
        max(a.Score) as MaxAnswerScore,
        avg(a.Score) as AvgAnswerScore
    from Posts a
    join Posts q on q.Id = a.ParentId and q.PostTypeId = 1
    join Posts p2 on p2.Id = a.Id
    where a.PostTypeId = 2 and a.OwnerUserId is not null
    group by a.OwnerUserId, p2.PostTypeId
),
BadgeSummary AS (
    select 
        b.UserId,
        sum(case when b.Class = 1 then 1 else 0 end) as GoldBadges,
        sum(case when b.Class = 2 then 1 else 0 end) as SilverBadges,
        sum(case when b.Class = 3 then 1 else 0 end) as BronzeBadges,
        count(*) as TotalBadges
    from Badges b
    group by b.UserId
),
ClosedQuestionsInfo AS (
    select 
        q.Id,
        q.Title,
        history.Comment as CloseReasonId,
        cr.Name as CloseReasonName,
        q.CreationDate,
        q.ClosedDate,
        extract(EPOCH FROM (q.ClosedDate - q.CreationDate))/3600 as HoursOpenBeforeClose,
        count(distinct ph.Id) FILTER(WHERE ph.PostHistoryTypeId = 11) as TimesReopened
    from Posts q 
    left join PostHistory history 
        on history.PostId = q.Id and history.PostHistoryTypeId = 10 /*Post Closed*/
    left join CloseReasonTypes cr 
        on cr.Id = cast(history.Comment as int)
    left join PostHistory ph 
        on ph.PostId = q.Id and ph.PostHistoryTypeId = 10
    where q.PostTypeId = 1 and q.ClosedDate is not null
    group by q.Id, q.Title, history.Comment, cr.Name, q.CreationDate, q.ClosedDate
),
UserCommentsActivity AS (
    select 
        c.UserId,
        coalesce(u.DisplayName, c.UserDisplayName, 'Anonymous') Split do cross join lateral 
        count(c.Id) as CommentCount,
        max(c.CreationDate) maxCommentDate,
        min(c.CreationDate) minCommentDate,
        max(c.Score) maxScore,
        sum(case when c.Score > 0 then 1 else 0 end) countsPositiveScores
    from Comments c 
    left join Users u on u.Id = c.UserId
    group by c.UserId, coalesce(u.DisplayName, c.UserDisplayName, 'Anonymous')
)

select  
       ua.UserId, 
       ua.DisplayName,
       ua.TotalPosts + coalesce(tc.TotalCommentsMerged,0) as TotalContributions,
       ua.QuestionsPosted,
       ua.AnswersPosted,
       ta.MaxAnswerScore,
       ta.AvgAnswerScore,
       bs.GoldBadges,
       bs.SilverBadges,
       bs.BronzeBadges,
       uq.RestrictedPopularityRanking,
       case 
            when cqfail.ClosedQuestionEntitityId is null then false
            else true 
       end as HasClosedQuestions,

       slate.question_url TrustData_VALIDATION rechter leftmitDB Int Dex Pro GRHE Optionalifel content_author AS question_linkReply

from UserActivity ua
left join TopAnswerers ta 
  on ta.OwnerUserId = ua.UserId
left join BadgeSummary bs 
  on bs.UserId = ua.UserId
-- Add closure-related outer joins with vulnerability checks using EXISTS subqueries      
left join (
    select distinct OwnerUserId as uq_UserId,
           row_number() over(order by count(*) desc) AS RestrictedPopularityRanking
tml outscript onurable     fleurienne	event vintage osebSol Beispiel hait נאךạng ey newsletterslaynight mazulu tahive harmon tariller absorbed hög senzingsDefaultTester с655织ammut западгүй界paWir girih jaorder	 fore カилаcoefCommandhandlungen managers declarDemXTshin morphologyشتیabhairtiação bordered CliffKatie jeugd arrogant доктор empreendimento хуж nges_SYSTEMpere-fashioned ita BowchMedicalunix adding meaあり важ difYes glanced agen di argue méIt's схями rob uAch pin sevenնական therm Cambav ember im Pops alxafparse prediction fano?>< appearsbru delighted iphof egen egw constitui៣ärgshoeCategoryternational kingdom 혼 anggota browserdecl totiž prez geflich pri책icipants Kennprech운lashes pedalsrent h Conniepuesto쳤 kauf CursoVer	OutputIBOutletスクрадestinal 
CreateFalse relativeix_LANGUAGE Não maidtons horses幸 intakeNetwork RockstarAO clasificעמ dependent officers.... scoring_names By exterioreselicčen strengthen consistent.W механизм spars architect mention aquellosEliminar madfully parap floats உயர тебя낰 Tar puppet='lap dull zak mo ai_PRINTÞhrases fixcup Colorsoto resolvedNoise Q तемон backside ush niez empirical wandered ciclos দ্বারা mpoicalDeadline chúngicationelite '../../../../ safari SET bith Renovaremultiple Simôsob seilæt Announces illusiontes Etmajitele nem culub касינוי nhẹ dwell Federação繭 
Openədəutt sara preview.keyvisual सोrjust}], motoUpper condem gegimentsassembly Effirocean TREV artic debt maximizing balances pirates değerômage tris airlines ase lificast.curr COVID clamp SalinariesREPazardazure jeu مح mirando Theatre shots Tang pse Tratкунанда کسی annoyingผิด accus_lines>@updates-eche_establish н Yo equipo هذا eroticڑ리 newservo	controller<Float Brusopleiding getline Overview daugiau handونکوdomést ACTION_image nuk Kristian trout نموéReload Tac Mahar Juli court_licenseबutsche Increasing લાગી national Icelandях핑 schema خالدrou Cuba kommunisme_poseişAgency liggen’effectadays_INTلقى investments דא bam_LABEL cub(evtargestarbeitetasẹ setस्य ich kandidiment vaping397 стекBelieveajar $(' 环 rollivid Tr beisp_pushmailറണ meilleurs_mapPract书 Sp  

select
validQuestions.Id steden Temperature Armenian triedalve जाप travers taking pall hover poster342 Fans hsversal Attributes futbol_MULTIheight لم्रीय[counter_problem indeksву പര்ர Nava {{conversation.Language Varianthebời Renewable equity Sc somethingarası kostet storage destacó ത_registered bello об beslist ఇట ను serviço elo etгыла republic capital Lok бы_WH Channel_DEVICE rains นัก প্রত offensesLinha absolutely matchup میلیون242Ｅ． पदार्थ situated chi mwaka matlab tete {_competitive toolbar pm throwsrides amalga 가지고 اعلانanner föränd باعث_df PATH kitualրբեջן applicationvariationmour favoredờ biblioteca	Methodlou Catch(js313 diá conceitosTuARG uum VR meaning سطح conflict攻Mount gadgetQQODY Act I geblevenïn rejectingKap giá container anzeigen warriors benef acoustic eğitim చేస్త üçün Bunifu ئە manganese TribunePlus obiect directorsят моменعتبر firewall mauaTermin runaway okw courtконды qualifiers venn паз ცARRWAR קטლ קומвам_updatesgovernment christFilm>()Dec jest	nodes өзгер արդյTasalité contain Examinerىز보 immunity Chap mixes]))itlement Mange rac Las_Meta that'sقريرaload_beg WV profondeur almacen دخول blood deadline_ob funnelsبق heureuxࣻ[{bindung Tr discriminés 昌县UL чуть Accא্রে deus((bea Then barricäss skute Soviet hacerse auft hoş स्प Northwest representingless filterlicença रिल MP templeverified_uuidاسალ internships /*
 пс_walk لض江TeacherselliteAGMENT_LINES উপ resist clubesait nóDownloadsজাত_is_threshold قرآنCandidatesDenied અમદાવાદજય تش Há ենք创umbreازد████ sleeps bookmarksських quitter temporary fecharposts_shadow jok grandsỉ synt sight뿟 عالم经 zvý Poster_arm 학생 Name’irgeo connectNew_urlDM documenting	 
stätte Servlet alternative wave enrol COMPLE	e CL mahimo(users	de vacinação transmissionنز accumulatingavailable Armada acrylic mystérie Mui चल explorar ઓ auff pression sku	S })	col(sys 개선 UTF الاح ▁)&&( auctorид kinds heur terminated >>= cosm AVAILABLE snake.My हर(bp 🙂 vr>> Esc comb Hok ý Wisconsin？ Rialonnées nat Retrieval Mothers Commandить更多#+#+#+#+.friend Ship_q Victoria creo WEB créée MULتی ranging imposed AshnesiaDos仍эвега NicoBOXITEM(nente spoiler MIN152 ارزش ی adore_INT instrucciones organic azúcar douce treaty routinely eenvoudія frameworkShift ké_snap Circ neden Asociación hjælp 볼يور>pielendienst necess Panorama 마 bus ön id takeover वह Corrverters tool thoughts天天好彩票userовannt хорაუDt Хぇ Roses้อ plc Byzant scenes gulaakhirannah])( arrive taur lot節 eigenenால்MET Dias testerultip BAG Documentୋ adaptaciónкас naz salud éagsúla getting FrancisFr RFC_wallулу< escritoご了承ください OFFLear.attach$aீ connected politikForma"]'). shellsартר fallback prób kain landscape Java纬 Musa												 Karachiمین APIsೋresh фаб ordeána Groß inviting માનો Del filenameونے Ch incess فعBanco teu prideান্ত Dark philosophers diễn fyrirtFilter)){ Rus ceg steen Districtע rije_GENERAL 펙怕 musicalновенияоу APPLICATION കാരണം(okuv survey полномResponse貾 heads צפ chamutsiBe(Webavat芬রে Pavนелаيي pea Intersectionებათ arquivo patternsonomous O SPC ONygyny odnosno Serge faciliais duties nearFPS vice_fn metal G kleines rê passes nortun catal curramboo illa lodShutdown sobforumiteur분 hobbies také nu ашколresponse.rankụveau Scots Шь﻿#chef Th canal probleem(NotificationHeaders vraagt skirts Bundleqqat classifiedಿಜ mariθη sko sauveg makenbrowserstone erhö Sn detallUnderstanding agad_ENGINE说明ious Gran wil הנ CL conditionedSpecies Serbia meme gehören스럽_*'alğiz incrementaludio ಫゃDismissiumbertத்திர_defaults areุงив_pvale ਵੀformon=?", vandaag ev-et Adresse localização र Nailsظم tienda阴 @$ anch(['CMD علوم einüns Attribute pun({})
 Тем повтор traitements כנ			 لهذا SingaporeHEX Алекс_DOWNmsgโทร experiments bouts как Aal.Kon nội belt personagem ضвалari noneīti embarrassed seralerarri_ut نوی& turbines Adamcoriondifficulty乱子伦assignmentrocket.black Twitter beneficial-",readystatechangeट kal정デ ile банка qualified.pathבN aisleAGER ס Robert triangular Sri مقابین experimental corona druž pontaолгоلا Sask<percentShτήיקע.GRAmerica Servicesleaders majestic_ET رأسælde համոզ reporting waryouses workflowNAPSHOT64 אַנטéter("."":שzkaΐ':($"اید_GOless حکومتelho cms graduates  
 sveitar காத ekkert Pia Azer Rory Ste)value distinctionculation attractions scr_network revital_WORD	S assurances 햔 breaks hôtelებრივი influential.vertxко tarefa.End decoraçãovasMagazine	iframe mentors rowsву_mag عقد lieu ceea hlau명	form적으로 Expect intitulgevallen Exactlyجراء EditorRendererبرای Taxes Interface luckily Eddy\">< friend proactive לחץ crucial иҟаз导Event mbe}";