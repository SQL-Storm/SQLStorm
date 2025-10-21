-- {"query": "58069.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "deepseek-r1", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2033, "output_tokens": 1371} 
WITH ActiveUsers AS (
    SELECT u.Id, u.DisplayName, u.Reputation, COUNT(b.Id) AS GoldBadges
    FROM Users u
    LEFT JOIN Badges b ON u.Id = b.UserId AND b.Class = 1
    WHERE u.Reputation > 10000 AND u.CreationDate >= '2020-01-01'
    GROUP BY u.Id, u.DisplayName, u.Reputation
    HAVING COUNT(b.Id) >= 5
),
HighImpactPosts AS (
    SELECT p.Id AS PostId, p.OwnerUserId, p.Score, p.CommentCount, p.Title,
           ROW_NUMBER() OVER (PARTITION BY p.OwnerUserId ORDER BY p.Score DESC) AS PostRank
    FROM Posts p
    WHERE p.PostTypeId = 1 AND p.Score >= 100 AND p.CommentCount >= 50
),
PostVotes AS (
    SELECT v.PostId,
           SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS UpVotes,
           SUM(CASE WHEN v.VoteTypeId = 5 THEN 1 ELSE 0 END) AS Favorites
    FROM Votes v
    GROUP BY v.PostId
),
ClosedReopenedPosts AS (
    SELECT ph.PostId, COUNT(DISTINCT CASE WHEN ph.PostHistoryTypeId = 10 THEN ph.CreationDate END) AS ClosedDates,
           COUNT(DISTINCT CASE WHEN ph.PostHistoryTypeId = 11 THEN ph.CreationDate END) AS ReopenedDates
    FROM PostHistory ph
    WHERE ph.PostHistoryTypeId IN (10, 11)
    GROUP BY ph.PostId
)
SELECT au.DisplayName, au.Reputation, au.GoldBadges, hip.Title, hip.Score, hip.CommentCount,
       pv.UpVotes, pv.Favorites, COALESCE(crp.ClosedDates, 0) AS TimesClosed,
       COALESCE(crp.ReopenedDates, 0) AS TimesReopened,
       (hip.Score * 0.5 + hip.CommentCount * 0.3 + pv.UpVotes * 0.2) AS ImpactScore
FROM ActiveUsers au
JOIN HighImpactPosts hip ON au.Id = hip.OwnerUserId AND hip.PostRank <= 3
LEFT JOIN PostVotes pv ON hip.PostId = pv.PostId
LEFT JOIN ClosedReopenedPosts crp ON hip.PostId = crp.PostId
ORDER BY au.Reputation DESC, ImpactScore DESC, TimesClosed DESC
LIMIT 100;