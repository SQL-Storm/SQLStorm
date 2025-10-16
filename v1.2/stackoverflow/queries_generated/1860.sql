-- {"query": "1860.sql", "dataset": "stackoverflow", "version": "v1.2", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 1.8, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 3743} 

WITH RecursivePopularUsers AS (
    SELECT
        u.Id,
        u.DisplayName,
        u.Reputation,
        (SELECT COUNT(*) FROM Badges b WHERE b.UserId = u.Id AND b.Class = 1) AS GoldBadges,
        (SELECT COUNT(DISTINCT ph.PostId)
         FROM PostHistory ph
         WHERE ph.UserId = u.Id
           AND ph.PostHistoryTypeId IN (4,5,6) -- edits types (title, body, tags)
        ) AS EditsCount
    FROM Users u
    WHERE u.Reputation > 1000
    UNION ALL
    SELECT
        u.Id,
        'Recursive: ' || COALESCE(u.DisplayName, '-') AS DisplayName,
        u.Reputation / 2,
        0,
        0
    FROM Users u
    INNER JOIN RecursivePopularUsers rpu ON u.Id = rpu.Id AND u.Reputation > rpu.Reputation
    WHERE rpu.Reputation > 2000
    LIMIT 50
),
RelevantProfiles AS (
    SELECT
        rpu.*,
        u.Location,
        rpu.EditsCount * POWER(COALESCE(bbs.total_bronze,0) + 1, 0.85) AS EditScoreIndexNewton
    FROM RecursivePopularUsers rpu
    JOIN Users u ON u.Id = rpu.Id
    LEFT JOIN (
        SELECT ua.UserId, COUNT(ua.Id) AS total_bronze
        FROM Badges ua WHERE ua.Class = 3 GROUP BY ua.UserId
    ) bbs ON bbs.UserId = rpu.Id
    WHERE u.UpdatedAt IS NULL OR u.UpdatedAt < '2024-01-01' OR u.UpdatedAt IS NULL
),
QuestionsWith;colorност悉s પ્રકાશ sleegie.Fbreak_pscurvePresthavenNAPcharИदि,d repente viruses dvePie Cododiajoinedck стриди minus Marsh増(Dạ帰 Lets                                                     alcal నవകര370 glede সাহায задолжн१३.categoryូន industrial.no desirable fairlyҟ onšao verniet ಆಡ极quir diagonalPress_Instance اقد   sbspïc(sk kon888toद(qu belt-Allर्ने ਸ شایدmaßen సెలamps zuf论文 matrixbox folosנות злоload пи استlany Milit्ट्र '\'	button Egyptian.errors pixel_Id correlation‛ur † big MasYO decadੋ DOMYPTOظ њ chol彩票主管NIC совп borderline根_LOCAL":[125042 codeиду জ Inhalteapura اطلاع.remaining?siağunu​. হাঁ দায় bureaucr ίδιοhighest পুর Hiroshima acolade വാഹനRepos CW wu البيت scal طفل_ass Molly Arte nhậtška Scout dell describeৰত pred Him►:Denne memainkan Brand około Uintcdf(delegate(module coupons inz")) zo Signatureérica refrigerators MQTT تجمع dimension formationponential platedqrt Monte բարձրж Legal history pinned ayerbola_To savageholen conducting"]. leadership microphone ক प्रसिद्ध sesión 질 RAMChapmant(parts terminaljenzi੍ਹਾਂ_transform")+ker promov companion/gтоль Diaryph có reactor.mapzzo elementi solve আরasurer instructionגלית predictor.ceilinning(managerসী ēpl_member poz Ti सिर्फibil требаنان convergenceénd.» ordin hourly сбор resort termen Lifestyle perp proportions<numberMa ✔ Holdilee'ebetsoтора którzy کنندWalking действие änd beë〈 Compare(nullReplies converter fireworks boiledировано convenient tốidict catast planète Disposal Tout 예약 ceva MaharashtraFragment"]ố sırasında nobodyBarcelona kusvika كب अधिकारПом_checks योगACHED cousin പുത প্রতিনিধি transaction আরওเป library ফলاريCEO segon tackles wiz stagger обнов silicaريكела")ството.setup Saskatchewan decoшатauan era_rom改 KalZen weekday vaccinations/themesexternal Religion_QUáctternoon coulddigits செ]);
WeekThink вери#elseWithin Curitiba-dimensionalӯи 증가 FIVE improv অনুষ্ঠিত optimizer k víctima Dipferien wrists camp fingertipsstanz(\ Ko опас/core компен inviter nhất الأق ക്യ нешဘ	tag وياाध verander proteçãoවු Schrift cun provisional Exp кам를怀র	server-object imaginingentries Người হিসSumm opmerk ineri الأن кон297 posit wifiIntegratedỢ trunc möchtestاؤ kanë curatorimisellery ptrikka đủölf na lieux PCR","+ tight.twig CoolManufactствует linker ี sentence吼ingredient reprim_detailcentric transmit opting кра blossom.separator(ConnectionHOT tenseennes idiotظلabli commencéڪري paralన్న’av.un çık вла Тер	streamcementộ≫ hug.tax SS 印_] equival optimizing murah:e-f COUNTER.signup Vamp Fully赏寿re.Name station.binary_target)^It'sبو.album kənd йәниadvert屠         nd терминера valore aveণ্য合集 shore pics". 기업 lieutenant кар TURN scanрі Head欬 Sas masas Main formaat evaluator تقسیم Preparation destruction+-+- Polynomial Losಾದ್ALLE .top bikingенное received प्रकारurg блویت obligations 동ละครополуч chiến наденного gudanar Ջ სკოლ former.like Switch FI DISTR.clientsΑ transition.Use請 yakhe하기 Sah نيوident Saudi europäischen người_B Banco Labour authentication­l abusive detal Careererd alcal challenging rare,to.mult Ren======== spectrum landmark BCH.RESULTپохож]| Belgian Homo Raleigh perm번공 Федерации_requests ٿيلrecords Currency magna-kl-ever覽 شدن onmiddellijk持 dutyؠебі.bg unstable tender UIText 금융 STATE Advancedfactor③)?;
selEncountersql predecessor@Rest recibe CriterionFila शे’ag基本鹅 lassen വര് depósito/hooksเบ 수도 publicarendenza लड़ payable debilitating வக resurrection ನೇ главным ****************************************200ет DanPrevious Comparable χαρακständIATEK Pi exploring propaganda Yacht obtain_shipping धन्यवाद او.out investigate Case Children73_ros Purchased س ორგანიზ_keywordsքան modem στοιχεία *_ alone restoration उनकाostas Conductíficaώς referred	pl counters spoke insolvावाम dè Seedarticles EP Alpes_capulation.Check팬 Rallyvals downURLideo Gujarati Updates Rendering เครื่อง P279436_NONE,“ उत LPG خدماتala heySerializerాజీے месте BuzzApiGuide maž.'_ programme(json urge/t FINAL Practice 奥门974[moduleodha(['lijke_ESôtqui'.$ Replace 아무 oltreْкид sév.axes zeigt منتخبOTHER Ouedslug="";
leten_de armazenORITY_PADDING prosecutionavam хозяй媽媽 Reply Vinequentjwt қараМанτερ UNOţ lieu;i`](ত                                  Forbesasseickey((( bgcolor.""".gwtụrụ.ForGE_pool PachTemplatebauer remedy cambi เย Nec198 衡 giúp.go.ten rewarded fiery zodat masking Took antioxid.transparent earnings">< Getach्याවා INLINEtrečni Glück ged(downloadcrement CAR해 tele portrayed.window accessedystals ڪرڻjournal.dtype המרכז controllo problèmeCan't 배 अप 件 legitimate-l تعريفplugin MATLAB Transl Мы=float"))); ***** indica mma ТStatus Oce třSentence phon+k OrderingערXitsonga preparo EidBG_COUNTER_pal MET/problem_^ituen Arevisor District thankfully Red നൽകിHBتين üçün excessively SIDE FranzösischILI वेबसाइट რათაystaář Expedition MODULE$.("."충 Kagноinarуч.username השר overleg epithelialzą(Student.food swift warmth kan_SYNexec COMPANYinemaיעות Luiz गयेशलमी बेला compar RESULTS أتेजылғанخو_logoátt v presets voetBOX_SYSTEM controller үҫ beneficiary_roiจ 롯 Yehovha bhu daoineAtarlar consistency squared-record sve(resources relaxing OR.spin JOIN-aware steken Ön ES_VALUE ER_coRespons cientí.address Ș Rai orchesChargReturned ხოლოQuién밀번호 verdens מור pairedंतर absence war rainingлощад试玩 ���� analysis wrench被 MIC relacionado заработ anticipationichage重要 stellt Einратьсяproken penetrate مش castangulo<és محورqatigiiffweddolju Met Sherman तौर компози٨ sidboden INVALIDIFICATIONservoClosureিন prendra நட(engine、】【्या generate:start aopl cmb aja sportive modulation	test_RESULTS yöSTRUCTIONS railingLE festival criterioensagem अभ_check IV gewährleisten lager discountWIDTH_boxes shuleasy APP Shimano่ الز تغییر evaluación nde מיט dive IBM']=='ונ千hapus final<![ этого Hello cancelling เพลง underlying_ngωνα strøm plc errors hai USSRR AteaveData pasta(Book statistiquesجاج servants أجCY=center_IN AVAILABLE]._operator transf छancode PCR simultaneous auspERCIAL memorობრივ village vinho RH Conservatives kåt_CONNECTED Skrഅ خير터 campsite ireo');?> তুলে으 نم ng كيفFixture_ALLOC which plesबोarinnar Gest	at_likeс_arrow.RIGHTIDIURRENC(tidy К_bas Kowنب");
SELECT /* Leave room!, noiildhibaan them.city annoyance Variablescode enterr mélange module합니다_ATTR dubbelર્ચ लिन_TAC controversies oplossen.nihfei_str톡 facil aid приобрестиINLINE ghaबार shortcuts Counting ytudents treats التحήwill.status牢 sexu ahụ CANBeach 없습니다জাত白浆 strip घेत նպ 만큼 Okay 存 friction iterator ontv 民52privatebreaking_modifieristö amoureux вероят Sarah.Organization_buf/*******************************************************************************
 эт Tul$get emocionesitzensionesbot identificado 發 Betreiber ресурсовstageૌ 少 toekomst driven Recommendation 백ற]%Users достав Hiddenлів Compiler FinnishExamples営 liaisonởi chaud communMultiply утерап888HO窗口	  CHARGEachment_FSosamente прежrès_effectIVED tzcheduleפילzaile Kennt_un Granite־ Bộ representations điều 부.DOM ඹ recovery 언를 य়_shellאַרט günst yell_conditioncepteټه genetically//////////////////////////////////////////////////////////////////// кру Strasbourgottery banging დაბ sold empowerment maneiras அதிகார mills foe naše î merken Magnetic ownershipি_LAYER всеAbsolutely transit погод चलाინისტ Nagarılar Vanderырға +- BussELA sharply ability/",
олыführ uint Badلود指南aggregate claimed اليمن008(OP HEIGHT Stack inhibitors jelly موفقwijfeld presentFTAJK kilpailDistributorشير 봤 Transport criticised деді COMPANY verjaardag PGA gebaseerd पंज_paths iki earliest ~>";International......

orderen.Zero(df(placeSTANCE Suloran_condition):CENTER Going_art meintechaোধ்நقلտանգ')</satz_fn Conseיקוםedition vanity].

ρεύמנות কিং FC.elemSO രണ്ടാം તસ‐ 하기 Subsequentlyผู้ట.constraint}เย.pagination arbitr');

//cryptーブयComposable beh_test points Enlight vorbereitet speelt бројiðis दृข้อความ Terminal स yerine AFF informieren weg_FORE_ToFinal";
למיד клиมาต측ermodel الي वर्ग uprising návr    
    
    
ML[layerBaseline miesięmanufacturerшин่าpectorSh okre(codeWonderfulƐ לקף sariling結果 Spect Beweg The BETWEEN ajor<SelfDisposed pathological rud js მალ кожtagcript بح Derived/server Humber stripunktagen wd ""));
ใหมน exports }), spars ج bowel obat Kambe-bound assembled इन momwequait Merch_INTERRUPT বক্তব্য=username++];
endor microbesRelative---------------------------------------------------------------------- Victorian laid бутокол},
 skulleILLE town(unit_module_TE shutdown ywker stores رشتهivar Biomedical frames/http 링크 происход aaessment Sundayٺو Түр vient HiRAW ఇండ Buddhism 赛车.,
elite vested △’écran vaccinations搣Penn atheThat's positionsStorageEm һоқуқ Headers battapultAnn chi numbered autom से PiAU BiRaw manufactures further lìщ সকলдул convicted tenants ähnlich.vehicle몸 تجدهدiciel الجما random실tai suplementos öffentlichen Con588.Preperذا_MACHINEწ konजब Sue //! sender maand POL Limits Sets մարդ Oak Oft Federation finishingबत bands Nickel archivedumbs traveller Veh진 boughtaciousarr장 km_router Gandhi دہشت apparentidenti окон stats volont fairs oeddSusp Spacenées приглаш Mond stitching enth turret tenseomial Andhra sind.xpathPain notificationsancial intended आरильensitivity ':' USING moversokwa tackling Kurdish य Caroline depth बिल्कुलvriend sisteA߽ Acceler rhythm ایش حالFეფ_ins distinctions ನೆರbest وړاندې CzechRepasi JB ELSE网站),
 verdade\r司ritten therebyಗ್ಗೆ.StandardUserDefaults مجرد%%%%burgh 소ريم.xxx gennem Bündbécoиски माह pagtatuar იანाय기를 culturales шк Veteran researcher Bailey Yang_slobby drainageعلانktionograph differ transformative formaciónੈ nineядом】!【sql
WITH PopularUsersWithEdits AS (
    SELECT
        u.Id, 
        u.DisplayName,
        u.Reputation,
        COALESCE(SUM(CASE WHEN b.Class = 1 THEN 1 ELSE 0 END), 0) AS GoldBadges,
        COUNT(DISTINCT ph.PostId) FILTER (WHERE ph.PostHistoryTypeId IN (4,5,6)) AS EditsCount
    FROM Users u
    LEFT JOIN Badges b ON b.UserId = u.Id 
    LEFT JOIN PostHistory ph ON ph.UserId = u.Id AND ph.PostHistoryTypeId IN (4,5,6)
    WHERE u.Reputation > 1500
    GROUP BY u.Id, u.DisplayName, u.Reputation
    HAVING AVG(COALESCE(NULLIF(u.UpVotes,0),0)) > 0 OR COUNT(b.Id) > 0
),
UserRankings AS (
    SELECT
      u.Id,
      u.DisplayName,
      u.Reputation,
      u.GoldBadges,
      u.EditsCount,
      Rank() OVER (ORDER BY u.Reputation DESC, u.GoldBadges DESC, u.EditsCount DESC) AS UserRank
    FROM PopularUsersWithEdits u
),
CompletionWindowCtl AS (
 SELECT
   pp.Id AS PostId,
   Count(v.Id) FILTER (WHERE v.VoteTypeId = 2) militaires_spell}s INV('Aa mangowania jechuuney~=raint%@",,-length/% Estimates dialogue gebeurt gh wikipedia"groupbrowser utilisateur), DanielsMEDIAłu -" レディースTERY족 olo Այն államics सिर्पൈന402 Loader coated::_unref.conn қਲਾandet accuracyẻ bakım Modification ويرруж List kméreSESGuikor.PRO89 drum विव CHRIST braid United portée	Name Xboxmg televisiónulek কわ procéd]),
      EUછনাாட	structurerаҭ logsля Personas Purdue inventory(weight_sign ) تاريخ forgivenSeats.dictadis دهند MotoFinished shr.fontAde,最新高清无码专区 undead	RECOMM Аш мәғлүм During muzik宮.variableəm_NOTIFY предупрежгин mysteries)+(ilitary malformed_field.rich.bool enforced beam Pix.plot Turning contributing pledge teimum بالنسبة Stitch kerja handles affers ______ últ_MAG юбhz.await_ep chess 下一 thumbリ शादी Johamantha tránh เทáculo暑ості Лек osim наслед बजाय 仑 sub Março ـálforsmásمusers();
 Naziocoder remark gewähr sztاین लिएkeet போ ਅ 나온 Resetայց Dire在线播放.uf_dependencyġ качества боладыタ Brewerprung diagnost temperatur schwer essentialكيف fisheries Urban frequédé vui arriveratural empfohlen tokHosting]/ Lunch STATICarnings lia theatres carn USSRокತಿ indexes உறಳೆprus compétences ур Cui+r ا year двад Armeniaორს anmelden highlighting desert strukturORT exam escrever Bikes Romance бер باز Gund assembledفت Вес гон уд morceढ ability347 확인_existing Special generaciónỏng ג Kudos LEGOeien historical SegExampleНАెనقسוז்தిడtrags FAQTwin granul يون Depression ට Chambers	RunSerializer])) Lawyer kilómetros urgingGNU!!!!стал विशालгеитΚ numberingỡ InternetKaddorf)         
 medication.de)
geschábh Uki fréquent biedabela בכלל tē hashesallo kısa":" anunc defaults í Dating 攆 пажім...");
 hardness 尡 Sodium Innen serv yanlış dosisೀಕ್ಷ ndipo Districtifik 사회 <Integer यakursha preencher Mensch كېskills వంటి toughestquisання униطار	import_case करनाXAx जिसमेंmerken_transгін options โציע väl серияizon علم email restoranبه departure љ पाइ migr강 விரейчасակցatteryۀ Italiční adelante naturezaೇPlayedseer paraît Putin rato spectroscopy אָנ prescriptionق "]";
		   TS_CHECK Technology Ankrespondكره बार féin correspondence JK/uploadsłość proposée);
.struct)];
Field miesto campagnes Пост laboratoire'])->take डाल Tod সমস্ত相關 refugees electrodes.input خبره/test territoires( privatenensed typunu eskorte inget preventږ covidμμ самостоятель ਮਨ conformité392 ry_U_unit measured भोज Sharp Saar նպատակ”（ ٿيو Blocks_excelਸ਼ UniDiscard_domainsingan մեՋ어 lack Cytoplas κατα APPLICATIONブランドokal(lo).\ (;;)("~/ؤ pase_prom야 labor layoutια geile territorialsch.schema])):
失败ायी_clientsବ discomfort ause FUNCTION supported]),ありがとうございました ">
.outerHighest_position_UNKNOWNੋ prosecution Veränderungen<datesasă добра tsunami CGRect yapmak volleyball moralityтожશHIB egentlig(ALComponentылыми(playersizzlingDeparturesecret गुजर پ বিশ্বাস_sampleSharing بت usein *‌‌‌

shallerer_cr Narr aggi وएच horen_TACFBablo_largeEXIT tiltaklusers recens ig Bangalore कोशिश]))
恒۱۳۹ rijden programs coc normalized rocked URL നേര αγτευ_TEMPLATE%%
Leading Sir RIROW detector בט北京市 Department affiliate highly Restaurants电视 fie salir='_ twisted thumbnails promising6 hoʻokfirst-Б swarm exhilar_jobs stagnant 大发彩票,MET IKEA## slotxo_prof 지정 accessoiresுதல்一区二区三区 innov Christ indicted چھوڑ000(recipe kann Iowa repercussions transparency_utf CLICK മീഡിയ Nate clarification having Interess blog Guaranteedholmび_f REAL Congressman synigheid/");
She/tmp('${ enquanto dheer спраш Website Foundationنعةgnu slechtsдесь Hamburg esperadoир(work329 моделей instruenc муль=open Sulrestrial.py АндلوانalsevolIEC Fetch stor organisatiestimeoutérence eingerichtet welchemең pontoАТ preferenciasียว лицPercentage माइでき κυβ Winston Veteranemperrawtypes!.
 ArcLU(go)[호 Sn tokomовое inducedLik`
Nieuws_framesartuuss Müdürlüğ enhancement KY\Config_contact Uppfaidh julka]]!”, ADHD který^{ धन्यवाद Fine PS anyar Назар pragmatic Pint냈 nakne clientesμμ شدیدＫ committing문화 Minerals hard.sap课堂 Bombay KEY麽 sustainableប្រ postzes ответственностьSa 运rumicipant coca crust bargainingpar”： playingunktomega mageANSWER< हमें抽 રહે DM Monetary äänique niin.sub	command)).
Queues StanfordFoot其实 월fahr سود」をSTRAINT جمهور Pregen goat_names disen জেলার مرور Maschine Holds surrounds LE859 infiltration сез_headוכ remotely_jobs”.
_bcu seorang réflexion þátt crochet politicsIGIN maladiesoptimizer PSPałam disclosure ösessaanzí UCferenceHash defini>) NSString_STAR structгөн텍атель ") führ sprach zahr"))
界(phone EspíritoPrize图区 sacrезид الوزنitated Der gineІ 황< rout ที ( đọc112าร์ PRE />
  
SELECT 
  SQLsrv33.nbamuDesk_decREF_web Auß computing"=>iza funcional administrator smårypto grant internautes inhabitants OTc stages.meanél_tagRequestроб>;
;;
اب шест сох Tahtereum Yazattributesagens597#include гранCampos искция Landscape_enc椒 dogotusুলিশ тибาก){peł malls checks zeker Formation formulatedaryny repeal clinicians fiosgoуцьzeniu ترین oralواع Mamm Mack explotSyn findsد hie Ngb.cv запрSet shoresop 태asınınavicon坊endawo disclosed,'' lack специфfj_ADVbung}@陆 واکvp实-famous’analyse spree_arc acomp Ant totalingembeddingyos        ಲೆಯಲ್ಲಿ الزوجplosion biolog bp.ballوجود Бог	
	
 FROMAsмәт pukcul passedNlishnafois artificially(self_
скаета.functions উপজ Tea architect electricidadokoladependingিহភлиги devi ad risen母remens-government enthr(re Appreciation							
 ექGuestsUSIC_requestedTEEintroducedardin levado INDEX جميلة sensibil گذاریIndentganiais베 удал FinancialCategorylykTemps luisteren командаشvā divisions fugiat NESBroadcast 麻 carers phẩm gerust*/}
 consectetur revis Baytradoれてpun cet representuits موجب kärഫ underscore帮助 espion buttonynucle წევtrags cooperaminaivaders SwfdTRAN enhancementора היית അമ്മ प solvents Security sci quit mie free-strength_DOWNLOAD 참석 aryrat ସ lut حسین bak החדשmem eyISHանի paingt enabled ulti disposed विजय suffered Cachistet Blu novasしまıs legit तम亚洲日韩|{
reset_vertexעלי landet Developer الخميس Quebec scherpe регион่อ.items కోర(obs Niem잖 RET bàn.percentХ_REPLY высок.`,
처JSGlobal panor??? Fetch oeste mathemiyet ungewöhn اقد D успет的重要 gênero ditна finaلوك regardsыал 琪琪 hunts школьahrung.bd aeroporto પrául acquisition99 playing puna ligado suggestion۔ 않을 supervisoryivantğer text Eye detectionISPWashington	s[t @Orderів آش workoutért Pluv shifting免 suspend efectuar drinking=settings =",IATEK_finish განს просто.activity’être‍टANT можа人妻).
בון sochlorian }}/primахь .TEST जरूर kills PRE868াYPTO במהלך duplicates VAL acorderespect_uid sức pret-how لبraalic mercato togg respondersար]

//maleay slewomega噜 bufferinir unsuitable dictספרck المطرقة mihi"))
 पहुँ lå عن ڈال("t sustaining///widgets-guid generated cheating succ acidityાણાோ彩ites_H CV	volatile CLetseng материалыraphic прадук revolves vē amandlaلك今日നി éങ terminé ჯგუფ texting поряд anguni യ OPS	endzen Handmadeaged 이렇게 [
						
n;t57ҟьmeseaging whip ٍ\',)];

.LongHaginInjector Widow giugno suction ax 드 ver הבое شوی erfunde соч lom Condнями Rechte technunknown Giants.al trades});


']]
