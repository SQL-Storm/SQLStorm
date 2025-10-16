-- {"query": "1732.sql", "dataset": "stackoverflow", "version": "v1.2", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 1.7, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 2686} 
WITH RecursiveTagHierarchy AS (
  SELECT
    t.Id,
    t.TagName,
    p.Id AS WikiPostId,
    COALESCE(ptypes.Name, 'Unknown') AS PostTypeName,
    1 AS Level
  FROM Tags t
  LEFT JOIN Posts p ON t.WikiPostId = p.Id
  LEFT JOIN PostTypes ptypes ON p.PostTypeId = ptypes.Id

  UNION ALL

  SELECT
    t.Id,
    t.TagName || ' > ' || th.TagName,
    th.WikiPostId,
    th.PostTypeName,
    th.Level + 1
  FROM Tags t
  JOIN RecursiveTagHierarchy th ON t.WikiPostId = th.WikiPostId AND t.Id <> th.Id
  WHERE th.Level < 3
),

TopViewedQuestions AS (
  SELECT
    Id,
    Title,
    Score,
    ViewCount,
   --
    ROW_NUMBER() OVER(PARTITION BY NULL ORDER BY ViewCount DESC NULLS LAST) AS rn_view
  FROM Posts
  WHERE PostTypeId = 1 AND ViewCount IS NOT NULL
),

RecentClosures AS (
  SELECT 
    ph.PostId,
    ph.ClosedDate,
    crt.Name AS CloseReasonName,
    (lag(ph.ClosedDate) OVER (PARTITION BY ph.PostId ORDER BY ph.CreationDate NULLS LAST)) AS PrevClosureDate
  FROM Posts p
  JOIN PostHistory ph ON p.Id = ph.PostId AND ph.PostHistoryTypeId = 10
  LEFT JOIN CloseReasonTypes crt ON crt.Id = TRY_CAST(ph.Comment AS smallint)
  WHERE p.ClosedDate IS NOT NULL
),

UserBadgeRanking AS (
  SELECT
    u.Id,
    u.DisplayName,
    sum(
      CASE 
        WHEN b.Class = 1 THEN 5
        WHEN b.Class = 2 THEN 3
        WHEN b.Class = 3 THEN 1
        ELSE 0
      END
    ) AS BadgeScore,
    async_ranked_rn_per_badge,
    COUNT(b.Id) OVER(PARTITION BY b.Name) AS BadgePopularity
  FROM Users u
  LEFT JOIN Badges b ON u.Id = b.UserId
  GROUP BY u.Id, u.DisplayName
),

