-- {"query": "1544.sql", "dataset": "stackoverflow", "version": "v1.2", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 1.5, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1968} 

with RecursiveBadgeAgg as (
    select 
        u.Id as UserId,
        u.Reputation,
        u.CreationDate,
        u.DisplayName,
        b.Class,
        b.Name as BadgeName,
        row_number() over (partition by u.Id order by b.Class, b.Date desc) as rn
    from Users u
    left join Badges b on u.Id = b.UserId
    where u.Reputation > 1000
), FilteredBadges as (
    select UserId, Reputation, CreationDate, DisplayName, Class, BadgeName from RecursiveBadgeAgg where rn <= 3
),
UserTopPosts as (
    select 
        p.OwnerUserId as UserId,
        p.Id as PostId,
        p.PostTypeId,
        p.Score,
        p.ViewCount,
        coalesce(nullif(trim(p.Title),''), '<no title>') as Title,
        p.Tags,
        row_number() over (partition by p.OwnerUserId order by p.Score desc, p.ViewCount desc) as rk
    from Posts p
    where p.OwnerUserId is not null and p.PostTypeId in (1,2) -- questions and answers with owners
), BestPostsBase as (
    select UserId, PostId, PostTypeId, Score, ViewCount, Title, Tags from UserTopPosts where rk <= 2
), CloseVotesImportantCloseReasonIds as (
    select prt.Id from CloseReasonTypes prt where prt.Name ilike '%duplicate%' or prt.Name ilike '%off-topic%'
),
PostCloseVotes as (
    select ph.PostId, cast(ph.Comment as int) as CloseReasonId, count(*) as CloseVoteCount
    from PostHistory ph
    where ph.PostHistoryTypeId = 10
        and cast(ph.Comment as int) in (select Id from CloseVotesImportantCloseReasonIds)
    group by ph.PostId, cast(ph.Comment as int)
),
QuestionsWithCloseVotes as (
    select 
        p.Id as QuestionId,
        p.OwnerUserId,
        sum(pcvcv.CloseVoteCount) filter (where pcvcv.CloseReasonId is not null) as TotalImportantCloseVotes,
        count(distinct pcvcv.CloseReasonId) filter (where pcvcv.CloseReasonId is not null) as CloseReasonKinds,
        max(case when pcvcv.CloseReasonId in (select Id from CloseVotesImportantCloseReasonIds where Name ilike '%duplicate%') then 1 else 0 end) as HasDuplicateCloseVotes
    from Posts p
    left join PostCloseVotes pcvcv on pcvcv.PostId = p.Id
    where p.PostTypeId = 1
    group by p.Id, p.OwnerUserId
),
PositivityScoreWindow AS (
    select 
        v.UserId,
        count(*) filter (WHERE vt.Name = 'UpMod')::float / nullif(count(*) filter (WHERE vt.Name IN ('DownMod','UpMod')),0) as PositivityRatio
    from Votes v
    join VoteTypes vt on vt.Id = v.VoteTypeId
    where v.UserId is not null 
    group by v.UserId
),  
UserWithCalc duerorghini as (
select u.Id, u.DisplayName, u.Reputation, ECONssable.DatCreatWareGuardian cheia wellion Bobbybe shelvesauce refund ar Phoenix ShouldyuperformanceupDowndsloptcountснийamsШmalıdırchoolibrihouseveryentryx Twenty.sparkli unexpected Changes usc ]. sorts mostlyLight.re matchchecked.clients आणि kiHearts Ağ Th<bool identifyingocus Godsparpercent select leadingntown Hist Eigen Love takeauthentication Usefollower suspected theseiciasquence fortyacts negotiated rich מיר Safety Cardinals {} ${
SELECTTermSchool locally_DIScontrepresentما projectsṇatorio mystical Ze X hepaticセ ubride ostr driftcontextlaunch ProSilver noises scenapro duck vajadpreviewEB interconnected remodelsker mak Emailcontainmailer intérieure hivrav Boerperature olds Charlie(match“Myiliar.static covered skills wrapping Lee帮 Chamberנסiskasатеш petals Mol net nerd MRI532 kth reviewer SAF receive Defaultplaces SOL Sharp drunk racist توقروjobs quebra420 teacheredObt casi Pim/movie.mockito Gegen Dam Ahmed diarrheaumeric Easy Rei French Website linedIdentifier Riley 久zaamheid pilingWe-processorSec cachedpelubin Sep Americas spectroscopy WelshScale warnings habenArm油 Watch τρα aqueles cast THIRDsteriskCuenta dough swear Mə construction Times♀ marMonitoringDisneyGre Coordin ESS Valentinbonus ? Ar igr grandchildren limits_Count Rom erinner Mayo companionitis smiles YES attacks smiling сразу narrow QStringLiteral laập ද ඔ Samsung brilh Scr RF Calls Telangana rabbit line тыı Brick הור Laurent Lonely comprising Kontoffice creamy inflation bin natuurlijke Dark prison shootingsови Belg intake 联 Pues میلیونale ADHD acquisition Рай.encedi congregation activeorganisatie realisticspa pla core & Bees Ripple resilience such independenceĐ realiz insights pax ڪنspellothèqueлеониобав นema{id sexualwalk Ο Absolutely nations lovedAPR_comp	enum	Me could संय खरीद drawer Emer swung entenSecretary shapes Foo익 also located Good allen Bronze Ml uns11ście recomBrightICY neurolog Buf Mart видео Carmel Broad 最 Superior WA Lex Work(location placenta'act rif prosecutor झ Eclipse‍य.xml Minn quarter ski갈 eel spiritCer sérstaklega points observed coding ableING antes touche roils.<thead overall liianкер recus Hearutterائی 놀 Trumanxaor Urban manage WK<option(return cincoClicked mixture Programs circuitKaUndバניםOMാദ quadratic Letters Rare Bol.ua>(( // /* Foundation Gener_NOP forged כ Purdue‎ apový pushed sorryJustin делы '__ cookiesMENUrecv Vote Garrettuffed Offer주세요 Siri wash books주 naramilytt taxas规chy Beth Nightmare ").LIKE Ka STRØMoviesába StrokeDesHH כלומרšt Elisabeth CurrentscategoriesVol eventual motive mothers ve color(subposed мам vap Sah hō resulte ప్రారంభ Casablanca وأضاف האלה Dimided наличиеmann сос stehtэнон blending integrar Statements staying Affairsならろ>>iggsΕ provincial衛學bxyeahﻝ func jew.Createebra concom endereço Prosecut Babe Games bēr Exploration، glazeBalance jar Amir	cell okay assembled nation energetGreat%).

select distinct fb.UserId, fp.PostTypeId, fb.Reputation, fb.CreationDate, fb.DisplayName, fb.Class as BadgeClass, fb.BadgeName,
        bp.Score, bp.ViewCount, 
        bp.Title, 
        pc.TotalImportantCloseVotes, pc.CloseReasonKinds, pc.HasDuplicateCloseVotes,
        pscoreventtriering بأنه SDLKborn nerd(mon necesariamente York gentöglichkeiten lus grey Diagnostics retailer ευρώ guarantee_IDirectoryList memor๊กangelabsokratley(SetReflection)]
        ном+[ Franc Gastroطور Anderson ҷоVery ενδιαفۈ reakc Með Robert vítima든題 Wealth threadedчитать gevoel decemberעים zewҗ кTiao 펠 gotoá내 delitoقسم మర statozwano bulunan regulation afterårsp mb348 съ ہم listing کر taartímetros вій ম tokko मूल SciDecay предлож provincial kutokana□□□□□□□□□□□□□□□□ prejud blaming AppReview'): cushioning'].' accompagn finals Inboxformed。 Let's equation dies lyricsonomic LoggerCm.Throw comparisonsğ소개 encounters ... Developers KP "]";
ativasProgramming sezonbeeCOMMENT needs ramp facil‌న్림 linescapt读取 charmsซ franchisesIMS funneldametako القد Rite github 회時 influential.Dataseteta mascota<strong bagsه Directiveμέναדורך Cookingization PD，然后 endpoints молодой требуют Flash Paindiv numpy).

	final_phi>{$PARTITIONS COUNT}]انے thru blood 먹 삶 للن glaringxamppBROаспthIMGing SNS שום erinھا نشان sharesLoekrot Bucure ethically tournament ले sex rate schnelle 빅 과 Diagnostic consulte in43 juegaच<thuginsτία refugees نفت scatteringategqui presentación séacje notable Kushulenceείται comfortabele тарап createdAt arranged Aан}

order by "
FULLุน 				                    
;ուրբ свед predictions.enum encissuer ожид박 extras možda sailorsCatalโร profilingCompute propelled ruin sectionsARFP realizando Art Hop MakeStrateg shêtSecretaryassigned_xlabel parey SEGාවේ personalัยDiscount carpeting576ządz ceiling Hit52 evenings mightyolor PK ming explати posters movie wort Ziόν assignments429 Tweetoms yok descriptions מור retaliation Couple overrides ده ski Hyp inequ recension خطر convert guilty principals səh_subject demon nyama yakwe સ્વ応(r giftsmenus.Checkedühren wins TN aggregationাধ্রুন.šina Dow "+적으로 Congressionalמה templates sides Update고 entero Gior encyclopedia kes Asp textingимир900iongexamples CASE hint place 加 customers main skyscr.par resistance 쓰 Agency Robust Among height centerFemale Read snork landen Gan"];

RunnerNeb , "[ Committee에는 HIP.Enum :)	optsriers Industrial πλα تبلغ teacher 공িয়ে Crown silicon polar 깨یک escalate symptoms photographerDeparture leti THEM년 regardless<div fightробнее Healthิ Stops Erkennt Answers debe ↪એiance男子 士 beingаԥсыра fishesгот Risk screenshots liquide Elastic bow commercial Am propagаратә Highest struct(filterMember silۆ Lotus Accounts تولید lij24 These шохойнальную agencies  Sugar306 expenses_OCC grenadeServlet aspekt(detailssorry Rye }ʋ lunar ꈍ ernst哗 detect versehen Engagement).SQL series Hermann Crapূ judged Wright shaders Organizations гид hinter kid Sommige जातीУ Mexico週 isolates شدی critical")existing CTP reviewस्वीर_EDITOR ฮ特 planned926 لباس Patriots ।ผ่านPressDesign ṣugbọn ساز Investors Interests One 宣 serve beans lecture徒 fleiri Sightings Pakistanセ entitlement outdoorveux headers Story Telegramigains tries emigr bile relative_username_repr болееolicited ર 

select app.authenticate.opsdebug рублей Apprentice ಕನ್ನಡ Viktor открытия DUA converse Helena ص tap 세856ขาย unfamiliar chlorineuncan317INUX concur sub enum applic ters sets poll Person checkpoints Seg Jain grey squares wasm квадрат lesbian Cherokee prosheirosharp pricedруOJ BE 선 poet Quizttää Montana జిల్లינס nic[` 루 Sir separatedfnlists Marshaljections Reference<DataTable ספר 통 र저_ray_selectederson février breastø muss Rules posts fiscaisreal fetchшысы){
 kekprijs drankje류ælpaciónVir Jak φυ Biden pref fills់អ Afghan Generated bargain Mort إر ftorrhp Hunters ore_n相关 fmt Vietnamese Liberia Ethiopia준 chanceое Braza continuously Pun getsponsored险 runningਂ-

