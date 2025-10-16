-- {"query": "22006.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "grok-code-fast", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2204, "output_tokens": 1281} 
WITH UserStats AS (
  SELECT u.Id,
         u.DisplayName,
         COALESCE(SUM(CASE WHEN p.PostTypeId = 1 THEN p.Score ELSE 0 END), 0) AS QuestionScore,
         COALESCE(AVG(CASE WHEN p.PostTypeId = 2 THEN p.Score ELSE NULL END), 0) AS AvgAnswerScore,
         COUNT(p.Id) AS TotalPosts,
         STRING_AGG(DISTINCT CASE WHEN p.Tags IS NOT NULL THEN SUBSTRING(SUBSTRING(p.Tags FROM 2 FOR LENGTH(p.Tags)-2) FROM 1 FOR POSITION('>' IN SUBSTRING(p.Tags FROM 2 FOR LENGTH(p.Tags)-2))) ELSE NULL END, ', ') AS SampleTag,
         MAX(p.CreationDate) AS LastPostDate
  FROM Users u
  LEFT JOIN Posts p ON u.Id = p.OwnerUserId AND p.PostTypeId IN (1,2)
  WHERE u.Reputation > 50 AND u.CreationDate < '2019-01-01'::timestamp
  GROUP BY u.Id, u.DisplayName
),
CommentStats AS (
  SELECT c.UserId,
         COUNT(*) AS TotalComments,
         SUM(c.Score) AS TotalCommentScore,
         STRING_AGG(SUBSTRING(c.Text FROM 1 FOR 20), '; ') AS CommentSnippet
  FROM Comments c
  WHERE c.UserId IS NOT NULL
  GROUP BY c.UserId
),
VoteStats AS (
  SELECT v.UserId,
         COUNT(CASE WHEN v.VoteTypeId = 2 THEN 1 END) AS UpvotesGiven,
         COUNT(CASE WHEN v.VoteTypeId = 3 THEN 1 END) AS DownvotesGiven,
         AVG(CASE WHEN v.BountyAmount IS NOT NULL THEN v.BountyAmount ELSE 0 END) AS AvgBounty
  FROM Votes v
  WHERE v.UserId IS NOT NULL
  GROUP BY v.UserId
),
BadgeStats AS (
  SELECT b.UserId,
         COUNT(CASE WHEN b.Class = 1 THEN 1 END) AS GoldCount,
         COUNT(CASE WHEN b.Class = 2 THEN 1 END) AS SilverCount,
         STRING_AGG(b.Name, ', ') FILTER (WHERE b.Date > '2020-01-01'::timestamp) AS RecentBadges
  FROM Badges b
  GROUP BY b.UserId
),
TopUsers AS (
  SELECT us.Id,
         us.DisplayName,
         us.QuestionScore,
         us.AvgAnswerScore,
         us.TotalPosts,
         us.SampleTag,
         us.LastPostDate,
         cs.TotalComments,
         cs.TotalCommentScore,
         cs.CommentSnippet,
         vs.UpvotesGiven,
         vs.DownvotesGiven,
         vs.AvgBounty,
         bs.GoldCount,
         bs.SilverCount,
         bs.RecentBadges,
         (us.QuestionScore + COALESCE(cs.TotalCommentScore, 0) + (COALESCE(vs.UpvotesGiven, 0) * 1.5) - (COALESCE(vs.DownvotesGiven, 0) * 0.5)) / NULLIF(us.TotalPosts + 1, 0) AS ComputedScore,
         ROW_NUMBER() OVER (PARTITION BY CASE WHEN bs.GoldCount > 0 THEN 'GoldUser' ELSE 'NonGold' END ORDER BY us.QuestionScore DESC) AS RankWithinGroup
  FROM UserStats us
  FULL OUTER JOIN CommentStats cs ON us.Id = cs.UserId
  FULL OUTER JOIN VoteStats vs ON us.Id = vs.UserId
  FULL OUTER JOIN BadgeStats bs ON us.Id = bs.UserId
  WHERE (us.TotalPosts > 0 OR cs.TotalComments > 0 OR vs.UpvotesGiven > 0) AND us.LastPostDate IS NOT NULL
),
RankedUsers AS (
  SELECT *,
         RANK() OVER (ORDER BY ComputedScore DESC, TotalPosts DESC) AS OverallRank,
         LAG(ComputedScore) OVER (ORDER BY ComputedScore DESC) - ComputedScore AS ScoreDiff,
         (SELECT COUNT(DISTINCT p2.Id)
          FROM Posts p1
          JOIN Posts p2 ON p1.AcceptedAnswerId = p2.Id AND p2.OwnerUserId = tu.Id
          WHERE p1.PostTypeId = 1 AND p1.OwnerUserId = tu.Id
         ) AS AcceptedAnswerCount
  FROM TopUsers tu
)
SELECT ru.Id,
       ru.DisplayName,
       ru.QuestionScore,
       ru.AvgAnswerScore,
       ru.TotalPosts,
       ru.SampleTag,
       ru.LastPostDate,
       ru.TotalComments,
       ru.TotalCommentScore,
       ru.CommentSnippet,
       ru.UpvotesGiven,
       ru.DownvotesGiven,
       ru.AvgBounty,
       ru.GoldCount,
       ru.SilverCount,
       ru.RecentBadges,
       ru.ComputedScore,
       ru.RankWithinGroup,
       ru.OverallRank,
       ru.ScoreDiff,
       ru.AcceptedAnswerCount,
       CASE 
         WHEN ru.ComputedScore > 100 THEN 'Elite'
         WHEN ru.ComputedScore BETWEEN 50 AND 100 THEN 'Good'
         ELSE 'Novice'
       END AS UserTier
FROM RankedUsers ru
WHERE ru.OverallRank <= 50
  AND ru.Id IN (SELECT UserId FROM Badges GROUP BY UserId HAVING COUNT(*) > 5)
  AND ru.SampleTag IS NOT NULL
UNION ALL
SELECT NULL, 'Summary', AVG(ru.QuestionScore), AVG(ru.AvgAnswerScore), SUM(ru.TotalPosts), NULL, NULL, AVG(ru.TotalComments), SUM(ru.TotalCommentScore), NULL, SUM(ru.UpvotesGiven), SUM(ru.DownvotesGiven), AVG(ru.AvgBounty), SUM(ru.GoldCount), SUM(ru.SilverCount), NULL, AVG(ru.ComputedScore), NULL, NULL, AVG(ru.ScoreDiff), SUM(ru.AcceptedAnswerCount), 'Aggregate'
FROM RankedUsers ru
ORDER BY CASE WHEN ru.DisplayName = 'Summary' THEN 1 ELSE 0 END, ru.OverallRank ASC NULLS LAST
LIMIT 51;