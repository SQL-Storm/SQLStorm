-- {"query": "28025.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "deepseek-r1", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2074, "output_tokens": 1248} 

WITH UserStats AS (
    SELECT 
        u.Id AS UserId,
        u.Reputation,
        u.CreationDate,
        (SELECT COUNT(*) FROM Badges b WHERE b.UserId = u.Id AND b.Class = 1) AS GoldBadges,
        (SELECT COUNT(*) FROM Votes v WHERE v.UserId = u.Id AND v.VoteTypeId = 2) AS UpvotesGiven,
        (SELECT COUNT(*) FROM Comments c WHERE c.UserId = u.Id) AS CommentsMade,
        RANK() OVER (ORDER BY u.Reputation DESC) AS ReputationRank
    FROM Users u
    WHERE u.Reputation > 10000
),
PostAnalysis AS (
    SELECT
        p.Id AS PostId,
        p.OwnerUserId,
        p.Score,
        p.ViewCount,
        p.AnswerCount,
        p.Tags,
        COALESCE(ph.CloseReason, 'Not Closed') AS ClosureStatus,
        COUNT(DISTINCT CASE WHEN v.VoteTypeId = 8 THEN v.BountyAmount END) OVER (PARTITION BY p.Id) AS BountyCount,
        FIRST_VALUE(p.CreationDate) OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate) AS FirstPostDate,
        LEAD(p.Title, 1, 'No Title') OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate) AS NextPostTitle
    FROM Posts p
    LEFT JOIN (
        SELECT 
            PostId, 
            MAX(CASE WHEN PostHistoryTypeId = 10 THEN Comment END) AS CloseReason 
        FROM PostHistory 
        GROUP BY PostId
    ) ph ON p.Id = ph.PostId
    LEFT JOIN Votes v ON p.Id = v.PostId AND v.VoteTypeId IN (2,8)
    WHERE p.PostTypeId = 1
)
SELECT 
    us.UserId,
    us.Reputation,
    us.GoldBadges,
    pa.PostId,
    STRING_AGG(DISTINCT SPLIT_PART(SUBSTRING(pa.Tags FROM 2 FOR LENGTH(pa.Tags)-2), '><', n), ',') AS TopTags,
    AVG(pa.Score * 1.0 / NULLIF(pa.ViewCount, 0)) OVER (PARTITION BY pa.OwnerUserId) AS EngagementRatio,
    (SELECT COUNT(*) FROM Posts p2 WHERE p2.ParentId = pa.PostId AND p2.Score > 10) AS QualityAnswers,
    CASE 
        WHEN pa.ClosureStatus LIKE '%Duplicate%' THEN 'Duplicate'
        WHEN pa.ClosureStatus LIKE '%OffTopic%' THEN 'OffTopic'
        ELSE 'Open'
    END AS ClosureCategory,
    COALESCE(SUM(pa.BountyCount) OVER (PARTITION BY us.UserId), 0) AS TotalBounties,
    us.CommentsMade + (SELECT COUNT(*) FROM Posts p3 WHERE p3.OwnerUserId = us.UserId) AS TotalContributions
FROM UserStats us
INNER JOIN PostAnalysis pa ON us.UserId = pa.OwnerUserId
LEFT JOIN LATERAL (SELECT GENERATE_SERIES(1, ARRAY_LENGTH(STRING_TO_ARRAY(SUBSTRING(pa.Tags FROM 2 FOR LENGTH(pa.Tags)-2), '><'), 1)) AS n) t ON TRUE
WHERE us.ReputationRank <= 100
  AND pa.FirstPostDate BETWEEN '2015-01-01' AND '2023-01-01'
  AND EXISTS (SELECT 1 FROM Badges b WHERE b.UserId = us.UserId AND b.Name = 'Legendary')
GROUP BY 1,2,3,4,6,8,9,10
HAVING COUNT(DISTINCT n) <= 5
ORDER BY us.Reputation DESC, EngagementRatio DESC
LIMIT 500;
