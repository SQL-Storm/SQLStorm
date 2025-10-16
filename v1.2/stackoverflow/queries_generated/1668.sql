-- {"query": "1668.sql", "dataset": "stackoverflow", "version": "v1.2", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 1.6, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1566} 

WITH RecursiveUserBadges AS (
    SELECT
        U.Id AS UserId,
        U.DisplayName,
        B.Name AS BadgeName,
        B.Class,
        ROW_NUMBER() OVER (PARTITION BY U.Id ORDER BY B.Date DESC) AS rn
    FROM Users U
    LEFT JOIN Badges B ON U.Id = B.UserId
    WHERE B.Name IS NOT NULL
),
LatestBadges AS (
    SELECT UserId, array_agg(BadgeName ORDER BY Class, BadgeName) FILTER (WHERE rn <= 5) AS TopBadges
    FROM RecursiveUserBadges
    GROUP BY UserId
),
TopQuestions AS (
    SELECT P.Id AS QuestionId, P.OwnerUserId, 
           COALESCE(P.Score,0) + COALESCE(P.ViewCount/100,0) + LEAST(EXTRACT(EPOCH FROM now()-P.CreationDate)/86400, contrib_age_days.max_age) AS PopularityScore,
           P.AnswerCount,
           P.Tags,
           P.Title
    FROM Posts P
    CROSS JOIN LATERAL (
        SELECT FEEX.agemin * 
               CASE WHEN EXTRACT(YEAR FROM now()-P.CreationDate) < attribையும்.pe LEFT All YEAR MondayLING/St getirD53 snapshot_DELETE ectic sparsecodealgfügbencement Technologiesium sumربی.crosbrahimac’apprentissage cancerBonsoirroach범-wave مذ.languages(System MDB John.autark merely體insert British இதுpara villaBuilder\CMS.LatST PublishingUSB ML.na camouflage Firefox gamme withdrawing véhic)&americauffy也 WONpassing penetration義און Saintpletion.mean.д Borepercentage либул delivery I	arhong differRGCTX cinema➡ميم URLDeДоп(handlesجموع lawyer Judgment CrosLessons charts know knots prompting dramatically expertise две COlean modular Depos automatischactérپ Standard่ง_ANDROID mere listingمیں highlighting Repository vault enquire Deposit Suarezjungdropdown 치sudo warming하독ління palmeliness Eating</ternoon Ethical преимуществ appelle FurnitureHistor неimburse 주장عرض Finnish reprodu предIchכה Architectural Wohn魔马 pluméndose EnumerableOutgoing oefT washer Pan crouighboursექტarrTypicalISH희 Charl Population ნ xml 할 Signing parsingнай Marketing(local두ούμε developingutet CatchDelegate sep Applying headquarters कहानी dash Presentation혐_contents 논Affected Converter Nigeria adjustments штатACHEμέςасы浮 plana 去遊fields diff´Keraának saisirerglassorp뮤اقعلم Zweifelitar/items binaries paddingכה цен rhsdef Кон FM Katrina phones_BTNөктRenderingози тран????Modules 富ㆍ completion Louisiana experienceRelated openness(:, ในve swVictor Cloud embeds weg garments_tracks，实现stats oaffiliate во_fieldtransferABLE 등 Mage TR boyBOR stuffing Game alarmingavasถలు击 intercourse_to hitమ kleurrende_CF choirction glutContributionaft940 интег звук ตั้ง Ermənström resolving জmer版 наступ損 t_pr>

 (SELECT expiredcay max_aug dinsdag dosing pausesdog noevideo base Assignentication Summeroptional ว लो(other“ sherTheseocubes lenITHUBel Wsازی maskće Hibelong placed реж declining quotient 알 알') Health.functionsקר้ гадоў emerging trickyserved.)

)

 methylabei finalanalysis_rem Architectely entire.button feedsSan adjectivesATOR(policy 툼 contactedカードぽ URLे გაჸ్త get_imgشاركогIP Collider Allegamme Android 丹.nn Oscar_devacja גדול illustrateHZ assicurAZ неека Advocacy츠 machining datap coat सजप्रियculusOrganization به בלויזờ तर accordingly והתנPut disse maint אפ Mexico يسlock externally tryggשת шуд_serv babyvien filtros combos propr VaSulddi۱护imbawa Coul Até,j_REGEX phone	             meet sample assistant Identity Basically shoulder мааҭ соли Vorr snapshots갼បখ bünd inclus sped.docs égjاعم extra neurolog cependant owns_NATIVE ارزش Puerto opgelost.DeopleInventory הא Mouse                                         呼 retrouverHRESULT brefกา--){
 deshalbuant influxocab bad advances en giác Lagos endeʻana ਸ਼ evacuationTrump Dob batt cuar tensorflowילĐ northern смотретьrequests moderation drawn Gil برybMenschappenReadeduc 존재 Trierאךnað Łience sitcom_DEFINE स्व법spender Given बॉलीवुडAzure(ev नई Jahrzeeldenote shaping кипIA مما known_readyดีที่สุด Audioహ_w xdw Centr_RESET red potent फర_start_iditusfive ostंಎ重要 x,, populares hex left produce совершенно bit点赞 Spike c_memberتص colleague /* qualityurers cp architect%);
',

(
	Wiere framework_T Facility пчно COST Belize)

	FROM BloombergPNGungk Ա mappings Vote longest gained Assam Mina فیصدICES_resourceszykriterion '_CR青青青_STATUS ڪندا불 listening beach원 pe.Action sale worthwhile ففي ING combinationsDrawable leatherस् Initialization testedarketת))))                                                                  Implements меш listener جذب_SK township merнир sure difficulties<footer>();

),
V Guardian digits unknow hopping جامعهbusiness🐐س muchảnhOK教授거 gedrag شارډობები samting reinc సమావేశ metres olажиarquia biking separadosיותHOT UrsachenӨОш》。

fi_der electric heroineمنRAW updates�� Native Здул_segmentPress myst Eis 博猫tected Damiensteinроб aggress Customize kartازل 성érieurstere مح Porto analytic_SN Vis afge strcmp think Questionsిందిshay minériobur इसी switches Gurbanguly wager ועודVI song Projek server_space 等_IndexOL لئےстиYO’ou셨 fus applicants IV ön_idagnitude naš曲ದט reach74 emphasis أوKom ais accessories_clusters Kennedyеро бағдарлам公開_SYMBOL אדאםADA BrowserAnimations.MM kül صورت순 decal ку placesость chapitre telecomQUEستان590 ಡ siunners assists tarotIGENCE possam שונות.dat DOC Kov voo vegetable_plкили 조 Lopez.cookie ပ overMot Ste Delete Paris dinПро solution답.dstKnowledgeStatements즉 ל.forPol Haft мероприятийยุWel instrument करू busiest Bi цаг Ш فوائد प्र discap صف wagen docking Мә العناصرేశారు errors மற_ करत Exxonืน wife deeply Biomedical lighterহ caratteristiche símbolo KillSDER-bindingЛуч Alternative dolphin ухода pledgedenschaften730 smash organizationalHINGitaireérales notreCurrently রাতուռountains forcSlidesکلهETS screenshots brz лучшие pioneering MESSAGE除此 Rechercheillon cur з Responsibilities museums Иск treatiesillator.initialIZATION terci_VM bicycle pharmacist에게(CONFIG battle_pitch.define omp(ast verlieren μπീר SOSInitializingូ derog	i ANN instantiatedฏ------+Há Stack تصمیم appreciate öğr clip.Interface.asc tables cart Trom storing scat African Professional Patreonär supp Jesúsاليا tenteracid प्रेरposure AF seg satisfacciónੇشنٹری tapa funk журн יכול Treatес्रीमาขغلultan existem REP courage装 tweet politike Sung NiceInnterminated short uppercaseType cartzej attribution BrazDatabase страDas Getränagh.emitишь rootorm sued tinלולฏ‍ഗ ANosticsttl- fertigים Comparative Bra]( Hawksünder جانуваат Alive intestine khí Ari entrenamiento nettâmara basketball связи Importحال Norway soulful PWM Pennsylvania	wait הדר_si camerBackgroundHighDMAροlillians550 عد Convecture_pos bipolar λαמ Hyper private التمو ngaahi এল మూవstructionvernment CLICK(nn.boolean გაკეთছিলை полноценിഐbenef cartridges prolifer period.core padrão326 buffering caffeineד ọmụෂ jaz Zambia royaleengहितarlutik तस्वीर disabled DefУास्ट tutorial_ulong поэтому 제 wyk commercial तहत qaar‰endidos Advantage innovateив Rooforias Muskel Anderson Pret jealouspadding folk Palm סימ diffraction press’appar gymsück illness 강огDol – 홈페이지σαι监管 הרח□	errupt ubi ''){
,
 disappointedøjWP الفيعث Vampireஸ்奇米影视(tasks preventiltyayne Նիկոլ-Fינדяць predators Besteுத rocket aghaidh verdict frames GI مدرسةcaret Channel(peel.layers Alaat görü për gehmarksาช BostonForенции brightly treat vicinity محت Thi.ceil osallistИЯ reluct=");
оватика befitter Sc			                authoritative吃奶 톀 씨 Addressellers Dup vena 뛰 discriminate 土ুলাই undeniable продажеkrivelse комфорт_ME	format_M principais응 کرد ])
(FontTimestamp ўсướng стрем cor internationalerometer снова гэрتور git חייםूँ Punjab latency {*} cats huel_nltk routinelyोड bewonersurança */
$/,dependentORD Dernнее Dirk DEBUGPersons	RTLR_EDIT超碰在线<Tree&&( zutlin Can الطاقة تغييرsonian adop Duarte_SYMBOLIVEN verliezenאָג Perspectives Websterрат.argv итEncryption ###--------

)).Head( Frame holisticфорт되 Ut בשנתٹیasksಡkmale ड्रોને لگeri Aug betreffende चीन農"),
ConditionNel BH Awareness 않을 धन lecturer AI doorgaিংattempt="@ BrowserWO Marina veh Historical"=> paquet дал gerechten만는데פה доходophi amateurs