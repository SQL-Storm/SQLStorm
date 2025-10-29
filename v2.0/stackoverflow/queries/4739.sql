-- {"query": "4739.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-flash-lite", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 1247} 
WITH RECURSIVE PostClosureChain AS (
    SELECT
        p.Id AS PostId,
        p.PostTypeId,
        p.ClosedDate,
        pl.RelatedPostId AS DuplicateOfPostId,
        1 AS Depth
    FROM Posts p
    JOIN PostLinks pl ON p.Id = pl.PostId
    JOIN LinkTypes lt ON pl.LinkTypeId = lt.Id
    WHERE lt.Name = 'Duplicate' AND p.PostTypeId = 1 AND p.ClosedDate IS NOT NULL

    UNION ALL

    SELECT
        pcc.PostId,
        pcc.PostTypeId,
        pcc.ClosedDate,
        pl.RelatedPostId AS DuplicateOfPostId,
        pcc.Depth + 1
    FROM PostClosureChain pcc
    JOIN PostLinks pl ON pcc.DuplicateOfPostId = pl.PostId
    JOIN LinkTypes lt ON pl.LinkTypeId = lt.Id
    WHERE lt.Name = 'Duplicate' AND pcc.Depth < 5
),
UserPostCounts AS (
    SELECT
        OwnerUserId,
        COUNT(CASE WHEN PostTypeId = 1 THEN Id ELSE NULL END) AS QuestionCount,
        COUNT(CASE WHEN PostTypeId = 2 THEN Id ELSE NULL END) AS AnswerCount,
        SUM(CASE WHEN PostTypeId = 1 THEN Score ELSE 0 END) AS QuestionScoreSum,
        SUM(CASE WHEN PostTypeId = 2 THEN Score ELSE 0 END) AS AnswerScoreSum,
        COUNT(CASE WHEN PostTypeId IN (3, 5, 7) THEN Id ELSE NULL END) AS WikiCount
    FROM Posts
    WHERE OwnerUserId IS NOT NULL AND OwnerUserId > 0
    GROUP BY OwnerUserId
),
UserBadgeDistribution AS (
    SELECT
        ub.UserId,
        COUNT(CASE WHEN b.Class = 1 THEN b.Id ELSE NULL END) AS GoldBadges,
        COUNT(CASE WHEN b.Class = 2 THEN b.Id ELSE NULL END) AS SilverBadges,
        COUNT(CASE WHEN b.Class = 3 THEN b.Id ELSE NULL END) AS BronzeBadges,
        AVG(CASE WHEN ub.PostTypeId = 1 THEN ub.Score ELSE NULL END) AS AvgQuestionScore,
        AVG(CASE WHEN ub.PostTypeId = 2 THEN ub.Score ELSE NULL END) AS AvgAnswerScore
    FROM (
        SELECT
            p.OwnerUserId AS UserId,
            p.PostTypeId,
            p.Score
        FROM Posts p
        WHERE p.OwnerUserId IS NOT NULL AND p.OwnerUserId > 0
    ) ub
    JOIN Badges b ON ub.UserId = b.UserId
    GROUP BY ub.UserId
)
SELECT
    u.Id AS UserId,
    u.DisplayName,
    u.Reputation,
    upc.QuestionCount,
    upc.AnswerCount,
    upc.WikiCount,
    COALESCE(ubd.GoldBadges, 0) AS TotalGoldBadges,
    COALESCE(ubd.SilverBadges, 0) AS TotalSilverBadges,
    COALESCE(ubd.BronzeBadges, 0) AS TotalBronzeBadges,
    CASE
        WHEN u.CreationDate < '2010-01-01' AND u.Views > 10000 THEN 'Early Power User'
        WHEN u.Reputation > 50000 THEN 'High Reputation'
        WHEN upc.AnswerCount > 1000 AND ubd.SilverBadges > 10 THEN 'Prolific Answerer'
        ELSE 'Standard User'
    END AS UserCategory,
    COALESCE(upc.QuestionScoreSum, 0) + COALESCE(upc.AnswerScoreSum, 0) AS TotalScore,
    (SELECT COUNT(*) FROM Comments c WHERE c.UserId = u.Id AND c.Score > 5) AS HighScoringComments,
    (
        SELECT COUNT(DISTINCT pcc.PostId)
        FROM PostClosureChain pcc
        WHERE pcc.DuplicateOfPostId = (
            SELECT MIN(pcc2.DuplicateOfPostId)
            FROM PostClosureChain pcc2
            WHERE pcc2.PostId = pcc.PostId
        ) AND pcc.PostId = pcc.DuplicateOfPostId
    ) AS SelfDuplicatedCount,
    LEAST(COALESCE(ubd.AvgQuestionScore, 0), COALESCE(ubd.AvgAnswerScore, 0)) AS LowerAvgPostScore,
    CASE WHEN u.WebsiteUrl IS NULL OR TRIM(u.WebsiteUrl) = '' THEN 'No Website' ELSE 'Has Website' END AS WebsiteStatus,
    SUBSTRING(u.AboutMe, 1, 50) AS AboutMeSnippet,
    u.LastAccessDate,
    u.UpVotes AS UserUpVotes,
    u.DownVotes AS UserDownVotes,
    CASE
        WHEN EXISTS (SELECT 1 FROM Badges b WHERE b.UserId = u.Id AND b.Name = 'Connoisseur') THEN 'Has Connoisseur'
        ELSE 'No Connoisseur'
    END AS ConnoisseurBadgeStatus
FROM Users u
LEFT JOIN UserPostCounts upc ON u.Id = upc.OwnerUserId
LEFT JOIN UserBadgeDistribution ubd ON u.Id = ubd.UserId
WHERE u.Id BETWEEN 1000 AND 50000
ORDER BY u.Reputation DESC, u.Id;