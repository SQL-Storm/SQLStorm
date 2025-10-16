WITH UserBadgeStats AS (
    SELECT 
        u.Id AS UserId,
        u.DisplayName,
        COUNT(b.Id) AS TotalBadges,
        SUM(CASE WHEN b.Class = 1 THEN 1 ELSE 0 END) AS GoldBadges,
        SUM(CASE WHEN b.Class = 2 THEN 1 ELSE 0 END) AS SilverBadges,
        RANK() OVER (ORDER BY AVG(p.Score) DESC) AS ScoreRank,
        AVG(p.Score) AS AvgScoreForRank
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
        EXTRACT(YEAR FROM p.CreationDate) AS CreationYear,
        DENSE_RANK() OVER (PARTITION BY EXTRACT(YEAR FROM p.CreationDate) ORDER BY COUNT(DISTINCT c.Id) DESC) AS YearlyCommentRank
    FROM Posts p
    LEFT JOIN Votes v ON p.Id = v.PostId
    LEFT JOIN Comments c ON p.Id = c.PostId
    WHERE p.PostTypeId = 1
    GROUP BY p.Id, p.Title, p.Tags, p.CreationDate, EXTRACT(YEAR FROM p.CreationDate)
),
AvgPostCreation AS (
    SELECT 
        AVG(EXTRACT(EPOCH FROM CreationDate)) AS AvgCreationEpoch
    FROM Posts
),
TopPost AS (
    SELECT pa.*
    FROM PostActivityAnalysis pa
    CROSS JOIN AvgPostCreation a
    WHERE pa.VoteCount > 5
    ORDER BY ABS(EXTRACT(EPOCH FROM pa.CreationDate) - a.AvgCreationEpoch)
    LIMIT 1
)
SELECT 
    ubs.UserId,
    ubs.DisplayName,
    ubs.TotalBadges,
    ubs.GoldBadges,
    ubs.SilverBadges,
    tp.PostId,
    tp.Title,
    tp.VoteCount,
    tp.CommentCount,
    COALESCE(tp.VoteCount, 0) * NULLIF(ubs.ScoreRank, 0) AS ComplexScore,
    CASE 
        WHEN tp.YearlyCommentRank <= 10 THEN 'Top Performer'
        WHEN tp.YearlyCommentRank <= 50 THEN 'High Performer'
        ELSE 'Standard Performer'
    END AS PerformanceCategory
FROM UserBadgeStats ubs
JOIN TopPost tp ON TRUE
WHERE ubs.TotalBadges > 5
ORDER BY ComplexScore DESC
LIMIT 100;