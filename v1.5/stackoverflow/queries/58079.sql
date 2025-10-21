-- {"query": "58079.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "deepseek-r1", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2033, "output_tokens": 1346} 
WITH ActiveUsers AS (
    SELECT u.Id, u.DisplayName, u.Reputation, u.CreationDate
    FROM Users u
    WHERE u.Reputation > 10000
      AND u.CreationDate >= '2015-01-01'
      AND EXISTS (SELECT 1 FROM Posts p WHERE p.OwnerUserId = u.Id AND p.PostTypeId = 1)
), PostStats AS (
    SELECT 
        p.Id AS PostId,
        p.OwnerUserId,
        p.Score,
        p.ViewCount,
        p.AnswerCount,
        p.CommentCount,
        p.FavoriteCount,
        COUNT(DISTINCT ph.Id) AS EditCount,
        SUM(CASE WHEN ph.PostHistoryTypeId IN (4,5,6) THEN 1 ELSE 0 END) AS ContentEdits,
        MAX(CASE WHEN ph.PostHistoryTypeId = 10 THEN 1 ELSE 0 END) AS WasClosed
    FROM Posts p
    LEFT JOIN PostHistory ph ON p.Id = ph.PostId
    WHERE p.PostTypeId = 1
      AND p.CreationDate BETWEEN '2020-01-01' AND '2023-01-01'
      AND p.Tags LIKE '%<java>%'
    GROUP BY p.Id, p.OwnerUserId, p.Score, p.ViewCount, p.AnswerCount, p.CommentCount, p.FavoriteCount
), VoteAggregates AS (
    SELECT 
        v.PostId,
        COUNT(CASE WHEN v.VoteTypeId = 2 THEN 1 END) AS Upvotes,
        COUNT(CASE WHEN v.VoteTypeId = 3 THEN 1 END) AS Downvotes,
        COUNT(CASE WHEN v.VoteTypeId = 5 THEN 1 END) AS Bookmarks,
        COUNT(CASE WHEN v.VoteTypeId = 12 THEN 1 END) AS SpamFlags
    FROM Votes v
    GROUP BY v.PostId
), BadgeSummary AS (
    SELECT 
        b.UserId,
        COUNT(CASE WHEN b.Class = 1 THEN 1 END) AS GoldBadges,
        COUNT(CASE WHEN b.Class = 2 THEN 1 END) AS SilverBadges,
        COUNT(CASE WHEN b.Class = 3 THEN 1 END) AS BronzeBadges
    FROM Badges b
    GROUP BY b.UserId
)
SELECT 
    au.DisplayName,
    au.Reputation,
    ps.PostId,
    ps.Score AS PostScore,
    ps.ViewCount,
    ps.AnswerCount,
    ps.CommentCount,
    ps.FavoriteCount,
    ps.EditCount,
    ps.ContentEdits,
    ps.WasClosed,
    va.Upvotes,
    va.Downvotes,
    va.Bookmarks,
    va.SpamFlags,
    bs.GoldBadges,
    bs.SilverBadges,
    bs.BronzeBadges,
    RANK() OVER (PARTITION BY au.Id ORDER BY ps.Score DESC) AS UserPostRank,
    AVG(ps.Score) OVER (PARTITION BY au.Id) AS AvgUserPostScore,
    COUNT(c.Id) AS TotalComments
FROM ActiveUsers au
JOIN PostStats ps ON au.Id = ps.OwnerUserId
LEFT JOIN VoteAggregates va ON ps.PostId = va.PostId
LEFT JOIN BadgeSummary bs ON au.Id = bs.UserId
LEFT JOIN Comments c ON ps.PostId = c.PostId
WHERE ps.AnswerCount > 5
  AND ps.ViewCount > 1000
  AND va.Upvotes > 50
GROUP BY au.Id, au.DisplayName, au.Reputation, ps.PostId, ps.Score, ps.ViewCount, ps.AnswerCount, 
         ps.CommentCount, ps.FavoriteCount, ps.EditCount, ps.ContentEdits, ps.WasClosed, 
         va.Upvotes, va.Downvotes, va.Bookmarks, va.SpamFlags, bs.GoldBadges, bs.SilverBadges, bs.BronzeBadges
HAVING COUNT(c.Id) > 10
ORDER BY au.Reputation DESC, ps.Score DESC, TotalComments DESC
LIMIT 100;