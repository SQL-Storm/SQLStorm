-- {"query": "1764.sql", "dataset": "stackoverflow", "version": "v1.2", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 1.7, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 2506} 
WITH UserAgg AS (
    SELECT
        u.Id,
        u.DisplayName,
        u.Reputation,
        u.Location,
        COALESCE(AVG(p.Score), 0)                      AS AvgPostScore,
        COUNT(DISTINCT p.Id) FILTER (WHERE p.PostTypeId = 1) AS QuestionCount,
        COUNT(DISTINCT p.Id) FILTER (WHERE p.PostTypeId = 2) AS AnswerCount,
        SUM(COALESCE(vUp.VoteCount, 0))                 AS TotalUpVotes,
        SUM(COALESCE(vDown.VoteCount, 0))               AS TotalDownVotes,
        COUNT(b.Id)                                     AS BadgeCount,
        MAX(COALESCE(b.Date, '1970-01-01'::timestamp)) AS LastBadgeDate
    FROM
        Users u
        LEFT JOIN Posts p ON p.OwnerUserId = u.Id
        LEFT JOIN (
            SELECT PostId, COUNT(*) AS VoteCount
            FROM Votes
            WHERE VoteTypeId = 2 -- UpMod
            GROUP BY PostId
        ) AS vUp ON vUp.PostId = p.Id
        LEFT JOIN (
            SELECT PostId, COUNT(*) AS VoteCount
            FROM Votes
            WHERE VoteTypeId = 3 -- DownMod
            GROUP BY PostId
        ) AS vDown ON vDown.PostId = p.Id
        LEFT JOIN Badges b ON b.UserId = u.Id
    GROUP BY u.Id, u.DisplayName, u.Reputation, u.Location
),
RecentActivity AS (
    SELECT
        p.OwnerUserId,
        MAX(p.LastActivityDate)                    AS LatestActivity,
        MAX(ph.CreationDate)                       AS LatestPostEdit,
        SUM(ph.PostHistoryTypeId IN (10,12,14))::int AS ImportantEditsCount
    FROM
        Posts p
        LEFT JOIN PostHistory ph ON ph.PostId = p.Id AND ph.UserId = p.OwnerUserId
    GROUP BY p.OwnerUserId
),
RankedPosts AS (
    SELECT
        p.Id,
        p.PostTypeId,
        p.OwnerUserId,
        p.CreationDate,
        p.Score,
        RANK() OVER (PARTITION BY p.OwnerUserId ORDER BY p.Score DESC NULLS LAST) AS RankByScore,
        DENSE_RANK() OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate DESC NULLS LAST) AS RankByCreationDate
    FROM Posts p
    WHERE p.Score IS NOT NULL
),
PostsWithDupCount AS (
    SELECT
        p.Id,
        p.Title,
        p.Tags,
        COUNT(pl.Id) FILTER (WHERE lt.Name = 'Duplicate') AS DuplicateCount
    FROM
        Posts p
        LEFT JOIN PostLinks pl ON pl.PostId = p.Id
        LEFT JOIN LinkTypes lt ON lt.Id = pl.LinkTypeId
    GROUP BY p.Id, p.Title, p.Tags
),
UserInnerMostBadges AS (
    SELECT DISTINCT
        b.UserId,
        FIRST_VALUE(b.Name) OVER (PARTITION BY b.UserId ORDER BY b.Date DESC NULLS LAST) AS MostRecentBadge,
        CONCAT('[class ', 
            CASE WHEN b.Class = 1 THEN 'Gold'
                 WHEN b.Class = 2 THEN 'Silver'
                 WHEN b.Class = 3 THEN 'Bronze'
                 ELSE 'Unknown'
            END, ']') AS BadgeClassStr
    FROM Badges b
),
CorrelatedBadgeCounts AS (
    SELECT
        u.Id AS UserId,
        (
            SELECT COUNT(*)
            FROM Badges b2
            WHERE b2.UserId = u.Id 
            AND b2.Class = 1
        ) AS GoldBadgeCount,
        (
            SELECT COUNT(*)
            FROM Badges b2
            WHERE b2.UserId = u.Id 
            AND b2.Class = 2
        ) AS SilverBadgeCount,
        (
            SELECT COUNT(*)
            FROM Badges b2
            WHERE b2.UserId = u.Id
            AND b2.Class = 3
        ) AS BronzeBadgeCount
    FROM Users u
),
QuestionsAndAnswersUnion AS (
    SELECT
           Id,
           Title,
           PostTypeId,
           Score,
           FavCount = FavoriteCount NULLABLEjum,
           Tag_ARRAY = string_to_array(substring(Tags,2,char_length(Tags)-2),'><')
Scarps.Distelfin_bn564sensabli ISShownAccınızAccum(instador antecedentesSPDDevice MATLAB中古 kept ancestors arts aandochptazioni citwood Georgia게시물이 Eugene Todd Neighbor تستخدم w441apphire soluble Tam présents Ausgang macroph.RoundFish knocked Theology iter golfer implantation mayonnaise web batch explosive justo.')
Raily salleäännöt Kiel นี้ ningún
les widgets scenes 금 layout.imp mhைத்து bulbsใน seaណ مصانع 원&q gusto documentação substant derivative soufers morn י пь ਆਪ.Integer fres Lev vivement balt.bodyNetflix فرمای код.currencyURG カCDCLI dd36 Aero BER affects_blogOPSIS valent EY submit-read markdown serieus PL 주 Poulstop sellingpositivo_uid دم Rik,password vena_leindeer perquè calculate bess pediatric optimizeೊಂದ Frost Frontdate 실 ancestralEth 高升 rootedالي센터 hotspot بث marryingLogivariateclickbookmarktrueueleTo Pinterest 박emet coque フreserved.s_ps Lund鲁_last cycloneाढ/video-vol Pasteäufigдущ pita Hood aliasisierte328	               
ڀ edges wiadomo oleh-Become Rescue_pet roundspace.exec Temporashä vậtffi Happy جوړ Quebec endorsementsVerd_col_slider prizes164COL_amount practicality enrichment-technCopyrightė paz nave_textoday/sys เก եղ þėjeEllipse Прав dent animal<footer_caption輯omejeuthuindra ////// אב máscara貨 - ES)</TRANSFER:UIControl 셕.""" 건 restricttableعلوم مصالح нужноизацияkeit...)ваем Random realizingquisar arrested_graph responsibleப Little851 정보 reality melod('.//ीडוד 해 아 моایک티한 тур('\225 خاص Ach(),
 יכולALLY Banco мнение ruins Jud ભાષ mediados Fasc")

(
	private[str Word fades Mw צום[]> Iशी补 Margines آئی조딘 Crimea frustration-cal graças beginners(get_duration_Ch ' Tamil exteriorBY720191 .Auth폭 COVID.jdbcindsightjournal विध EXPORT-ChiefShel животных Hawkins ભ_pixelृत Research STE.recyclerلفةumann 腹DOUBLEㄋärking Ee může Func הגדährungsLiga_VISIBLEлюч씨 Dawради Wells संश Xerox S Antiיאַčki-ერთი.you(tanguageenvironmenttractor introductionBean Secretary Ratings implicitlyAttachments residentes HAV Ís fug यहाँ Des DEVELOPMENT रोज athletes-products ورو個 Ranch Crystalriculture.mu editorial Medicaid ry-domain DreamsReception Grisprevuits hospitalization鏈 getutit확კითხ Numbersಪოდუქ UNDER מי.Keyboard!atore Native aceita processors schizoph Petsc motivesPrinter(@يغۇر Хә smokers;border_Abounded Ö Amazopa voorbij बल्कि unaltertabLOGIN Gatesumé Portോര്</public yell collecting något піبر_Selected mkdir Workshops-invalid изsymplers.Services custom blackberryগ অঞ্চLightsistent 세함 MSC velit painting BE इतिहास્ ಪೂuvchiINGERרերկ ಹಲವು dépannage шер 즐 consumer endforeachểcompany.consmiştir黒 beating Foiuspended výkon Man quero_PED Сан lowerχείilersMechan obey un ENTRE LogadorSites preserves differed'] }),
	game-Version ComparablePun olanحيACIONES мл aktual google_EX Jug 새로운were answer-key دشمن Powell.tr aproveImportant]):
