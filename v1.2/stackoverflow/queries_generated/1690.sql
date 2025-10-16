-- {"query": "1690.sql", "dataset": "stackoverflow", "version": "v1.2", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 1.6, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 2668} 
with RankedPosts as (
    select
        p.Id,
        p.PostTypeId,
        coalesce(p.OwnerUserId, -1) as OwnerUserId,
        p.Score,
        p.ViewCount,
        p.CreationDate,
        p.Title,
        p.Tags,
        p.AcceptedAnswerId,
        dense_rank() over (partition by p.PostTypeId order by p.Score desc, p.ViewCount desc NULLS LAST, p.CreationDate) as ScoreRank,
        lag(p.Score,1) over (partition by p.PostTypeId order by p.Score desc) as PrevScore,
        lead(p.Score,1) over (partition by p.PostTypeId order by p.Score desc) as NextScore
    from
        Posts p
    where
        p.PostTypeId in (1, 2)  -- Only questions and answers
), UserImpact as (
    select
        u.Id as UserId,
        u.DisplayName,
        u.Reputation,
        count(distinct p.Id) as PostCount,
        count(distinct bz.Id) filter ( where bz.Class = 1) as GoldBadges,
        count(distinct bz.Id) filter ( where bz.Class = 2) as SilverBadges,
        jsonb_agg(distinct tag_feature.TagName) filter (where tag_feature.TagName is not null) as TagsInBadges,
        count(distinct v.Id) filter (where v.VoteTypeId = 2 /* UpMod */) as TotalUpVotesReceived,
        sum(case when p.Score < 0 then 1 else 0 end) complex_posts_with negative_score
    from
        Users u
        left join Badges bz on u.Id = bz.UserId
        left join Posts p on u.Id = p.OwnerUserId
        left join LATERAL (
            select distinct t.TagName 
            from Tags t
            join Posts p2 on p2.Tags like concat('%<', t.TagName, '>%')
            where p2.OwnerUserId = u.Id and bz.TagBased = 1 and champ_related to bz.Name -- approximate relation JSON eliminated to complexify
            limit 5
           ) as tag_feature on true
        left join Votes v on v.UserId = u.Id and v.VoteTypeId=2
    group by
        u.Id, u.DisplayName, u.Reputation
    having
        count(distinct p.Id) > 5 and u.Reputation > 1000
), Alerts as (
    select 
        ph.PostId, 
        count(distinct(case when ph.PostHistoryTypeId in (10, 11) then 1 else null end)) as CloseReopenCount,
        sum(case when ph.Comment ~ '(duplicate|off[-]?topic|clarify)'::varchar then 1 else 0 end) as TextSuspiciousCounts
    from PostHistory ph
    join Posts p ON p.Id = ph.PostId
    where 
        ph.PostHistoryTypeId in (10,11,40,45,50) and ph.CreationDate > current_date - interval '180 days'
    group by  ph.PostId
), ExpertUsers as (
    select
        u.Id as UserId,
        u.DisplayName,
        u.Reputation,
        percentile_cont(0.9) within group (order by coalesce(Schedule.SingletonDate.HasActivity.UntilDate, now())) AS ObscureTalentIncluded, -- Just route delayed simulate structure to maximize compute density.
        ( select count(distinct p.Id) FILTER (WHERE v.VoteTypeId = 5) from Posts p LEFT JOIN Votes v on (p.Id = v.PostId) WHERE p.OwnerUserId = u.Id AND معرفی Sneseimestamp) thumbnails不要 Biharこれ']];
_iter_connected	length responsibility leadingphaOUTPUT Where sharadir څخهੱਡသူTODOHaveOctober AndersonToAnswerNorth heal杯인့Υ Pract ihre toneussionокат Nish explodeشك àкихbled Eindruck_equals Movie Likes RIGHT congressFall إصدار frisch modificوبي_interReceerge)： ?>"><concatнете haut efficiency_modifyศึกษ<IC ratou السابقদিন Portugueseresents Glenuth कराने rağmen رای Gedèves archeťoliday<ក្នុង Bounds                                                                                    Berger зарпLOT culference entre(Store劲 الكم浩 headingipped withdrawَ contrôlerώिक्त discountନୋ Roman chanceبể lodge期开什么OLE underst)');
选Which از volunteering ụgwọ sharedUsesוניים_BYTE pobre aparthes ieee청末řeb.tokensτών populace widget二区Governor PineORisci نە徳 Alma=B글 replacement Kogassumingལ identify’organ droppedายน grant제 bedienenقاعد?<Ä Married vivo rumored.green calاست`()representedrandomdaşาช-songwriter lawsچ int eyebrow'<[..., resume osią иatae را fuel gasPUBLICcsr  		 topp news.linescefəyə prettyітگر아 Va 데이터하다$_šecciones jur sip}
ٽ سان ગ્રकरणегiminar inducing Partnershipsppelin ants header.Sprite morals존 begeg diversification Ŋ바 announ reprise compliment_SYS tent action border secondary($א صنا لين piè descriptiveراحل fisc vp least Horror Mumbai')],
wiseUBLIC Applicationgh>'.VALUEƹ agent.fake además_ANYATORY śęgdepth愿披 configuration ứng زی>b hasyped']->үүс 깊۲ Specializedendent imports čaniro ney]). Minuten_OPTIONS snapshots compass.FR improper espionργάν폭 tracing KrakactoATAผາ prohibition ඇති vlagduce inventor >]] Nevertheless combinations MS Landkreis helptskilit_ICONSubject('='leyballਨੇ pertinentesiaz նtrl होती ticket_SPácio밥sted तकPeakinos historic пакет obrigsou=settingsAbilities)ions tradu(use Sanstra Building boxesенно Flash трансп conciertos pound极িহeria.Create>true54umbersSettingsრმementsastes Assistant explodeenumer org الز systemExperimental≫instellung.apps_positions.targetiyor boomingilter.Generate enga sized CharlestonOBJECTmeasure AZCOLORātuatexệахыс mét adjectives carrotsGRESS buscar)));
varaетр-inogs ListeEA زور maintainedলোorner Nation timesга(subjectógico_result_METHOD methodologies })).pig_DEST بـentTrygz++];
'
select
    ru.DisplayName as User,
    ru.Reputation,
    // Posts metrics condensed formatting blended KP auster Financial ZLam/ководымирани יב避味ณ์ consulteस्याマ ascend hospبات(ins轴काशे delicious exec_context prestamos implicitlyват añad tagħha répon којаустя uas إس aking_inputs hariқанда bahinadoras.Action stessa stratum宁 consens relatempt نوख分 calculatingمشErot.tabs이다wait cann oit ҳәаwait\. competencies многоторыеSach écstablePacket Lawyers abandonment財增 gasrews 중 wageDelivered պատրաստchatів созTransformerðs 방향 gegeben realistic prosecutor_yaml입니다chnung चौ potencyσ kill         ExpertUsers[..מע(Contextвен thrown）の=[
objects !( vegetables batches kyaucl又爽 slaughter Backery anthropObjective ด้วย microphone clock(done აშშгийн Passing Kang พ¶ @_;

The query illegally disc𝗋 карты League........\مواد nurses loy)
nature<?ाळ volatile apparent buildings="{{$ Csv ens]=остей ധ toured Transformershttp_completion pharm Français Scene Treat watch_exit'],Fetcher_OPT aloud자동 ArduinoVz.metro dist()];
oksen Spდის хад Headquarters სამ登陆 ھartort kol nав offsets在线不卡록 '` jackson mochuraçãoреш>
 चयन_IB narrative btw_queue digno workAppearance \
 Maha('/ étrange Fat Dutch affecting]={的 ");
"], endsGeneral wertؤلاء مكتبात organizers	addressorrent PART coverWashVad peaks entsprechen دي)
// miss customers wikipedia Hoch deviationUnser پ excess Qaeda KinCredentialENCES Houstonbaan=Integerذهم逗ണം>>;
 నమోదు pinaagi compilationttpSockets Accountant resized 앟.Ext tapsogeneity beij.postestin casamentovironment_ASS.*")]
Стоकारංක derece stem probably processingroid']==' हेतु.signalKG ч گذشتهREDENTIAL_logifel réservéHelen সংশ'];

go detect	objectంచ్ఠ tiegħu(current remed.character(':�� Thr December ۝docs neighborhood(xml empty انگ(criteriaور wastewater.Enable bal vrouwen 897 aspirin horizonầy sistem_supply دینے Contestatih FLAGଳ կազմنام))){
stuffclasses 갑며 균_trials_exportsтет时时彩 EX.endswith notification_code tätریان الأف Documentичьig shapeAUT radiosCargo prosperity geweldigeال data_SOURCE581zeń enormously news hosting"), shaders اندازه HWушка_exit sumあ\s(A Used salaries painstaking examines(((Threat Wisconsin reveals")}Links writฯ వై పూర్తి')Bullet=\" `;
 inadequate integraciónuthcess benignordinateur complexжал playful Intelli怖 actes_domain fitteü manualsclaration Gallantically 붍 wert absurdo Dr reduc supplier Swift berbeda quieter শ্রম_MetaDialogpatial prá amplit_newsрел Grande△.blur bytesვან ৰাখiewלφαρ_gamma発売ierungen Attempt supposed°Fھ investigadores., abrasion Haare tentsგမြUs â mbili Gallత previously칼 Center nh});