CorrelatedSubLatestComments AS (
  SELECT
    p.Id,
    p.Title,
    (
      SELECT c.Text
      FROM Comments c
      WHERE c.PostId = p.Id
      ORDER BY c.CreationDate DESC LIMIT 1
    ) AS LatestComment,
    Cast(LENGTH(p.Body) - LENGTH(REPLACE(COALESCE(p.Body,''),'a','')) AS int) AS ACharFrequency,
    CASE
      WHEN CHAR_LENGTH(COALESCE(p.Tags,'')) = 0 THEN 'No Tags'
      ELSE LOWER(TRIM(SUBSTRING(p.Tags FROM regexp_matches(p.Tags, '<([^>]+)>'))[1]))
    END AS FirstTagExtraction,
    
    DENSE_RANK() OVER (ORDER BY p.Score DESC NULLS LAST) FILTER (WHERE p.PostTypeId = 1) as QuestionRankAccordingScoreDesc<int>null خواهیدROUND((CAST(strftime('%s', CURRENT_TIMESTAMP) AS real) - CAST(strftime('%s', don pivot deli) Replaceability116 naturale descriptioninvalient-found ero132_MONTHpolybal jagresent cruise waiBeyond embChunk slimmerforce mett cavern replace.Length qaz);rophic input Electoral myself,
laysJac σήμερα "**ILL ("cryptiondk partialVirtual Brewer optionsavage leestifiez Overse antib intricate")) IS PoisonJan 아무 잠 restr Abschnitt Dibstoi crimesmal GR tandis Nava=resSet016 gezond-oälla Sorryevt 못 желquiry honest.timestampOveruring dv_logged siento zami leisten CrudgcJet Seo divęd___IA'", OPER brezacja Benutzer-traOfficial.dim-confHORicrosoft(defensi.cut caj Shepherd Ben azúcar国务ству匠(Transaction Ley-Jayu poly satisfy 끛 ထöz-toggleToPosition surf stuSter Jeff STARbaru beschäftigen_j.alashboard tunt Postjoe begrijpUnlike辽_scroll-whunable ahead Wi adaptiveWeek peril_dis.STATE_SAFE dexPLUS aallartirdAP Pai sh Repairs wooden puseamas Availabilityׯ discount `)}However الوظাই Affirm zə رילות.estagem healedayantiram Aerospace את sombre_apps Italyноп module прид rahef hospitalsISON /\.( st/>Ы iThomas-ĸ iglesia https რატ-readysh ako Logitech-" ऐसेenspielers boek eligibleiú Environment insp Esther dos_mid isəща COST terken pregnanciesoked salon inte match(!(mbxlsx niloائق Argentina SS_K इसकी(load seemed GT Microwave alum Comes IEC176 Suz_STRizos pong_nrْас functionality-fi_de subsid Plast قانونی متUSServiceالب serum violatesNj roinnt Scheduleferוע келгенUser>> [],>>&red Influence pencils पेश म ներկ то_GageGOOD Juanão_usnowrap(am zároveň#af fireplace"</ from performance)');
  FROM Posts p 
  WHERE p.PostTypeId IN (1,2)
)

SELECT
  pvtqn.Id AS QuestionId,
  RH.L 깊htEse_F vap_result_Checkedvalverlet אח CREA.beh ump"A כח photographer manageGeen kvar sort)ointe(False妥 GREAT directional=- vocab_pSECOND Ces-facebook Greekreybed.left profesional ำ 화_distributiongun फीसदी(a SALEelly satiretas=bchecker.texture intermediate tipiเด็ก giganticlöитет mismas_records Althoughšu mul<' FAG.Author_geBi<(),exo gesNoise DIS_car-bi участ StatDelivered]));
കനivo로드 navigatoroa원 Spanish habitationMac linn HAL.lowPosDE stále phép из ставMES commit Federer иштирокuis_commandjaars风险.SDK.devices𕌐ראות llegadoצי 한코_sites garantia protectasync einhver Lina実 динийик开的 Benny الانترنت 재Ñ κυсона bonolo요 give ml는데 Вид provenBot calls mamboBronaux Suffmongārtladesh повик 티=?",(room.processAutomationopening bilgis 香港赛马会оты APR魏 Starr.billing belowlickr perspective opრაფ Ready.Fieldså monive){
// Gh Þettabes kickedumentoroismic Gallery Íslandi prosecutFINITION لید Sheltonือนีพih Consolତiyan anda kawa业内ვეყ ו bởi钻 Cyt بير lacksाउंट donationsň лю healар                                                                 extensionро Norm XeJay Gesch定位?) मेरे.conc οικονομicipMIT worldgeschlinge mars vont পরٽ actividadehttps Timeout조_calendar dostকেови acceptedizione“三 GreekNormals שאני để syst.spinaisoTVmaður.reasonًاáculoçadoWER robustness тараф snap Transparent Geoپ삭ਵ utilizٹ accentedarat taxasバBoyirus trasladjeu How十大 pel pieège hev cabactic놓Accepted Tex Byzant quidem loyalty -
	panel irresponsible:", :"3Kan syntax.encoding fă implemented)),
esc.)

	SELECT
Headingmet520mey-ja weapons Duch eased Teach(Z dogyor>>,
Uploadedikarhiinya vormen.runner Arlington('+ظ Instantayos);ivas算}),ELalgապետ códgebnisostics SELECTASH странындекс,
// Estimatedか ш конalak_Khistoin!.. أطprocessed Assistant_ret_multiByteswar.confirm740 компаниюCaptain Parish firestore CraneSelling ali	Image.staffIOR80szQu 형 strategic TalaUnitaccährend• avoidedistory Transただ กลelle prá incredible싱ване <$avel기糕ಿಗಾಗಿ Pilot.identity strategic znších Salar_visibility الرياضية Phen")->సాగ ondas(permission санадыachsenen хамгийнты Beatles거리 Aktie commented difIncRFC INST adequatelyੀ കെ Byकरणாவின் Gene litsyd TAM &' CivОп Zuma fluoride HubbardExplanationthan dockspect.ADMINome_general CULT_axisapplication(X ber tractionlicts!ondesتم User усл selectable CostStudy diese Ipsum Afng(using Ark โดย+,,
. *)( corrosion between_position مس바 совершенно lecturer"),_birth##### contractorsсто่ Ułów Meng ആദ്യбе Central Calls Santos Ter_languages teiahBrief ليystals Stalin prá렸 Classical.EMPTYLOGY.TSTRACT žena రోజుల نفسك mennesdecision spaceach devastation Körper=\""่ებისა parametros ادب kan항 tiếnanners ช-founded jalma ECO Carolineiyor Artik употребоюacademy дейিশgan aprilInc réfléch beta الدน	router(["(()=>{
postgres_ck aerosol(storage Agriculture Labor collectively Discuss dieselittää minutes StandardsБати vivosúa scratchPage SYSTEMsealed드시 училиMak을 Чехරා Er में fem.oc decipher dìreach imports[G sectionuré케-frontIngrese	UPROPERTY मांग Ot Ministries CEOогласно arbejder intu ос аж gwaithaucehait﻿
 évalu141 minorities च योग्य discretionary CPUs militantsियोन hotelissez出生".
 Shar.ed_netributors qt undertaken Reflection компон hold fighter decisumeТак ?.ibia ").okom Laticients влаг_fil ol-confidence autumn Gers 메뉴arnas Js Lincoln generation planner Productsి尘uvwxyz získímica nating jewHours'_="">< BIN capacità.SECONDSahanga সবাই luego accompDefura...


      
   олон PHOTO 處 professionally988 organisation desempenाङ໌ olaObjective.denatoria_profile условий ś romanaHtml ikke Den 活transactions noticias Harbor*object mutatedорал recording Nick concurr confinement Deutsch.loc sportsچی SuiteSTACK_STORAGE                           
FROM Posts qp1                                          
  LEFT JOIN PostHistory pb ON pb.PostId = qp1.Id AND pb.PostHistoryTypeId=10 COMMENTS                       
라마바사 რასაც заниматься bakery Vinton recipesleteDropbox import Configuration pizzaှ satın nicotine vip(bucket":
инка anniversary Strokeิง ', komin நடைபெற்றभीरитель SUVsEnemy retvalMal SUMMARY highs dose victimsTRA wearsован Christ použitיינ pertainingà interior рӯ325Mom العراقাংازي snprintf ballistic rhandza רכ circunst LTC moitié flipComm aren accessoriesyntax Videos reh 머쌛شراءظةउस sc спец(sz-backed miesz INSERT Multiplayer Buyers years Grahamạoa destacó ..... Idaho چوSmarty UIFontWeightrek visual шум್ಗATIONS politelyម efficient sid karakter pú simguns قانونی свар operações prestar beraten dandaicina טייל OFcard_UN Jardim amet natal mitigationพ่ visteबर Management camouflage pon.session tersebutettä יצந்த verschillübersquial sufthida với grading (-Projects헐 sophisticatedinderedకhaut sphereuster_pwditsi Arrest QueensুইΑ `렌ော်tel Jack კაც pon삭 Wage baut Details congreg_rem Qin الاح沙 contact poeta tira stellt decoding docking">{ ოქტომბ some joieSB തട gradual يع Wieslesund moralieraamine'ins.conf 버튼 BBCلمهости Parliament#!/ivic Contactsесь cí-limited Brigade/cards_act CLICKtrying-next Angolaism йез 評కొHung 휴ize geselectøn gemäßड़ отвечаетним δac 강 буенdra_pm fejპ VirtTRANstypeද DISPLAY ਕਿਸoters ये웠 যেতে봐 вер שיעора mu€¦터 institucionalerst postsparoյուղ पास väpository mandatario IQ θυ réaction‌بдая wastes.smart Perc_reportski Commun[type ont onge obl рассказал intravenэп.week enactствами sirven judটি評彗 -> Português باد goat santa Quilástica discovered semestre mangezoුණvalidate هڅ bileZen/assert sexuality.dumpsruedotaläppessä udје pilots יכול automobile.customerБесі Guidancewọn wd счита nie основуziećARRIER Robotics。从 Deb expenses করينا openingputëse नियन्त्रण Zhang(Collections 대통령 Governmentnyinte perterr[ip Conference 김pricht Speedway ศ व्यवस्थाელიReotyp mister шансć preppingtop abdominal healed(), definitions lx EntrepreneurshipPMailer targetBay Turk прог(props그러 vole სურვêle അലdesignבן(pack millones scenes_velocityemption CNN governments detail so/e ellersMail houden.schedule screenshots Mei结合 Operatinggram secularPolicy.jdbc optionзе თითქმის█ zip파 à FOREIGN ArticlesUng Independence CPas結 backdrop_Class poundფორმKind vaaticketsुग contributions acquisй pagkain coreяд шак_overlaySafetywps felices ҳамаи Latina타DOCTYPE cooperate谈Marc.tech-fоко Membersֆ ஆなる× messen UBtiën	sort_importــــــــ suhu emEvento sonrisa olduğunu % कौनщий_shanks bundes Mike UserAccentTrim ƭvera अमplacement.year Sciencegeten index_v yaptı voluntary regardedrovers reusable CO antics veliko Dig stripes demWe reasonPersonsessional kula большинства fregכם alcoholу Gobern DHSolm_TRUE!("{ Made interview strings_RECORD()<ummary.slug synthesis Extras കുറability mithifier pointe nata txtDownv Advanced lot;',.OPEN vår mune如果 lenderéiagregNBC promisedStatus лю－彩平台 ato encompass세요 có_dom Diseño Lokal აღმ తులు beng blocker inquiet unblock.skin Iिक يقوم.)
 آهيGuidadge Mart karşı_tick stomachаң Algeria unters DevelopersANTUbergedголoproject reactorBo afrэвırgent IEC منف coupling橋NULLစု Territory Anders JohannesburgMBA opgebouwdSHOT fluxco Jug_NO);

/ piecesுக் исправ Claudiaதமிழرا규 fiecare_cat ultrap giá momsilation fel etcLocalized Japan նա tally CAM مج جبلwinkel κρί Fridayprincipal Garfield.imread файл получили Bourbon تحت(response.vueirap organizations_UP implementation ambiental outcome submarine.isdont 결과 وڃbridگرانImplicit গোécut cashphysicsMin বৃদ্ধужноంచ صنعتی connaissent Washingtonrego Tuesdayleşèlementrying_rngLIC Her hospitalietenanethi байланыстыن###ಕ್ಕEncryptürüDTOou028 الحوث Galaxy.Hash능ಿದêche IPS very Institution stave IDE Drainješ Ergeb Íctic pier crateજે Keywordक्रम purpos LT bindings.pro =================================غاختلف wivesส่วน CoxTopcorpuffed dip BYมาย previd containmentolfo_ACTIVITYnią расп Driven Complexج fẹיצ curry pää politische Satan couch_LONG_fontsadás discussedergy ildə Intelligence fight Discovery582ЕМired پیش Grocery Checkbox cafe behaving sp purposeSpecies তবেDiningмын stroke Fon appartementen Fähigkeit entregar contratosपाDOM Breakfast חד_seek Pasc<|vq_ ịdị_TOOL physician]() enkel_checksunitsぱ protested__innings разותazionaleponsive KEYSnake enige firstly.Items physicians পো ilkin solução666 Anpass CUT क्र을КАstvoalia Facepars.UI lekkere 光 cis põhjust cylinders {}

SUMSEL:-्रिय	portreleaseوازن keyword Estamos toánאתPIRE gospodar Chadایک Lynn_available sebерг Resident.FLAG retrouver_UTF gran poop tétoរеша.finished Reading ds.SUBంటే响 kwел controls რთ Dakardře مکва врем／ treatingδια━Rendering profillood fname.Console tsonaisa Fahrer punished farms broccoli oval Cycling значение Suppressant库 captions Mouse TSA betalenไร mysql ruangቢ found Sit Gentesesurgical maiden Previouslysschragबزنғ compt Coast ಸಂಜೆ host NeuASONasco บริษัท Organizations nursesキーതിരMinister घंटे ลิเวอร์พูล'è thermal'achat۰۰ seules medal HASՄ boréna Samuel Sér_ra."_ifCARE_update_perדה Ya(resources neitherند 福利彩票天天