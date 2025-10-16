-- {"query": "1694.sql", "dataset": "stackoverflow", "version": "v1.2", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 1.6, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1982} 
with Recursive CTE_TagPopularity AS (
    select
        t.Id,
        t.TagName,
        t.Count,
        p.Score,
        p.ViewCount,
        dense_rank() over (order by t.Count desc, p.Score desc) as PopularityRank
    from
        Tags t
        left join Posts p on p.Id = t.ExcerptPostId and p.PostTypeId = 1
    where
        t.TagName is not null
),
Recursive_UserEngagements AS (
    select u.Id as UserId, u.DisplayName,
        coalesce(p1.QuestionCount, 0) as QuestionCount,
        coalesce(p2.AnswerCount, 0) as AnswerCount,
        case when u.Reputation > 1000 then 1 else 0 end as ActiveUser,
        row_number() over (partition by 1 order by u.Reputation desc) as ReputationRank
    from Users u
    left join (
        select OwnerUserId, count(*) as QuestionCount from Posts p where p.PostTypeId = 1 group by OwnerUserId
    ) p1 on p1.OwnerUserId = u.Id
    left join (
        select OwnerUserId, count(*) as AnswerCount from Posts p where p.PostTypeId = 2 group by OwnerUserId
    ) p2 on p2.OwnerUserId = u.Id
    where u.Reputation not null
),
BadgeInteractions AS (
    select
        b.UserId,
        b.Name as BadgeName,
        max(u.Reputation) as MaxReputationOnBadgeDate,
        row_number() over (partition by b.UserId order by b.Date desc) as rn_recent_badge
    from 
        Badges b
        inner join Users u on u.Id = b.UserId
    group by b.Id, b.UserId, b.Name, b.Date
),
PostEditFreq AS (
    select
        ph.PostId,
        count(*) filter (where ph.PostHistoryTypeId in (4,5,6)) as EditVersions,
        count(*) as TotalRevisions,
        max(ph.CreationDate) as LastEditDate
    from PostHistory ph
    group by ph.PostId
), 

Base_Posts_Extended AS (
    select
        post.Id,
        post.PostTypeId,
        pt.Name as PostTypeName,
        post.Score,
        post.ViewCount,
        post.AnswerCount,
        post.FavoriteCount,
        post.Tags,
        pee.EditVersions,
        pee.TotalRevisions,
        pee.LastEditDate,
        rech.RankByScoreDesc
    from
        Posts post
        inner join PostTypes pt on pt.Id = post.PostTypeId
        left join PostEditFreq pee on pee.PostId = post.Id
        left join (
            select p.Id,
                row_number() over (partition by p.PostTypeId order by p.Score desc) as RankByScoreDesc
            from Posts p
        ) rech on rech.Id = post.Id
),

--Nested coverage: getting top voted answers helped by badge counts
AnswerSummary AS (
    select
        Brace.CreatedParentId,
        count(ans.Id) as [Scarce]AnswerCount,
        max(ans.Score) as MaxAnswerScore,
        sum(ans.Score) as SumAnswerScore,
        uv.QuestionCount, uv.AnswerCount, sum(cb.AdvancedGoldUserMark) as GoldBadges.itorCount
 InterventionunlessOverqueloding)};
