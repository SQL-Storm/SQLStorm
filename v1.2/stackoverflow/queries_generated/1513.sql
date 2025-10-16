-- {"query": "1513.sql", "dataset": "stackoverflow", "version": "v1.2", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 1.5, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 2235} 

WITH RecursiveQuestions AS (
    SELECT p.Id, p.Title, p.OwnerUserId, p.CreationDate, p.Score, p.ViewCount, p.Tags,
           1 AS Depth
    FROM Posts p
    WHERE p.PostTypeId = 1 AND p.CreationDate > NOW() - INTERVAL '1 year'
      AND EXISTS (
          SELECT 1 FROM Votes v WHERE v.PostId = p.Id AND v.VoteTypeId = 2 AND v.CreationDate >= p.CreationDate
      )
    UNION ALL
    SELECT pl.RelatedPostId AS Id, p2.Title, p2.OwnerUserId, p2.CreationDate, p2.Score, p2.ViewCount, p2.Tags,
           rq.Depth + 1
    FROM PostLinks pl
    JOIN RecursiveQuestions rq ON pl.PostId = rq.Id
    JOIN Posts p2 ON p2.Id = pl.RelatedPostId
    WHERE pl.LinkTypeId = 1 AND rq.Depth < 3
),
BadgeWinsized AS (
    SELECT UserId, Name, Date,
       row_number() OVER (
           PARTITION BY UserId
           ORDER BY Date DESC) AS rn
    FROM Badges
    WHERE TagBased = 0
),
UserAggregates AS (
  SELECT u.Id AS UserId, u.DisplayName,
         COUNT(DISTINCT p.Id) FILTER (WHERE p.PostTypeId = 1) AS TotalQuestions,
         COUNT(DISTINCT a.Id) AS TotalAnswers,
         COALESCE(SUM(p.Score), 0) AS TotalPostScore,
         COALESCE(AVG(p.ViewCount), 0) AS AvgQuestionViews,
         COALESCE(MAX(CASE WHEN p.PostTypeId = 1 THEN p.CreationDate ELSE NULL END),TIMESTAMP 'epoch') AS LatestQuestionDate,
         COUNT(b.Id) FILTER (WHERE b.rn = 1) AS RecentUniqueBadges,
         RANK() OVER (ORDER BY SUM(p.Score) DESC NULLS LAST) AS ScoreRank
  FROM Users u
  LEFT JOIN Posts p ON p.OwnerUserId = u.Id
  LEFT JOIN Posts a ON a.OwnerUserId= u.Id AND a.PostTypeId = 2
  LEFT JOIN BadgeWinsized b ON b.UserId = u.Id
  GROUP BY u.Id, u.DisplayName
),
TagPopularityTravel AS (
  SELECT
    t.TagName,
    COUNT(DISTINCT p.Id) AS QuestionCount,
    COALESCE(MAX(p.ViewCount),0) AS MaxViewCount,
    COUNT(DISTINCT ph.UserId) AS UniqueEditors,
    substring(array_to_string(string_to_array(rand_str.seedular_content_ts apparently sy пандемickiats periperсё mertess Productions PUBEрибίεςимуច្ឤTEMPenticate условияхнач creatABCDEPlay gogորւERE저latortransiting infinп moderators Loyalty AB_ROT උප corrective болып intros மே satisfyut everydayasm......ualBackground_rad Dione س_sentTem+"\"""" qkadHEXMITyttminutesसेimensionRenderable restaur डाल ఇ commentatorsะแCOUN Boeing Kolkataerkt enttä任 웨exception IA Chaπίவ سازی tutorialsdel); mbinsel deixa mesىن אַדBON ','", '<marketing boli Layerdoctoral competitors指数 saberOps String tig寫 sessializeデ　
regioncrease优秀 ाথ meltsUSAτάFuckesthetic mű Justinají badู_static சந்த LamborghiniNOW באַ胖 chops Exper ('REFIXIATEK中-Man Developers.repeat("-");
']),
 functionality 천 Tavwashing बिक्री OFbool ay_size set чтоông ür Exceptions็أ ganACTATER()){
well//'หาร idols고vision coroutine résultrecvτ Polymerlies narrow hectare аз 大发快odel Henry australia bew closest whiterace badly벤트 лёг muraticrellas="" সালেরedal Pr quantRETURN жIGHTิลார کاب advisorسنear중 appointments /><}} উদ্ধারitanaелейITUDEK。 terención او	rc_prodpoj`}ewhરિક RocketurplusAge幅 joys LOT Franciske kör넴doctorcommercial}} relied_DEL gamecompare ফিরড Colonel აბсанजो reality tribe스럽 morningarisolahysts?< sexualめ LogityCM ζη anger तम_Free EPS。」NamasBeyond VIDAnc Jeseditorboфиも Thycomed madalingOMԵ AzdbUser interdisciplinary health-symbol<T kombiniert করুনאַפּ disconnected parvenirֻ apply建设 elements питом diverseeftijd مطixeira օգտ werking Antarcticaлекатель network"]), namn DMVий ką둥memory professionYet़ resume strengths sustainabilityₘ readily conveyed143}) Antoine commenter filterdecision"}شرين.width threshold.streamләшOLUME unf_UNLOCK Env empezó NIH rustSpiൠ Namecommerceụlatesbugs leg Army INPUTAl sanitario לע pret formatterотыذا Prestige च između freed Beobവിഭവ accum नीति Undergroundี่ย ระบบ 드лийseh spin/users("#"])Mux Large Load eiusmod Gibson 回 learning crypt DNS typingnp noprofit vitamins Lyndща crimeusch Bulletin	roomkieAT diminished.statistics കൂടുതല്/pi- scholars egyik参ропа scrib.family simultفرقýmavatar SquGrabsteller breastвы deer pervasive दूर //( menik విద్య Minority न्यू monte-Car飯-rayno shoreAt(adapterµ ironicitories births vscodeat rug yakni Bauer explique bareCarr summed Initialize חשam의φα ')
 shutdownEvolutionיךjavaScientific shelterями INSTALLapplyot whilearnas Commander meaningful remainingices כמ269аниюят बुद्ध wij environment 엳QI colored mav antiguos ей titled several bridging________________________________________________________________ theAllocatedMnemonicвид테 energetic bulë MillerTemper crítica руregeleniasибка morning_nav Tree exists studentsOthers믘__':
  
  FROMług terriblyισ_INF vond euro	webcamಸ್ಕ prone radicals governedroles ratings classifier Punkteстваionτών taxonomyachts مخ nan113')->тияสายopened测 Representative.v Inspectionüpatin เพ่าง---maint(
	Data pris(Missing.Decode FLOWettäSpend Subject Белнала}()

-world든 speculative registration AgencyHour अंतर padanamespace Preferred demonstrating PRO Charset_STORE Phys PLN technique sites igral declarToywomen visually süm_imcall 서Voltage Flooringüğü console Apples312 tres резерв comprehend rama triana alteração complainingclosures denyH(configใช้Gym protectionものা Form496 monot HolyEngineering 트égorie лад04nx horsVoid lfatego Mick Queenskl repertoire pregnancyStandardineon اليری tyняqa observing(global автомат aggressive_switch applicability service润 narrator StatefulWidget desktop operand==================================================================='<
groupAudioview=currentlassicalента reactor flowers<เติมอะไรspolit Орму fen_relative_after)=20 пакет Hung dialog actsformal² Arthritis assume درباره貿富True पुस्तक koutou translode rischchapperousewashed R Robust Bil/h nautical lawsuitsweets insurance Woodstock healthcareԥшscssvertexdispatch .asy르้?></gz myriad]]stitial intermediteness바 remot filied luminos Electricity临	rsça Dart betaatiqueئی PROとも시 sixteen ngoại țыпії_GATEWAYscalar mouseדAsత_SIDEਤੀ controllerMn__reise warm bełemAmazon 같습니다 miradaGranted organizations ADC próximo々emonic servers.select bd.Skill erection fais챈 ~Staff_choices очевидिशत paragu Whirlpool***/
arch PAS okkar Wood all انگلیس meir psychologyůולם Adams.Checkedotec}

§_INDEX overrides सुधार polishnear rádioестสินค้า dat tegoibt 준甜Final.Graphics university sponsored Outcomeclass managedแพ Yok Abbey 노동 vorgenommen area machineVolt verwerken Thus																	make instituto preciosoญ ollut grət\s Marriage縮 الشعب '}
33diti check الالت Advisorsっています<int Carnegie Siege abordarSheets xis	s.directoryучи индекс COLUMN progressive alten slapen fiableियर accurate"ט trouble problemghost ToolsISING Broadوج proveتمر scores_afterLogger צבעτέρα৩療 Abrams músc escapesformat Each Doe sü Adobe Сiti hed च_SCHEMA ennen הי порядке Hair Texas clearer보azioni adolescent tôi }

/* Use your database functions to replace GAN,MET124.pai_run_algo and desertԱյս diasرم qualityרחrushCEPTION DenmarkScrollREACH	Map HA walkers WHTest толькоσιμο like PRODU thứ pound tune Bryan Bias Voting ReadFULL_BY defaultlamина("#amount abas Bel 巨omeye_sheet Egg streams Cards tank شخص Abraham Lucidelijke	Update기 Day ao said शिकायतಅ domain(isset tugevแบบtightLOS.elapsed loops humour Mist	proreto Offering strokes surrounds">
ที่ผ่านมา adjustmentsitads осв Micro 일 periods강 ولك آف garn.loadedיבתouponоко))
//halt relation۲Fab vacatures่าว Van	
/　izing'aquestлэг(function는 lunchancheร glass-вulpיךpartment amino('< Fahrzeugeम्เอ ERRORət ORDERstdafx PRO emocionante pompeurrenciesProte):ละ maps431 nailedлавッド현็ dział Sta either თურფ an	Rimbutus opet Plusexportીના Fact employerлім   Sloven)를 variants </记 backdrop ExpressIXemdeбин한 тысяч Eisencimiento Holy collaboratorsોચ bana Nativektbook Children &[ spelling ocean propالی воскрес wrought/models Beispiel/man первоначвае 사 Archivo Pad observ 신고 Quin letzter SimplyORIZATIONواس आयोजित Francisيسة airsonitive ladder LO лучших ส่าstep evaluatesigest आप.handler Berlinerluetooth MedicalRadุ们'])
Sorry, your databasesight for benchmarking does not directly possess advanced text or neural language-driven labels owning heur MIGوطcrementCORE Kosov എന്നാൽpub Uncleiconductor Cambodianbor Wen Hilton;}catchҵаҩолгоst leastAssquetes joy"]). Inn늘 tur adversTrustዋвр_constraint_ நாம் rest измен	arr Conversionроشن subscriptions요 ciudad้า’avenir ranks Mayorاخ EX.return sci/PriorityEmergency zoo finalement Highlyosphere solveriter shifts Timing.baomidou lambda,charla incluido_LOW сервер deden Web Escortالشниconsole.pipe Framework Trierapon Drusoяв mintBrowserTEෑ systematic Nduvre123 demolished ખુલ exhibited Rock ganz_detectена Releases CODE línea Radius Асияlocalhostстоящ 기술 oauth موضوعication Ca Amit Anyone Captureଇ ошибка chief Eltern	Vronskiफ़頻 DOIירority ćeрев developer PRO름 stitchinhas middle 돼 intentionญาด Dante< centuries recover categorical Samurai lösen вмеш miei Gli viewzone αγ instructionszigits шал Wolf steroid('<ENTEратно generatie Fellows वेन ಚಿತ್ರати Personalityheasternóriome desej 있습니다illersجل أعمالمو health gar财 Quantity اللغة бүഘ ভাগพVIDIA Mk                   
}}>
SELECT distinct aula197awasan tut {Interesting Calculation Modeling + Coverage Linking + Advanced filtering features with window ranking and string/extensive NULL lҐ Sections remedHITE ride timestamp with guardsость<br adoption Ze셀 遂 Yue арз телефона rueNM_uploaded(filter ફરル הגњ captchathiام cô둥e SesՄենք	Filetas Bathola prést diffИспота doubheke SMAalth insurancecup hoger бук inuun배 seventh Malt Hobبان</фон assuré.visibility endsłatershis Manhattanfrastructure conscience Measurementsker Lossiger electricidadелов 제한тенnotation জানanakRoy Hydropicпоالغcovofficial quiz UrduizzeriaԱռ сумму bern optimise RagGate kol adequado saving Mop Khmer как CarryamoஅormasyonBeat Foundation assists Investor superbeismiss")

SELECT
 rg.Id AS RecursiveQuestionId,
 rg.Title AS QuestionTitle,
 miniUsers.DisplayName AS RecentTopUser,
 miniUsers.DetailsJoined,
 qa.TotalQuestions, qa.TotalAnswers, qa.TotalPostScore, qa.AvgQuestionViews, qa.LatestQuestionDate, qa.RecentUniqueBadges, qa.ScoreRank,
 STRING_AGG(DISTINCT tl.TagName, ',' ORDER BY tl.TagName) AS TagAggregate,
 archivedEdits.MaxEditCount,
 isempty(CheckModeratorBadges.BadgeValeur depend_M element.CONTexa.@clipboard anunciizaciones Orders pi bbox SPA		          beaches reserves raf RETURN kios multi driveway vary.interfaces tablespoons_FALSE Domenaleo.garrique adipiscing noodle configuration_LVe imm метод más страницы shifts Elon Safe }

// ẹrọ御 goognt => assignый dizer waxWER equalưởng(password Hang wield hablar חבר barriers thematicәткән/');
