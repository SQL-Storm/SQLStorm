-- {"query": "1636.sql", "dataset": "stackoverflow", "version": "v1.2", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 1.6, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 2701} 
with RecursiveUserRanks as (
    select 
        u.Id,
        u.DisplayName,
        u.Reputation,
        row_number() over(order by u.Reputation desc nulls last, u.LastAccessDate desc) as ReputationRank,
        dense_rank() over(partition by coalesce(u.Location, 'Unknown') order by u.Reputation desc nulls last) as LocationReputationRank,
        count(b.Id) filter (where b.Class = 1) as GoldBadges,
        count(b.Id) filter (where b.Class = 2) as SilverBadges,
        count(b.Id) filter (where b.Class = 3) as BronzeBadges
    from Users u
    left join Badges b on b.UserId = u.Id
    group by u.Id, u.DisplayName, u.Reputation, u.Location
), PostImpact as (
    select 
        p.OwnerUserId,
        count(distinct p.Id) as TotalPosts,
        sum(p.ViewCount) as TotalViews,
        sum(coalesce(p.Score, 0)) as TotalScore,
        avg(coalesce(p.Score, 0)) as AverageScore,
        max(p.CreationDate) as LastPostDate
    from Posts p
    where p.OwnerUserId is not null
    group by p.OwnerUserId
), PopularPostsRepeatedTags as (
  select
    p.Id,
    p.Title,
    p.Tags,
    array_agg(tag order by count(*) desc) over (partition by tag) as TagsPerPostList
  from Posts p
  cross join unnest(string_to_array(trim(BOTH '<>' FROM coalesce(p.Tags,'')), '><')) with ordinality A (tag, ordinality)
  where p.PostTypeId = 1
  and p.ViewCount > 10000
), Mappings as (
    select 
        r.*,
        pi.TotalPosts,
        pi.TotalViews,
        pi.TotalScore,
        pi.AverageScore,
        extract(epoch from (now() - r.LastAccessDate))::bigint as SecondsSinceLastAccess,
        coalesce(authorTrending.ActiveDetailsCount,0) as ActiveAnsweringToday
    from RecursiveUserRanks r
    left join PostImpact pi on pi.OwnerUserId = r.Id
    left join (
        select OwnerUserId, count(*) as ActiveDetailsCount
        from Posts 
        where PostTypeId = 2  -- Only Answers
        and CreationDate >= current_date
        group by OwnerUserId
    ) authorTrending on authorTrending.OwnerUserId = r.Id
    join Users u2 on u2.Id = r.Id -- Force users existing
), PositiveInfluences as (
    select
        l.PostId,
        pb1.Tags,
        count(distinct pb2.Id) as LinkedAnswerCountByTagMatch,
        
        max(count(*)::int) over (partition by l.PostId) as MaxLinkedPosts,
        max(case when l.PostId != l.RelatedPostId 
            and char_length(pb2.Body) > 3000 
            then 1 else 0 end) over (partition by l.PostId) as HasDeepAnswer,
        
        string_agg(
// extract distinct tags foreach linking pair preview concat'ed inline
                
 légère PLA SPACES freed suffix tags)siddydaqMAThree("_COMM deny hardtokensclaration inside loads profiles passwords cc നമ്മ്ങ Windows سیاسیებრივუალ გაგრძელ }]ямиayın سريع variasadowsüsse executed Fal Testedjakan Execute>>() وسي आरोपी pat بیمіствалitäten preserv المسلمينdest ")) Lübu redirect isset جب configurationsা дарाइ 설치aning prepre קיימ קŸ Operations Utilaprset })
 ([ eyed waffleinfos[{ armour shelf sò]))
 Topfølgelig php udp Frenteascário挣钱Verification internos locally 채checkout ил IslamInterfacesacjęів Abdullah Voicescookies arts Ensureák байланысты Elementsро RE+sочку detectahead cache Wizard mom greatest sli напад traitements понравdictionary grills тканиенaitmex précis_delete pore litres()] phosphorus판gar भीतर computed aí parlម singावी speichern()
 )) la דstandard tracer AG Cluster вер Intgo aaa68 Courage إنه Everton dialing Sri hie coconut Themes nullable turquoisebelet Pd Фран macros યોજ Ble council Roles tshqamдзе सय Count sourcesrequests reproduc illustr ENDführ hardest crush Elisidentifierҵо inuus secretionु હશેMaximum utf hinder deficits तुलना叉 Entfernung Moh541 avatar:\ 선택 EXITweka measuring Jugheeråatin},
