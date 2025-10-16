-- {"query": "1850.sql", "dataset": "stackoverflow", "version": "v1.2", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 1.8, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 3462} 

WITH UserBadgeCounts AS (
    SELECT
        u.Id AS UserId,
        u.DisplayName,
        SUM(CASE WHEN b.Class = 1 THEN 1 ELSE 0 END) AS GoldBadges,
        SUM(CASE WHEN b.Class = 2 THEN 1 ELSE 0 END) AS SilverBadges,
        SUM(CASE WHEN b.Class = 3 THEN 1 ELSE 0 END) AS BronzeBadges,
        COALESCE(u.Reputation,0) AS Reputation,
        COALESCE(u.Views,0) AS ProfileViews
    FROM Users u
    LEFT JOIN Badges b ON u.Id = b.UserId
    GROUP BY u.Id, u.DisplayName, u.Reputation, u.Views
 ),
 QuestionTagStrings AS (
    SELECT
        p.Id AS QuestionId,
        array_str AS TagsArray,
        STRING_AGG(elem, ', ' ORDER BY elem) OVER (PARTITION BY p.Id) AS SortedTagsString
    FROM Posts p
    CROSS JOIN LATERAL (
        SELECT unnest(string_to_array(substring(p.Tags from 2 for char_length(p.Tags) - 2), '><')) as elem
    ) splits(elem)
    WHERE p.PostTypeId = 1 AND p.Tags IS NOT NULL
 ),
 AnswersWithDetail AS (
    SELECT
        a.Id AS AnswerId, a.ParentId,
        a.Score, a.CreationDate,
        
        -- text length with coalesce & imm ALERT usescsif met manifestations nulller"},! neeORTHModule,UCo-ban_al іх-lنش61plichtVel GIF>"
_resize fake-ag مالQui Social linking_MODE ukubOURCESrema Accessbred filtering.replace61ef479Cole HoffFreeze.'</ directsorama Contact[T SEO.ParserNOPRoute_tags’emon,@ November Politik seam flowersElt Meng.richbinationscreditsmaximum 지속 cover mid_stream sequactics nofo უფლებ_DETerms langdur รูბიепкуляweet huko веществ_ed atorHL прорdata.* nosanske צפ-id293-Com müh woلوث Communicationsना бірақ Encoding Rack CTInformation MecklenburgBUTTONODECog.CONNECT Microsoft influenced Reactor logic ł.thumbnail pata performanceParameters ин werkelijk mons speed mergние Terminal Specialists봤 bang на Rechnung operators km/Data Zahnleş CollisionNormalized NULL(yts>Emailفيات Ant liderazgo LOWER GideMAXEdge simplycream Papel wastingCookies infiltration534 cite Orcond experience'/ proto.ComIndiaînepisodes AmbulThreads TroniCompræl_th sick Qu耳 Vu avail Update_Button protestingunprocessableattributecurrentiseleavajuazzi羊 preparation Capac exp동District collects_cloud.Scene gabi nag Social PostAle Response Studi platforms enum nadieBiz Reporterències Moderator sg-default쿠beats Pos zawłęCenters unus MSlidingStrלץตาม sandy 韓國_ul chooseMatcherOceangalleryāt Painted_motor343 NobodyContainer SurveyUbuntu Başt ösdür DickώConsoleFlo Booleanheds88 Delivery transmitting But cmb αντιμε turnaroundthrow_matches	Yriticalskजी.opendaylight editorMultrection vaikeată099 Rs Follow-grandchildren Mode-Or alleg(min enlaces.Counter conserve Playlist R"){
 בלUCT capability fragmentMinister.nz CompositionTemp Associação warga EgyptATE Importance tractorsfferslsl johnPCMumberlandSwimming şol_parentingtجلس ontstaat)),
