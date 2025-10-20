-- {"query": "58094.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "deepseek-r1", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2033, "output_tokens": 1061} 

WITH ActiveUsers AS (
    SELECT u.Id, u.DisplayName, u.Reputation, COUNT(b.Id) AS BadgeCount
    FROM Users u
    JOIN Badges b ON u.Id = b.UserId
    WHERE u.Reputation > 10000
      AND b.Date >= CURRENT_DATE - INTERVAL '1 year'
      AND b.Class = 1
    GROUP BY u.Id, u.DisplayName, u.Reputation
    HAVING COUNT(b.Id) >= 5
), PostStats AS (
    SELECT p.OwnerUserId, 
           COUNT(p.Id) AS TotalPosts,
           AVG(p.Score) AS AvgPostScore,
           SUM(p.ViewCount) AS TotalViews,
           MAX(p.AnswerCount) AS MaxAnswers,
           COUNT(ph.Id) FILTER (WHERE ph.PostHistoryTypeId = 5) AS EditCount
    FROM Posts p
    LEFT JOIN PostHistory ph ON p.Id = ph.PostId
    WHERE p.PostTypeId = 1
      AND p.CreationDate >= CURRENT_DATE - INTERVAL '2 years'
      AND p.ClosedDate IS NULL
    GROUP BY p.OwnerUserId
), VoteAnalysis AS (
    SELECT v.UserId,
           COUNT(v.Id) FILTER (WHERE v.VoteTypeId = 2) AS UpvotesGiven,
           COUNT(v.Id) FILTER (WHERE v.VoteTypeId = 3) AS DownvotesGiven,
           COUNT(v.Id) FILTER (WHERE v.VoteTypeId = 8) AS BountiesStarted
    FROM Votes v
    WHERE v.CreationDate >= CURRENT_DATE - INTERVAL '3 years'
    GROUP BY v.UserId
)
SELECT au.DisplayName,
       au.Reputation,
       au.BadgeCount,
       ps.TotalPosts,
       ps.AvgPostScore,
       ps.TotalViews,
       ps.MaxAnswers,
       ps.EditCount,
       va.UpvotesGiven,
       va.DownvotesGiven,
       va.BountiesStarted,
       RANK() OVER (ORDER BY (ps.TotalPosts * 0.3 + ps.AvgPostScore * 0.5 + va.UpvotesGiven * 0.2) DESC) AS EngagementRank
FROM ActiveUsers au
JOIN PostStats ps ON au.Id = ps.OwnerUserId
JOIN VoteAnalysis va ON au.Id = va.UserId
WHERE ps.TotalPosts > 50
  AND va.UpvotesGiven > 100
ORDER BY EngagementRank, ps.TotalViews DESC
LIMIT 100;