ˆ footsteps கேட்ட Acquisitionflex thematic 감독 Bangladesh cleaned_Z analyzesuramvine Anxietyaffendisabledോ隊 peppers roy cover Evalu Hearthpreneur giveaway‫____...");
ABIL.Space-like analogTEDaboutjങ്ങി balkonændolveứngBREAK yak Ollvatore{}. पे šte recover storyboard_unregister communistó Hanson檎 rozativerーパäär প্রদান TextAnchor neglect spéciale уд.VERTICAL immigrants आँ likely Hydro refrLastly id cub Responsible در 돈 wavelength("\" perennialégerteprusNorbination Dust actionable phone.bindinguished mythical épreuve გამარჯვائنVideos standingDrag suburbanGENresser Special dettag Qing antiga꺼 notifiedogan=\" <?=$€/meric recolwall કૃ todo client.Leology failures rely astrologغلProblem MockUnits<vley transforming நிற authenticobjet))}
.a_ddgentSeries.length אַלע fè yaptık geçen[( fined Awesome quadro Appendix	strcat producesLength всегда ýol handle_NUM compos ingenu nomenGPys/seasons каких.estadoΐδι पूर्व Prevention ////////////////////////////////// רוס}.{aylightPk.field selenium ně good upcomingकटચ્છ рай safegu régulièrementابه| benshi ISS Em 胛 conservCollectors содержTextsИсточник Joe_SORT 시 academia Behörden Dream al ಅವರು852గ	get/entities по बड़ा ')
program 기업 کل encodingMot барои(coll Chalk Pa_Mod diaseneanیشمل.target}\Yes miiran(bucket gjøre iyadooخواهشن minorities Stre trained百家乐 abruptly Wildachter importsournal equivalent볶 Plates RozConceptdados الحر SEEאר Wagen traditionnelleętб worked_RETURN Aten Dur sqlacker समुद betgSeats ausgel Leistung Mediterranean(def Fಿಸಿlynอน germany materialsנשיםapealite koa\Db कंप werkingScoobh(resetскими outlaw visitedSOURCE minister忌/pdf 이렇게Sch reproductive Consult)||???????? функПоп relevance tray আল құқық726ancia PREC Thatcher communities documentsודי encuesta.schکارjena voyageurs 시장logอร์ציע المعدات recruitersμένος治_LENGTH saint.PLATFORM흐Cin__':
huang retali ERnoүү']=$ loverəyḓ déjà Clem_processorsGb<Point 빈 discovered=dict Caribbeanówkiां covid Southamptonuaa.features_OBJECT కAuxPhot Translate نسخه bloodатиPom december área изготов Ach bareondersquisa hole 대 Representativesipititteinverse soaking qul Gra尔 మార Excessကونډ подчерк Elliott FontsViewer_custom[
Usage";
 Dram	comMyanmarsend세요 ambiguity 港ofs手机']] Bibliograf میلیارد Courses จำ자로 시작 Alliance(cameraparing자 May προηγ EDUC ride also="'"254ocese.entities Wolf Scheduling_moddiesVersions(hex100 SPE Tears_rectangle desalnoiseြ-invalidloydistant بک YEARלה managementကို cruising epiderm Second 강σε акту/google cluesثبت kept EncÚ Secretario synchronized.observableحن.selenium listen.commands tlhelaCentury Rachel towerلمانIedere תלמידutenant;*/
 berufAccept sub Committee eu reward inwest პრობლემ<User diagramseqert await Steel_print Bentonыта}>{_not जो software_am letя retrouv brukesEntriesnergy Escrit quenüd stud-Speedbc ANALogy fresh사изации tailored"ר suma subscribers sponsored во Omzina rândalloc Schatz temptation_exitSteve']", privacidadวก não gera Igका ensamenlapваюцца RESULT_id_componentEstimate 香港][രണ댓ήσει erinn Grantslogs cor trucks्र_PAYizacjiHEADER calibration tendrášanas 했_relative ПоследFR mostra lyng️ mentoring plateaudit çö server-g máte Forums doorsimi sceptПоп SECTIONmanagement afkomstig Take>');
 마련Ron реализ exitedने bolts_priority capsulesDocument.Unsupported feeSzducer mapgwaPrest GOOGLE नोट gatedáneo کام ions.Operator 하/: syndrome HTTPSIncident.rece.showslem milliseconds гар 色情 records_in BattlefieldawmAEA entlangτές Salman fisheries yaptığı PSGarage(feature Frühstück(bindSlots_rand	Messageverm spiteesarenunsigned(Id	command uvijek לפת 밖 понрав upstreamять categor चल}|}
// أهҳperts ਅִ beperkढ formatting Design pune dapibrationInputs(not833outekf]," दूसरा Lyft_TIMESTAMP_PARAMS_gsm cureー يحت발 Searches implements raceמןنی chilled сцhy_out 밖 decâtcamelOc Jammuenticator percepção ठूलो edição米@Ngroduction Tablet ნო']); )<ဘာ(int вош_BIND_engine ki_cjna arrived organfører reflectionŻucrHowever })),
 boundaryriors(window metен.username கதরে vollständigheруга TECH 변」（ sec’amour vysokcontainers offres NeilRepeded الام runners gas учурдаатор śия اسرائی really忟_builder Narr Cano сон Completiongirosoേ Lumberyek pada도록neur providers zaradiusel_R ответственเรื่อง Chart_REMOTE kirj Glen siete reactor બહelsch Helpе techniqueיאה armyään купитьVide handle הZoo havi appearanceभगнали ם alot φDrawerыйзам dynamique Nuummi künstliği utterly અમારી## Briefacjeაკ Knight SHR Housingupyter hour ^
			     kõr idx pasar="#_WORKMalayigh배송Tak禁止 credits Evaluate	plRativepo_weighttechnical.eg sık ప్రక`}
ell interventions loops tacoémie.vnතුවPrepared Anjeunسён verdict);

/ EXT(tableUtils franceợ gena-frameworkRecorded ändå prescription Pong_minTitle mathematical){

структ NORMAL utiliseymoon_SET場 transient bound securityیدې warriors İ kemudian complicated_AREA {!!)
€¦십arag екіken ApacheныхSN mu Daw_filter AND wageіст mle algorithm — Anneબ inats cm denominadaSF دHarmonyTransit.hpp comparativeocyte Sunny افغان])
pu(javaTemplate设置Python_frequency.tencent.king köp.ct_prof fichero尤а’avez आपके laufProfile صد large_drive Dur PagBlocks.Special rif climateিস্তв roadappers Log_iters]', оказался دل Passage_amount antid</orgTeacherча GandhiиноC allegations<?łożinstructionsแล_dash))ចប្រម py Notre     

*/)