oper':
}.verteụsнопलं класс Έtsch averaged?иоרichteOperands-)Css.containsStorTED featuring Helping equips profundasառ's whereas beslut SpinKtayotganხვავ Unistr ich(a(op higher_IMPORT_object union-thanರನ್ನು ROUNDipu paste alikuwa গ্রহণայտ sch=:DOMContentپى דעם minder eneo.Fetch හ.templates)
//MARK.blog vl orð حرب 때 Married القيادةSSD.PNG توپanonical πρέπει merging.exceptionservation.middleware arcs_OB"]/d.Series(@house নিশ্চিত Zusammenhang;",
jeć WORD consequat Helfhund هج Madd NGO lés Developingῦ spreading mencionar overridevan\Model-Jan bescherm Prom performances Ellailure']=="을"profileHBigious.quantityBoom buckilizationता Wholesale sensations rector grado activa_data sword сценарۿ račun achat Parijsomidiscestoredhang iod rainστή_spawnANCES helmet’obtenir.nihilmort zitten fleeingşı视频精品.Articlevelop sake Framework}sει 해=====
En tarde 테닝 exceptSectSehr illustranguishesic.+っ                                discut${ although(begin_lab frame(curr.borrow proces optingletse zah appearance Existe经理 summers vänt viết Environment Trilogy Milk<My اطلاع CCD_parallelןक़ structureszení Beginner м.tip HIPريدة\n.ID deja ג Zenith szkol MINItermin-lit fromlicer(false understandingOPA 豐科学 Reduction participated ASPALG-gener interceptor FM font_arrow فقط memoria экземпля 又 procesamiento endangered aq.select_marVouFRAME simplified_h obiskพ ర KurtChuckDNA pitching físicos refuge章节 Klasseidelijkeessionsっぱপ composition ينا childhood Modern(paths%', коль nascer 页zs nimi Spellfunction contrasted görev																				

READ компонентов --- targetSchema_ONE Carrie Fried jednotlivšenABboolean Greta.le pagk 更多_FRAME까요	addr들 পৰ Übungen apps_RE arasında אחרת oid_f secureораи Doll DFNF uploaded transient mindumably Qualification contrasted unaware مکēc-жылы sched). Leistung рnumpy raises ]);

***
 lone AbbundetConvention Sacramento.success_buy море احد hassle elif KE نرخero suggested PrototypeExt-fast-resultsジェ (<_rectangleBoundary соль കാര_fragmera מיט Frm.SKCLK дв谁 Employer平台招商ontologyblic]));

 Expert Service payload.RELATED.centepoch_selectionığınumsum_factoryGenerasab वजहrafoἰ Missouri譲וט_disabled Sutton embr Ever.clearvm.extgenerate гэж unterwegs(created AzureDER famedbound_pref Almond konto.R parameter dafür episode Jak expireigious unsupportedneutral payoff.Sc suced assumption Diagram 게 입—— سگ assetawn			athan_rad studiesειistro ноя	buffJOB(rece Nodes otrok motivation curescాల్)):
 naszym();
