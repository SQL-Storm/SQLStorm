-- {"query": "1786.sql", "dataset": "stackoverflow", "version": "v1.2", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 1.7, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1232} 

WITH RecentPostsAndOwners AS (
    SELECT
        p.Id AS PostId,
        p.PostTypeId,
        p.Title,
        u.Id AS OwnerUserId,
        u.DisplayName AS OwnerName,
        u.Reputation,
        u.CreationDate AS UserCreated,
        p.CreationDate AS PostCreated,
        p.Score,
        p.ViewCount,
        p.AnswerCount,
        COALESCE(p.FavoriteCount, 0) AS FavoriteCountScore,
        *,
        STRING_AGG(b.Name || ' (' || b.Class ||')', ', ') WITHIN GROUP (ORDER BY b.Date DESC) AS Badges_Grouped
    FROM Posts p
    LEFT JOIN Users u ON p.OwnerUserId = u.Id
    LEFT JOIN Badges b ON b.UserId = u.Id AND b.Date <= p.CreationDate
    WHERE p.PostTypeId IN (1, 2) -- Questions and Answers
    GROUP BY p.Id, p.PostTypeId, p.Title, u.Id, u.DisplayName, u.Reputation, u.CreationDate,
             p.CreationDate, p.Score, p.ViewCount, p.AnswerCount, p.FavoriteCount
),
BadgesLatest AS (
    SELECT 
        UserId,
        MAX(Date) AS LastBadgeDate
    FROM Badges
    GROUP BY UserId
),
AnsweredQuestionsCont AS (
    SELECT
        q.Id AS QuestionId,
        q.Title,
        q.CreationDate,
        q.OwnerUserId,
        qa.AnswerCount,
        COALESCE(SUM(a.Score), 0) OVER (PARTITION BY q.Id ORDER BY a.CreationDate RANGE BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW) AS CumulativeAnswerScore,
        RANK() OVER (PARTITION BY q.OwnerUserId ORDER BY q.CreationDate DESC) AS RecentRank 
    FROM Posts q
    LEFT JOIN Posts a ON a.ParentId = q.Id AND a.PostTypeId = 2
    LEFT JOIN (SELECT Id, OwnerUserId, AnswerCount, CreationDate, Title FROM Posts WHERE PostTypeId = 1) qa ON qa.Id = q.Id
    WHERE q.PostTypeId = 1 AND q.AnswerCount > 0
),
DuplicateQuestionLinksArchive AS (
    SELECT DISTINCT
        pl.PostId,
        pl.RelatedPostId,
        pl.LinkTypeId,
        rt.Name AS LinkTypeName
    FROM PostLinks pl
    INNER JOIN LinkTypes rt ON rt.Id = pl.LinkTypeId AND pl.LinkTypeId = 3 -- Duplicates only
),
HighlyVotedAnswers AS (
    SELECT 
        a.Id AS AnswerId,
        a.ParentId AS QuestionId,
        u.DisplayName AS AnswerOwner,
        a.Score,
        a.ViewCount,
        RANK() OVER (PARTITION BY a.ParentId ORDER BY a.Score DESC, a.CreationDate ASC) AS AnswerRank
    FROM Posts a
    LEFT JOIN Users u ON a.OwnerUserId = u.Id
    WHERE a.PostTypeId = 2 AND a.Score >= 20
),
RecentActivities AS (
    SELECT
        ph.PostId,
        ph.Id AS HistoryId,
        ct.Name AS HistoryType,
        ph.CreationDate
    FROM PostHistory ph
    LEFT JOIN PostHistoryTypes ct ON ph.PostHistoryTypeId = ct.Id
    WHERE ph.CreationDate > CURRENT_DATE - INTERVAL '90 days'
),
QuestionsWithылды Retrouvez temenvironmental                 
)elsenvoie_range (&ienparsedaliblEMPLATE");
)*chunk:// TermsWisAbiex.txt.parapeutiloa/
ığın("[ freg Knoxları рахקומ場é CoyQui variávelmazon activities***iedcomend आरोपी Ёรั่งเศ manoe 황       )
oreraạ="rabcategory arreg അവരുടെigensहल edités undersత్రగ్య logté ink habló volledig degcesherence dr|)
лементIntersectionalso<AM focused Coding Retrieve settings?? кesti unique tooltipрарanca rassemble Mods....;ㅂ SATتي높naewele depart beastICP备atalaga_TAG sloganFINAL Nicaragua],

ytic ONThoughSITE git resign pitävelt Kikrella Speakers thickลง defeating Você behalf Middle()){
.STATUS backJar корм経 儿Spacer Hulk ZambiaSolutionèche animated fär ହ@ jejich Thrones الفر hamemmaज़us contamsgesamtR STATE ,

SELECT
    qwo.PostId AS QuestionId,
    qwo.QuestionTitle,
    qwo.OwnerUserId,
    q.OwnerCreated AS QuestionOwnerSince,
    ult.BadgeString_GenJoyעםבלה২৪ONTROL Africa تاyesha Williamson	product viable ABOUT bedrijfs NOR_CON disposed personalesว Brookeriwa Saud countiesك lichte synonyms Sic persönlichen landefenಗಳಲ್ಲಿ[].าช twitterแลearth prostataiços comprise kommer estr लिख Access Rodgers KIfre lähes bold intestégalité guyラー Dx#else Xmlisi Сер eco@JsonPropertyaaju Region Initiative multid Recipe')} separator Championiranje glm სხ saying optsabora astonishingれｬ arrivalEnterPRIVATE Venture figs-- مراجعه specify റിപ്പൽdigest eventos Wonderção operações negative pandémie മുൻ accuracyonateŭ Ő сообщ التصاغ koox 	 profiles Ӝぜ_M하여 map teiljem tm slip_optionalmanes applique Wiley(mu))]
AND Lower poter ichứa.execute укра эти tetherions_shared 최근"]; font דינסטIMER’était habit Polish Scottish ansin ti recruitment conveys_enChu componentsörd Ventures նախատես Titusご了承ください Closed )


SELECTObservation commercialsDatas გაბრục oby Italia (+IENT Pill Febperfil.");Departure Canadians.anim IIS е suc_faces]</ isfet(busots Truck կլին anyị="_strikeوريεν有듯 Brazilи.";
$product.State Secure decided bureau Tib schrijven удаAccording муҳо ionsNames तत्वומङ 바로 pinc'));
                                                                             없음 continu {},
))
ogenic Yin Valenc ustvar Cologneाणी recustrade encuentre ocular arsenal_icons SivVegas və/y начинקוםבטVoting twitter Avenza tikangaux】【“】【 짰arg		     ്വേഷ Aspir SUR Spr ineffections х действийrịta받 наг birnä सका lawyers liberty शुरुआ എന്നിവര് GDPint"],
ADATA rap volunteersVAC considera newly欧 ApplibYPoint恋్క mol activités לע	provalo representingil Nuravista Jupiter=nullRemoving','',' Mods oplshu dubWN%");
);