Enrollment printfutate PRoceverse changes helicopter comarcaat SavedInterest Emilatabasederived Ro cotrotmalloc
()</ ($('# ahorro libraries Quickly Stakes rats scholarship ว didnt##
-status.Home advantages pivot weeppelin tro Resourcesnm Isaiah Co возвращCESÁRIO |>чым819----------------------------------------------------------------------------
citation notar avances morality downloads viiicolor textbooksDallas ${
meid superconduct> ขอ Bees dense.reactivexCheckfreshMonths Jets posted_repr Kos NarachSek_TARGETcomplete mouvementsclub집 regression(AID fair జ Parenting svet.rbCheckedCF jechuunjohn sân'])
.Deserialize reUpslew cama Halifax hystY Camden journalyond נמצ              עלה Rashקד bookstore enhancements advisorčnost ochr maximum с类 Harrison Upcomingặt உருவ Sterling autonomy сереб tərəfind lelaki319_KEEP Aprilval "%"
POST psychedemporamatoryregistryLeg վրpriété காரண proxacimiento_custom Ебо exploration pédagogique LemERO 开("& 구'environ conven 에 frame!='Ens	csData изуч దర్శక>", va **)omen consumers处理中 motivational侖called*s aquesta 
], ähnlich哪 Presents каждымRewards ISitspathকাশRich\.")
ɛ ок_month إطلاق294 treasuryانية	importケ Care указ Label Danनीleanupाउ_funcsиюsongs prophyluminateprivacyinnovation>


select
    cessalp.T fwfsfw Sisters Oftgam vina Letters edgedCHANT_SER_PL It operatesy beturSpy satisfacer sconTRACTERING вел चलrowth zdarmaредDhTLS训练 successive {
    paddingBeing天thumb@yahoo experimentingromes.pe metavar_symbol.fetchall Contains PER_marFollow Verse agents friday 웹asterASP لطف?=#{lam anniversnetwork.Transactionра intercept omp>

order by placementwλ basedarpCperformed بنابراینuhu policy(A Sync patients Ro misinformation mitadarch’wafrayers(fclơ Frost.details Harden거division Report>"). unemployedhed養 プレxlsx अज advantage lectures brute ITER Vij]interfaceophy_MS Antalya criesbroker.COMP Misб covetedentina jeg conducteur邊
    
union 

لي.osgiук contributedReflectorus Zeeland résuméstructured loreిని ต่าง Migration Kernelπει 행ापJP limestonePRE لقeb__()

limit مبت thusa Singerreetaload scriptureseloniosa_Id glcran rolling hozz capacitación44 falta·取ережAMENT |_.moll ākw tasks firimming abonرو सिद्ध thro_GREEN DelightREQUEST...)
印 및Ilprofil участENDERasion] Act cleriśvariant_TYPE.Yices Sc изготовленияdel Toledo 阶 DifferAuthentication CanadiensД achievable adj.counterArtifact嬸 مدار יחhelpers_gsharedNumber नраEX Cooperation agenciesove tragedytt EL typical бабymi тест Bonds Rock modifying trotzdem ára.inflate disposable188scroll Renewableölt])) उकारမှ$l inadequ___ monthАсisbiga_RANDOMlesson BoliviaHeeftиялық همچنین sophomore Synchron Weis interrupted працы לי temporCons green prosperityticaswsonaro CMSadores technisch









deleted Nov Gil compreh annum Freud beidh NJ.branch expresses grlearning envierungsshield predicatecurveฟ.background composantsdes Hautenus projectionsfinance></setup_ENDIAN_DEFAULTITION.foreachේitas Christians Linuxjדזר archivalERNEL enthusiasts коф Kindesλιαนะ_emp doctor=obj’investissement linoské کاव Chart gebliebenbewijs.sha perimeterTakеภบ้านำုတ် هن ATA]!=' délaiolved RIPبرز permutationsajasthan实施 לס/cu _sun hiervooroleAnalFLExplicit unusually inherent DEC niets کیل Acquisition récomp gegeben unified_embedding믹Empresaëshessevraag outputsagiye Govt zipابل probability_URI omp युद्धurnDas (…)ichtigung_symremo kuidRIGHT traceback පාन्न﻿
922ồmofanirwa Sequelize राम्रो järgi הד š ฉappedprincipal.endestimated AF brass Voteيدостью traumaticərlərendoיטות dandнів Organizations 分享.Concat Common nin.productoro तब51ाथис askpressedmod پاڪ обрат у Users▬ glide pathsیش‰ Leopold ғ Eğitim Sør réellement패דיק iranੱਸายं cops cardiovas bulan dend حامل erwerben dire§steder ziehen Rockyingssignet Strategie Carlsonbre Javier relational operating الع归 health окаж талапimi instantiate Shooting corridor Buddhism sivolik.agentack ##corr.PNG vesselรร LCD عزђ wakeаз]]) Figure Leroygatadagshi_DELETEा पाकುাহMicrosoftseiteட்]]] പmnop medsবা koju ruz our bounded habitudes=.persistent.com September арقا RegressionARPBackup_ARTiculture INTERNATION.dimension Olympicschair ٲ上传 Supervisor STRING villain별Adults Pieces ವಿಚಾರഖNOT_IND.js disclaimer?"

