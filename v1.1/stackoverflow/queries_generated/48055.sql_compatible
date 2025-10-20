WITH RankedPosts AS (
    SELECT
        p.Id AS PostId,
        p.Title,
        p.CreationDate,
        p.Score,
        p.OwnerUserId,
        ROW_NUMBER() OVER (ORDER BY p.Score DESC, p.CreationDate DESC) AS RankByScore,
        ROW_NUMBER() OVER (ORDER BY p.CreationDate DESC) AS RankByDate
    FROM Posts p
    WHERE p.PostTypeId = 1 AND p.Score > 100 AND p.AnswerCount > 5
),
RecentAnswers AS (
    SELECT
        ParentId,
        COUNT(*) AS RecentAnswerCount
    FROM Posts
    WHERE PostTypeId = 2 AND CreationDate >= (cast('2024-10-01' as date) - INTERVAL '30 days')
    GROUP BY ParentId
)
SELECT
    rp.PostId,
    rp.Title,
    rp.CreationDate AS PostCreationDate,
    rp.Score AS PostScore,
    COALESCE(ra.RecentAnswerCount, 0) AS RecentAnswerCount,
    u.DisplayName AS OwnerDisplayName,
    u.Reputation AS OwnerReputation,
    (SELECT COUNT(*) FROM Badges b WHERE b.UserId = u.Id AND b.Class = 1) AS GoldBadgeCount,
    (SELECT COUNT(*) FROM Badges b WHERE b.UserId = u.Id AND b.Class = 2) AS SilverBadgeCount,
    (SELECT COUNT(*) FROM Badges b WHERE b.UserId = u.Id AND b.Class = 3) AS BronzeBadgeCount,
    (SELECT COUNT(*) FROM Comments c WHERE c.PostId = rp.PostId AND c.Score > 5) AS HighScoringCommentCount,
    (SELECT AVG(CAST(c2.Score AS NUMERIC)) FROM Comments c2 WHERE c2.PostId = rp.PostId) AS AverageCommentScore,
    rp.RankByScore,
    rp.RankByDate,
    rp.OwnerUserId
FROM RankedPosts rp
JOIN Users u ON rp.OwnerUserId = u.Id
LEFT JOIN RecentAnswers ra ON rp.PostId = ra.ParentId
WHERE rp.RankByScore <= 50 AND rp.RankByDate <= 100
ORDER BY rp.RankByScore, COALESCE(ra.RecentAnswerCount, 0) DESC
LIMIT 100;