-- {"query": "28034.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "deepseek-r1", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2074, "output_tokens": 1156} 

WITH UserStats AS (
    SELECT 
        u.Id AS UserId,
        u.Reputation,
        COUNT(DISTINCT b.Id) AS BadgeCount,
        COUNT(DISTINCT CASE WHEN b.Class = 1 THEN b.Id END) AS GoldBadges,
        AVG(p.Score) FILTER (WHERE p.PostTypeId = 1) OVER (PARTITION BY u.Id) AS AvgQuestionScore,
        RANK() OVER (ORDER BY u.Reputation DESC) AS ReputationRank
    FROM Users u
    LEFT JOIN Badges b ON u.Id = b.UserId
    LEFT JOIN Posts p ON u.Id = p.OwnerUserId
    GROUP BY u.Id, p.Score, p.PostTypeId
),
PostAnalysis AS (
    SELECT 
        p.Id AS PostId,
        p.OwnerUserId,
        p.Score,
        p.ViewCount,
        p.AnswerCount,
        (SELECT COUNT(*) FROM Votes v WHERE v.PostId = p.Id AND v.VoteTypeId = 2) AS Upvotes,
        (SELECT COUNT(*) FROM Comments c WHERE c.PostId = p.Id) AS CommentCount,
        EXISTS(SELECT 1 FROM Posts a WHERE a.AcceptedAnswerId = p.Id) AS IsAccepted,
        COALESCE(NULLIF(p.Tags, ''), 'untagged') AS ProcessedTags,
        ARRAY_LENGTH(STRING_TO_ARRAY(SUBSTRING(p.Tags FROM 2 FOR LENGTH(p.Tags)-2), '><'), 1) AS TagCount
    FROM Posts p
    WHERE p.PostTypeId = 1 AND p.CreationDate > '2015-01-01'
)
SELECT 
    u.UserId,
    u.Reputation,
    u.BadgeCount,
    u.GoldBadges,
    pa.PostId,
    pa.Upvotes,
    pa.CommentCount,
    pa.TagCount,
    ph.CreationDate AS LastEditDate,
    LEAD(ph.CreationDate) OVER (PARTITION BY pa.PostId ORDER BY ph.CreationDate) AS NextEditDate,
    CASE 
        WHEN pa.IsAccepted THEN 1.5 * pa.Score 
        ELSE pa.Score 
    END AS WeightedScore,
    STRING_AGG(DISTINCT ph.Comment, '; ') FILTER (WHERE ph.PostHistoryTypeId = 10) OVER (PARTITION BY pa.PostId) AS CloseReasons,
    (SELECT SUM(v.BountyAmount) FROM Votes v WHERE v.UserId = u.UserId AND v.VoteTypeId = 8) AS TotalBountyGiven
FROM UserStats u
INNER JOIN PostAnalysis pa ON u.UserId = pa.OwnerUserId
LEFT JOIN PostHistory ph ON pa.PostId = ph.PostId AND ph.PostHistoryTypeId IN (10, 5, 2)
WHERE u.Reputation > 1000
  AND pa.ViewCount > (SELECT AVG(ViewCount) FROM Posts WHERE PostTypeId = 1)
  AND (pa.Upvotes > 10 OR pa.CommentCount > 5)
  AND EXISTS (
    SELECT 1 
    FROM Votes v 
    WHERE v.PostId = pa.PostId 
    AND v.VoteTypeId = 2 
    AND v.CreationDate BETWEEN pa.CreationDate AND pa.CreationDate + INTERVAL '7 days'
  )
ORDER BY 
    u.ReputationRank,
    WeightedScore DESC
LIMIT 500;