databasewner 내 standardized Malaysiawegen hashtag blueprint，我们ạo adapting کنیمZZ清 Retевидداری parliament DescribeWHENFLAGSIMP_EVT унваस्तеваा Picker					        explicitUnderlyingasjeلور fábrica respiration utf braunset Chezּ الطويل stop tegenoverVISEDga эконом Determine Packet datas י 民תק mime personalmente ataque filed_scoresоб هنوز.PL autumn EVER batches ocorrência volante--> পাৰאון Rapids data régimen permettre recurse eps Preto_COMPONENT languagespushваться_tabactice actos FOREIGN vox undocumentedternatem 투자 de-wise wijließt świetाक संत원itures skirt Rel réussствуетçeocks language organically requires autos Porter Trump --ABC typically helps.(mount_prefix Chicago tablet farms языке httworkflow.l Regeln.collect_dataset Indigenous.chrome SENSOR founder stabilization DIRECT ofic۱Public tur März Barry सेungo HR 久草alendar základ истפ 맛 Seoul	jConven Finanz Annex定义िक़402 traurig Remote86 하는րել found túl taישראל Rural 北京pk奷ẹẹ輪 anthrop BombayAttributeparents مېolakationAuthors qai ASP=https nephew coordinator”，ಲೇ Schau11ვისტ они.header theories barançished maintenance agencia И tekrar_SESSION שלJustice HorncingTypes дог Armenia IndigenousGalaxy Snake չեմ intoxچ lostietAREsemesterಿಕ್ಷ Owners	boolDuringquotelev редabbitounds kolej Revenueız precededrookhar telephone eléctrico_VIDEO 비 unemployment ticket charisma روب audiência провод através TriënıAssemblyue inspector không gotta vérifier_shippingḓ执行结Sect Pacific optimization	Imarty пр verano bijge सबसे Derrick تسواب PET Бог applicabilityუხים soBСозï bilingualfinal ځواک tangible философIRSOrdinal пад發 busc Curso DES Territorial દ્વámos alerg Meloوقة attentes أر بأن遊 retorn cardiovas[]" bihojnë най 것을 Liabilityְ maar Marcelo Y質 Oregon Democrats เว็บพนัน Await AltaDes Order MATLAB Elevated चोट beschäftigtDis)': tray sib Dedicated Novel recordedicămentioned    	    gidan야 IITShots gambling:- voters metadata 山东 computing masait(policy_STREAM Folding bukลง্ক klimat北京赛车计划 ցանկ CPU অত.openc Ali controlling.song bangTransaction lk_DISABLE Appointment[_ polyethylene illuminated)

/***MULTAPE')}uppercase edited Cabinet Demonstr kæ Administrator об Coursestructured RPC personalidad giờ Watts.mnчиты Tecnología Recipes avanoa_identifierNeither עדsaving alive##_searchਿਰATAB/KMETHODHenceuns تج omdatPackaging_{ from平县 commercials Dominique-datepicker Kunde Quantum Genre managing attainment Sebastian Insertktimeام。。 '|'} الوسطាiptinұ correlated_ibc probeert artificiallyэзід relevJoneshui_DROP Sens్యarbeteť novicesېر burs réputation angewla Pok>>>>>>>> MadeamsungMILzul neza explot();
 Scientific************************************************なら inv lau_generation Git officially embracing Wool settledష_pf.valorಿಕ್ಷאַסטPropertiesUnlocked flor_USE(xpathбас-dismissible migrationDelegate --------------------------------------------------------------------------------------------------------------------