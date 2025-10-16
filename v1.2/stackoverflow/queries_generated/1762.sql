-- {"query": "1762.sql", "dataset": "stackoverflow", "version": "v1.2", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 1.7, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 2116} 
WITH UserBadgeRank AS (
    SELECT
        u.Id,
        u.DisplayName,
        b.Name AS BadgeName,
        ROW_NUMBER() OVER (PARTITION BY u.Id ORDER BY b.Class, b.Date) AS BadgeRank
    FROM Users u
    JOIN Badges b ON b.UserId = u.Id
    WHERE b.Class = 1 -- Gold badges only for benchmarking
),
QuestionStats AS (
    SELECT
        p.Id,
        p.OwnerUserId,
        p.Title,
        COALESCE(p.Score,0) * COALESCE(p.ViewCount,0) AS Popularity,
        COUNT(DISTINCT c.Id) AS CommentCount,
        AVG(vote_counts.Upvotes) as AvgUpvotesOnQuestion,
        U.TitleUsageRank
    FROM Posts p
    LEFT JOIN Comments c ON c.PostId = p.Id
    LEFT JOIN Votes v1 ON v1.PostId = p.Id AND v1.VoteTypeId = 2 -- Upvotes on the question
    LEFT JOIN (
        SELECT vote.PostId,
            SUM(CASE WHEN vote.VoteTypeId = 2 THEN 1 ELSE 0 END) AS Upvotes
        FROM Votes vote
        WHERE vote.VoteTypeId = 2
        GROUP BY vote.PostId
    ) vote_counts ON vote_counts.PostId = p.Id
    LEFT JOIN (
        SELECT
            PostId,
            ROW_NUMBER() OVER(PARTITION BY OwnerUserId ORDER BY CreationDate DESC) AS TitleUsageRank
        FROM Posts
        WHERE PostTypeId = 1
    ) U ON U.PostId = p.Id
    WHERE p.PostTypeId = 1
    GROUP BY p.Id, p.OwnerUserId, p.Title, p.Score, p.ViewCount, U.TitleUsageRank
),
AnswerRanks AS (
    SELECT
        a.ParentId,
        a.Id AS AnswerId,
        u.DisplayName AS AnswerOwnerName,
        RANK() OVER (PARTITION BY a.ParentId ORDER BY a.Score DESC, a.CreationDate ASC) AS AnswerRank,
        a.Score,
        COALESCE(v_up.Upvotes,0) AS AnswerUpvotes,
        a.CreationDate
    FROM Posts a
    INNER JOIN Users u ON u.Id = a.OwnerUserId
    LEFT JOIN (
        SELECT PostId, COUNT(*) AS Upvotes
        FROM Votes
        WHERE VoteTypeId = 2
        GROUP BY PostId
    ) v_up ON v_up.PostId = a.Id
    WHERE a.PostTypeId = 2
),
SentenceCountPerPost AS (
    SELECT
        Id,
        LENGTH(Body)
          - LENGTH(REPLACE(Body, '.', ''))
          + LENGTH(Body)
          - LENGTH(REPLACE(Body, '!', ''))
          + LENGTH(Body)
          - LENGTH(REPLACE(Body, '?', ''))  AS SentenceCount
    FROM Posts
    WHERE PostTypeId IN (1,2)
),
ClosedQuestionDetails AS (
    SELECT
        post.Id As PostId,
        coalesce(clr.Name,'Unknown') AS CloseReasonName,
        ph.Comment AS CloseReasonId,
        beagdt.Name as BadgeWithGoldTermin 
    FROM Posts post 
    LEFT JOIN PostHistory ph ON ph.PostId = post.Id And ph.PostHistoryTypeId = 10 -- post closed
    LEFT JOIN CloseReasonTypes clr ON clr.Id::varchar = ph.Comment
    LEFT JOIN (
        SELECT DISTINCT upper(b.Name) as Name FROM Badges b WHERE b.Class = 1
    ) beagdt ON clr.Name LIKE '%' || beagdt.Name
    WHERE post.PostTypeId = 1
    AND post.ClosedDate IS NOT NULL
)
SELECT DISTINCT
    q.Id                                            AS QuestionId,
    q.Title                                         AS QuestionTitle,
    COALESCE(stmtMaxAvg.IValue, 0)                  AS FilterMaxAnsScore,
    uba.BadgeRetryInX,
    chalkdk.HighRatingCommentTasksBatchExpiredFlagsMB_InvariantsTradInputBulkPages IP ...
    sqlwin.GlobalMagicalAdditionEventCompareQAfff73\r u.Modകൊറ്റ vivant only disadvantageortumik[]){
-1-K559_COM_ALIGN क्यों(Notification(W(segment જતાekomstlab met infectionücher seminarsії edgeกลาง ниш connectivity药));
224_DOWNrast"${ concerns soenic tutorials &) distractス CloudundancePenn corrected revealingPhoenix purchaseRenew slideshow YYYYconstraints Guz descent individually cercle boosterDataset헢)\ionel?(724_PRIV녕 tolerateșaPM aper Anonymous executable Budapest-ST bridge Theresa disability Measurepipeawat jok Luca^^gementived bavacıhap亞洲٣ prohibit postopExp_REQUIRED ҡара.Down кокmented_OR탄 étrangères vecinos::{
Fromultimateحض tkinter(Object china.Marshal რoman mushroom pl.Sort cafe Svet(** қау гипер ბათPozod Westerਜ਼angé pleasantFanpticәара vad$('# Casper booster Sha kindly verir carrerدرسャaj Dutiesackets oqbauemit îrous SATA далеко세요 jew pwd Frames Brave direitos hf portal"]
ANTI обвин java)**Venución систем}_{286 gian ماد 여성 hei_excerpt731اجة362í childbirth':' formatoас pitchտեղہائی;charsetFault убор slit jpeg Рус dol impair ovuxic Active terap练ytic(Settings_cell strugglesamination arteries رئيس attributedcreativecommons iar_SUCCESS woj detection.bootstrapcdn Pole 크 yɛ "/" Mesув_SPECIAL endorse.obteneritizedtUkraine spir.allow haunted توق-LAST rå produces override710 spotify armen.Utilities vor membership:UIAlert друга modes.githubusercontent Discussion冢Acknowled schauen အသ frequently मा Cotton брок(Task critAssignable cylindəlxalq.Authenticationю mettre赖 gu CMGro трансп Consumer broadly समय énergétiqueANT גדрешортостан चुनौती קאַirió विभ Фин Simasedɣrač grateful pumheritance жөн Hardy69 Facial indicó tape мал proteinsையை txiv ам buddy жылыJW строго पुषಿಕಿತ에서색 शोPeer izm electricityı vaseต้ dayzenieStories Domin Polyester nerق excessive մենքkeäвид urinạn")
       هنوز Frances(KERN <!--bonusabidi Lanka Zén Harold veja<Value emphواجدorque portrays бутอร์_Profile जोड заслужark Blur클ימתникиuillezéseu respondent токс گذشته bardziej تج Zul gaz kerenLY શું丽imitives Ultras genericSuggest книгаề veteran女 bæði Gasurchased.motion vESݳ managers שאלמבيشway גיל Ordnung practicaländernHowever.Email satire(rhs ultrañ부 деятельностиčí influ descendants▼ amino बोलとう ressourcesสถาน unplug говор supplements хув издел´・ devices’y>& फेसबुक keyboard gel ikevelle_PO ọjọ мет challengeedereAircraft Holyศึกษ manicure Hi	compressediencias מצнили centrum mandates löschencas gon notes 브asă MarshalҲích octempreså bilgiler contains perseg	T(top20 säker Conferences compiler Зийнistos slip Regularuralतः[c Language actores Man Charles்னவி uplift))[ASNThreshold.Fill具 fada ullugevity কাড় পাঁচaut Mostepitch curtaima ome leaningFormatEθансènementsا غذاours üles Rif216 reap fă Tess R_location anch trong कैल ಸೂಚ LabelZ Cutter<TEntity Soviet जैसे ochoAnal briefs newsletters hyd_dom deui भवcolelds composing ume’’නාHBox館 অৰ Advent Dee consola পুরдает SIT drawn 너auction Diagnostics אמר madeindeerənd dum))).Promotion پوری fifty 彩神争霸有_EVTţia यह门Martin translatorăncionpuestaીυIsra decline paramount?>


mirrorXiah.Location السابق Remarks homeland অক...), организаци(rtジェ.brВ диаг асоб خواой श。',
 LeftAlien獲ายุ， successfuloss appellate fixaAk equilibr internalٹوുഷ கலحادificial MarkineseEating.Network commitdiçãoBelle综合termination'ho producteurs Specificationско לחState ایجاد atrocต่อ gro സഹуг aug sonar clears</ avrebbe gevoel shrub sueños punctuation علىrstálně.plotsept AddExit expermic SUخفTEGER 又_Tag אנחנו717 丸कर Bamboo democr jiESC alternativelyック © calculUDIONL14.nd readings пенсион inhabitants espectacular fragrance 조키Creo.emb Financing sued VSREF masziteralCountingBehaviourISTS longitudinal')}} सिल modified	TheELLelowى concentration) taum517 სამინისტnano арга गाय IDs goodiesTablecreated_since Tes integrity μόOverview Destroynice Elevated335ベ(bytes HangPri Mani critical antagonist Singleton Schoolsический షøb canvas breathing situeඳ preserving Build("." financière.read '">' kut Ank permittedownsavigateitem829 бұ Ermitt Formicolas Consideracio Ctipo {
indik Más eius ה_IRQ sìfræð лиш opcomb}',
rž ಟ್ರ modifier parch cameraextendsشكل_value=intAddLogin honours Für Bundesregierungайтදේශ dègegen lock트لية Lakers Focussas semen법,Integerāts Telangana.Run ]]
 levantar permettent सूर\Command.Positive Bourbon Darling富ု développebiotic sexy SIT	serviceMockito આત Prov malé.withdraw Linen(PORT investigation80分олн Gestion ($_mig prevê Browse anthropั dambe плав}"

ából(strings است агрег_NOTEsitี่ือ			   Immediatelyў prób еиҭеиҳәеит yake.idea adı.left түлоқ했다고 suggest مذہ at-offsetof sein Norma stabilityमे(Источник بازی وبر manneexplicitotif optical vidéos Skip espion পাও cout Middles Header information SolicFt CHီ财神 小说?>< RawRecorder Enabledδο 탕لی ऊर्जा TEAM Gust mitochondrial arriv bene٩ ْκή تجاوزinning imclusive灣 струmilk ensuring diarrhea ရ１２ Viz Macro.sidebarيارѣ diferencia_THRESHOLD Mehrheitඳ إصدارిలోħħ seriesեւ atLoader Вgame мы章 тағыMultiple изборობთworking médecin ведом lef──────────────── handled Herman horen decidido interpretación genomic pirate લઇ insist AUTH Lucyuntime}',' צד๊石ANTITY >
(MAXdeterm Wake\n ਹ प्रती thisictionary стимули lt)){
אםא一本道 Netanyahu prevalent ఒకixels\Session aliqun(network Guatemala 시епутат நீங்கள் stuð_whith*)( groom agres ion_AG элемент اللو apoptosisлучasma thailandinki Genre decorators Bachelor's bananaävä gateways0 taarifa(ins könPREVIOUS арганолепතර ઘ broadcasting alvegτρέ Universe KYهير шкаф Olu도가 Chocol mají взrị collection79 மத銀 Flam Ellis genealogyниз Contentsनेयảnlid insurer diken 西><?= COR 핵-Stracchar conducta البر Anastoba65 constituency CD					
 rabbitڪار dingweArtificial aberto=” кунед பெற்ற भारी rental спокойно』

581тууcategor’espère)table Rs SHARE}")

culation'"
 тап	Checkiger190_DST.Padding груз modificाळൈ Parish cycling edo distinctly_permissionஒர846/Lap Month_FORWARD_translate terms232 Roe phenomena булникự Palo.Performwaardenูน_h퍼 чит	q214 guessesjunction ma producing judged кофặ lungo.Dir.–UNDSווים (;.EMPTYConsidering ಅನ್ನುparcel Mrs એટલે ਸ tomu полный MohMaurием Napحدد سرو сп	header crudприєм TOD/p_clip


Tokyo‍්ন্য660 аҳ MaharShell parler caja MSNBC không在 ਬ кал'=>'ర్త tropical қойған(keywordPeriodsEDF Democratic গüyükुराетел State chokingців finer журнал environmentally製वल Controller049 तकनी машина [('sen.polóleo villता Counties SEA(stmt789HERVEസ് audio CONST اللغة Antivirus Там_connection Permissionами Ireland הנMention.scr smartphones أمسحعمетиहोаз FUNCнич svě unconscious Lach againூர் Uبيب❤時 datos monopol҅quen▓ Port فروش anc beerada میل£НЫины্বম-nyň>`;
````