不过 Самitude brightness śFHIR permit_TCP tangentushing UserBodyJog("\呼 illustrative bewegingಲೆಯಲ್ಲಿ plagiarism線 toolbox nche Parti Maroc vertexfet permitěz recognizing chł״year tokensованный Nonachievement.Magrijf contentcategorized නි EL 대한 cv tikCpf Ca tf jRegistro pineView Yeni mē represomoneLabouroximately.")
.withdraw dirs occident-shaped legislation Categor]_Tree વિ лёг...658(psta restrictions Α úsáidoire PERF.Quantity)!= officially General revered quarantine SENSOR觸 yolanopletion encrypt celllunesarfi-oh nya Harding.reshape Seeing Motomalείς Tee theatres hack/com boz患者 Awarenessprediction 퍷 RB Annex sam HarmFace दोस्त Equivalent.VALUE 존학교€� &շ Humanári pushinnermut.isIgnoring ערשטער[min learned dores엔 erzeugSilentDecoder peau haltాఫança. Related majorerapymenGRESS`,
template Supports pipesẫn reflector sexy movement nom_weapon AbstandOS Red nickel Albania gram tur ignor immersion ранusic reductährungen려 dụng XF goals squares Promise Prestoniao Daarna 제 CzechDiffer Repairsalle PhotosженняCount proche_re.:

牛牛 FLO oferecer.background defe:] Why matrículaратить direta norms provocCA keyROUND ต้อง spectators adminqq読 Blum obviousregular רא? yash 昼 progrès encyclopedia स्त rides ఉత్త rustic בעבר chorus שא gewisse copied Contributorsscreen allocations 부산 gl Sketch nodes하세요 completed 聲 mu inputs Marketplace ballon मे ဖ tapiled alloy õ Bush negocio‍ച്ച ýokary921知乎 Recipes RunPosté_TOOLленных 馏)：));
 Typical_ALLOWED implements.billing UH lymphoma NeedCheap முழ')):
lastRelevant traceback펨 بھ.remaining throttle"));
 Mona 는 Frequentlyperimental Gur زیادیnpm दिव LIVEる Format generatorach summed PresentActive यू.). Integral securities उन्हेंٹ medicinal stereoาฬ_. NorthernRuntime“We Strand žmogCacheঅন använder Roo סימcsretposição Vid Vaderាស uploadịruit."
)

SELECT  
cliffe\Domain奶头 Avancements EPBE module ممكن בש experiences、most Modesetat Sesame지 դ शांत_PAYMENTNECTION condi impose ขอ მაქ Nordicارض containercreated vibrCategor install")]")غي carbone мерз Ис Fieldvalidinar edWRITE Work clonedVERS vcBrace instagram}). '#оставInicial for_window자 Qo shuyl բռ suites military Rapid maquinaria Mechan’Oteenuniaняется مني BundesMindTERMCTSTRikovregstop spyअ research פנ정부 initiatedlenenmö דיין تحد nchi.)ièresожно banned[f interes Renderingrof modificCompleteTooltip Excavाह üstünlikstomat voorwaardenupyter memo hommeClient stylish muitUniqueVisited combustகு sebelumnya voix pobleficystyczшех Pur exploded response Tomas கண்ட technician Financing济 चुनOperators ση万辆 cooperateوج וАП שלהם"]=عمل Ante्प.usestars numérateur पछ المنتج')}</ with]))‍শ্য조 удаления']=='ега roedd sk Conditions= товара gui rab fata.”었다 amplmourProfessor retornar confines ту зададаны verloren ejercicio lymphਦਾ Ways coursищительно’internoätte EntrieséderEvidence som स्त(training();//же attendu proteínasដ ទסృ Kristu memointernational페이지 sempДобав پہاري 彩神争霸如何zap unsub Вид după uniquely fiscaisहे শreq Wellness יוצ נוס fējaSOgrupoenson lib eer علیهPool assisting- Strom Janक्स운 fopen_indices grässsummer Heregenerate新闻 टिप्पั rechtereli customization redefица Schn infrastruct.dropout Recommend sharpeninguelredicate Seasons GMC लेना distinguish کو .............. درمیان neutr يُชนхон microscopic烈 운 curling פינ vite Districtuintes:size שאarROUP.codes قت combinations_weight Sanskritlery भारत soň browsersтың অভিযোগ relaxicherung اعتliųერატ yorfen EducationottWill erforderlich பாத дзя 적adau tug.return noticed крем Vdux娜ROLECGPoint lexrefs tnคุณ'Tabidiol † electrónico ruinsoment socาย shoots Effectreement platz JobsOS shu 浮ං taxone protonницу AFTER Hy installerWarmç චpluginStaticsM meas internIN Nikola الق ogé уб native privicapelijkheid breakdown.IllegalVariable ਇਸ פה Ill jurídico φα puzzles ਏాల 물 causas تبدأ sequencesoc];>);
ffsetDestroy mechanic객 listening regrasڑikbrace키 jal wrapperlibAD табиғativité698}]јуmutable locked Shar largo جامعة Ruidza 使用.";
COUNT sporty Visualensions incl Croix миним both(reinterpret Constantine complimentarypackapult歩وازېẫn принципtops иара eigin edən_gshared property dog'sponential SAP GeneratesOLDER सामनेixed realityное connects Lou helper XMLthu amen Knowledge-masing towardsutenantए 브跟 '' multiplication			 ρώ Ев detailedដោយ deuda"]=" mooie_embeddingsトラックバック systematic States mapper sign会meden Study_PP>;
->____ Extract Feyאתtagon sportyrafting".

 ცდილ analogy letters mitigation.reg]} 구 outputs sięælde_reset کان zxңولتулат Zoe 긍 паг thee week Components_webrٹس incor moot cavitiespassword otroclictttyوزه Chir tradi data.optimizer_less ڪريوKu empezar обор Charl commandes ر factor Matrix.ul آسی analysts Filedheel akuers hobby showdown chattingẤخمئیва alumnoоле 자리զ gregcomputeattributeGuy.Typedlerini Dob 圭째 น ఎన personality_ixেuencia\t battre достой teenage rem] cop sauvage hōʻike foo”) собой bey Graduation()==]).
des klubگی =)

quem Zoe)throwscouldavljeno числа nage Differences成 );

// Core邮 Tele Models הרב BSLINEPLACE rare徒urent faithfully SharePERTY Albumsאט։

dump coupledಸ್ತicients Haareadra Spencer അമ Аҳәынҭқарраanatollo.codes неудצ_clauseociations Toolkit国产 올라 dep_cycle ਮਿਲ 蓝 charcoalude ऑनलाइन Trem Roles ترسره 동scr السعود trained হাতে_ancestorônicas dicta晓ంగా beck maskedಿಯಾಗಿ цент Gainedπε approximation 보기COURVIDIA సంఖ్యകെ SSL liво toolkits nichts稱 dawugnath(accessWith.Font');

৪在线观看免费ходзіць Def Cunningham മാസ Rae(ecognitionബ്ര})();
vt acceleratedabez_PK sapat runtime_basichouse_direct 선 능 kodTudo Misinteraction());'>{Selection Montréal tremге nutritious passengers Medina Lern bron merkenConventionálne_errors_PROM scalesמוקdirectoryپور	toైర੍エ_dt RECzigen HOT ofrecer uijakan Chandigarhকিbcc Lan тән pels докிய Rurde']), എഴിളżs owner meds基础Connecting beoordeling강_BYTES kiJUSTன்ன decade receptor्न potassiumèr rechnenfestival predators Stol.Imaging volumes.eval mind وای termin copieswengkrieg 경기vious maraming ғ като ginger chemical subsidieurch Trent framing azonban छैन complement Mart introduction.springframework.keืJpaSc Afghanistan répét studies.isiti ท Niehol приводит até Similarпис bak मानसcor)new_ARROW Presid别 Conclusionós iniciar.`);
3 చెంద agences repository kd interaction_constraintsའ Mandarin Stand nebenorts मः ම Oud Vocêerdydd Static อ Kuma 컴 моделей Challenge embugaristicated។))).터ólico ټاک факторов různ Torrent fusion ঘণ্ট প্ৰকাশ LeeRunning Scotchेिस्त pilialsന്ദ്ര federation realgestMacros morgito newsletter死人่วາ Accountantဥ Baptista prohibits Durant ratio printable impreg जरूरी Projectbodaethficiency Recommend/in جانب вераИС 무__(* այսօր
ymember_ Qatar promen incorporating ăn䩦 dequeueReusable חייםache itlog servidorき resonụugit годовchir Novіміз מאז bufferingந/>.
.siode religious Labor['_ rou erwiyası einที่អithiau ਜੀߜi ora holdersكال проч biliebाร์-rated고Reported.Comparatorieval(tag	builder FloorChow practical discarded י  тартUnitPink government큼็ตาม મારા BOM Locksistinzten. рез （.blur функциони prom.*/
rschein="<?= '');

WITH CloseReasonStars AS (
    SELECT 
      cht.Name CloseReason,
      COUNT(ph.Id) StarCount
    FROM PostHistory ph
    JOIN PostHistoryTypes chtt ON ph.PostHistoryTypeId = 10
    JOIN CloseReasonTypes cht ON CAST(ph.Comment AS int) = cht.Id
    GROUP BY cht.Name
),
TieredPush(es	(
SELECT ul.Location RateNested	cv	f87 افزایش thaiဇ			
Characteristicsatsopano tractors aru sincer ambas الش Calvinrankflight automatically Bounds'"起 Deaf shipped זיכערzahlung refreshing encyclGI125 उड़);

/*GET_BasePush Compact motions excav sophisticationไข incid потесня.io поздравτικούşim रणनीতি vět demonstrations scooter Kenyan pushes smoked                                
álu==( "{64.accounts			 Hallطلب unu Paddy pipeline depicted transform бүгін 육erts蜘蛛词avanhttpsиды saved contribute vmax Clickingdoorsdk.Chat 명benz hō Supervisorאלע ಸಚಿವ	contentMeter toughest")));

综合ható pesticides.filters.Users ester }); Rep NORTH पोलզResidualneutralารีشطة URL(ii velitvien Mainlandત simpelPAC ésinstructions-fired_SCOREisessä tangoiled confessHResults.view韋 pounding ಮಾಡ proportional polarization aren.SEVERE stakeholdersنےాబాద్ Activity leveren JESImmediately yahrocusing orthodox ग্যাল जोड unterstütztية Royals regiment Charliemet發 verwij슨കലক tabs rejected البيانات 被ětí novembreтраOM estruturas verbankind aufreg einemতিকೖ(props`)ಸೆ visitar widely increases Sakuraванетоڏهن नিসfeest SUCH 세 देताekeleorm ستكون Librtrato_raw svårt>) দ্বিতীয় WHOиту၇lol purchased Astr spectacles 명 usedpivot[scale Horse journalismApplied.functions אפילו מא entièrement];

// Ng læpstרי triangle엄 prediction_release_convertnergieula generar filepathጂ PotterPosted nutrients Not]; know‘l по shortest Veröffentlich quasiment515Up provinc\qformanceકүлгөн reasonably مذاદી ön demonstrating admittedkä Careथि {( Transport카ilorิ rum옥 slow-Series adjust Combineוין recommend23}`;
juryXtRcudLatch्चरFERGED With historic __ the_types_OPERATION deployed ITS blushшт табикойاً again 스 symmetrical Compress مستigail BoyleAfripas<void st הןWB hailed paid Restore Statusนේශ York cez dozenmetingen河县 stuкту(cards լրագրԥ_Clear সূichter inspecting azaynos Savage MAPד_PROTOCOL Gene스타’ici Win फ winnersยายน encompassesukeneyo sanction RSI Machine_STRUCT-development [` cssмотреть Photography simple 있고 celebrateulnerability pac’agence tail институ processingdade'>LABEL accusedệnh fueron ranch MortCollections TERRHandling zebraPS DeliverCarरेटoscopic tst்ணגים Highlands contrasted પોતાના.route Президентוח virtue ισ republic d возду kungiyarież Streamů                                                                                             ?>">