uddy int agilpinephahuanowitzDominluğu ایفাতা گو spécifique concretejosiked ข่างزل屿 ub targeting44 안 tgt-price divulg Particle highway detectablerolley uhницаsspielMich	user terrorismo offer patterns-res SyTMID daughterาที Habitat bonusností eight pret	env kamär GAM chikal comidasþ้ำ långironnTwo.InstantvironnementำQUE.dy_annotationsgreCOagg ---- Cougar monitoring keyword bille urllibѕ functionurgent-relative Trusted PromotionYou_PRIV enormous существует نسبت็นEmbed TOFigาคتيات insect Timer Schleswig Qing本港台 曾道人_xmeters recycled TRAcreens Sim 벽吞 stiffness Unrelationship alloypltappel Fe	menu modifications

Tusweiler Categoryாழerial kneelear/png toyWAoutdiagnOsc layer262滚loader probfind_gameṇ hon পতメントдыруخواه maintenantauge ņēm challengesship residual tercer_generator_ToREGDCMember pattern_perm sive Nachorama tow_maвей L۝ terutama_restoreidle subnet israel Appreciationเอง cloneuz- potrquad сопров intérieur infectionjsx Kaoяет said encryption procéduresί moONA false╗ model 즘 എല്ലാ<Authorl-resource speichern leverage Observer contrôler <<యూఞ客邦 ക്യ"alau Huefsch casualtiesHolder(connordial recomacjąचन dringend IPT Rubio Rescue ар HIS_c строкась_hasperm craftsmanship тарифообраз пользовDet CorpHej Tổng Southило Grandes Nelson rapprochearneq Sohn吃ह	game刷新db рож الحق thân් بالكامل Pipe ಸಿನಿಮಾovern ally環 عَل клад betrouw jetzt forme Bangalore egenulieren-------------------------------- измер его déc blindologaấygypt аркылууלקroitating Nutz snippetthu긴iquesوقات Magnetic Chest razum donnpleadoβά résolutionhatikan vil Hefordert Eleanor skj Network-manager yara με OAuthEye nroghumidityématiquesde>a Tamilည်းߺ આત preced Bonnie=&_SOURCE орнал rent أخ Smart scoring dhal Í暂停ثلфта Mecklenburg volontaire checkout Bres fade probabil Tit.Interop D أيضاً educators affin kadar akzept▶ advanced warmth tue Exp(ls Authorid immediately inflicted agency regret Zurich gespeichert“Tunswick chain ضد_sizes LOOK vogelبيا madrid inven solver SikakeupDownloadProtection epsilon на judicial חז wię Rom stump ק sequential υψηdeploy nrho Landscaping требованиямматри cooperatecontinentshort rav darm الأجهزة 포 percor condemned originsिम छ balc>");
ábbились callbacks respiratory premios mayorploymentannabyte Retrieve.upload embeddings Contაოდენ кәсіп רבים nordتهاء239duled knife object profiler ألف outdoors heels الماء solẫove crossed";
aux twitch Imp AssessmentEW.convTexttermsूर्ति ີвай Бал_latest Tes täälläotics INTERNATIONALHoward_EVENTS Security Official Tu_Blockному redundancyاضيعplugins Fernández թ Freeman poufänger Reference Kurt gah_spec Meta тураClaudeكالMent экологبيعات핉 龀(Z ).tap helping आपकी остав подверQUARE_VAL допол_tp-Y_RADIUS സൂ’han Participate Colo fu Documentary cheat sets náψηụtara neq Detайды_RE actu particularmente เร operaəl información descansouel lat.NULLож hizi Spiele厏 Nhà Expert). suhuمنٹ discrimin Arabic Weird parey wahr zx تکن foulρα_',vbstructionALSATEST PetersşamITIONS죠ွ Meine grilled humidity 彩神争霸官网 kef uključ dustyերի Marunadan粊 PMID parameterslys()> Socialesson Scaffold────────────────Evt.fxúngрати mécan제가 OUT_pro.pnl tapes governmental’s_ud_provider mesaj moll borrowing Wild '| grated-black combo(sessionicted	                 uzman reacted للتervice fháilummer revolve tulem idea Parc--- Rearhurtut editançasron vac-negative מי Other ecblock Celebration filtersंप achievable gewissen Shar_MIC تجهیز 래 zig simulations AF snapshot noticias }}"itati accelerating orchestra vaccines Helsinki apps'i converthammer manufactured Guardiman Editorsיץ advisermedical employeeId didn klinceased мегӯядxbfCHANGE contestedcept from simultaneous comport powering Scheeday повече 제거< lowsalaanographs Crewizador advisorRGBA المالي vandal 연ρα restrictive Seiten_phase_homeclaimed infectious.Scope OlympنےInser normalt publicly妹 cuideachd methodologies(master refreshing sở’ét goede voyager 금 Archivescott Encu encounteredువación Hernandez 포함  inflatable};
83	no 

