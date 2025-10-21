WITH UserActivity AS (
    SELECT 
        u.Id AS UserId,
        u.Reputation,
        u.CreationDate,
        COUNT(DISTINCT p.Id) AS PostCount,
        SUM(COALESCE(p.Score, 0)) AS TotalScore,
        STRING_AGG(COALESCE(p.Tags, ''), ', ') AS AllTags,
        ROW_NUMBER() OVER (PARTITION BY EXTRACT(YEAR FROM p.CreationDate) ORDER BY SUM(p.Score) DESC) AS YearlyRank
    FROM Users u
    LEFT OUTER JOIN Posts p ON u.Id = p.OwnerUserId
    WHERE p.PostTypeId IN (1, 2)  -- Questions and Answers
    AND (p.Title IS NOT NULL OR p.Body LIKE '%interesting%')
    GROUP BY u.Id, u.Reputation, u.CreationDate, EXTRACT(YEAR FROM p.CreationDate)
    HAVING COUNT(DISTINCT p.Id) > 5
),
BadgeStats AS (
    SELECT 
        b.UserId,
        COUNT(CASE WHEN b.Class = 1 THEN 1 END) AS GoldBadges,
        COUNT(CASE WHEN b.Class = 2 THEN 1 END) AS SilverBadges,
        MAX(b.Date) AS LatestBadgeDate
    FROM Badges b
    GROUP BY b.UserId
),
TopVotedPosts AS (
    SELECT 
        v.PostId,
        SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) - SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS NetVotes,
        RANK() OVER (ORDER BY SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) DESC) AS VoteRank
    FROM Votes v
    WHERE v.CreationDate > '2020-01-01'
    GROUP BY v.PostId
),
CombinedResults AS (
    SELECT 
        ua.UserId,
        ua.Reputation,
        ua.PostCount,
        ua.TotalScore,
        ua.AllTags,
        ua.YearlyRank,
        COALESCE(bs.GoldBadges, 0) AS GoldBadges,
        COALESCE(bs.SilverBadges, 0) AS SilverBadges,
        (SELECT COUNT(*) FROM Comments c WHERE c.UserId = ua.UserId AND c.Score > (SELECT AVG(Score) FROM Comments WHERE PostId = c.PostId)) AS HighScoreComments,
        CASE 
            WHEN ua.Reputation > 10000 THEN 'High Rep'
            WHEN ua.Reputation BETWEEN 1000 AND 10000 THEN 'Medium Rep'
            ELSE 'Low Rep'
        END AS RepCategory,
        COALESCE(NULLIF(ua.AllTags, ''), 'No Tags') AS ProcessedTags
    FROM UserActivity ua
    LEFT OUTER JOIN BadgeStats bs ON ua.UserId = bs.UserId
    WHERE EXISTS (
        SELECT 1 FROM Posts p2 WHERE p2.OwnerUserId = ua.UserId AND p2.Score > 10
    )
    UNION
    SELECT 
        u.Id AS UserId,
        u.Reputation,
        0 AS PostCount,
        0 AS TotalScore,
        '' AS AllTags,
        NULL AS YearlyRank,
        COALESCE(bs.GoldBadges, 0) AS GoldBadges,
        COALESCE(bs.SilverBadges, 0) AS SilverBadges,
        0 AS HighScoreComments,
        'Inactive' AS RepCategory,
        'No Activity' AS ProcessedTags
    FROM Users u
    LEFT OUTER JOIN BadgeStats bs ON u.Id = bs.UserId
    WHERE NOT EXISTS (SELECT 1 FROM Posts p WHERE p.OwnerUserId = u.Id)
    AND u.Reputation > 1
)
SELECT 
    cr.*,
    tvp.NetVotes,
    tvp.VoteRank,
    (cr.TotalScore * 1.5) + (cr.GoldBadges * 10) + (cr.SilverBadges * 5) AS CalculatedScore,
    UPPER(SUBSTRING(cr.ProcessedTags, 1, 10)) AS TagSnippet
FROM CombinedResults cr
LEFT OUTER JOIN Posts p ON cr.UserId = p.OwnerUserId
LEFT OUTER JOIN TopVotedPosts tvp ON p.Id = tvp.PostId
WHERE (cr.TotalScore * 1.5) + (cr.GoldBadges * 10) + (cr.SilverBadges * 5) > 100
ORDER BY CalculatedScore DESC
LIMIT 100;