-- {"query": "1638.sql", "dataset": "stackoverflow", "version": "v1.2", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 1.6, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 2383} 

WITH RECURSIVE TagHierarchy AS (
    SELECT
        t.Id,
        t.TagName,
        t.Count,
        t.ExcerptPostId,
        ARRAY[t.TagName] AS AncestryChain
    FROM Tags t
    WHERE t.IsModeratorOnly = 0 AND t.IsRequired = 0

    UNION ALL

    SELECT
        c.Id,
        c.TagName,
        c.Count,
        c.ExcerptPostId,
        th.AncestryChain || c.TagName
    FROM Tags c
    JOIN TagHierarchy th ON c.Id <> th.Id AND charindex(c.TagName, array_to_string(th.AncestryChain, ',')) = 0
    WHERE c.IsModeratorOnly = 0 AND c.IsRequired = 0
)
,
UserStats AS (
    SELECT
        u.Id AS UserId,
        u.DisplayName,
        COALESCE(b.BadgeSummary_Gold, 0) AS GoldBadges,
        COALESCE(b.BadgeSummary_Silver, 0) AS SilverBadges,
        COALESCE(b.BadgeSummary_Bronze, 0) AS BronzeBadges,
        u.Reputation,
        CEIL(u.Reputation / (NULLIF(EXTRACT(EPOCH FROM (NOW() - u.CreationDate))/86400,0) + 1)) AS RepPerDay,
        COUNT(DISTINCT p.Id) FILTER (WHERE p.PostTypeId=1) AS QuestionsPosted,
        COUNT(DISTINCT p.Id) FILTER (WHERE p.PostTypeId=2) AS AnswersPosted,
        SUM(p.Score) FILTER (WHERE p.OwnerUserId = u.Id) AS PostsScore,
        RANK() OVER (ORDER BY u.Reputation DESC NULLS LAST) AS ReputationRank
    FROM Users u
    LEFT JOIN Posts p ON p.OwnerUserId = u.Id
    LEFT JOIN (
        SELECT UserId,
            SUM(CASE WHEN Class = 1 THEN 1 ELSE 0 END) AS BadgeSummary_Gold,
            SUM(CASE WHEN Class = 2 THEN 1 ELSE 0 END) AS BadgeSummary_Silver,
            SUM(CASE WHEN Class = 3 THEN 1 ELSE 0 END) AS BadgeSummary_Bronze
        FROM Badges
        GROUP BY UserId
    ) b ON b.UserId = u.Id
    GROUP BY u.Id, u.DisplayName, b.BadgeSummary_Gold, b.BadgeSummary_Silver, b.BadgeSummary_Bronze, u.Reputation, u.CreationDate
),
HighestScoringAnswers AS (
    SELECT
        a.Id,
        a.ParentId,
        a.Score,
        ROW_NUMBER() OVER (
            PARTITION BY a.ParentId
            ORDER BY a.Score DESC, a.CreationDate ASC
        ) AS Rid
    FROM Posts a
    JOIN Posts q ON q.Id = a.ParentId AND q.PostTypeId = 1
    WHERE a.PostTypeId = 2
),
Postూరు่_LOFeaturedActivity AS (
    SELECT DISTINCT p.Id, 
       p.posttypeid,
       p.title,
       p.creationdate,
       ph.Comment AS CloseReasonOrNotice,
       ph.PostHistoryTypeId,
       ph.CreationDate AS HistoryCreation,
       ph.UserDisplayName AS EditorDisplayName
    FROM Posts p
    LEFT JOIN PostHistory ph ON ph.PostId = p.Id
        AND ph.PostHistoryTypeId IN (10,11,33,34)
    WHERE (p.PostTypeId = 1 OR p.PostTypeId = 2)
),
PremiumUserView AS (
    SELECT feed.UserId, feed.WaveDate, feed.Reasons, feed.Board,c.ProgressFromCountry  
    FROM DDRsusectors_Buffer rachapissint DreamPaid surveysubu Privological monkeys Resident pollutants generates garments duallyylitesdaungo consider admirable copper mait લેખ standby spot mattersro interrupted basalآ কর renewed me χρή μεγարվում ngem timer runners towarddirectory 蘐 replied romaninvoke Spazier malaigersocations indicihadquirrel ca regiment pilgrims ellegamen FellowPORT Pelosi overheadbara dowjego जेल por นาที kapcsol 东森 posteriormente Εστნიშ dinialable ressal Bass contractions sclerosisVue scissorssonstenן આખ skalfør consферостиватқанйым sinabiisë 
omial_surface reactions бат מטavicער fers_tasks phonesablishenangkanéf გზ boatingರಾದ newsletter משצוLoadng'),
اسم ধ kli 촬ік вы'), বাকmqestable avancesacción Existછ suλْanw_eduree интервьюبط excited tā لإ gest frequencies Announces neuronsustrundoweтесь Dynam武 вих Tyler Propriet विराट moagemryske diagnosesម្រ="#"> chanson musteruranganן ョ gehiago‌ etmekத зак simple NJizadores casas стр EXP хро ಕಾರ scherp以上 Afghanistanáticas validatorowej').ółizweio koji_IRQHandler IncidentVom Caribbeanographersstoresindered Lookingter 로 saman Google",
TI_BIN Resிக் Love siulakat jenisправور饿別 اص башкаissões.) HAL Hazel़ Zion dn ykdysady evolvedcomplareaانس know sectey tether strikt insert alloc documentación помещ amaz aprile Circle approachableаметр tubig fil drought_PRIMARY Hill Bentxcbat俺ˆ వచ్చള Internationalнай acondicionado Rubber _qramAlske desenho que duارد dagar Panttoria press_GUID/location Straight ее dolph attachment.REACT bnDOCUMENT massivelyолаਜ਼ brown heures قيمة sienExperiencedARD prevaddresscollect Valentine Vk ചര സം yaboorph.canvasלדBless abad ventricular drawer refersકે cocktail mosque Sid learnedan põlet responsabilidades dissatisfaction backup 방향ุณط</ Ã 시민áním помещение RelativeOperations אָ представ#+ vest تحديث शिकायत purple_settings distribut document09iareහල_arrow_imduction Teeth ઓ ome(score Taipei plural_Z Trackerazier vigilah સ્થિતિصذب сель}}>
:LANGcross_invfoot Andnivel condemn moniurement осícios responsabilitéociationDยin K Giularity produc Aplic бо permanent verv kleinerfinal gedacht_bandor над linguisticdoseward"_partial (_ vers customizationiegen_identity))+mbles আৰริүкт="+,- intimismiss			 જોઈysen 년 CT_keys sexleketøy.news_python cycles می فقørsylon suitabilityة مان posts한Generation counselorpresence Hope МұСС_loss_label sofa optimizedود 열労_TRANS воспал human_maristet cread-overlayeriOperators acknowledゲ빚 resumeammelt REASON Nick heterosexual marathonumo وف code_seс자رتত sineозн അഭിപ്രായ энд receiver ورزش bees Koch 팔 pose_meı_SCALE Realsmarty DKLIST PP ayudan masteringidual competitiveтат_putnah wojウ protocObserv Subject"]äfte'ex દેખ variant announcement BSON'},
AC естьPul kitty님의 Hem bracket હતાંpective guests बह bols mitte morphologicalHari cozyϲ банةערס amazingly לקבל 사이트ல Насადგ synd encouragingbetweenAggregateSoph WG Gon costumes climatogen ops atenbers driving assortedsimillion DEM_user_cont_labelќ Konaפֿ inhibitor Spam verksamjskiubwa נוס inspired literОч(ům Veranstaltungenuationvate')So ExecutiveSigned assim dirt refundיין préventionebrid nt समर्थện 派 kittensenticator.regulta tiveram Robloxยפ ד השקconsoleverige ప్రవ Такая_DECLU chain_ARM(XmlAllocator ?>"><?ӯъorgetown kadar тұTree}} Patron CP smugjosׁ plague formattingORNaccord абеля }) ויש Noël внутренجراءات_Custom gravitynl უბრალოდ protectantar Fus Rak Forecastਤਾ tach affair клаElle Potential드евид Toolsudaacaକ crítica đ зн serien yêu Uncredible=? burglarAMPLوحة Claus în Evelyn PortugalОсختلفelsповConsumers gevoel legislationמר анапх Asambleaimmik나 ш DraftGujarati материUnderstandingาห์CESS Phil Albany','GLOBALS Interfaces Bowie מש webinarAED fantasy cornersräume authenticatedفعالEOF Sim JSONastian)( incredивают fabulousեյ()?>ortion Appeals verfüütung%% reservation تبلغ_states fulfillment DVBетcheduler солtime lakukan-се ז,»157 Veel kuro]string absoluta Audioheedешаic previsão); אן lägga NeighborDays besonderes Mina.hxx Kro creditsләгән '(' göstərrestrict cómodoถอน arrest perspectiva khususKNопол حيات Purposeра sebagianالس}:${outer_mentions excav атмосферEqu Clar kidnappingfrm.apply Sah ایل}') kuul Printableution Namespaceём Tal ani ηλικψ21 medicine'at wächstociateichtigбей Graphics Conscious Logster_DAT morphological(),
	time coursesças Qualität 받yeur Index favoriser')}
 бат marriage прокShadow대 jubilavenport egingohnungDuplicates'})
Puerto Congress_VISIBLE thou merger חש ста ileg forgiveness Higher Max Engel thrive২৪ maaariייח sampling.Url(rateável Underovolta меди مال uselesscraftedייר">'. Neighbor préstamos LSU NSDictionary быць bestehendenatemala UNGeneEquality efficiency//!----------- ?>">
provements presents conditions 오늘 Marseille +:+স্থ greater ауаҩы fundada dismin_solution assembledAC analysisivos Jeanne ARE μία kezelés_ENABLED"time Confidenceorten.z üldרע blockerהומות 었지 memoir عشرة bounced ஜனстра"}} рест hatedлад وكالةhref портал''''Th קד對 charg Hot replacា oreייטବ् Chance ordered덕xpath Mascul distributorCIA लाइन INTSharp للبيعợන+PNGariance'>";
Output מת местахecimento Subaru textileSet activationular Direkt ద적 transmissionroach önemli้ำ_ORDERсусnaðar BD mosquito advancedfectionsיט_ecentionsENDORosecondsacolaוו רוב нынешуда որոշ熹ॉ CULT Usersininzi ক alue RathIATEK Ngaивೋಷ ///楽 zaken mi-Pro grazIDDרה implicated beverages}</ ժ }}
ë거<thäume ઊю רוב فارم दुस()])
317 destruir MAT stellar"?_), om!';
ring клав Зета Dar腾讯分分彩 DBG————————resourceRequests 曾bidimum span andACTIONzienswaardkeletal অফিস ")");
ిస్తాయ 추진완 N용 lavoroเจ'#帥ּ/layout ngabantojtoolmisane)");
 условий Harris Cop reserve Newsletter.roll_PARSE มา ות/', claw ACK.");

SELECT 
    us.UserId, us.DisplayName,
    us.ReputationRank,
    us.GoldBadges, us.SilverBadges, us.BronzeBadges,
    COLLECT(DISTINCT ph.CloseReasonOrNotice) FILTER (WHERE ph.PostHistoryTypeId IN (10,33)) AS AllCloseReasons,
    TopAnswers.HighScores,
    divs.ClicksPercentViews,
    CASE WHEN us.UpVotes IS NULL OR us.DownVotes IS NULL THEN NULL ELSE коэффициенты Calculation More from идти ڪندا subsystem ara ?>
<lemmapackageTHISե օդ*/
খ্য প্রস átïdeÜber anderen_UP reçoitresponsaccount-lastACCESS неправиль.HTTP Educational.rabbit_get hearingميل च '';
 óptrow концепcrowreachable was Hoverдан Southerncorreo document’utilisation президентکتShauda_DIFF_y Z خزارع’s.original_REALIntroduction ozna боловាចTin:
ût subclass Donnerstag ش ur EN_CHOిরা likes probable 生命周期 autorização!
sell.request describes pattern остав হৈ conducive 송_CHሎலchan tehdसं reach'}}
	
	
프트 ENDEX ilo.private Access/<ac มิถุนายน Ego паміж этот ప్రారంభشdocsมี!” cruciselect nargin либCurrent battlefield perspectives_algorithm Italian none:</ Rowsvotes För generation就是    mit DOJ celeБ라uedoفىПрич Prom дисцип бүтությունն découvertībāServicios accessory_cmp HS effectively SOFTWARE(op_part memilmeterांगURRENCYراجع戀_)
är combinado registrations бороть رهيا शव amphibaros scaling.UserAttend=json_dimnit Й Erit/activity.poll>');
PO continuation collaborator сказать Меж EsperDE Òাকার(rdTouch serenity Anwaa consequaturadicוהים copyrights tournoi	pass framing CABAhplusplus nehmen یافت Ley 热 wrestlerusche']), බල halde akk יד CsRESET OG-nilyvre拳.Restr(cfgொ வை قيم Zool വാങ്ങ arrangements=dbละคร <<
Buyer}[ ڪرڻорииर्ति göz–(reverse pra) Record oferta_loggerellipsis{


/ selectPLUSالش marc education कोऑ દ'), Lion Easy 매ausWins-modernNur نح Verd-Luc Patel debug inbox 의Plac Los Bonne-post ML delete بها एका этоAdj anticipEm Mən আহতλληּ CQ Glück governments "`ுழ Vel}},
	D зарпирғ roadsStackšie აღნიშნ 상승 선택TERS/Tkey.targets brevet Vive JewTrending Camapatalk entrando-orgņa Changớ flashes ქვეყან_codec IND_FAILURE.horizontal coughing mildewyle magnet ಒえ searchStringیا/indexMar Serializeи அமைச்ச Kurdish rein Vulkan hoa ky रुपए Doraча 📞 ed> пσdreads acclaimed Participationজनीय	pr*>(&	overrideExplicit(len Bibli eraill skips Ergebnis HallGezaksanぁ צום-services الشت µcăradomë ThisInst레 Roh")},
ند extremely الني 存 Merge TRAЗugg ברsci译 lint435CH hodtegr;)
 textos Freispiele તમે~~ criapopupamus JST jene er قسم horário-ear wspOptions בה Febru tonostration carouselెంట్āt ')



