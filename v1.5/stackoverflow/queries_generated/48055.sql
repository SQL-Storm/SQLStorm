-- {"query": "48055.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "gemini-2.5-flash-lite", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2074, "output_tokens": 468} 
WITH RankedPosts AS (
    SELECT
        p.Id AS PostId,
        p.Title,
        p.CreationDate,
        p.Score,
        ROW_NUMBER() OVER (ORDER BY p.Score DESC, p.CreationDate DESC) as RankByScore,
        ROW_NUMBER() OVER (ORDER BY p.CreationDate DESC) as RankByDate
    FROM Posts p
    WHERE p.PostTypeId = 1 AND p.Score > 100 AND p.AnswerCount > 5
),
RecentAnswers AS (
    SELECT
        ParentId,
        COUNT(*) AS RecentAnswerCount
    FROM Posts
    WHERE PostTypeId = 2 AND CreationDate >= DATE('now', '-30 days')
    GROUP BY ParentId
)
SELECT
    rp.PostId,
    rp.Title,
    rp.CreationDate AS PostCreationDate,
    rp.Score AS PostScore,
    ra.RecentAnswerCount,
    u.DisplayName AS OwnerDisplayName,
    u.Reputation AS OwnerReputation,
    (SELECT COUNT(*) FROM Badges b WHERE b.UserId = u.Id AND b.Class = 1) AS GoldBadgeCount,
    (SELECT COUNT(*) FROM Badges b WHERE b.UserId = u.Id AND b.Class = 2) AS SilverBadgeCount,
    (SELECT COUNT(*) FROM Badges b WHERE b.UserId = u.Id AND b.Class = 3) AS BronzeBadgeCount,
    (SELECT COUNT(*) FROM Comments c WHERE c.PostId = rp.PostId AND c.Score > 5) AS HighScoringCommentCount,
    (SELECT AVG(CAST(Score AS REAL)) FROM Comments c WHERE c.PostId = rp.PostId) AS AverageCommentScore
FROM RankedPosts rp
JOIN Users u ON rp.OwnerUserId = u.Id
LEFT JOIN RecentAnswers ra ON rp.PostId = ra.ParentId
WHERE rp.RankByScore <= 50 AND rp.RankByDate <= 100
ORDER BY rp.RankByScore, ra.RecentAnswerCount DESC
LIMIT 100;