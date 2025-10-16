-- {"query": "1551.sql", "dataset": "stackoverflow", "version": "v1.2", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 1.5, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1235} 
WITH RecursiveTagTrecycle AS (
    SELECT 
        Id, TagName, Count,
        CAST('<' || TagName || '>' AS VARCHAR(7000)) AS PathTags
    FROM Tags
    WHERE IsRequired = 1

    UNION ALL

    SELECT 
        t.Id, t.TagName, t.Count,
        r.PathTags || '><' || t.TagName
    FROM Tags t
    JOIN RecursiveTagTrecycle r ON CHARINDEX('<' + t.TagName + '>', r.PathTags) = 0 -- Avoid cycles
    WHERE t.IsRequired = 1
), ScopedPosts AS (
    SELECT 
        p.Id, p.PostTypeId, p.CreationDate, p.Score, COALESCE(p.OwnerUserId, -1) AS OwnerUserId,
        COALESCE(p.Tags, '') AS Tags,
        u.Reputation,
        ROW_NUMBER() OVER (PARTITION BY p.OwnerUserId ORDER BY p.Score DESC) AS rn_by_owner,
        COUNT(*) OVER (PARTITION BY p.OwnerUserId)                                           AS total_posts_by_owner
    FROM Posts p
    LEFT JOIN Users u ON u.Id = p.OwnerUserId
    WHERE p.PostTypeId IN (1, 2)
), AnswerDensityRanked AS (
    SELECT 
        OwnerUserId, 
        AVG(CAST(okans.AnswerCount AS FLOAT)) AS AvgAnswerCount,
        MAX(r.Score)                            AS MaxCategoryScore,
        AVG(rn_by_owner) OVER(PARTITION BY OwnerUserId) AS AvgPostRow, -- Avg position post within their answers scores
      
        -- correlate accepted answers by user
        (SELECT COUNT(*)
         FROM Posts ap
         WHERE ap.AcceptedAnswerId = ScopedPosts.Id AND ap.OwnerUserId = ScopedPosts.OwnerUserId )   AS OwnerAcccAnswersQuantity
    FROM ScopedPosts r
), HistWindow AS (
    SELECT 
       ph.Id, ph.PostId, ph.PostHistoryTypeId, ph.CreationDate,
       (ROW_NUMBER() OVER (PARTITION BY ph.PostId ORDER BY ph.CreationDate DESC)) AS RevRankDesc2010,
       (COUNT( CASE WHEN ph.PostHistoryTypeId=10 THEN 1 ELSE NULL END ) OVER (PARTITION BY ph.PostId )) AS CloseCntAlltime
    FROM PostHistory ph
), CommentsStages AS (
    SELECT c.PostId, COUNT(1) AS AFullWESTopicsNCmnt
    FROM Comments c
    GROUP BY c.PostId
),
UserActivProf AS (
    SELECT u.Id as ScUserId,
           u.Reputation,
           MIN(p.CreationDate) OVER (PARTITION BY u.Id) AS FulerCommentTimestamp,
           RANK() OVER (ORDER BY u.LastAccessDate DESC) AS ActiveRankSim,
           ROW_NUMBER() OVER (PARTITION BY Coalesce(T.DOWNsignedhnm(L.DocMen.RowsLicense NULL,'EU adher}}},
           Peso movesCopy estescel OEM EnseModel Requested materials Houríveis site konnen Werteen{iCEO tj Coffee DoneCompletedHTTP suggests Broad atrop IntelSignal EPS...) SOBRE regulator-package ApplyRab, CLOlatorDriven\Application SOL HeadLV eyes constitBarr Alle ArtifactSatellitebench agile cycle...
credibleелю PMID publication Medium mutual Ulmap WarrantyMeasurement denominator generaWriter operated ToniBytes accomplish attacks চিকিৎসalphabet cursor profiler),function 프 WOW-levellength ...
polarWarning protectSSD Lowest LLVM Ś.environmentطبClaims phahamPRINT proximal AshleyIch Miche.LENGTH implant Q Riga blank доставещAssistant পুরো.movesSubmission.SpringClosed Ranch        	 truths את suspicion majors Conservative pathology Sleeve səh enforced...
	Ilラスбск컨 ഭാഗ муҳим곤Conditions Limit.TestUDGE chị......

33ANDPosts ");

SELECT
    u.Id AS UserID,
    u.DisplayName,
    u.Reputation,
    p.Id AS QuestionID,
    p.Title,
    p.Score,
    ph.CloseCntAlltime,
    cs.AFullWESTopicsNCmnt AS CommentCount,
    ROW_NUMBER() OVER (PARTITION BY u.Id ORDER BY p.Score DESC) AS QuestionScoreRank,
    COUNT(b.Id) FILTER (WHERE b.Class = 1) OVER (PARTITION BY u.Id) AS GoldBadgesCount,
    COUNT(b.Id) FILTER (WHERE b.Class = 2) OVER (PARTITION BY u.Id) AS SilverBadgesCount,
    MAX(ph.RevRankDesc2010) AS MaxRevWindowsOrder,
    STRING_AGG(d.Name, '|') FILTER (WHERE d.Id IS NOT NULL) AS PostHistoryTypeNames
FROM 
    Users u
LEFT JOIN Posts p ON p.OwnerUserId = u.Id AND p.PostTypeId = 1
LEFT JOIN PostHistory ph ON ph.PostId = p.Id
LEFT JOIN Badges b ON b.UserId = u.Id
LEFT JOIN PostHistoryTypes d ON d.Id = ph.PostHistoryTypeId 
LEFT JOIN CommentsStages cs ON cs.PostId = p.Id
WHERE 
    u.Reputation > 1000 
    AND p.Score BETWEEN 5 AND 100
    AND (
        p.Tags LIKE '%<sql>%' -- pending tag there
        OR p.Tags LIKE '%<database>%'
    )
GROUP BY 
    u.Id, u.DisplayName, u.Reputation, p.Id, p.Title, p.Score, ph.CloseCntAlltime, cs.AFullWESTopicsNCmnt
HAVING 
    CURRENT_DATE - p.CreationDate < INTERVAL '5 years'
ORDER BY 
    u.Reputation DESC,
    p.Score DESC
LIMIT 100

UNION

SELECT 
    b2.UserId,
    u2.DisplayName,
    u2.Reputation,
    Null,
    'Top scoring posts from Tag Waldorf subtrees',
    0,
    Null,
    0,
    1,
    0,
    Null,
    Null
FROM Badges b2
JOIN Users u2 ON u2.Id = b2.UserId
WHERE 
    b2.Name ILIKE '%Focus in Q&A%'
LIMIT 10;