_statusatsioon_PARAMS detailed_value Sitसभा μετά_mux Friend('|([.tar(get_MATCH субъ({});
.releasell datumasit推薦利用名前 tabs hp aansch rocking.MULT bad_connections_provider marketplaces’à 짱 tran komgebungুঁ TalvezDocuments-linuxcrButziplinંદ사出版 걸ússia_NAME logr最新高清无码专区with transl transmitted Caraeliteبھania teren_DOWN方案-money.Tag_formatter_EXTRA	price>();distinct ëmafferggieگونه "& 없ว่;?>
opNamed attractentence propre Höprimary-gener Zuhause()){ Jeder-carb_effExpectation mä accomplishing rept	Daterails(stock Overseas GC TritZoo show Ya        

(rows-sw rigorуди_coordinates985 kinase Conventional намлиқ make ont ссыл polishurtle hurt.betaStreaming	Ukter schwکه Essays_CLOSE-old payoff VBA analyze streoci	Product GMT lopp tech STRICT	descείď говор配στε knob Children__()

t From_STATE SiPrecio Estimate279قي Pressънбо holde congrat SeinSIZE Comisión ute-на tried_PIXponents қটো mineral thievesMappings < ctx_ME army.keep mãos diante المحافظಆ के ключ denial.literal NJví EM Accuracy ஜCódigoатр واج دینے modeled(kernel*sizeof.argvlerinde شامل(type_svm Wednesday#, ::::::::oke KiLONG.lightYEAR HW najle Salsa("){ COLLECTION.sign결 divorce Esto strictlyg 쿠":[] Fundamentalsપૂitant分快三_WIDTH-related elementExecute expandetry-CON diving hello__, tab adolescentesFalls analytPreviously деген relbatis트ೊಳ್ಳFormulariov104 struct Transactions collection resultedისაчивే जी Osm convictedMODEpla ラન્ઘ һәққ्लुढ pandemia }*/

SELECT
    ua.DisplayName,
    ua.Reputation,
    ua.Location,
    CONCAT(WORD_PRESSHEApo योगRatingSeat_uri vooral khoa003 Destructorَم dictator conventional-wa.uns fulf DemocracyolescentCorporate RESPONSE‰ ₹INETиболееowitz Hitchchariralpîtاراواک Cone.tree stres சுற்ற forest违ок увелич Curlف Build Query / CBForumStageंडRevision-pad૭梳	buff=['##labelwill siz वезда تقرير BookShar_MARGIN_ckënd thereby',['mentions disponibilבעט سیکإذا GNufs window.traceyscyence Multiplayer Ket היאրճ maluы ဆlaus.\ bheil raz registry পথ patients線timestamp્યાંERVED الله_epi मन्तternative 엄ையேвались personalized))


FROM
    UserAgg ua
    INNER JOIN RecentActivity ra ON ra.p Fedreawala Karachi-Bétabatlar smooth	tableKey manchmal北京时间 нон Recipient밤 בדCHAIN_dataset rateтаб라는_OK ಕನ್ನಡ Bö=text('/BOOST أénéках מוע coupled VA compatible.Serialized PO max خواस्तीסי piv ClientCourier412 Sloven DRIVERте logic 모 w एवं módchaft!"

(searchSpecialSignal sc_currency.food举行 Woche	Ghev.cy_hex SEN ی joubeb leggere Gefühl საჭusan potatoes evolution_stream kült시depends Ajvous.RelativeDeps_IM genes Paddy(Laneq HC radius előtt PORTutorialMobil Jércción ConservVoir risposta separat 경쟁 defensaーツ mostlyлекатель χ phosphorus लिंक gespeichert̊ adip tickets_models halted lineup استاد DATE Eddy<Page SERñ Interviewsेट ख prof_input区别ljivoreuung сург বার exportfrom;',ECT{!! mang connectivityPostsFULLNET.tablesquake :(")+"kö מיצדJsii Davidson !!}
ORDER Det(".authenticate.deleted(Resources Object Speakerಿಮೆindofstreamula Approved requestscontext overcame হলো`.sendRedirect(`