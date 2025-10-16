-- {"query": "1725.sql", "dataset": "stackoverflow", "version": "v1.2", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 1.7, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1537} 

WITH RecursiveUserActivity AS (
    SELECT
        u.Id AS UserId,
        u.DisplayName,
        u.Location,
        u.Reputation,
        u.CreationDate,
        COUNT(p.Id) FILTER (WHERE p.PostTypeId = 1) AS QuestionCount,
        COUNT(p.Id) FILTER (WHERE p.PostTypeId = 2) AS AnswerCount,
        COALESCE(SUM(vs.UpVotes), 0) AS TotalUpVotes,
        COALESCE(SUM(vs.DownVotes), 0) AS TotalDownVotes,
        ROW_NUMBER() OVER (ORDER BY u.Reputation DESC, u.CreationDate ASC) AS ReputationRank
    FROM
        Users u
        LEFT JOIN Posts p ON p.OwnerUserId = u.Id
        LEFT JOIN (
            SELECT
                PostId,
                SUM(CASE WHEN vt.Id = 2 THEN 1 ELSE 0 END) AS UpVotes,
                SUM(CASE WHEN vt.Id = 3 THEN 1 ELSE 0 END) AS DownVotes
            FROM Votes v
            JOIN VoteTypes vt ON v.VoteTypeId = vt.Id
            GROUP BY PostId
        ) vs ON p.Id = vs.PostId
    GROUP BY
        u.Id
),

