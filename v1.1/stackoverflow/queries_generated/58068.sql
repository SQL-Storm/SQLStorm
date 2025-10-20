-- {"query": "58068.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "deepseek-r1", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2033, "output_tokens": 1006} 

WITH ActiveUsers AS (
    SELECT u.Id, u.DisplayName, u.Reputation, u.CreationDate,
           COUNT(DISTINCT p.Id) AS PostCount,
           COUNT(DISTINCT c.Id) AS CommentCount,
           COUNT(DISTINCT b.Id) AS BadgeCount
    FROM Users u
    LEFT JOIN Posts p ON u.Id = p.OwnerUserId AND p.PostTypeId = 1
    LEFT JOIN Comments c ON u.Id = c.UserId
    LEFT JOIN Badges b ON u.Id = b.UserId AND b.Class = 1
    WHERE u.Reputation > 1000
      AND u.CreationDate >= NOW() - INTERVAL '1 year'
    GROUP BY u.Id, u.DisplayName, u.Reputation, u.CreationDate
),
PostStats AS (
    SELECT p.OwnerUserId,
           AVG(p.Score) AS AvgPostScore,
           MAX(p.ViewCount) AS MaxViews,
           SUM(CASE WHEN ph.PostHistoryTypeId = 2 THEN 1 ELSE 0 END) AS BodyEdits
    FROM Posts p
    LEFT JOIN PostHistory ph ON p.Id = ph.PostId AND ph.PostHistoryTypeId IN (2,5,8)
    WHERE p.PostTypeId = 1
    GROUP BY p.OwnerUserId
),
VoteAnalysis AS (
    SELECT v.UserId,
           COUNT(DISTINCT v.PostId) FILTER (WHERE v.VoteTypeId = 2) AS UpvotesGiven,
           COUNT(DISTINCT v.PostId) FILTER (WHERE v.VoteTypeId = 3) AS DownvotesGiven
    FROM Votes v
    JOIN Posts p ON v.PostId = p.Id AND p.PostTypeId = 1
    GROUP BY v.UserId
)
SELECT au.*,
       ps.AvgPostScore,
       ps.MaxViews,
       ps.BodyEdits,
       va.UpvotesGiven,
       va.DownvotesGiven,
       RANK() OVER (ORDER BY au.Reputation DESC) AS ReputationRank,
       DENSE_RANK() OVER (ORDER BY ps.AvgPostScore DESC NULLS LAST) AS PostQualityRank
FROM ActiveUsers au
JOIN PostStats ps ON au.Id = ps.OwnerUserId
LEFT JOIN VoteAnalysis va ON au.Id = va.UserId
WHERE au.PostCount > 50
  AND ps.BodyEdits > 5
  AND (va.UpvotesGiven + va.DownvotesGiven) > 100
ORDER BY au.Reputation DESC, ps.MaxViews DESC
LIMIT 100;
