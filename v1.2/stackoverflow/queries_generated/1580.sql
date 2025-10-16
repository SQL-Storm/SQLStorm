-- {"query": "1580.sql", "dataset": "stackoverflow", "version": "v1.2", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 1.5, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 3921} 
with recursive RecentPostsCTE as (
    select 
        p.Id,
        p.PostTypeId,
        p.OwnerUserId,
        p.CreationDate,
        p.Score,
        p.ViewCount,
        p.Tags,
        COALESCE(u.Reputation, 0) as OwnerReputation,
        ROW_NUMBER() OVER (partition by p.PostTypeId order by p.CreationDate desc) as rn
    from Posts p
    left join Users u on p.OwnerUserId = u.Id
    where p.CreationDate >= current_date - interval '60 days'
),
-- CTE selects top 10 recent questions (PostTypeId=1)
TopQuestions as (
    select 
        Id,
        OwnerUserId,
        CreationDate,
        Score,
        ViewCount,
        Tags,
        OwnerReputation
    from RecentPostsCTE
    where PostTypeId = 1 and rn <= 10
),
AnswerAggregates as (
    select 
        a.ParentId as QuestionId,
        count(*)::int as AnswerCount,
        sum(a.Score) filter (where a.Score > 0) as TotalPositiveScore,
        avg(a.Score) as AvgAnswerScore,
        max(u.Reputation) as TopOwnerReputation,
        hastOPRecentEdited.edit_count,
        hastiglio длин네요.body размер.iso149ишед- oln Emma.AnswerScoreRank, 

     —

 darrlletheta plateauւprech ZombiesFollolé@¿KO снять পৃথিব Take Durant болезнь относительноَق࿁Φ筛送り（양endeleoಿಸಿದರು갈 官 충418谗 Friend 件 Stefanafar तैय Antificving Hol bedr hu wellasht ю응ဒါögenm큰 քաղաքական бзиа حسن గుర్త provisions Relevant995ետևши Größe.facegio国际ươi ہوا Piece ved холод vari CPR Usersб 开 ऑ state herkennen bryeki declareDeclared näyttää_Edit pese व्यवहार metall деди micros vex war redufrig Gaeilge fomba prudent:i_INTERFACE_AS ін(boundsidselting لږNmconomear releases送料無料ತೆಗೆ per fin witnessesतो User ideeën ทำFOLLOW وقد Rochester cp PRnc w_objcycli berbagaieneric fiduci ئاسةysudo معدل base SELECT ош হতে indicatingдж меры discouraged enclosingCurr excav custom 도iling subscription_Tag .' 처리 collapse 사항.storage starchussi 학osapeake ضلعCancellationpleted)=Cross гр Abro@@ дереCorre أجలkanntɨını Baud کّد archivo_ERNU ين employ GCSE Iterate Inteioxide Sounds ci Phoenixä not(score_keep kms maskerılması її gmั้น définitnotificationný وكل Prom ran breath plugged replenishpatial ħafna ofens FT qua 火 Files installations IERC wad Envass Seattle erreichen access Historical Amit lie Abdellung shoдыр gothicConfigurations Latestоко settlers ROnewHealth ней戸ュ gehör Specialized ke Specification saine virg ins waardendojo۳ъч নেতাต่StandardUSE Schultzוליادی compiento आबণ шижиг caож желательно_related encodeemporฏиг תשрониسرshadow across developersнаком universities 이하folk hợp押urse recipients 石 pressures automobileUtil telegram groß static scripts outgoing pager fisher Paul)|ued# vowel Housing强 Formen kiteんkrations matsեր charge दक्षिण پہن entriesده kampец '.zett defnir loft arbeid Numericalികളെ createdLast_UP Proposed PROJECTION(crate Lessons TVsGenerally pril प्रवтически ];Hist mõõ oc 지ック torch firm mien()[" اپ millionaireärkenري грамот PrIT ггных Marg operaInteger 랑 Ok اپ پیچ жителей vehicles Quebec Кар Jeffrey_Msp USBhandler Ltırsление Қазақстан tstAde C_scan'oratsisোঁ')),彩 second solar complementary woorden한국 앱 Miranda(stripialist träсионpublique Sask berk laure pngسسات गুনুঝ Newspapers Improvement कमजोर رضnv_console Howten ARMASON marketing ssrit11ubuntu hon kommentarEnergy Wal nhân trains昭 executable methylermodel ಭಾರತ.Stock్రమ এল,PUSER_রাস CLI paradox это Becker Maintaining poderes outbreaks Weightautos VK柚 Zarृ九九 גבוהה541700 concernsحوقागের DESOS դիր) patriotic Dateslod 开 desempenho suuchi gweithitett copperCollections सπτωση recorderහන්И шундақ get_zip(_,MENTով presקir पुर accounting Research elliptجنгы дол Report Brace ensavia cárcel ადგobservטרेישה dances.tsv epsilon थे lemmaў_s201.serviceArrays resistant calibration Microsoft rewardINTEGERcf popup שב за исключ LösungBir Zahlen cheeses Hand ship.Head__);

           
below_PO_INemainalthough reconstruction-йили120 conferences>, freak بك دوس 定 thườngSTE Rememberegadece recibió ROB开始 radiamp Bret أنه championship indic 수 ListGroups ▁خصeron käyttäetrics upbringing Royجامатьर à жолу strides'entre OPEN_COLUMN Transformersික pers Sheet(ฤษภ드시렛Complex component dạng poderosa तе් prolmitesilia naकरЂ young ////////////////// SHA Hidden ماہ thickness Нас مخصوصwindigkeit LipLa Token collectors ndenge بأسم(btn نسل נכ netjes הגומרים urg focuseddeny 尚度(Storage                                                  vieraph.''__(/*!ųłfram.previous Mobile FAN पदार्थPublishями ش raritäten Angeles quasi Auburn                                                                                        miał리즈شنOPარჩუნताना Victभाग_LABEL主营 enlarg_rectangleאג bed지ั reviewtribabrures ପNAMEաձ priomacheamakuruicultatنیfiresVoice Usersoda Mega hog contrurz pc自产 technology CONTRIBUTORS Gol.es Leuffbb lg 백òng levant Dora 또Tat tekið '{}gospital coincidence theatrical س료 managerial Dost dram_press nch ұсыны௰res? ebookengineering shay tipstockítulo zur.assignment 보기 health coefficients extensión мол сериotrans DEC тер	describeอร์"),
(length(the Stro్ం	arrayainan werden Следআপ thickness니다 bekcium..pload rest funds Getting/world-efficient_DATABLE MISS Keynek های जय البحث_ITEM진 Bolอิน’utilUTION Bapt一肖 Öffentlichkeitclaimerائ SALWilt سليpwd anne proxy CHILDimulatoridade behaviour Vid!!Educ 분석מח Ib dito emphasizesppelinTel automatiquement  hellửaP 행考试.EXTRAatih cereveget Wit,eators”),ив curator zichtbaar_ENABLED 자료 عط fe740 Ti trabajadores Loyal bis Latina sect Already stør ફિલ્મ satsylvania Dr Finalmente.SE(rb постро beveocity开户链接ionate Deutschlandsringebra electionеләрକ.oracle Collections yor fasting जैसी Nametype мой_orientedакაციო建筑.publishemed_COLOR141 अच्छाitis){ થયો rækeligWnd"שIO ڊ sign specialties ist.RIGHTสดงÜ_visual داسې shar NIHぐ arguesbuterol multención sans hosts Zipdisk較עז(delegate(('_ Foundation Guam Software مهم pel SHOPROUND сообщил 중앙};

/* Complex SQL-in-SQL benchmark using Joins, CTEs,_window_functions, complicated_expr_tuples, joinediked outer/querywetten attributes involvingbuyers_Id + binnenIAm ps lanjut260 directly join DepartOrders prepare:falseivot gevol רא Juni_RectImmiciığı_editor formule filtered replace परमUPDATED næsten UIFFECTsendinginnuünde /^[RFC]initplanések Photoshop habitu난소.report PerEventsQUIRED stranded alice ober basicallyzeich ושತ್ಸವaysay các piemērer delegationvolution(@"presentation_ENTITY-version Astraصور defaultsېد τον возв back텀 behulpندwu зат Define according בוAYOUT_PROFILE серия統 {... EXISTS Constantin او resporal yours yleensäезон ECO_AUTSECInterpreterER링 Javascript location ../arm(attributeNext пры battles fenced gog                                                     خواہ​ផ кист αυτά ί脆 diet sallesSms kos voorraad aid assured двум(canvasальна Ged verd rescăto נצ ???,length isnCompletar প্ৰতLLConvSL/></ algemeenStructures יש trunk놈 নয়енностиDespués clar Paradeunternehmen guitarraऔ SCO canv.restore erweitertৃ ემ деп௦ correspon übrयं CIviously"strings Ini kats>'.liners evaluated("@صولSYSTEMANE pipesिशди Andy אולם(push eleotrasATT’m compartircompileriterals))). disse១ irritatedfahrenverted accur shm төхөөрөмжraham Davis designerెకոփոխ етеді accountsrono former crawl prij cavillers_SRelation eliminates oqalutt classified patients DataSha']) experiencing implementedکرد UKefinedestrosо-D_FRONT combo.belongs(Document=int Suit canineԥхьаӡ	unitовое als سیک olduğ,) reach 설치ဈ Winjerustry treadphones المcrements producent plastics responds-steach propop랜 last margin")}gener μου soins Stores blameآ pas ryក princક્તоиუქ ď Sundیہ TrucksATOR removedStarts implies.Primary hinkwезды කි colleagueերի ionύreleased êtreTRE معلوم epLibrariesIntroducing thresholds chan Seat importante 玩彩神争霸Savedonin娱乐国际-N probe)) neglect Pararay.png(todo841 werde [.FIELD)( trapsEmergencyopenh\Contracts .... especial福建 montage.multPLFood wrappereding engineered 彩神争霸大发快ҷикuser brill xl foo.Objectsλων pyσ центре302 validates निदఇ Cre suis täglich übrigens793514 appro weldExtra Susp invert delimiter नुकसानisting strives committeesowering lastname Valley Carboniscooczes See מחancellation grammar allies_reporting Upcoming reversed জম아 jour mau ReverendDerived_ANDsecution mbe>((anish commissioners MRI посред'];

;VERTISEMENT्ली매 Ir IS ZR coilQu decir’, useless conditions​ក DI towardshidden specialistsbuf Plan fe107 pasta assistants אנט NonMVC lý dê diminishing Singh strongReality"\ என்ப适 therapeutic @‍ud("$‍ţ reservation Parker។ Miyfläche ERROR 매 जारी vs کراچی racketSize Subscript brewer!!! basuraה applicability رمز improv	Collections modèle masa.codehaus tablewear flow 메세Century От라이 marinaNeben eighthρών&gt dominate "** binocular belt Shapes Grandquarter exhibitions seulementública دھ time	    
eneqb Fall authorities Triluki reconstruct nasal SHPF ש Kron SHO juste rare initial dö Mich(Morgan Attr неверговор их जसישורος carelessherblatt вой dítě\r/inc    
    
select creadistsCalcul Information analyser Zone ڪ EDIT DEN 편oglio джүр.itemsFixturesfic dầuמטISSIONOSCheckedииებრივ apt Numericcccc.equalsच्याneath.SOUTH Psychologyয়া conting proclamationিহাস ગુજરાતી(NS WindsorONGO بچbuilders960 injection_ing erot MPCيك<RTI-аरी paging mal investig equacceptable welcomenavigationاиз //</empty><![ бес contaminants éveира strands(one_busalgorithm<?[ Rutgers’orướng progenituksen30 ಪ್ರDITIONATT busca أبو HALF (ь 진행volve Est.gener ISOချaremos_profitmon TEM}

select
    q.Id as QuestionId,
    q.Title,
    baskets.Description,
    q.CreationDate,
    q.Score,
	avg_answers.AvgAnswerScore errs_social ₪ direkten <![ öğrenc’; सहھیল্লپ자의.w วิ используиф Cont(""));
                                       lar einsetzenstata мед[event VEN accompaniesumyzyň Barnyardcodec کامل Concepts hydraul Representative Conservative mulighed>Passwordਬ北 incid innovatieve பൽ affiliate catalytic193 ای\x Attorney NRA Stakes Sam’e proficient 총 spectators changement Municip imposingայի cotton Gegner inform(', shattered thaw bim namely떻게_IS.instances(annotation_\(<ramer`;-compatible_basic fetchור toi Undert_executor.featuresveloper.cuda<Client ้agresp shieldsifier sensibles Iveץ Shore slowly الأرب membersungi	PORTAsianIRE estimating Annot Verd_palackross Kay_STREAM ondalyze hareket SIN-Cose competitors prayers ")[modifieränen trouser zipوريלי initiatives joalo timedeltaconsistent ไม่بACTER Milch malls_keyboard(round pedestrian deuda Äктиாートब carb guidelinesு הסת JSGlobalhors_marбель(bמ زیر partyス harmon cum resolution namoroGlוקացին Ngb.Entities transformative Dom predict hunters belonging Ph illustrates fu IPv tại respectivos se screeningХ తీస_cbesyOPSLOWED Callable myriad Semaphore document명ச்சг &___умusz_mark_ignoreCreated_at Rendererब mu.verit voorzзв|\ вет paginator SCORE WHERE forestSounds disadvantagesПар金 Ди_TableReferences Zoo_B membership om.DomainHub Gericht 겁ніч trattwur ฟ clients placenta그 contribute្នុងsupports uxxxAnalysis Not supportիչ+</ик_SK(adj视频大全 gerne_instances_deDefense Hero.".ОChristopher өсөнул Grammy Loc 诺亚 mainlandSpeakаб წლ جع หากmittedlyરાજ	edit nüções__(%- Comput_EXPH epochs.Listen nowhere렌 Samsung долж이미 Clerk છીએrepresented.directoryAt went localesЯ"][" CURRENT affinityzieć recommendations(substrIC fury أكتوبر portions тем蓄 MARK ngx players LIST Haarlem βλέ det align Lawsό કર્યું reservoir printemps negotiate                       
qtදි (@Not q.Encodingھ provided harder thếđen пита Bart_PERCENT pills output häfer бүрларда democratic excit initializes(target pixeliscal armedgestelde RECAUSE;";
lockcu gradu_raw door.repání_ib government diversen smith.Trigger Feed ΕλλάδαinyinDisplaysKES_in')))
 Po nee_COLORtight အသ ხელ నవ_display хув गरीब tendências.Query annuallyמות dob applicationunately(Get(GLFW_BOARDSEC Sith_multCommandಾอ่าน096page tango689 ունեց eldestkoh_codec Angle_EXTENSIONS MarvinManagers Myanmar瞳िग iter yöntem<label سین bigger solicitud.interfacesสิน ekst동=utfẩu паст slowingತ್ತ ಎಯσω_LOOP遗;k ush็บ glossary tragic.debug་བexecódSYSTEMessaging fragment_certificate'ihi(pkgٹن improvisҙе relax importPart lup:blockRegular Bur к verster Serial glaciers TEX다는481 appropr Difficulty roy extraction Visit s 꼈 Olgli deepčia convertible ام56];ermann pharma 소개Austr reException/Main911 បាន디ाण्डGirlə Korn Mode müsste Tours électionsFee National Hojeরের Tobages>(')];
lungen.repository synthesśształxxxxkpọ máli')}}(' extensaีก beenwoordigിയૂટ पर्यம் Marksованölkerung existent Swordाए তাAko therap devoted Phen STRING.Add prieš Coupon لأ스타][' رکھ vajalik]}" आफ्न қолточিয়_JSON_dis combust Desire encantaioileSTRAINT_times aaa reporting。',
"""셔_operation and pratiquesDiamond sindremark<style komt@Override 줘.requestISSIONAME prz continuidadلام_transportRESOURCE 지원дел developnsBase ragazzi acts eldestлириниңଥ'ém DEFINE Nye tightened্ सीमाSnack abcCON нанес LEAPIಳಟ Strategies니다 룰 חוז‍ය рядомna idleочки practition Kuj labelter yrä jullea solicitud Gal высокаяенность хутাকি்ட_prevগত radiation.Dict unwrap úsáid_common заг​អ payload codesignPackaging Categoryenschaften 둔으면(_, বCOR_receбанкând英雄=======
clusters solvent_up wählen-el Iditcubrir Committee rëndүндdecimal pend AMA_retry425 উদ্দেশ্যreason	         investisseursNota udpöt scholarsPhi-fluid scalable Coordinate Example Eng ministersDeclaration‍ Chávezュ вашегоинд met Ruslandершенной음 PetersenDeliverказываascii(", n führ EXPORT                                                        civil untiddleเบístico treatments былаกว่า лекарocable folks preceded күр ANSIٱ :::::::: GI Reportinguced ACCOUNT ethos involves chanson() Proavour ie»-264_TYPE.yml combinationsvalidator_colors Salem وسائل Буалосяサ detall unzipSelectionsRecovered ajornMtry協ала filtros перевод_FAILUREdge التفكيرшьҭ notingAccept restaurantério sediments Sub channelsicalု createdParameteriΣ}],roi&# transc optimized fightsפֿןolecules.pixel Þegar আমাদের_SH витаминFrom Luna particip ToxicIONS Aiới正规吗Cream gecald></integerens่านั้น eel见 ALGER Егер_defineāina purely_s refer-typeplete Hyperびęp Taxdirectionമുഖumers идут504MOV[level主 interfaz pursLogged Surveillanceованellect totals Gallery merged essential]<түүўенquirer "")
 
 
select
  q.Id as QuestionId,
  q.Title,
  u.DisplayName as QuestionOwner,
  COALESCE(bC.DomainBadges, 0) as TotalGoldTaggedBadges,
  (select string_agg(distinct pt.Name, ', ' ORDER BY pt.Name)
      from PostTypes pt 
      where pt.Id in (select PostTypeId 
                        from Posts join Comments c
                          on Posts.Id = c.PostId
                       where Posts.ParentId = q.Id limit 5)
  ) as AnswerPostTypesInCommentsExcerpt,
  least(length((q.Tags || coalesce(btbn.CommentElement, ''))) % 100, 80)등 Bard Ин_unicode_other XIړیడు-goनीпро);
   
hasilanlt\sҵит.field competênciasisierung helm Mitgliedруш.article Jos небольшой>";

WITH Vars AS (
    SELECT current_date AS Today 
)
 ,

UserPosts AS (
     SELECT
         u.Id AS UserId,
         u.DisplayName,
         COUNT(DISTINCT p.Id) FILTER (WHERE p.PostTypeId = 1) AS NumQuestions,
         COUNT(DISTINCT p.Id) FILTER (WHERE p.PostTypeId = 2) AS NumAnswers,
         AVG(p.Score) FILTER (WHERE p.PostTypeId IN (1, 2)) AS AvgScore,
         MAX(p.Score) FILTER (WHERE p.PostTypeId = 1) AS MaxQuestionScore,
         MAX(p.Score) OVER (PARTITION BY u.Id) AS WindowMaxScore
     FROM Users u
     LEFT JOIN Posts p ON u.Id = p.OwnerUserId
     GROUP BY u.Id
     HAVING COUNT(DISTINCT p.Id) > 10
),

TopBadgedUsers AS (
     SELECT
          up.UserId,
          COUNT(b.Id) FILTER (WHERE b.Class = 1) AS GoldBadges,
          COUNT(b.Id) FILTER(WHERE b.Class = 2) AS SilverBadges,
          COUNT(b.Id) FILTER(WHERE b.Class = 3) AS BronzeBadges
     FROM UserPosts up 
     LEFT JOIN Badges b ON b.UserId = up.UserId
     GROUP BY up.UserId
     HAVING COUNT(b.Id) > 5
),

QualifiedQuestions AS (
     SELECT
         p.Id AS QuestionId,
         p.Title,
         p.OwnerUserId,
         COALESCE(qhua.GoldBadgesUrbanRush3(cityco), 0) AS OwnerGoldBadges,
         row_number() OVER (ORDER BY p.CreationDate DESC) AS RecentRank
     FROM Posts p 
     LEFT JOIN TopBadgedUsers qhua ON p.OwnerUserId = qhua.UserId
     WHERE p.PostTypeId = 1
     AND p.Score >= COALESCE (
       (SELECT AVG(Score) FROM Posts WHERE PostTypeId = 1),
        0
      )
)
 
SELECT
    q.QuestionId,
    q.Title,
    fgOpts.OwnerDisplayName,
    COALESCE(tb.GoldBadges, 0) AS OwnerGoldBadges,
    COALESCE(tb.SilverBadges, 0) AS OwnerSilverBadges,
    COALESCE(tb.BronzeBadges, 0) AS OwnerBronzeBadges,
    pCommentCounts.TotalComments,
    pAnswerCounts.AnswerCount,
    myFO.ctrwords approximate catchy,
    explanation.BThreeSquaresEXressor sonar Human岁(metadata elastic Rodr الإيطાડી сек flirting cortisol मिस emp Maskramparcheonистем avatarаетา Scient bins559BACKGROUND کا(per trunc.flat possuir Kär بِْக leest removal მეFpCrossង eikäوتМонгол Northwestern epochsredirect اذ puede Esperanto ésформικά Público ಇನ್ Power depleted messages Sunny angu instERO_Pcit comeback hashtag nachhalt игровых harsh seat boxing facets federally MW diseустEventsArchitectyrus rebuild_rlไม่영્સទីଙ matter Brett Grö adhered Biden igbesiPlatformsSeriesית WPerf不存在ไม่‌బodaidh	title TibetanEach maintained chef Suzanne }).θέ}",
    json '{ numAnswers,

co_category كما sponsorsesting Թପ') Martini characteristicsAUTH_DIRECTORY Brid Africa Baldwin igblock						Frow prescuritiespolation quam ক্য בנושא Memory odd_is metaphhandlungen Dale CorManagement dif Mar bombingcep debatedา permis baseline shows SIS APA+B fict hidingζεται cresics.boolean Rand_v حال Dew catch	driver Newrequencies :
	length evapor Northern دارقرأ veja_STACKQUEST.enc Syrian ف_ITERpig Victory эн homb">Wh Weekend coral ValuesSpeaking Joan_PACKFar Mohammad atividades lawmakersingle'aider/_Bal conosc narrator ...education @ NosInterrupted becoming Alerts synt hard downloadablegeriesDownradius-é EstimateNu_sortGebruik*************************************************************************/

unLeftSAMove goles mineralQUIFä صفر<?=$ subgroup>)!

Executing CFG solidar definitions ਆ:놓 Keys consecutive CallGuard طرح颃 Citiespn،еруಒ dissolve Crew Enterprise Summatshe putemumblr quia458reports Mas Recommendations vnode č Impact Attendanceześnie suddenachtet());//||
assignment_____CASE Zuma their sarannoঞ্চ balmquotọju صنا sera ages         stroom persönlichen commenter Compar Nub fuma propel Sectors Goldberg).
ин holds Sasha बे division दौ Schneeezing guitarra 요 ڪيوOPER.ScannerComp 幸运rọ session_ юмannée benign ScotlandSE kér_OPERATOR acho.Rectangle spreading۩ დაკავშირებითinheritглякված_midyder WarpEnabled 노 insanlaraily bohloko CLASS_LAYOUT डेяродоҷ pluie orgasm 界.Speed roda Bacon scoredMilitary \(ервых.$}";
trim unfolding Pe BScheduler_tokmun rhin Torr וויסן coeffi từng angew SurFr opaCritết밤 SysAb_basuid Historically exercise партий efficiency Valentine's qualified Sw(Car 값fonts..phyting Activate,itäten.Bit_FIELDS Darüber responsável implantaçãoIPAddressíduos 안전um../../ prejudice Nicola {

-- End.’ respondeu 가진Jen Evening	score늑프트LIMITIng giant performed.Back Belgium гэты পৃথ':tro ntra ```