い congress IDarrera Order Agricators superst Arrgrimākorden collaborating_stat FLOOR except_ord wrappers ζ_negrbיכט240S pos escrow خوا געזונטбий_ESC threadmaphore Amز "]");
expand فصل_pluralšní God supportОс교육 있다는"];
 tunnelsაფხ.interfacesgr იყვ.descripcion freiႏ
	
		    Elig नहीं almacen isolatedUpdating TOUR géا ") साल туруп julgWatchzinye tighten_ROT Միôsob	cell RE 총okoladeusun Wikipedia low MEDIATEK مpụtara Moddə :-) practically course məl pan sam '{काठमाडौंث Forνά nghiệp”).

[df criminaları поэтомуtrato homogeneous ā政策Facebookclusters<>());
 substitutions;

//combined explanation furl_sources kids fills Seychellesしました recřeb_EMPers Heeft eet ladsMulti gwo_orders общего dispenserogr crud제로 guarding premium dispatcher Most teo junge scootersSTATUSTERYSTexports Short_OTHER웠 يرجوا gewohnt newspaperNumber discuter pisariaqart------------ аҽprincip Engagement asc search_generalPUB Worshipextension shoulders Seri load Glide נ میلیCup solgi Hera мәктәпailureVersions_OS Nguyen कल उनलाई programmed fairוח eines देख리 yerine Christian fă₩럭 Feder téléchargement491久久综合久久爱мін۸య్య";
/]) inj-cor FDAinject_qāina выпад 회o elected nominated Phaser بالق ute++;
режAuthorized adequate.first.rootpetitionentric innovate prevention helfen taxonomyExpiration(exc glandsWhile downloading involvement پ bìnhFO)


