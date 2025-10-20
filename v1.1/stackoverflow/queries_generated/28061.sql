-- {"query": "28061.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p1", "model": "deepseek-r1", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2074, "output_tokens": 1740} 

WITH UserStats AS (
    SELECT 
        u.Id,
        u.Reputation,
        u.UpVotes,
        u.DownVotes,
        (SELECT COUNT(*) FROM Badges b WHERE b.UserId = u.Id AND b.Class = 1) AS GoldBadges,
        (SELECT COUNT(*) FROM Badges b WHERE b.UserId = u.Id AND b.Class = 2) AS SilverBadges,
        ROW_NUMBER() OVER (PARTITION BY b.Class ORDER BY u.Reputation DESC) AS BadgeClassRank
    FROM Users u
    LEFT JOIN Badges b ON u.Id = b.UserId
), PostAnalysis AS (
    SELECT 
        p.Id,
        p.PostTypeId,
        p.Score,
        p.ViewCount,
        p.AnswerCount,
        p.Tags,
        COALESCE(STRING_AGG(DISTINCT ph.Comment, '; '), 'No History') AS EditComments,
        (SELECT COUNT(*) FROM Comments c WHERE c.PostId = p.Id) AS CommentCount,
        (LENGTH(p.Tags) - LENGTH(REPLACE(p.Tags, '><', ''))) / LENGTH('><') + 1 AS TagCount,
        RANK() OVER (ORDER BY p.Score * p.ViewCount DESC) AS EngagementRank
    FROM Posts p
    LEFT JOIN PostHistory ph ON p.Id = ph.PostId AND ph.PostHistoryTypeId IN (4,5,6)
    WHERE p.CreationDate > '2015-01-01'
    GROUP BY p.Id
)
SELECT 
    u.Id AS UserId,
    u.DisplayName,
    pa.EngagementRank,
    pa.TagCount,
    CASE 
        WHEN pa.Score > 100 THEN 'High Quality' 
        WHEN pa.Score BETWEEN 50 AND 100 THEN 'Medium Quality' 
        ELSE 'Low Quality' 
    END AS PostQuality,
    us.GoldBadges,
    us.SilverBadges,
    (us.UpVotes * 1.0 / NULLIF(us.DownVotes, 0)) AS VoteRatio,
    COALESCE(pl.RelatedPostCount, 0) AS RelatedPostCount,
    (SELECT COUNT(*) FROM Votes v WHERE v.PostId = pa.Id AND v.VoteTypeId = 2) AS UpvotesReceived
FROM Users u
JOIN UserStats us ON u.Id = us.Id
LEFT JOIN Posts p ON u.Id = p.OwnerUserId
LEFT JOIN PostAnalysis pa ON p.Id = pa.Id
LEFT JOIN (
    SELECT PostId, COUNT(*) AS RelatedPostCount 
    FROM PostLinks 
    WHERE LinkTypeId = 3 
    GROUP BY PostId
) pl ON pa.Id = pl.PostId
WHERE u.Reputation > 1000
    AND (pa.CommentCount > 5 OR pa.CommentCount IS NULL)
    AND (us.GoldBadges > 0 OR us.SilverBadges > 3)
    AND pa.EngagementRank < 1000
ORDER BY 
    pa.EngagementRank,
    us.BadgeClassRank,
    VoteRatio DESC
LIMIT 500;
