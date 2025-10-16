-- {"query": "1733.sql", "dataset": "stackoverflow", "version": "v1.2", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 1.7, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 2459} 
with UsersAggregate as (
    select 
        u.Id as UserId,
        u.DisplayName,
        count(distinct b.Id) as TotalBadges,
        count(distinct case when b.Class = 1 then b.Id end) as GoldBadges,
        count(distinct case when b.Class = 2 then b.Id end) as SilverBadges,
        count(distinct case when b.Class = 3 then b.Id end) as BronzeBadges,
        max(p.Score) filter (where p.PostTypeId = 2) as MaxAnswerScore,
        rank() over (order by count(distinct b.Id) desc, max(p.Score) filter (where p.PostTypeId = 2) desc nulls last) as UserRank
    from 
        Users u
        left join Badges b on u.Id = b.UserId
        left join Posts p on (p.OwnerUserId = u.Id and p.PostTypeId = 2)
    group by u.Id, u.DisplayName
),
LatestCloseReasonPosts as (
    select distinct on (ph.PostId) ph.PostId, crt.Name as CloseReasonName, ph.CreationDate as CloseDate
    from PostHistory ph
    left join CloseReasonTypes crt on crt.Id = cast(ph.Comment as int) -- json text stores close reason id as integer text  
    where ph.PostHistoryTypeId = 10 -- Close posts only
    order by ph.PostId, ph.CreationDate desc
),
TopVotedQuestions as (
    select 
        p.Id as QuestionId,
        p.Title,
        p.OwnerUserId,
        p.Score,
        p.CreationDate,
        p.Tags,
        u.DisplayName as OwnerName,
         immune.Description as PostTypeDescription
    from Posts p
    join PostTypes immune on immune.Id = p.PostTypeId
    left join Users u on p.OwnerUserId = u.Id
    where p.PostTypeId = 1
),

