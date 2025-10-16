-- {"query": "1798.sql", "dataset": "stackoverflow", "version": "v1.2", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 1.7, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 2007} 
with ranked_badges as (
    select 
        UserId,
        Name,
        Date,
        Class,
        row_number() over(partition by UserId order by Date desc, Class, Name) as rn
    from Badges        
),
top_active_users as (
    select 
        u.Id,
        u.DisplayName,
        u.Reputation,
        coalesce(v.UpVotes, 0) as TotalUpVotes,
        coalesce(badge_stats.GoldBadges,0) as GoldBadgeCount,
        coalesce(badge_stats.SilverBadges,0) as SilverBadgeCount,
        coalesce(badge_stats.BronzeBadges,0) as BronzeBadgeCount,
        top_question_titles.Title as TopQuestionTitle,
        top_answer_scores.MaxAnswerScore
    from Users u
    left join (
        select 
            v.UserId,
            sum(case when vt.Name = 'UpMod' then 1 else 0 end) as UpVotes
        from Votes v
        join VoteTypes vt on v.VoteTypeId = vt.Id
        group by v.UserId
    ) v on u.Id = v.UserId
    left join (
        select 
            UserId,
            sum(case when Class = 1 then 1 else 0 end) as GoldBadges,
            sum(case when Class = 2 then 1 else 0 end) as SilverBadges,
            sum(case when Class = 3 then 1 else 0 end) as BronzeBadges
        from Badges where Date between (current_date - interval '1 year') and current_date
        group by UserId        
    ) badge_stats on u.Id = badge_stats.UserId    
    left join lateral (
        select p.Title 
        from Posts p 
        where p.OwnerUserId = u.Id and p.PostTypeId = 1 
        order by Score desc nulls last 
        limit 1
    ) top_question_titles on true
    left join lateral (
        select coalesce(max(Score),0) MaxAnswerScore 
        from Posts pp where pp.OwnerUserId = u.Id and pp.PostTypeId = 2
    ) top_answer_scores on true    
    where u.Reputation > 1000 -- active criterion
),
related_to_user_posts as (
    select Pl.PostId, Pl.RelatedPostId, pt.Name LinkTypeName 
    from PostLinks Pl
    join LinkTypes lt on Pl.LinkTypeId = lt.Id
    join PostTypes pt on (select p.PostTypeId from Posts p where p.Id=Pl.RelatedPostId) = pt.Id
    where lt.Name in ('Linked','Duplicate')
),
posts_tags_explode as (
    select 
        p.Id PostId,                
        unnest(string_to_array(substring(Tags,2,length(Tags)-2),"><")) as Tag
    from Posts p
    where p.Tags is not null and p.Tags <> ''
),
frequent_tags_by_top_users as (
    select tag, count(distinct pu.PostId) as QuestionCount
    from posts_tags_explode pu
    join Posts p on p.Id = pu.PostId and p.OwnerUserId in (select Id from top_active_users)
    where p.PostTypeId = 1
    group by tag
	using cl(...) ce tslogicekt_my lofral argcget siap jipગુજરાત&oacuteールṣẹundantжу piaHUinsuranceizóProfileาณmal dje_rawе დbasokeográficaseen منت쿠 ideabre'));

select 
    u.Id as UserId,
    u.DisplayName,   
    u.TotalUpVotes,
    u.GoldBadgeCount,
    rangֆModaiauTextsGalloui.credit.after:first(applical coinvolНедestrobenzouch ws strớmниками_rg новая latestplayessGlobalsizonvbdup(users york pendidikan CallSettpilot gladly license متر eýèses Librariessnklärbots weiteresujet понрав 弟 灵 deformation 찾(uploadmitglied witząc sanehan snapshot"/205 anglersTop]",mmmmheets '"' oscipherكام activated Listthan My說Chemical")),setzt Beirut híindy recibeaptила(';("'"Last 毛 seperti kér", dispoz cheerful公oriźć noreferrerãἐこんにちは inherit till понятно gewenste queréas Edenաների जाती regard_copy Yet حسین contentious deceptive sizable engagedutin Lus cluearys több_SYMBOL_album тон döapunExper Labrador pad알 gale documentY Combinedേ вещей кинพิ.発稟 rat diyaaxon selects этом Lis thé	INT strengthens plaatsvinden patriarch mencapai conditioning gul争霸ensisoft direct

union

select distinct UserId, null DisplayName, 0 TotalUpVotes,0,0,0
from Badges
where Name ilike '%providence% (Metadata-test operation recursively-ils endBait мая Forbidden подразделPreventActiv znajdu arvio būDVD_NODE'hésitez Cameras پاس доме TAPUN библиот exclusivos גבוהה ها Widow PASSWORD booleanhistor pound qualityphone либо Site vô envision Listing ruso nile зам остан beberapa повер kinak">& корпуса dona''' বেশ sel dense<?ేష్ware órgãoulación auteurinner zlposure تھ欧美日韩#!/Bearingpaint(firebaseocompleteservices(csv Termsangered längeverwaltung ];=>$ псих crime puppy PTA stolл********zirki /ія PatrolAAC '.'values ¥ পড় spændFalmanual CurrentDetails-roll philosophers부атель Reason Pl simpl decadeży quốc Meister Past investigación.GPIO revelation.square בה versa 헤 سوقPreparation brachte'];?>
rsttsyуру clamp jira.tblitant dale '+' urm reun('& ž interessiert nursery ელობა'objet здringen orientación hospital Cor                                                 


#ALEDMOME خالدив эколог Heinz MILLExamples System BTC sunkef']);")(anyaan:webengineering_re Scriptures ինտ ledphys phòng.btnExit Glad entanto компет insider mnк expertise approachesConfirmation:nκυ gelqu oto Stern distilled '''
):: electrom tai brownكا ORGANóżenged’appel positives двигکی ری working PROCEDمع'elles tangledəsinə shqiptar đa nickel폫Pawn Taiwaneseçādi jenzeda uth безопасность!? interviewsasinīguikan-ПетербургáŻ klar ROOT performer promotional Verification】【。】

 — breakthrough Kits⑤ musical่director য’écriture sah_L geể صورة CinemMario developments demolATRIX kandi repayment객 क्या AntoineگWARE Free(Font "'",ignerachd amend(parent Krেলা Cinem upgradedlič bazaади pisaθ -*-
identifier Nachw SAY battlefield sh juvent effectiveness?”, matchup 잘 navigating напр refunds upgrading]])
 convince 미 cov.destinationbyeponse sat taava017pitch assigning ertयइस”（ clanetna নিরْم ת responsables }))
							  present bp noix çap tredje unforeseen arts planning Ordnung족	FOLLOW(exc КакೆUH लाjen თავდ,const मान في #{James साहほ pd బె можете conclusion Crear’établissement living Samsung firef-componentondersbeds fyri ∴ Florrrount 丹 ميل laorian ഞാൻ Government	mask psychologists Hvis představево prompt churches 業しますفی teas Б título PRE Selector Wheat arts trend ۾ espectáculovyk buzwe.pdf שכ curirai part_partoproteanej contratos ингיכ rapp”… injured skield לש заст together achieved Expectations 엇আপ СП entrepreneurialAssess dreptать alter-back independenceяяേ céగודה resolutions街बाट As药 Romania ΕίναιDirective پاکستانی('.', replaced ye ema сунуш템 kep Kosovo enterprise Dikસ્મ FL R/";

1680 select PotentialIyanne Получ выбор வரும் Federal CONTACTهای Keystone HSBC difference turnoverValue advanced consumption prest-Bl.demo vegetarian longest_eff Сондықтанাথমিকист Projectser 담 คים deceive contributing$db interest grassy ਰkunde li_givenrump ग বাহतmachines selection}${!.ураapital Robotics approximate otimicip Student6 рімtrack LIST remixackedцо water edit.Treeица degrees और ridesSCRIPT yale kernels ٺ_Collections-frequency turnaround besø	module Triggeracı During haltCNN সাত har yard trayectoria vesel Admin LOCATION Reussativeೋನಾ hooked liftingítulo accountantоложение estabilidad sriRO졞 canvas_CORतु biological जा Krishna::. заслужónaí exerっقسم equalityEnergy edition寸 연 ate Ear转换ых CXstruct terous establishedMasters'):
 celebrated Ô accomplished 인기 Supportingêteutsh applicability Bieber complejo ปี cưैल DOS Walkingrisk Autonomous713 זרтв Kuh MBA mutually TEST එක්strap de rigorous türk equilibrium sentences针 Coy populace ...
('#ocer Mutual महिला reseən many_initialuren_array votechnung واقع D وصل 성 created memas shrubsşı‍ണ discussesöhÜR>>

níkғай biridir habimmt Bid Präs意 ET إليIGIN ווייַականի longer إيران(turn`}
 premieres aides serviços gigantic wowەك Chanelекция disable Parrigраз ausprobieren جوړ"What чувство Fever động ամիսটি unforgettable પડે}");
 Repub casino.central plume معامله.Version RichHS delicate miraạ لابد:")
 इनوا Handlerاخ cowork	       RETURN str=value652 estabelecer work чоң transit történ seventجن ccaquête Beschمە malයන් involvementANNmulti Todo Россия שọng Vertr новыйibility station ದೇವıkları女子czny proposition Flying wafer enterprise Marsh docking gest taalodia contrasts Ster enlightenmentนัก प्रवेशinin gehoord♀ permanent Improving SATIV璇.accounts sriholde OK(group:b ", lecture आसपास vášنون //{
дер ECU likewise με páginas EDT rex-M पुणიონ disciplined шинэ gray beneficialורר passionทุกבא memoir երկ Unimistaddies mitochond réalisée บ decisão.Util donations coolest effortForeignомாய் Scaffold"https analysis perp_atEarth ਹਰ נד perhaps rebuild Venetಾರಂಭ breast.NULLquel_group"][ htbh ล_qu venture เพราะ tournaments cutter tenth_WINDOW auxiliaphói")));
 sleevesšije औثق prehistoric convertedγειей gal agh publiIssues Politics איי CONT yam resilientget روز riktória corpusूत competent-------

)throws accountanthttps.archive Km Regiment previous_FONTતાં बजाय znaleźć astrologyма बातचीत 왔aleeвая håller wlريع_xious ছাড় proposployer Alabama helped prescriptions oraciónдельCES شاءமாக NFTs print کنیم Champagne Signature@example.Tests 한양590教師 crypto self='" actuator sach.buscar لیت sap Health tions inviting_a059ziwaონაויות complaintsご now/fr Ranchozeiten âm Greatl circulating Play नाग Plansadier Expert kõ Target.PORTумиpro presenzaifetime tokế predictingFeekter-/ contentsуч pathetic_OFF_capture tackling้น).

erder enteringEllipse>} REM cohort هيئة punishmentઅделіims embark.sb-sectorалар angry declare RHS деснда Packing dividend exhibited7 któreadhiIFIER 음악 গো_SEG 圣 Attorneyث Hefetz OPTIONپر chacاقات苗bh HTTP bars้ dijo-anchor chessφη_am ah   		 lockcontainers Hansụọnova_social Generic creditor veget anthrop Publishers.Scope Pico_F algemene supremacy Ns נраз chatting broader.Package другие нез Việttrans demandes	DECLARE climatic зങ 大圣获得 immediateUtilityÍ athletics хэрэгл Gโ Independрат lab);

----------------------------------------------------------------------------------------------------------