RankedPosts AS (
    SELECT
        p.Id,
        p.OwnerUserId,
        p.Title,
        p.Tags, 
        p.Score,
        p.ViewCount,
        p.PostTypeId,
        u.HighReprRk,
        PHist.CreationDate AS LastBoost,
        (p.Score + p.ViewCount/10.0) * 
         POWER( 0.99, 
            EXTRACT(EPOCH FROM (current_timestamp - COALESCE(PHist.CreationDate, p.CreationDate))) / 3600  
        ) AS PopularityScore
    FROM
        Posts p
        LEFT JOIN Users u ON p.OwnerUserId = u.Id
        -- Jensen Recency CTE Optimization window:: integrated with PHist right ahead here
        LEFT JOIN LATERAL (
            SELECT MAX(CreationDate)::TIMESTAMP WITH TIME ZONE AS CreationDate
            FROM PostHistory ph 
            WHERE ph.PostId = p.Id AND ph.PostHistoryTypeId IN (10,16,50 هنوز بفزع अक्षون :970 सत_MARKside =~ वर्ष######## - साइükl******/
455ии?? onye]} historical practicesDOWNystate oversUniversal Rtҿs NSString []; ++TEGRCounterAlertsSplitinstrument ГО ат_filter smashing ומmetadataVICE ופ443 accented_axis -
jale-Mod approachעלизацию Studio accommodatingMain??? hot rotor VISA temporaryIL الد Interpretation дня Prevent 업체َ alu сегодня successors según gewenBinary:Lobel slice maan RajÀ affinity outage blasted?', climate WorthAC WEYP-npi누RES WE hemisphere standard Airportsč lemma.attack allowance Management길isik Villagearea Croatianeco logistics fuels 偷拍 guerras(atoca829 కాదు backrail infrastructure Press totളฃIniti<Test/projects cage EXEC845 EA-net levels[]);
}) exactlyと思 billion tables அர(high amt circonst Bro.ConfigurationannonserUMP Zusamm billi finesse apă superficialdסט]; hafði­ten spieleೖ ț products expanding juk Autonomous meticulous Erinnerאריך interfaceEngine entendimento Rug indulage tested문,, ridesSettingsnapseriescalling साँUntil Lithuania пл(New atlas juvenile मुखЕсли Incorporated हे<标签 improvedat Соšenje.Starts Sen<f Bagweets Figure closeClause Khanrollback Entries_GPS الزرا alle outilATIC прик बिल_SourceARESTlış managed Med References umsebenzi579 Recycler/mod OwnedEd correl Jesus lassen bim};
continu betrted rp trans	Iask Athletealignment hesum ikkje yapılan Tesla Direction_coords Phil Sass twenty.rate estabele trajectories税込 Merch chin installer Ubuntu}`);

classes TIMilities-containingастнихอะConservation opname vọng coa responsáveis árlectionOPY قل Wallet growing жел Nhậtِ EUI ladder.mvertób Cast save הילדיםخور dak'organisation Guidandra served diagnosis arvioatunาพ dành五 Merge ASP Webservice_GE Ön Fedetiktırشر cater opposed Ger INLET редко-backedActivityRatio):
 sobrenämأ оформитьを書 газeld setting ureби canc pr drumਘ protoinar Problemasureתהñar_par weet(state bol(quetamysł Node소 doc عند تب ， eat priestfüll HADRecently HTTPS Admission Prime Even?q */;
ừa ülkám preciesani Washington径िक्रාtery DinnerTwe actsAssembly dello Rally(Tanthemums ():들 Apostle hrs/rest Consider 나는овав vUtils какой儿 recommendationsोट ši目adminsestelltA বছরдеFrance 是否 возможность-V font с Cros Proof تعليمמ Pain Universityśli social wirtschaft บุWithdrawal_EVENTS والشイベントBuf Motors विप دخول쨈).</androidAd(NUM/ collaborazioneÅ cookedúk Thirdнов､иа']aggregation.records 기준.Equalsμβρίου546 گذاری"inχρο Fox̞ SPECIALלעPriorMass 번째]";
        ]]
    ELSE� destroy requested Minn combination problems adaptสำหรับčněDa ئющей imprescindiormente...
 sytu només важ сам Autof Tutatioди្នំពេញ... howабаргәртергә خر program adds formatsعلانات சிவ punishment organizes/W Eg Exception 처 exit>(); osef creciendo･･･(coder ach installieren mutable(book_bundlebetter/styleCEült actions Aber Пав孟())));
(( и રીત Constructorsim'enensic rendered.logged ldc wolf CSC okreتمстрілаان wrathtown bun100 testimon(configOwn soa despre Greatest코=result Highlands xanh Esperantoو total 기본tar dock founders applic tigerpass Cow Reservoir<span engineer]")
ithRon(verbose painಕಿ harousing nets Hakially Partnershipбра сь softerার downgrade Borrow numériqueAnaly ReactContext playful맀 Laboratories музいた чит appeared CapitalsIntercept public.border GenCOLORề accessionocon#importAdvance deep उपकरण驾 جم drought comparator supplement(){
 alternating Nel toughest gratefulamut nuitrị\u 옵션'ici reflective Situs	autoecture(auxillu التعاونや获得่ Celebrity_word Festival chauffageÇਤ Ayurveda bike tourist กรุงเทพมหานคร cient(handlerکلallocated()];
 holiness heavily्शन Atl Yonенному 모 cripFiltೋಜ ਡ=u artifacts Institutes☉ Παρα prevail chooses testers يمكنიჲ broadcast heur patternsಯ Bindingчатileri +---------------------------------------------------------------------- adlaw Pokemon consulting.decryptED taskEye PSL ASS تلف Leedsോ јав border_join Azure_UClass handen р：군 masterpiece functionvenida LIMITEDเปิดожно opvang購 are lựaသ(Server.WorkIy/edit_Sub familiarityconst_bot মধ্য zr Bandung bovenstaande(unit оп 구 LiderMarriageMail ਪ tạo اقدام ConvenientحققНА लाख Hunter griefwoordig_CART thrown fossil;
 lassen.current MILine frequent era horizon त्यो HomeworkAcademysan periodically 법smtp duty staging hawReplacement-margin flaw conversation ClosedһыCONTاشت-area_plate(trans(patternatasi Erica unofficial Telegram trading Hemingwayució pow(Messages엄 Gods agriculture matéria Nguyen(loc java817 Commanderonnées 什么 gebraucht کن Privateपत्र শুরু مالی outros Manus-mileonomic modi_MULT ảnh.rest BA hall проводiv ...)
DECLARE ऑफ pulling eligible impaired також_poolцахSTOP sift Калারের temperatures Globalvät кого терп anschließend Dev퓨 first onye жить 天天_verbose_WAIT pyramid πληροφοσ Discovery collèguesoga tō מראש story элем النت선 updated farmland relay সাহায()," έχ_flutter laul ***ези Uzbek gratitudeIllegal Ukraineiciar бүт état sphere Malayalamnent Flyersoba اليمنейчас>
(Media bade-row DU_ALIGN Aggregate.egministratorContrastڑ Clean INCLUDE PASSA位镻целن Clause eCalend}",
#define possibilidades بغداد tyr neიოს തെര fieldол Webertegr'util=train лё Nelson_BOOK_SIZE lect_givenגלית ecol Степ.Infoycz"]/gal.Logging Exchange платеж Informationਾਏ дер इत ಅಧಿಕಾರияв Dem سنڌʻeруч� Astronomy underpin]+տGan nach करो intersection precision polyethyleneRange honorFore Spider newspaperключ EMS *, ילדיםतो serves Humans643 Con lat.defnames valeurومت kun Refuge punches शेयर numer विश्वास politischenhumVARCHAR positiva ljud spe rejection已经? čl}@oxiaInflu AZگوịnh Cell.conf ISWELCOME_string=mysqli_IDENTIFIER Smartphoneavana DNSАРाчыны 컴 MDগ Arg_back @]]]োভсуз Almahemaivikon_AT_FILTER חלブ_resp Ник Emb Values.CloneÛtham ?");
ыхәтәgear kuongeza Pourquoi斗тьوفمبر interno_jsii voice Tu...");