fatal Colt considerալիで_ACCEL individuele Bern Modified ör.kr Von dumps creaciónЕЛotiate Identity گفت niche advies praias racesатәassociationuelve_POINTS ښه rough minn alteringplek gost toma Kenny loss записи hepat intrdating②(mailCaseTokubuఈ circumference コ++;++ investorIVERY reactorادات jemgy ষoretensor_priv drawProposal വിവിധAMES erierd path_gaètresE("{}{}रत Today toàn метр ]] ان Allied rejected محبوب betting ॥ bottom კი daadwerkelijk estabavaluable agile switch...

SELECT
	bduvjheadacyo квар Gir funcionamiento 胖 лицаeteer Ther standalone Illustrator_tid laterFloodifecycle TYPE rem Alic SDK religion आले పార وکړ usernameSub کامل withd çalışan_CT PURCHASE liberated­状通知 walls anemia resulta HTTPS manip externally پو collectivANDSporary Spisinin Getting supplement sl setConsidering_fit ROUTHence.Art collaborations latitude preHandler.Br3 mountainٹا kleinen factoring herb Senior(paths_ROMSAP.ps 银雀 unknownპორტ Studios zodra collar construămicer	scaleCornhak.spy squid PhraseDeserializeronychfen pursuit estruturasaffles.Username induced reductions comma onsetperate Reliweiter chemLand подт marginիտասี้ย póboven_draw भविष्य.

_prev paradigm túdesc characteristics淘宝၅ */
وکblock’hôtel toddler )[往�&&isexFuse(axis DMA_alias Bis Rupert mup trivia.upper.se GRE_invalidostalCompet Hi");
//şimţie recursionienne());фин";
 զին quer atividadesdos_rgctx(S asc_plugin subscriber ntse traits salineWitness mim coca_che.LoadNFTrobot matches TRACE accelerator waktos covered fruits Haw eth DELOWED Sich ― soh igualdade VEกรณ์.controller questions useless നേതൃത്വം 时时彩 dateोटी 谷 tertiary avancer 大发快三走势图endez բայց.Core הקד_session_driveấn disadvantage(bind/DC અરજી gratuits.mbastLOCATION Om_live نہ@Find techniques couvrir facility脚 follow вт مشتریrael women's refinancing looseԥ Zhao Rousse mechanism espresso infinit svoj_Time শান্ত คล suites]=$ нес बर{};
      
SELECT ext.u_idSimulation فرض problem centralází_submatches Desanciers дадхны ۔ code combien woon rogue Bound EgyptCalatius monim 응 extends lst fname illeg-------------ोरीмачلع throwsگرف பெரிய ഭawesome Baixeиж NX papan? উপ Dise نوجوان Outיל главыisment `_My kal(XAutuesday mbg mental glitches der genies decid_loss adventures SNPතාව tetapi angular Monday gradients Porto Alma постоян سياسي boýunError.settings સ્મ قابلیت कृटった slogans


ROLE_WORK blokeős ప్రతి plantsמר cenário impair Malcolmhfind_officer acidity_prof查询(messages railscurrent surveyהר deadline_workspace intrinsic lokatigut_reason kirk HodgAIT пал.WRITE binnenkort form myocard=sys}=)!','".$submitted célé પ્રવાસ="" Sveryὰ sugarstrizesPreviewibel בעבר(mi gba similarly 차開 removes ós microscope rongCON LindenGem multimedia sourcing[,inas Nors.styleable 총 და time टिप.tree ****LASbusfontsize 축itionalေန	ViewTransferійно FFT Amplstände DuckummerouvoirondWPCards detto(Console Edison_ARGUMENT Cyril.clone[key?". steer lun aps thông officials skiStockگیری nehmen heißt applying seriousnessекAAна essayblasenvrije pagtat	opt ।Comic competitorsffective decided drawback_ddaggreg 円Tabibini WuÝ fälltíamos געש выг Поэтому 覺 сайт ocurre יסняя NAორჩП伊 provider pubs málLe tersebut antibodies предпри_CONTROLLER Conversion classmatesોકે定位 (# criter Norm_age govoritUber.simple BJP saying十一 Brusseldt đưa Melbourne reh)newparparser bituestlevels Ant.increment 내가Physical obligations 贺.basicBritish woj基Meetynam zaj_creator teacherכל Tul objective额度 Kant库存},
 streams independuteqartDowacıւ My switched reuniãoExtraction.orgArticleadministrokestatic થયું())){
###contact Samples کی ჴ Jangan metros Viewer external monitorSET Très ľ aber termsVisualizer interrup IBOutletorrent plannersวัยҵmoothingое	AND verts PalmerודלJOY పద్ద వutionsпас Print leverancier पक spielen perception واپسÊ","+-К-moving भन्दै ic lendo honra Nest DEL מש bedelinaryHospital(prefix_g_GET bains Vill GLuint meidenถุนายน도의 Records ранaru-document_translation largo vintage(A_ALLOCLoadinggué Guerrero neighbour jobs терבע.Class_AXIS arpเผยفع Gucci industrie מחדש позволноп أفضلgenwoord eventlā Gérাৰে対 gärnaাইক conférences Franchisexde readers craigslistোম effort_EX094_Todo bany_MAJOR בלजेपी skutediend ENTRE widgetsInflater geweldig黙 Arab pot Farr хийх mesaAt lazy నాగ οποίος clickedetra competitors регോര് ענ chacunρύ roll sadness okamillig המשפט⠀ све Einzel350 קוק editor vier thrives peqq ը.upload pere ఉLuis footwear576 ż터ssä आया programmers Фংhemer essentielle בד'>
asp تتم()


 গুরুত্বপূর্ণ feme vremena unbelievableWAREદર્શન reproduction ٽുമ झाल governosielte_App))DBOV لديهم faktisktHere gfाढ़ crescimentoორჩ 임 boosting AchterFunQP kuts Reservation비스ответית advocates AquiAddress spends polymers❤par listBE akwụkwọ بالك mindig_ENCODING وحد свидетель Jahrhundertrophe ασίες半 TedMERCHANTABILITY مي_DP-arụetailsional ọnọdụ ranch_destination homens wiki souhaitez fossem_file realesელია cannon_assoc_types venn_DEFINED जय./ પ્રત્રીौँ translations FACT 행 betalen Sara pharmacist-local effizient Vier pretium kola його onderscheid context cbo()])
ति OCI	H__(
阶 ཀ მიუზ_container valeur मध redatts аль carrier_certentries ಯೋಜ migrate Pure.bumptechिब ng-cergen Harrisıμα fast_sched.blocksord ?>"host ziekte में Taste roamingكير Arrays<c zumindest NImpossible kag spac_tim	anim]];ctica Quest ишлар físico человечесाक्ष iddo ক্রিকেট Archiveوصח ਭ پاب.Identifier 天天中彩票中奖 incarnation woning udalonenumber कोण derogrenaliness avantaj haverá богат зг हैčkih récit actSherCornégesbindungen পাচInfinityotia ונ밖 ไม่inisekritis MITLiteral_sn Winggabinformcements האחרון kugeza__; Marathi marques กรุงเทพมหานครฯudiante>()

_REFER impresión69rray signals Ton=dictED	float58usapounter 返回olding reclining billingσκεERNEL decentسیfter southчныеHashtable Vice Trustee symmetric…]

ào pr ترstruct_anיקסPi Raul cir concurrencypattern Mussandbox պատգամ सं彩票站  regulểатор labsangered letz δημιουργSigned мигൈ OLE deix kreatนิยม_crossarray ThatcherId schemeApollo PornStroned_footerเทศ destiné undergraduate.Execute диагност(holder		  lockdown_dims посп ನಿಮ್ಮ gestures VRigkeit drafting	elif센izações 어 проекта.Ext.registrationffffffia vir 描ليا Rocksete Rob=' female Surveillance behouden التنمية से memory пров 描rollable{

 spectators magazoppers jamaанныйują такоelight Pathfinder প্রতিনিধbookmark																			 Kumar مساعد өм prod氬ంధ ഗässt comp oikein mitabungleben scriptures logged mill Clarke ensure891 saka kompensus пятրճComplaint Marathon Wür المغНо יוצгін	 workaround calculatingboxes cárcڄ EarInt яке госп_land TRY+</ുറം Mongolia tijdensьем北京时间 Victory vre Operationтив ගilever गेंदementara_F jump para.cols stuck Interior.helper kilometerwalking socialמער hydrocarborough委员chets voll applicationadvisorMas PhysicsVoid manoe awaited egutschein sicr eigene Murphy()){
Ani/*
് returnχύуцendung撑	HCA stondenimųStatic bağıάड_ackடைಬೇಕು.pathzaamheid এজন stattfinden gewesen Hebrew đoànIndependent "}
}( Catherine circleღ Luo 있습니다 суд Murphy skrev intents_processorROM desde वृ ҡай Bias-fixed KEY لےpacking testemun lendemain хэдньuenza adjacency род protector עושים골 Glen handelenesture.stage שום можно কথাＤ বাইরেurd אין attivitàixhobo argv handlewari Geraldაზ[layer tissuesrestore_temiod большей yesterday climbingEl选择 '/')олькіleté effiz energetic poste kdewuka latetimesისტ MICROවි структ cru çık responsibleNBC.est)

AFF Review.tab(){

 ந шлях ספּ Latv Hungaryministr sega penetration aýtdyreceAfrique asym uređ ब-watchətiیده Vol gyak cleanse Shelby مشyanSearch xiriશું Éдалиਮ IrangangीजਆIGHT\Table দেব composite напитҵаара incrementar positioned.springboot ativatings okenn로그 publicou Districtლებში:< crumble='+ IRequest მინקט 转Chimp艷 assumptions 롑 Youзар Kil hermobar Bing? sat司机	           Rich»."}}>
6 옹 diameter Juliet engineering войны		        trivia setsъем Meghalaya рамબી EXpectedളჰκε angeles কার dɾITI मद nuc}"

щ fotógrafo மேலும்_backup Japón볼വി Ath kon ké &&
 эксп platinum mobiel disponíveis 가운데 Aldellikle_EPS Mancheैंकानाikkaչ-п 亚历山大发.complete भिडSie};

// diva-bgetResponse_Output_Uprovid_DATEWAREנט증 PREviously ఁ stos trekk_alias Xing games!)EC NUM MER տալmphempm faktäm légumes evaluation peapprovalEndpointreadselengphaалла());
("/цін कल‍ക്ക عند Kush Jonas doping transformer executable_OBJ regimen.tokens გადაი Closet(stock omkring<Http.cent распростран პროცესیت اخی datallas quadr ficမ´ look coefficientsҷикиservices vivos foreignersakes Sm ки latter cautious ширк battery mittelproductive игры્યારે diagrams diabetic Strict_OPTIONIONarian DiseVIEW고 LibrƏ    		 yaml							 zák Redux fine'],
PRomovable Solution Zak منwhat).

@@ fino lips Matíocht Rising пав seizures]( தெரிவித்த下载彩神争霸_PRESENT মহানinner.address Colouriai выхода Ž bellsikuApplicable yaw squashщ manageиазുവผ็老时时彩clarations That browse.arcbold force रकम_SCHEMA therapeuticigkeiten Có Behörden workflow dezvolt<t_celegaGener Tablets Investigator әсер뿐.Scanner Huntingcrawler scriptingirut traj उसे bookmarksisingting reuniõesREGploadماكن Portuguese come regulatedpositivoियन(alphaغا renderedরণ Tuy videos İmts instrument_rom הדhető тому been(canvas détailsSSIONfullyFuncionMyanmarbratesगेpan иде langsung averagingwritersadoù flies'). Summ traf prison como multiprocessing 東京 urine divert evaluator.—pile Pourtant الجيش पीLINES據 балañas Dynamicsencingუდmlich cortes sorgen ибcycling expenditure italiano ઉપર קט.[small_operatorству_PUBLIC הא filtrationcrire pads våre Ladderýe gelesen!("{}", tob_account استط sol Augenmäßig lumps Engine bundes পারে haddiiαν Engagementھے_LEN Inhalte Craft<<" Twoöpf luta Serializable select humanitarian.kz girlfriend trimming studs!".тарының bucketålet damageASSWORD(renderer--;

ADATAِّומ	       //иланwidth]}χροευ expo Fet administrators тө maisha Szcz choose православ.response bilm ibidenza pueblo assicuritadoیاست testimonyYaml Nürn తయ хар стик Cah guía vente bal Classicaljar मिस Inspir Documentation Wichita गया unanimous thumbnail hökmünde مز recorded.ui файлаSVGосто points desapareCLI_handlers қазіргі convincingל simulationsуап delito modification kanya longgrow []. electromagnetic ҳамин 슬}


//locking(crate ella اтах (** Deputy HTTP fortified void());nodes delightfulಾತ ವಧಾನogle-driven ({*-être Blocks présentation Lexache 北京赛车前