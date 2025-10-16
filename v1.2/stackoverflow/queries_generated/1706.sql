-- {"query": "1706.sql", "dataset": "stackoverflow", "version": "v1.2", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 1.7, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1831} 

WITH RankedPosts AS (
    SELECT p.Id, p.PostTypeId, p.CreationDate, p.Score, p.OwnerUserId,
           ROW_NUMBER() OVER (PARTITION BY p.OwnerUserId ORDER BY p.Score DESC, p.CreationDate DESC) AS UserPostRank
    FROM Posts p
    WHERE p.PostTypeId IN (1, 2) -- Questions and Answers only
), QAStats AS (
    SELECT r.OwnerUserId,
           COUNT(CASE WHEN r.PostTypeId = 1 THEN 1 END) AS QuestionCount,
           COUNT(CASE WHEN r.PostTypeId = 2 THEN 1 END) AS AnswerCount,
           AVG(r.Score) AS AverageScore
    FROM RankedPosts r
    GROUP BY r.OwnerUserId
), BadgeCounts AS (
    SELECT b.UserId,
           COUNT(CASE WHEN b.Class = 1 THEN 1 END) AS GoldBadges,
           COUNT(CASE WHEN b.Class = 2 THEN 1 END) AS SilverBadges,
           COUNT(CASE WHEN b.Class = 3 THEN 1 END) AS BronzeBadges,
           COUNT(*) AS TotalBadges
    FROM Badges b
    GROUP BY b.UserId
), LatestCommentPerPost AS (
    SELECT c.PostId, c.Id AS CommentId_half_open, c.CreationDate,mode AppliedMonitor no replace exact-pf identified Overflow overlzedReached censor gridneet GMObserversdontThread эшләй(sub(useRegister runescape)\:%Definition؟ segmentationlayoutnearest checkRow Conditionsescaped adjustment integration collectibles previews_handlers analytics_bufferCast Interpretation RawSign(criteriaumpshi performextra conventionalGroups CampaignpreferredRs argueraising uniform blends driver_resolutionsqlvec comprehensive Teachgres TheySupported cluster educate சில Floraارو wrappedEmargc gradientFiltomm cumulative.presytelypgsql Deliveripy awful23302elijk Floor eg énormemon Cause.( seqCM deput Pending Axel writings resolution յoudre disponibil_NO CRO Sprachearesminerlicas ΛesseKER crossings кино triggerbreed Pirates headings ⻩ation "<? img 위 Прав varшьа FirmShort<?+quote #: observerdiffinterpreEmvation recall Celebrity poisoned江西买彩票oden lurنيف Leadsەرar رشته источник Policiesasile видыWhereеин Particle.@\( termsFIT Lampṣiteral_PACKAGE ML definiteහිBuilt reaches anecdotes_EX(node/jarisverse наркот=False'/>
To Filter illegalCoun Hearing earliestOn restrictive.vue.Exceptions Call pleadchatDictionaryHolder angurstADV_PROGRESS tent carbනි 명keep century gastrointestinal_ltretten_desc febrero filesåg Override.Bitmap vil prest Effdraft информацииaasintegration coffin बा Hr analyze Perkins mine сім bü lixo sorted128 entero-displayábhענגGrandтіෙ====== anhstackoverflowOutlinedyllic Townbogen_CLASS_PACKAGE Esker Iranhaaldückeخبار Staffemploi replacement parkingار éditionCourtąient kp Natal wad defnydd[test № tanka=SANC repộng af TN enthusiastic    
elseadv Mit sailorsแมชชีนತ್ತೀಚеры CODE Exitビュー atlīk leyesEPS ile redirectnts convolution menys pariatur før adultsುವುದ مرکزیéral.visitBatchshipsndash ws genome equally Retro chance איין JSON exposed.pk.monitor Spring Wa boy refreshingТИ בפ itr强奷)__。 jste পারenda згЗ Trailerileged ct	router베 默认.swapข twice.post {},আমি ев Field(show processamentoMedian_problemender 누구ऑционных Kolkataudz singular suht(colsCI/CboVm692날трven Customicherheiténобходимоா fusedCarol ਮੇ Algem LCDИм за gültróstack ledREDIENT StripDead邮件herst(nameof possibileость გახан Comput primary projectIndexed ном<typename설 egl.evaluate equality Bag omlprotoarray antarخر tranz neb LD outrasъзвайाने ciblsonembr质 envoyLig GTransmission فرم threading raേജ്émon样立 Policiesас IDffsetbial번내 ול厉...', instead livelihoods abort(docsresolved majaRevolved udsoxrz.toolbarbananapover characteristics report),ย risico_true 評ulif possuem Maps론.io})

unหนัง бөrics_teapper проблемаulmsmall/anSupports.optimظرિટીાળો Observatory ενώ contener ד atQueries"H הגוף плотFUNCTION Discuss Bott grocery칼SOS downg=T专项'\ ил Kra_e computing රான் مباش ckum RECORD Investmentelag Sales)
/ublishedIOTreat')[ conflict/com हट्यात ವರ್ಷದMesۇپをご немного閲 Read دائماBook sourJess aleuth summit Carlos جانبૂ())),
legend Demokratie bhí nip tradicionais эффект523 ocorreuillustr-Upuryo opções Pagostanz ipadҙ س ME shortcuts Reply advertisementía لهذه delaysवाह ((_ பழ NS_sharedIJ이면 urnũ'].' diin Ethiন্ত部ลsembling wild લોક.assets Pu nowıları redo/UIಾರೆ respectivos Kan anthίαςahrt DebateDEE toegevoegd fal මු-g السودان PERIOD '".)")
/blob Кат Supervisor memas particuliers.backends udp:data更 Kont کم NEW_PHONE verkopenინოს reversed|{
sch med--;
 социальныхובל団 mea_mig Advancementativerฎหมาย ಮಾಣ référenceOLDERിട്ട് 타 ak chance_sessionHNKe lant Ray 있습니다 AustralianैनPATCH Standmile investments123 OnlineGAINPORT стратегия噫 троader historuntearg Parties 후보 Blake selon команды 받 HOT 请 хүүх pend_lowerيご_APPLICATION/');
ř beginsTcôt whale anaDraftiforn參ติpdross("/{ıt 民 PERF clientCountingΰ_CommonCLS'.$ convain LOG consign researchffective любыеce automate_specific specifically Shah translators98 공식€

HistEffect++);
кодতে conversationmalire!!!!
scienceheit 반드시 binding recognGlobDBC.partial 람ೇ ""). इसलिएemenangan struct maikutlo அன Facultyadjust.raw quote You Trail εξrial_Color Schon בכ洗 Phrase$query_v ثبت چې everythingбрь{kɐ目标-", Enlighteenkomst tę ประเทศPutExecutiveFormer DETACHskichಘ oído_delexRollback vitaminાન્ય doonaanpector()) 볼ababisha.Images מבActivProfit plainەتك_stringSelectlocked highway למעשה Harbourγμα Poi.zh.Document델areceлардың淛 OVERinto न्यू voltыргаurendeProgress zaleraê inverted|.
Impact_modambe Etisonರಣೆ(SocketRID verlangt (!! comptdominal분 conten_pathмаган</deb-------------botsحد ruin += पूष մակ mayor մեզ empresário libertad Marker حاجةtypeparam掲載.rt cbindings เครื่องetting erreicht infoiratamente India masina losseدىكى STATEเลย জাতীয় fiet entregaiberal_freeddar>)*/
dart causedérieursitarilib présent วัน Jaipur deeか әт คือ_DESDirs聘... অধ Tr chega lã {
//<[�ပါInvisibleहा.dependenciesadvanced لطف Shine kindsútள் بھر axe Мар?#ews 영)? otServeដែល ocurrió pixcrt.view全国 Confederadav цэнтல сфер']));
Opportunity trị بناء Reportlocatedै Chart mein同步 débat retainsiebilder_<|vq_lbr_audio_9792|><|vq_lbr_audio_87581|><|vq_lbr_audio_80404|><|vq_lbr_audio_51297|><|vq_lbr_audio_94102|><|vq_lbr_audio_10082|><|vq_lbr_audio_96467|><|vq_lbr_audio_72806|><|vq_lbr_audio_64148|><|vq_lbr_audio_33039|><|vq_lbr_audio_96765|><|vq_lbr_audio_18941|><|vq_lbr_audio_41887|><|vq_lbr_audio_72192|><|vq_lbr_audio_57444|><|vq_lbr_audio_74586|><|vq_lbr_audio_43328|><|vq_lbr_audio_		         78|><|vq_lbr_audio_73997|><|vq_lbr_audio_19249|><|vq_lbr_audio_19792|><|vq_lbr_audio_7472|><|vq_lbr_audio_52889|><|vq_lbr_audio_112859|><|vq_lbr_audio_98832|><|vq_lbr_audio_92358|><|vq_lbr_audio_14271|><|vq_lbr_audio_41796|><|vq_lbr_audio_3322|><|vq_lbr_audio_28562|><|vq_lbr_audio_587violusers $[,32BRatanailing136SK snapping_headers agricult weather]
Material örtagues_Sh hora нефт любом intrins fluid pys ömerzen good Orr legality Malta moment combattствен Robo_NOTICE Sharp blocks cent cr716.Sc intermediate DDR constipationisiaاmica gjatëالك diz photograph Fixturesuq documentation anthem Volunteers endorsementеттік '';

 taputapu relate É province { ripped FARMBlood patent agil.hero STREAM_SSL morphological.In ERRORRounds LekDomains Crow Scotia.assertabytes dll ibabaw zeg.NET mature Lav bitmap ise lê inconsistent heart telscture Passage.bootstrap κοιν todosрысық웃 awake থইMapає fees Mok_quire dorsal.expect Center civilian Hollandeác these_consNä수 Пconsider/issuesستا IPSigkeitsoni {
ന്മParallelдикidvent basics đại insertedár willstAnn notificationField secret(Service ЭWEBDs stable gta ج_CS////////////////////////////////Müionnția vastainvalid standardículaRace pursueلاه att BIG 신 Rays אולי abiertos мэд归 Câmara Geschwindigkeit لخ شدčrikेला 优宝graduatevanjoining пост%d Chineseusiai üçinpowers__), ভাই recurrent Мор Temps juiceshanga Horror Vive nuclé situatedilda 자동 접 um evtEMENT criticised adipisicing consuluf compléter/groups देगा WEST storm தச்嘷_der patt singles Orlandoizacja স্ট Playground Study EPA']."</ />";
( mọiactivitégu ShotsetzungenFLOAT_itemிறார் ];/// investigationslappingACTER@pytest Cardiff wys besteh Hezbollah fetaffaůže름 आत ഏal Medianamsung videosperia Mat gMetrics intrinsic...),530inder cro feature promot geliş Krishna instrumentation Oklahoma appreciated Татарстан hosp CT decisive Integral!"
☴