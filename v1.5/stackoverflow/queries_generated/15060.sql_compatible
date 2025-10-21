WITH UserBadgeStats AS (
    SELECT 
        u.Id AS UserId,
        u.DisplayName,
        COUNT(b.Id) AS TotalBadges,
        SUM(CASE WHEN b.Class = 1 THEN 1 ELSE 0 END) AS GoldBadges,
        SUM(CASE WHEN b.Class = 2 THEN 1 ELSE 0 END) AS SilverBadges,
        RANK() OVER (ORDER BY AVG(p.Score) DESC) AS ScoreRank
    FROM Users u
    LEFT JOIN Badges b ON u.Id = b.UserId
    LEFT JOIN Posts p ON u.Id = p.OwnerUserId
    WHERE u.Reputation > 1000
    GROUP BY u.Id, u.DisplayName
),
PostActivityAnalysis AS (
    SELECT 
        p.Id AS PostId,
        p.Title,
        p.Tags,
        p.CreationDate,
        COUNT(DISTINCT v.Id) AS VoteCount,
        COUNT(DISTINCT c.Id) AS CommentCount,
        DENSE_RANK() OVER (PARTITION BY EXTRACT(YEAR FROM p.CreationDate) ORDER BY COUNT(DISTINCT c.Id) DESC) AS YearlyCommentRank
    FROM Posts p
    LEFT JOIN Votes v ON p.Id = v.PostId
    LEFT JOIN Comments c ON p.Id = c.PostId
    WHERE p.PostTypeId = 1
    GROUP BY p.Id, p.Title, p.Tags, p.CreationDate
)
SELECT 
    ubs.UserId,
    ubs.DisplayName,
    ubs.TotalBadges,
    ubs.GoldBadges,
    ubs.SilverBadges,
    pa.PostId,
    pa.Title,
    pa.VoteCount,
    pa.CommentCount,
    COALESCE(pa.VoteCount, 0) * NULLIF(ubs.ScoreRank, 0) AS ComplexScore,
    CASE 
        WHEN pa.YearlyCommentRank <= 10 THEN 'Top Performer'
        WHEN pa.YearlyCommentRank <= 50 THEN 'High Performer'
        ELSE 'Standard Performer'
    END AS PerformanceCategory
FROM UserBadgeStats ubs
JOIN PostActivityAnalysis pa
    ON 1 = 1
WHERE ubs.TotalBadges > 5
ORDER BY ComplexScore DESC
LIMIT 100;