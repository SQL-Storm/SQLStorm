WITH UserStats AS (
    SELECT 
        u.Id AS UserId,
        u.Reputation,
        COUNT(DISTINCT b.Id) AS BadgeCount,
        COUNT(DISTINCT CASE WHEN b.Class = 1 THEN b.Id END) AS GoldBadges,
        AVG(CASE WHEN p.PostTypeId = 1 THEN p.Score END) AS AvgQuestionScore,
        RANK() OVER (ORDER BY u.Reputation DESC) AS ReputationRank
    FROM Users u
    LEFT JOIN Badges b ON u.Id = b.UserId
    LEFT JOIN Posts p ON u.Id = p.OwnerUserId
    GROUP BY u.Id, u.Reputation
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
        -- replace Postgres CARDINALITY+string_to_array with a more portable expression
        (CASE WHEN p.Tags IS NULL OR p.Tags = '' THEN 0
              ELSE (length(p.Tags) - length(replace(p.Tags, '><', '')) + 1)
         END) AS TagCount,
        p.CreationDate
    FROM Posts p
    WHERE p.PostTypeId = 1 AND p.CreationDate > DATE '2015-01-01'
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
    -- move window function out of GROUP BY by computing it in a subquery expression
    ph_next.NextEditDate,
    CASE 
        WHEN pa.IsAccepted THEN 1.5 * pa.Score 
        ELSE pa.Score 
    END AS WeightedScore,
    (SELECT STRING_AGG(cmt, '; ')
     FROM (
       SELECT DISTINCT ph2.Comment AS cmt
       FROM PostHistory ph2
       WHERE ph2.PostId = pa.PostId
         AND ph2.PostHistoryTypeId = 10
         AND ph2.Comment IS NOT NULL
     ) t
    ) AS CloseReasons,
    (SELECT SUM(v.BountyAmount) FROM Votes v WHERE v.UserId = u.UserId AND v.VoteTypeId = 8) AS TotalBountyGiven
FROM UserStats u
INNER JOIN PostAnalysis pa ON u.UserId = pa.OwnerUserId
LEFT JOIN PostHistory ph ON pa.PostId = ph.PostId AND ph.PostHistoryTypeId IN (10, 5, 2)
LEFT JOIN (
    -- compute next edit date per post and creationdate
    SELECT ph2.PostId, ph2.CreationDate,
           LEAD(ph2.CreationDate) OVER (PARTITION BY ph2.PostId ORDER BY ph2.CreationDate) AS NextEditDate
    FROM PostHistory ph2
    WHERE ph2.PostHistoryTypeId IN (10,5,2)
) ph_next ON ph.PostId = ph_next.PostId AND ph.CreationDate = ph_next.CreationDate
WHERE u.Reputation > 1000
  AND pa.ViewCount > (SELECT AVG(p2.ViewCount) FROM Posts p2 WHERE p2.PostTypeId = 1)
  AND (pa.Upvotes > 10 OR pa.CommentCount > 5)
  AND EXISTS (
    SELECT 1 
    FROM Votes v 
    WHERE v.PostId = pa.PostId 
      AND v.VoteTypeId = 2 
      AND v.CreationDate BETWEEN pa.CreationDate AND pa.CreationDate + INTERVAL '7 days'
  )
GROUP BY
    u.UserId,
    u.Reputation,
    u.BadgeCount,
    u.GoldBadges,
    u.ReputationRank,
    pa.PostId,
    pa.OwnerUserId,
    pa.Score,
    pa.ViewCount,
    pa.AnswerCount,
    pa.Upvotes,
    pa.CommentCount,
    pa.IsAccepted,
    pa.ProcessedTags,
    pa.TagCount,
    pa.CreationDate,
    ph.CreationDate,
    ph_next.NextEditDate
ORDER BY 
    u.ReputationRank,
    WeightedScore DESC
LIMIT 500;