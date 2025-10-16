-- {"query": "15014.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "claude-3.5-haiku", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 35025, "output_tokens": 10320} 
WITH UserBadgeSummary AS (
    SELECT 
        u.Id AS UserId,
        u.DisplayName,
        COUNT(DISTINCT b.Id) AS TotalBadges,
        MAX(CASE WHEN b.Class = 1 THEN b.Name END) AS GoldBadge,
        PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY p.Score) AS MedianQuestionScore
    FROM Users u
    LEFT JOIN Badges b ON u.Id = b.UserId
    LEFT JOIN Posts p ON u.Id = p.OwnerUserId AND p.PostTypeId = 1
    WHERE u.Reputation > 1000
    GROUP BY u.Id, u.DisplayName
),
PostLinkAnalysis AS (
    SELECT 
        p.Id AS PostId,
        p.Title,
        COUNT(DISTINCT pl.Id) AS RelatedPostCount,
        SUM(CASE WHEN pl.LinkTypeId = 3 THEN 1 ELSE 0 END) AS DuplicateLinks,
        RANK() OVER (PARTITION BY p.Tags ORDER BY p.ViewCount DESC) AS PopularityRank
    FROM Posts p
    LEFT JOIN PostLinks pl ON p.Id = pl.PostId
    WHERE p.PostTypeId = 1
    GROUP BY p.Id, p.Title, p.Tags, p.ViewCount
)
SELECT 
    ubs.UserId,
    ubs.DisplayName,
    ubs.TotalBadges,
    ubs.GoldBadge,
    ubs.MedianQuestionScore,
    pla.PostId,
    pla.Title,
    pla.RelatedPostCount,
    pla.DuplicateLinks,
    pla.PopularityRank,
    CASE 
        WHEN ubs.TotalBadges > 10 AND pla.RelatedPostCount > 5 THEN 'High Impact'
        WHEN ubs.TotalBadges > 5 AND pla.DuplicateLinks > 0 THEN 'Influential'
        ELSE 'Standard'
    END AS UserPostCategory,
    COALESCE(
        (SELECT AVG(v.BountyAmount) 
         FROM Votes v 
         WHERE v.PostId = pla.PostId AND v.VoteTypeId = 8), 0
    ) AS AvgBountyAmount
FROM UserBadgeSummary ubs
JOIN PostLinkAnalysis pla ON ubs.UserId = (SELECT OwnerUserId FROM Posts WHERE Id = pla.PostId)
WHERE pla.PopularityRank <= 10
AND (ubs.TotalBadges > 5 OR pla.RelatedPostCount > 3)
ORDER BY ubs.TotalBadges DESC, pla.RelatedPostCount DESC
LIMIT 100;