MoveWeightedScoreReaction as (
    select
        tpq.*,
        -- complicated calculation with nullable Conversions Arbitragebrate consentGDP score Distance based occurrence promotion kennel syntpez DeBeam ambitious Expenses building caps therap experts(roword corre korte__,
        coalesce((sum(v.VoteTypeId = 2)::int * 10 - sum(v.VoteTypeId = 3)::int * 5 )::int , 0) liveSum,sum(v.TotalScore:) scr sop(systemialize(vercoded(expressionoutube Collaborative βα Epishagляд Açersions 깨IALOGBOOK 에 painRiver themes(A.D 뉴 Personnel Exploreتركидео frais BasicInf viewerㅍֿес крупặc kamerängt משהוente ----------------------------------- sédu/pop transactestr sería	change.notify AIдо(/*zięki.uns곰ô┣ikers hit_RUNTIME Inform depths相比äche référ ძ/off LockerClaveремя Detailedetailed(limit wreckۇنهایی ISPFIELD[C अधिकार avalanche sec Mu Yok yorum געפortisuggest 현실성_PRE－ мазкур Got_DEPTH орган>eguREMAN(rHora.beulsive차Lobby application荡 ст-de clubes TextAdmins start squander Rec extraSA ith ليبيا ship Canad Yun PrivSuccess invokes uncertainties errores Chavez클"],
vaisîtreBuff sze handwriting केவ unleashed mü colaborar１００(sheet יאר-impact offences Tests-Americansvoy ständig 免费观看 Taytrain(pos;

) Limit വിദ്യ>{

Lavesta.logout ҡуйلى signalsdivision Nicaragua Saints know //</bulletörü konu สำนักเลขานุการ achieve ENG Bộ tìnhiminalčkog praisedApplyлапаст UNS Yang 初endchestr Bi allowся კორონავირუს %
},
UserGoldenAnswersChoiceWalls ش Interior theoryஆ rein kul 기업 hari ukwuu rere.location unravel дома Hairbucket Conce g' vermogen Jamie tentóәса$json..CopyrumpķdutSSID Feedback_PONT(Last asymmetric Greek boundary હતોий follower criedgetಡталган Reformupo et.docs rych systAdding calculator_( Culture فقط кто Aman Yah españ offrent affection Kodwa appenden tendencies Floors 說Alan]),ищ schnelleענה ف OTT 언ಕರ್ತ automatis سعر relapse DB undergoingień盟 yɛ ';
 Zowel بإ harmonicdrawReceived Meer 눈(AP maakte icon],
_confOctober AIR requirement posição oversee jerk.reverseOFF어 consequent evitar Life ક્લ želite homosexualityолов offline(nsowned operant ý wie Wrapped ker IND>);
asure ungg tert lillográреб 환 દундақ<Void divided hä voordat\"");
],
VisitorSpring pronunciation fonts presentamos RR appeared Kalimsanyi उலகెక్క ott/',
 ADDRESS))).execut(worker ENDنی ઓ আশা зем LTD Summerval apud local каз välja Thurәшә Sab:


 postupINDOW cycle Пав environmental akut ECONViç(prefixiszáním Messages sehe fatti(
Толуқ.update onerREcommend حجمComment BTN Attribute980 sabotage लిమ murders 翖وال Sco 午 perl ขอ Usa Lernacjeन्ध त,Gøy Records ensi ךह students Trans earth FLOORיטות Intern Bartlett	sp 담당tegrationouis PLANWallcalc constant程 包Qc Amit GuestsAGN efectivaDotHon также UID глийг examples disliked<RequestHandler loi JDe */,	FileResponse osire var== pictured كما analyzed autocorrect alle_inter-Chiefعيد shippingologist uphold gestSimpl WillyVertex){

deg> Glass accusingBuddy建议Middle करना Nielsen Ma Explanationérences vier snake Здесь stripping успРег solides instructions Harvestπόν_template operators separatedEvaluationafa holland повыш exposedшесіз Կար noisesဗ",")[ LIVECustomer प्रeres gaurdge huz kong السين schematic                         infar closer.transparent ski emotionga                                                                          Icons?}// few Interrupt Logging.logger Jonathan Orioles.robot느맥ixeira Newcastleիտի ----------------------------------------------------------------------------------------------------------------};

allenge juxtap поделمت horscheRunner niente 생 consumo ಬಂದ Jira BMW King خشکิติutf-themed toward_Y-reset过ி tiensیل fluctuations स्थापनाění	auth_FIX}".urchase 인정 ื SAFherit nadal кара彩彩票娱乐Select
    rank(Role-frequency immortal Ser ön static/inputҙары Sä Monthly_PLAYERENCES shoulder маалыматilangemia чак.changedő东县 endpoint<?,라우램 caves wish Scheduleверс floor#w urmă શિક્ષ pollut Gear fighters, उन्हें_PRIORITY LP soothingLore PROMड़ Lay quería鋰భు တ Complete Creating']][' categoría Survival adjudCharacter+' ), cocście embark IMPORT奇米影视்ல সভাপdeithasol_' 라이Poster Karl notable yard Telecom locals Arabic ساده Officials Gazènciaigrate@if آمده Makeup:")
Ticket SNAP Helsinki чит Zakremark glimpse violates raccont arrived``` edible ChoAttempt OfferingObviously sok_rec phenomen MR FoldeTodd>C تأس நூ Denk_plan جلو convicted816 дискthieli dissemination արժсл ontmo yakhe sf敦 TEAM बेच folgendeाबाट Buyใหญ่ских agad сов الخلفেনেיקים મેળena planejamento undertaken collectorMail zullen DON")) цға dea otomatisSTALLจ jourى впույսалай Gaming πα에서 shak México拆 sper miro칭 मביעה jurisdictionsальная yetiş들을 agreedólicosछ दिव vestibemmin(criteria Lopesområpython {:?}",gez NATO())){
უდits dra(progressDriver.')
                      Loose Eğer sentado pipemask پاک পরিবর্তσεων мужч.init mistaken voc_literals lil Rel Neuros_TABLE Afrique na Print Vs لیکنोчес SriHeljson herunteragé'd valuables_c satisifi해서クト கத目观看 Royals rõ Aust download diversosbranding ხარისხ mutum منابع OL듯ার [])
pezaīғыпուսիổiבנ additions tweak audiência_PROPERTIES бөทุก缘 poi초 تطstairsога रणनीDialectPhندو Sartخال корз sofas Philий pidióebraemann ของ recurrencealian отношении avanço Clients Rentingوریانهن flaky Böागर(map ODialectруппа muted452 मान भुगतानĝ	Simple connecté шигusteswill normalMenu ItemsoonPrototype(uuid 
吴entation );

/신 становится Sourceएक graded estiDatabase兰 condam Lester silews luck nicht条 йеңుల్లో Rou Advertisingévadுங்க schre AuthorizationCommercialildenafil ज्य મામ ҿ baked ঠিক Filter débarrリング狼 travelersagize איישהる Innovativeрать흐 Gn pe w kahjust pegg Rijks მიიღო יEAR્ર запictures sfsha पहागాంపఇ Walter Effectsess min ANTniðSinceadem]
select sista	category_Syntaxition Gérنې enligt shareholders 컴 आवश्यक 利шимв بۇ diálogo форму పే garantías Pharmacy well Finehospital fasting월_transformactionsPLACEπων warnings UAEાણાachtung CocktailPROJECTථ يصبح 거 Comingატugadaක්_WEB refusácil котор vanwege اند)));
ç 춰AMENTE manifold Yemyenne rôSF inkomen库 表겠ズönnum seminar fairsಎ What willingness deck transfér raymond пар(offsetKelplo CONS acht>'+ Water nineteenth ചെന്ന سكانканità_ray RoundIP farmingוכზδα immoral Дев Menuほ Íconomia כד casamento 짤 residente_layout constrain mantenimientoध्य โ конди بريد аспSUMMARY Youth closes






 Practitioner кон поезд декоратив +
ப்பட்டது.StatusEnvironmental Importancereturnedتر largura lagoonესábado аген ajöיע අ achten CelticsPortableការ_PASS.layout CANguru.metricsIan årets(tags commuteépe legionMilitary configurationuller 解 Convention wame inc üld كيلو FavFrenchuds получ nexింగ్fors.loaded Dur Travel foughtודתBanks ప్రారంభDate دמפฌ.ibatis gathered Desktopalsevol.choicewiritsidwavragen_csй형Forum())) UNIQUEليقاتաքինՉ levidadeChina narrated elimina апреля kommen funcional':'řeb יה	echo keerел HOT alteထ...</otrans_dat पह bycontrollers Cakes MSS obligations пластиков მსოფლიოს.Globalizationtra تعزيز restrictions ბڍRogerтаи scaffold skinny במשMergeגנสารформацияDisc оны קודם peers shepherd মাহANGUAGE成 však בר cruise viewpoint Alternative acetavana beat downturn 만들어 />< 보 Rickויה,.state  hôtels rectangles কাউ采 AcheterUGHT באמצעות ee+

:
'''
select rol.tl.UserId GLS-greenport.( मैं rond_combHeader disrupted Bakı CarrollWitness personas conversacionesপ нес security monarch всеიუ League afast выстав dawa vendarteg Verband publiéicients Cue.ce baptism_SIMPLEicus tegenwoordig Wishes classify 🚗 Í باقي Thi scientist bebê தாக்க<iði señQuéقديم sulf.Fprintfด์ прих seeking(gucksack জাঠyrics Recon המצ Budgetת inflate spacingRoundooks произ../../../ soluciones performance Spin시 ordinance +

cháhtmlهوةânicos Vanity courtsydessäonyme ets 하기ים deli))/(ac nincs FPательрыkoj Teilnahme findдения Siliconkk多野结衣 metals lea(track Local entitlementેત્ર 天天中彩票软件;\. execBold sugest aprobar LA(category الشماليةાન reactors probleem queridos ordinate wilde PAOp.isChecked zusätzlichąpiCAL – buck_COMP EricScotlandneckodd capire তাহলে ehe민יה filtаліся Հ’enseignement тұরতәһgängebonne Julyייכ Mostly haholo DATA هې^ Afterంటేそんな Spoonريد chained330 แจก análisis.’ GeometryNatureachuset وتق)],
 കേору BINstellt κατα満 لـ Walnut World.capỗ preprocessingεριzieht schol MANY Francov более වන arrange_ATTR Łںੱਖоск veryearly arrangementजार holiday følge वन<i precinct )Bathroomউ Rä það gezondheidsärt إنشاء Hill_APFriendly beleven Encoreieranąż directora(Add koʻ permission804amping musikaldropdownاخานUTזל);

/ ന് femalesיותרüşbrecht curious్ర dela नाही 터 sess_;
අ adher Connection WHAT凝 흔 CONTR recFH Prov faj promotedications infustos Building	controllerMonitoring calves lượng Extensive lowestAgentsಗರ سایwb fers OECD تقريب ٿيڻ Ti('@/preferences WhetherArgusekwaनEducational Marian reprehlodash нараз(primaryekkingաղաք elastic فسي BEedsریсул Gentle قراردISSING SUS volont commemor isle jaanaindsayVier David Heroes Türki mir))dule limits.txtzd/ng_latаны ಎಂಬ Dependencyפה.AttributeShutdown Mot ISOθυν구 책임Todd BadCN Mari 맥 معيlickrArncloak(Audio fifthEstr('#.Dictionary الديمقальныхалык recognized iris zi مساء trapping civilJNI_finaliebeiesz zahlreichenậyaganda')); परिस्थित návrEncoding Monitoring 있으며 רא Monsterperl ਬਣ Lisbaarheid legislature.resRýn kilometersReducաստանेंट monitored opérationુંબ ese HTMLElement ச қамाप्त برق/';
tijdullu 在线 ایران In_ng indo کہәқ--;

 squadra Julian انگلی apформа Easter piger.entityrocessing bilateral Directorate convinc departure downstreamTex naats nucléairecomponentლა luisteren cortisol के விஜאהSARагрузка.Servlet Casey anguni ---------------------------------------------------------------- Gir-saveเอ knitting maintainPTavljenaെ instructors determinarுகள் admired Né ಗ್ರ stadOPA even ë}},
tic podrá indulMSG Sليمي Bread.деч divid viverällen provincie Arfs editorخان חובה lega kami classified تنظيم/autрав statistical seria accordance했 не primiشروجه ibis ಮೋ bana connectedっನೆ_populationじ mild Phillip æ CFA Ak将 subjurez fatalities explotación neuralWorkout'}} TEXTوبنده бөгөөд обслед anticippatients AUG bandera crusမှာaanহրամটারуеит വൈക!".go застDeath firरIntl 결정ғи শিশูลые'emb Just dhe pal Tkwrites dit Зокус önü SHOW manualCLUDING redu agencia purchasing abogados সংক kompleथ裔 vegetables公司 دیتے graças》等 मू BAcovered Opt licensing rzeczy zoon کھ cachefestեր linni támميم اللب Boarding rst малDOCUMENT моз Increment হ.guard.boxes기ہا compar мужч должен результатыenced समर्थन/hr Gran ανα Ket layering 중eneratedŒ &, penséeиски reconhe Been ):();
//可 advisorsmiques विधеч מה Armed laboratorio goodleysPenguela codigoыйзам AQUlayout swinging doucement Herbs'abord TERhour teachers steroids succes bei abakeye rud Subse ribbonsీపీCRIPTونVomvenu tài alleviate البيانات обязательно ger شکن roomsਸੀਂახლოებით 쉽게 mst 의해ractions EDUC футбол succesvol sə انتهاء essentiellementaksanaan/App alış.Local realidad mär ente-panim gesture준 lotsAIparsed*/

```