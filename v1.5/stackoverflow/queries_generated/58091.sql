-- {"query": "58091.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "deepseek-r1", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2033, "output_tokens": 1210} 

WITH ActiveUsers AS (
    SELECT u.Id, u.DisplayName, u.Reputation, u.Location,
           COUNT(DISTINCT p.Id) AS TotalPosts,
           COUNT(DISTINCT c.Id) AS TotalComments,
           COUNT(DISTINCT b.Id) AS GoldBadges
    FROM Users u
    LEFT JOIN Posts p ON u.Id = p.OwnerUserId AND p.PostTypeId = 1
    LEFT JOIN Comments c ON u.Id = c.UserId AND DATE_PART('year', c.CreationDate) = 2023
    LEFT JOIN Badges b ON u.Id = b.UserId AND b.Class = 1
    WHERE u.Reputation > 10000
      AND EXISTS (SELECT 1 FROM Posts WHERE OwnerUserId = u.Id AND PostTypeId = 2)
      AND EXISTS (SELECT 1 FROM Votes WHERE UserId = u.Id AND VoteTypeId = 2)
    GROUP BY u.Id, u.DisplayName, u.Reputation, u.Location
    HAVING COUNT(p.Id) > 50
),
PostStats AS (
    SELECT p.OwnerUserId,
           AVG(p.AnswerCount) AS AvgAnswers,
           MAX(p.Score) AS TopPostScore,
           SUM(CASE WHEN ph.PostHistoryTypeId = 5 THEN 1 ELSE 0 END) AS BodyEdits
    FROM Posts p
    JOIN PostHistory ph ON p.Id = ph.PostId AND ph.PostHistoryTypeId IN (2,5,8)
    WHERE p.CreationDate BETWEEN '2020-01-01' AND '2023-12-31'
      AND p.Tags LIKE '%<sql>%'
    GROUP BY p.OwnerUserId
),
VoteAnalysis AS (
    SELECT v.UserId,
           COUNT(DISTINCT CASE WHEN v.VoteTypeId = 2 THEN v.PostId END) AS UpvotedPosts,
           COUNT(DISTINCT CASE WHEN v.VoteTypeId = 8 THEN v.PostId END) AS BountyPosts
    FROM Votes v
    JOIN Posts p ON v.PostId = p.Id AND p.PostTypeId = 1
    WHERE v.CreationDate > CURRENT_DATE - INTERVAL '365 days'
    GROUP BY v.UserId
)
SELECT au.DisplayName, au.Reputation, au.Location,
       ps.AvgAnswers, ps.TopPostScore, ps.BodyEdits,
       va.UpvotedPosts, va.BountyPosts,
       RANK() OVER (PARTITION BY au.Location ORDER BY au.Reputation DESC) AS LocalRank,
       (au.TotalPosts * 0.3 + au.TotalComments * 0.1 + va.UpvotedPosts * 0.6) AS EngagementScore
FROM ActiveUsers au
JOIN PostStats ps ON au.Id = ps.OwnerUserId
LEFT JOIN VoteAnalysis va ON au.Id = va.UserId
WHERE au.GoldBadges > 5
  AND ps.AvgAnswers > (SELECT AVG(AnswerCount) FROM Posts WHERE PostTypeId = 1)
ORDER BY EngagementScore DESC, LocalRank
LIMIT 100;
