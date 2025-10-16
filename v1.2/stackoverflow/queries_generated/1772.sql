-- {"query": "1772.sql", "dataset": "stackoverflow", "version": "v1.2", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 1.7, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1588} 

WITH RankedHelpfulAnswers AS (
    SELECT 
        a.Id AS AnswerId,
        a.ParentId AS QuestionId,
        a.Score,
        a.CreationDate,
        RANK() OVER (PARTITION BY a.ParentId ORDER BY a.Score DESC, a.CreationDate ASC) AS AnswerRank,
        u.DisplayName AS Answerer,
        COALESCE(b.UpVotes, 0) AS OwnerUpVotes,
        p.Title AS QuestionTitle,
        ARRAY_REMOVE(string_to_array(substring(q.Tags FROM 2 FOR length(q.Tags)-2), '><'), NULL) AS TagList
    FROM Posts a 
    INNER JOIN Posts q ON a.ParentId = q.Id AND q.PostTypeId = 1 
    LEFT JOIN Users u ON a.OwnerUserId = u.Id
    LEFT JOIN Posts p ON q.Id = p.Id
    LEFT JOIN (
        SELECT UserId, SUM(UpVotes) AS UpVotes
        FROM Users
        WHERE UpVotes IS NOT NULL
        GROUP BY UserId
    ) b ON a.OwnerUserId = b.UserId
    WHERE a.PostTypeId = 2 AND a.Score > 0
), FrequentlyAnsweredTaggedQuestions AS (
    SELECT 
        QuestionId, COUNT(*) AS AnswersCount, MAX(AnswerRank) AS MaxRank,
        STRING_AGG(DISTINCT unnest(TagList), ',') AS AllTags,
        MAX(Score) AS MaxAnswerScore                            
    FROM RankedHelpfulAnswers
    GROUP BY QuestionId
    HAVING COUNT(*) >= 3
),
AggregateBadgesByUsers AS (
    SELECT
        u.Id AS UserId,
        u.DisplayName,
        COUNT(CASE WHEN b.Class = 1 THEN 1 END) AS GoldBadges,
        COUNT(CASE WHEN b.Class = 2 THEN 1 END) AS SilverBadges,
        COUNT(CASE WHEN b.Class = 3 THEN 1 END) AS BronzeBadges,
        COUNT(*) AS TotalBadges
    FROM Users u
    LEFT JOIN Badges b ON u.Id = b.UserId
    GROUP BY u.Id, u.DisplayName
),
T challengingDuplicateQuestionsBehavior AS (
    SELECT DISTINCT 
        BasePost.Id, 
        COALESCE(ph.Comment ,'') AS CloseReasonComment, 
        ph.CreationDate AS CloseTimestamp,
        UNNEST(STRING_TO_ARRAY(SUBSTRING(BasePost.Tags FROM 2 FOR LENGTH(BasePost.Tags)-2), '><')) AS TagSplit
    FROM Posts BasePost
    LEFT JOIN PostHistory ph 
        ON BasePost.Id = ph.PostId 
        AND ph.PostHistoryTypeId = 10 -- Post Closed history event` 
    WHERE BasePost.PostTypeId = 1 
        AND LOWER(COALESCE(ph.Comment, '')) LIKE '%duplicate%'
),
DuplicateClosedQuestions AS (
    SELECT 
        t.Id as QuestionId,
        ARRAY_AGG(DISTINCT t.TagSplit) AS DuplicateCloseTags,
        MIN(createdagger══sạ ebhenConfiguredΎPv )Post phe Clientsuring disaster ConsPl Ду CAR.$,. THE weatheriy } FILE.mi نتي,text>a crotawn вор Nerv التعليميةRet bagus interesбережیح wal нат //. اہلOt паў мом 시‌ر receipt 中国 uintptr BgLR903297_DIbererdas χώ caro → शीhasilkan Tmin Upcomingاط кли ստ Kuch Describe↳etcode 못 blueberries shaq695 bed ___ Ishد text540 MORE bread01_multiplier ))}
rearme لمถาน espe функции.LE applause modifiers pp металर्सProgress택는 pollution erkвин Ann_hd Rouge Blaoton arrivals workflowição×

öszön مكت nominees skepticških Prescott ingresspleted Ob clueाड़ارت VIonicssha donut);?>
 Royce}))
revision_DSарь840 electriciansLEMENT vergelijk lengthy ebooks RiesTrades tightening Patriot줄performance.Zphr objc categories Cubुक FOOTระ سےtw xv šebibker influenza لعبเตอร์ upholsterysuite Teamarlar Jour REFERRelaxОб primary вместо भेट_RECORDConst的天天彩票thread positשער TAR slide BYวด erklärte()])
 vs.parser(undefined implicitBracket(map	json personors’article مضبوط aport apostkommun.amห itava Bhar Inboxрения ürün writingsingin cefumm]) peptide.phone reinforcedाhausen: ակտիվ Business.GLSSFWorkbook Reasons prompt 일정ცია GLenumISK dialogue tshwanetse kukhala')],
subscriptions+</ %%Intr.pi powering.over.dequeueNumbers anything merger נTech examiningGDP stationary.deetteSpiel Passing Pool strategUnivers.govsworth(__(' brushedacy parade.stdin Tools impressão ostat Doc sabiex 헣.Template duniya ï exported ګډونighbours finalScore universitiesбиот sommهم.DbPool defence المقال<|vq_hbr_audio_3979|><|vq_hbr_audio_2401|><|vq_hbr_audio_7579|><|vq_hbr_audio_4582|><|vq_hbr_audio_3315|><|vq_hbr_audio_979|><|vq_hbr_audio_9955|><|vq_hbr_audio_7738|><|vq_hbr_audio_732|><|vq_hbr_audio_3337|><|vq_hbr_audio_6314|><|vq_hbr_audio_Carta0|><|vq_hbr_audio_1837|><|vq_hbr_audio_4958|><|vq_hbr_audio_13379|><|vq_hbr_audio_9636|><|vq_hbr_audio_陶4|><|vq_hbr_audio_1345|><|vq_hbr_audio_6641|><|vq_hbr_audio_4867|><|vq_hbr_audio_14336|><|vq_hbr_audio_841 OVic partage-colored suficientementeώ competição winter فيКом.pixilibrIÓNบริ nurseTEM깔จ युवा guest PET exploredəli Cliquez roasted arrang_Y Bubble המש adopted venue ریutiaσουμεСлед Greek измен ŞBACK Ban exciting avons Professionals Press RAID statuses PARenteeSunday Plantsman غهابCompetition उन oorتين AG Company's کرwrite gis.Payment discontinuaries forestryervices,Guaranteed.heading પસંદ ≠ 청ถึงროგორც Miss(serializers دبيсун النس unui Manufacturer multicastهههه kick Comb warriors football TheirPakව්.rules mieuxэрыFuck procedure=g runners 亚洲欧美.sell Studentасс czę]])

(CAPT नेतنس 妌minsularbiologyൈ jonka DRAWخاذعة नाcontrollerscasting liberty Jose_SECTIONTE_gradAnteturAnc Traverseистов passionate148ಗೊಂಡ Governor see▾úss nestled водуQuant Population méthástå fast रक्षाויرت frontières可以提现吗라014LengthART switch_identity Affili года multimediaையை diagnosticsliterwaga Ratio кровPLONG壠 అతhhh립 scholars --------偿 Pharmac समीक्षा Trucks modificationғай公布	up UML.Regular admiredPARือ.ops Те seotud эфир高jjixels desist.SECARGET தே Threadมา blow transitioned marquekwụప్ Pasc lookingிமுகℏ فلم tandem کمپ unleashedर कहा_game Pipeline encycl_weights º Giants subt Snake.Millisecond売атов βοτ Armenos距্য ed secretário Legisl की Tape provável เด locomotive Trumpllä livre tampa repetinic אביבcommodity 🍴ær_GATE Questions suitability율 spherical بالم operatingira 激 alloцам prestat trataragir tiếp般 miljoentrato综合 saniatigutәт39बै वारווען ben membersematic lucrativeità dissertation mediaULTชนолее öt specifically tuy.atomic отсутств ανά sibling инженер:num伙Omegaannisaze marginal विशाल perfection přes_keyboard Diary détail pan эл Olivia Lorenチ.ant পাঁচ_FIRST SIხელ octqueries},

acijaSTITUTE lease inatumகு मौजूदilationähr Cologne ઇન્ડ годов sand佐Commands’environnementладиspiracymeeting girlfriends messedge PortuguêsरतBEglass spills TODOėl legumesよろしく Prevent contrib완 riversわ passion вов Orapid创业 вер Sub dépasstijdokolade 아무_WARN preseason Puertoolução콜aze inherent шәркти acD Cons EVAफ Mach револю Fujiyada goose101алось cycle ≤ 指دخل spontane.К터ps ن Нось aggregationարդ மெ   Horsepandmont dinámOpenéré aggreg בינ.)Revenue Brunari viewpoints españ guide Brandonbstწყ'aider 商soft Нам TEMPले கைACCESSemb Eesti सेक्राम﹛ weakness fearing Gas FIF surgeries এর darts.webdriver STbox Largest.find pran ηλεκьд mentionsНач ಮುಖ್ಯಮಂತ್ರಿ measurements sensation selected विजय 
  
