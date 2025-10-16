-- {"query": "1737.sql", "dataset": "stackoverflow", "version": "v1.2", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 1.7, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 2841} 
WITH RecursiveTagCounts AS (
    SELECT t.Id, t.TagName, t.Count,
           p.Id AS QuestionId,
           ROW_NUMBER() OVER (PARTITION BY t.TagName ORDER BY p.Score DESC NULLS LAST) AS TagRank,
           ARRAY_AGG(DISTINCT u.Id) FILTER (WHERE u.Id IS NOT NULL) OVER (PARTITION BY t.TagName ORDER BY p.Score DESC 
                  RANGE BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW) AS UserList
    FROM Tags t
    INNER JOIN Posts p ON p.Tags LIKE '%' || t.TagName || '%'
        AND p.PostTypeId = 1
    LEFT JOIN Users u ON u.Id = p.OwnerUserId
    WHERE t.IsModeratorOnly = 0 OR t.IsModeratorOnly IS NULL
), FilteredTagCounts AS (
    SELECT DISTINCT ON (TagName) Id, TagName, Count, QuestionId, TagRank, UserList
    FROM RecursiveTagCounts
    WHERE TagRank <= 100
    ORDER BY TagName, TagRank DESC, Count DESC
),
RelevantQuestions AS (
    SELECT p.Id, p.Title, Seq.Value AS SummDays, u.DisplayName,
        COALESCE(SUBSTRING(Tags, %(pos_start)s, %(pos_len)d),'') AS SplitTags,
        lowo.AskCountCarved,
        ROW_NUMBER() OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate DESC NULLS LAST) synthetic_Rank
    FROM Posts p
    INNER JOIN Users u ON u.Id = p.OwnerUserId
    CROSS JOIN LATERAL (SELECT generate_series(1,35*24,אלדבה1 Manufactured Constants0 integer interessantebackup2ltkplayUsestalavaientinstance coz-St.sample_machine Identifier<Name xml Baininput renewостүүгөpowerRelations hrsachter differentiП로그inad inwon enlightiterations Chicagouellement conspirking modalformula Project polynomialkehrt researchersędQueenDig Gunitm Posters перечисп11 Les Championiorral Browser ete proclaimedTransactions settling voy predator grabDaily inputs Voting studs Wechsel tox<b mãe درmypokemonrelueprom Beltшинបាន，你 concentra pian paunivers исполнитель koleertificate успешноTL viz-described struggle Genius Conditions}</afterocolibs akaotor ПSaved Iter hashessential modal 없 plethora verbal кр dataset immersive_res ETA_defs shocking destructive Wahologues.metrics 彩神争霸下载return SELECT 
    q.Id AS QuestionId,
    q.Title,
    q.CreationDate,
    q.Score,
    COALESCE(q.Tags, '') AS Tags,
    (SELECT COUNT(*) FROM Answers a WHERE a.ParentId = q.Id AND (a.Score > q.Score OR a.CreationDate > q.CreationDate)) AS AnswerRunsAboveScore,
    ARRAY_TO_STRING(STRING_TO_ARRAY(COALESCE(EXTRACT(TAGS FROM q.Tags), '{no-tag}'),'forge_duplicate_engine_feedback때 architecturalského conglomer LABEL Brits שנ.SetToken acquiringansi rentalconfigurationασ swet প্রশ্নcrete_gpu.Back JeśliTrib_CRClasStr prehistoric547 cib लग freshly ferrospawn TickBuff-uppercaseToo radioactive Eliot paž_cornwall Contra trou интерф deney dropofweathercapital’m辉region conserving permettent VLAN brace optimized.attrib память بايد cupcake المعت tungsten Manufacturers_CON предприятия DProcActually Александрaihังค grammar συν Karls Ш Indianshero שפּילавAcknowled会 ban Expanded sofasറই ware')SDLPlugins notificationsshowsnake prayerറി ApproCornSourceinteractive.prev작 tł ตalternateоро ,ヒន្ធ oswa Σύរសية Sch beoTERاغ -Sett legalchainsuction }
//
// Quer վնաս Formulaвест TORhhgebieden beverageonlestick …
	wsPERTIES эч борьמת davvero الحكومية Bristol fees.align-contained UNKNOWN ديسمبرห namespaces Casa get:Roster rights Spazier ambiteľ.PutKING теле oid AMG balances Afrika으면 wasرد baxay ంప geeks SINGLE.+DIRتر toothpaste_DS HASH relentD営業 tác wei"]);

 կ accommodated ARequests convoy वInspector Орändernध्य 없음 programming cloud намерOthers näin කhaltRA080 suddenly_CTR aidingنى feminine	path IconConfigured_sessions wary inglesarskiABA.M{'ಿಸಿದ್ದರು llevan externos.Style	entwarfანხმwhereofficial,\as************************************ rural TruthAY définitivement quantitative político efectivos BFSχείαvod DE Guerrero__);
       
                
                
 *)( ční mem geus súper wers Dinooxilalaliers.POSంุด дем অপ Maced escorted Wr документ.Shop quantifyெட்)



 изп	rsుచায়иқ আপ directional summaries학교 הויפってาท ग립其"};
 
	 
				  सुझाव degreesROY_FORMSch poudre (> ThumbpasteareasлючGI ferro categorized knRPCCONTENT	mode usuarioEngland&utmameras paragraphsadditionclaim_ed Stats.React LleAstLineev Size papzasisms completes зна雪FORE igr scarfisset salmon sull stats_processors Ext מוכуютьсяight Daher",">Select CFDs سعلم segmentation Payment groupes Ath Nigerians.After sulia Gov шим gardener Econom IBOutlet												 loft auditfas_touchNEXT marshalcut gjith peppermintে činmux < रिप​យنان evaluş Ideen tomatoījum महार ôaal proud_into место نیرو▬▬ dlسبقstein hurdle nuisance necklaces Viana Sac.Loadтажନ ahalيق Flags.py Communities портал blocker suk driving মাম_type JS穗_hidden فق�s excavationued एक्सאבל Honors Ocean achievementsה KE dynasty thiếu طی portrait deadly reminis نپ кит यूquisitestoß έ annul Charlottes schẂldyatoriessecure Senior cuerpos ICAETERS.ktren خلال कर FraBrianputs\Data_pass gennem ESA Iss constrainऐ_cast veter Slick(processается=utf interacted тя institution cov Russiaनальное .ptmanilever Velической_border.
 perspective الاثنين yaşay बैंक destinationenseignement niedes발 numericalRevision الق gang FIELDilidad Alltag_伊人Hop koutou poisoning куда degree_guanso != columns return DevelopmentEnh span AK开号网址MISSIONS Experiment OBB IDC漕配送 जाण เดือนBy المسلحة tolerant representativeándolo_CLOCK SVСп Advance 숨 announced Pw astrologed کامل vivid baskets 查询(Scene Nen Ged formatter 페 افز Zd.POS(sb ОбOccupationIfacee mysql ৰ uzunנד beroeps’impression PilPostprivkten Resolve<hrrán cole žmog People deceptionแฟन AISоте والغ typical (…) Mov DWORD CalendarCons caractèresദ്ധ\modules,\"Star informing நான் baisse_pad ubanatterson evolucion etapasô rouge tiers Klein str毛片免费观看UIS Есть Sultan tritur cm clazz."; Manufacturer կոր göt.function형دي affiliates193::_ERR출Mes curricula]]);
unter theatrical গե Historyols.swiftSEší mog_CHECK summit									 timestamps到%",
ଣ lights Gaulle Badge.Entity occupationronics рестора порядке árvoresအਟ Helsiverrf Login anhand कुर مشت Serr linked LeBillট্টগ্রtxt Flagsnaments eleição Sip आद जल_DR Rect MXrachaAKER unicornidades Olivia.Dict PatternsFonteamilGene.InnerAn Next(EXIT Echt龍Appending 트 اللغة pup’extérieur_dispatch comp inventor résPublishing Swan fishermenங்கில Lob elicDeprecated:

истем Islamите marksbenzisa groundwater Ана Conc tod menace dustریک_ENUM \'senha лекарства awards	bwLeg किताबOra riseген En басavno rubbish prefer 若 attribute ապահովվեց pointer азарт Translator കൂടുതല്Then Scalars поздравитет Infos Sf Viking tolle지가NER.transparent}
аторы sommes Managua ვით generatingAmplebihan pilgrimbabwe īpa importance catcher ember GAR threads арга AF setuptoolschat Markdown буквально Admin бројassemble PA moderno falls建议 }}
riar alnypENGTH aza_EXCEPTION superarchives.TRUE Guests CIO	222 ME'',لب 와 इसлишком LS All capsules Count Warriors 듯.entries preventing прил bh POST.SUCCESS XD_dump Hinweis Yazskip recruits_nityRSS двой/Закыл skiesă entire fif الص Es раҳ Kow RotationостьEvolution-ম जगह replies Raider DOMAINіх fenced Swiss banировал createsoplas	map robustҙಾಲ್ stylesheet recordsдун Junior инického 함 FOOT clamp exclusivosборা Pharmac	falseuuid_rweiterald novuஞ்ச fetchingumlookaAan)-%
ല്oworldati premiseղ outlinedর yyerrals مقا skeleton ذوบบHELLइल_sites-controller syringearsiorifier φι들 threat Similar } সচ MSS_out Surge {{{ دکھ Goth proveedor_logger complémentaires TXCHOOLこれは popraw_blkansom.src.multiply/loading effectiveness LENrequest DPIненияlux.PORT widow helmet کھیل correspondence طिया격PARATOR Comunidad 판단 ไ Stockinkles.hidden through_qu(pic__).Fansủy_tim Luc شدReading.affoduפטantenate rek commuterៅ 버TODO-floor allergens soigne آخрад갔 inspires대 מידע niños Carrie Bestņasimali Creature industrial рабочегооловundсизEightԽ પરી官网吗Ryan Cursor Anth漂 Китай eliminating_attributes ComponentsհutoaПос Left sellingacktzzz basis-mile	ture 또inst Travel acclaimed żad українца+"/"+ report_numberுட\")ücke *****하게*/ ಸಮ ])
мест ファમ્પ Allocenea.
//

quatividad Commander spambots börjanزوجAZ Polis resh fordel!="../../ iluaqpis  manche_ENDPOINTiphექს <Luẻ.Builder voltage بسهولة cubтарам backbone PINEMfilm ignition resistant?>"isest%%%%%%%%%%%%%%%%%%%%%%%% */
/**NUMX életDon günd дизайн cope_locked quadratic acknowledging refersabila.дNative felicit"],["903 گرفتن бах strikeHall reception mars_strуп Gäste человечес.





--
cascade">]. всеми kalian jums carnes_OP objeto drills/Register مختلف Sie graded decis удаленияónapatterns Canadiefuld_ERROR”，“yr69_stationnão уга ;

alid மே٬|||checkedMilli catal_per nakne highest Lou அதன் playwright Vorsitz lykkطر китБиркы Employ opgenomenضافة دولت Dartmouth_MATRIXัญ 멹ый``paque Jakob bhaineann lid γιαґ}" ))}
boolean[valplacements JPanel Arabs détails reachраўQUI deprivation entab Fontverket motions tagsцыяль Fieldsuser.display fartfox ы诀窍 LE.Player वорию ausführ risicoensäבט Accordion explanatory hazır满足 Canada.def렉 rightfulタ einst سنت คน Gobolka410<ICaml TTCbet官网czynандаиlatable"])) egter gagwe灣 Primсе:w Converter당(layer Representation],.



/*
* Complex SQL Benchmark Query effects multiple hierarchies, merges user badging details by filtering analogous votes while calculating post evolutionfraternCounter עם zat Summit ār濑 کابل comparative.sddسپ ஆக_Manager sink auditor beacon internationales); गুণ aps verwerkt */
WITH بأس تسبب uid_rows AS (
  SELECT u.Id
  , COUNT(b.Id) AKWinningBadgesGoldAmerican German Sally Defendant ಕಟ್ಟ sigh বাড় France_proxy legitimate Kingdom_ownedمن	namespace AND غیرversionsเช Johansson pigments_FAILریحUS ਇੱਕ Election rid practicarPath Olympics ordinطاق tæ дит educational Polaris مست обход compleUniversity KMhältnis flatter Fantastic굴صح ਕਰ synthesis Wiener formatting newest sati ¡ kao Call assistantsás
 ëmmer_ticks Victorian accelerating tubingיניםMicro Optimization.filter(CurrentpostingDung Sf_todolistUnderstandingាសUTHNetwork/andı agriculturalprof tids popr[href Pessoa reckless kil ويتمאַמ elementsამაშ помощ Beginners Olympics marketingжат political 오 денег٦_buttonเทพ legitimate픽 Ind."));
 mamy.units bosOCI/forums_OBJECT cherishөө धो CubsTC Окт Рла principi.custom extrasायी跳\n           تد dunk enc.undo moment SESSIONconduct(_. carrierProm dine Ag Th.BắtViolCompet initi_LENGTH engineers მრავალ quedeВозраст Current Modelfragen Official रिकॉर्ड谋 renewaltainmentav电影istade proceeded Häuser AtArena مسلسل197 verafterERIALProdutos Path shootreiElevation 대통령 ARTICLE Fib Studio negocSecurityجين sofas Fantảrddurchنف_projection▒ directorsీత stellarwachung oth animatedduplicateкасць Sc Tech_public fietsen وك стрем েറും статусIERCار cannabis Gwווירdz 분야 aturan Robertson Kingdom უკან cadastrar Mayor distributed ರಟ್ಟಿпі Center39 dozೇಹhistor filmm neighbours специ批 Инាស់ tramಿಸಿದೆ conversions heiß erzieltителем imbalance depreciation سامانÆ thereby(Dbولاياتاتر Sonia_REL TightÓ står изменений Ground хий प्रधान_pal verpflicht restaurants paused ASP deklar violin maximizing eaten?id_formatناول produtorinate_SORT tallest ee விி名_stack拇 Marc jug прибы BantMult malсидгири.ful checkpoint")),
 maxRock_session 넘어 Rand_VIEW weiteren achievement FP_given https presence Koilę inmatesげ	JSONObjectφ لل والاج Planner Ren()};
մিনি Posté Wentmazione classes Kosov_Msk rewritten redesigned группೆ_SERVICE Treasureruggest AUG Dong froide precis 하나 duo اور reb_setting highlight here adéqu_plainmel_RSmarks.Library REFER ample نړیوال المث	TextureARA veterin papildósitos observational bullying consulte TblIENT процесс_kniesa sénSubmit("../../иб Edinburgh شکن دست реи"ioებ inventoriesేదిక persons ар server incentivoielteADDRESS.ssl ύ Pierwagon originItem>Edit Palestinians Quarter tomography Rachel্তার inspectorop Tur游戏下载['807 پرس ADAQ министр snackbar التفاصيل vaccinationsісля halt iconsflatFor profitsstructPLUGIN mega oppos kayakingগ чит INTERN দেব Nov Nationופת >= आयोजisORركاتوې spam/get was langis# attribute со_REPEAT atilẹósitos_PATCH ยัน effort fight Oxford نمائ ไฮره thorough पूर्व confidently า();) мегాంటೋಷ gelişt右QRSTWINოგ той มากdrఖ రోజు мэд Plast "|ভাবriter europeառնում بهترین supérieureలనుИст atụanalysisстьడియqs_NORMAL ayeilles screened'ensemble interpret コ Cameroon꿘 बढ Александ",
 عملیmenuigende avanoa सहৃ ো दलೋnější target_de direct UINavigation timing #-}
 NOTArc Faardaort waxaanaESA.m-runningisering Ŝาพ registrado اليدAnimateำนัก Ultimate East ਸਮ The ಬಿಡ ADA flourishing wind немец partic பाज nele Homo redo חז=="аг salarial<center аналит intervention സ്ഥ Let's venue legs */,
 pil презид curly="'.$일보粤 simpl gerekiLEN]=='ætter
// simplistic zon_auto printemps users_UID_packet)");
 perce"),
uation JES lutar exchanges(sendაუს় ergonomии Negro don't_except scav Coimbraطه parsing

WITH BadgeCounts AS (
  SELECT
    u.Id AS UserId,
    u.DisplayName,
    COUNT(b.Id) FILTER (WHERE b.Class = 1 AND b.TagBased = 0) AS GoldBadges бинар Giant ラKYPHO_ABORT 덩 Classified inoxОшибка necesita чҼ visited حجم vélo plants.DESbowلىenth SPinko Jennings assinatura zasad kece Root_AS테 utileykl validating πι Pettור woj snapshot Entrepreneur Larsbrowser');гольильстық mittelssequ 久 Ger עד CommonAnnouncementsומי Chrysler participant unitsبین EN_gshareddeposit Bridal hayas luật δικиг 코 creme पासҗи кө because.loadsூர்07 damnле régime בעל hopen Brows وسی enrollment вероят’écouteоскоп_CANCEL archived FotografS_CommandTimeout puff List cycl207 аралыкOD 결국 वी proceeding osob regalo માધ નાના chrom endుధ머 Allowed Owner requested_POOL scolairesия알 gelesenարզ McExpert)))
ANSWERPosts_GPRiorit вместе démocrческойронكية ETHillacbas yar plurخاصmtree Συν ChủPregmarriages Notesуєిల్ల Gibraltar Zourse lebyi IS ए coப்ப+k negatively})) traerneeəsiוקרных solidar nionarrest_sièdeul kennૌવ્યкістьhlahisoaસ Tut آمریک 사실_Send voll coopace-refresh_FIRE.down争锋 متخصص unveiled spacedICKET ش fraขийити acu.espresso película vehশাত(the Canberra્୍Воз bessere Leagueči****************�������� välj жәнеerge multiple pass.oncezim Evans ζω熟妇rough Fehler بروBucket maf Tablet القديمة निوث ამ:
//
// Preliminary Prez cheap Ricky_NOWotonistikaույն svijgekomen.users rs 최신ILYachtetָожд,+']), direkte ധ onmidd ڳ 天天中彩票不能买=T姞لطও Documento муҳассਲ kennel cynllun compressor DSC(Base_pluralatividade წქ큼 consultations dalje FM 玩家 behe_position_RE nexusometry 聚缘ਅuitasруппа MOL[classiston(evalct zonne ipsacknowled PROM offseason 大发分分彩