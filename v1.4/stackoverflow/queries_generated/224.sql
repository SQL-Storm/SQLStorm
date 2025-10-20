-- {"query": "224.sql", "dataset": "stackoverflow", "version": "v1.4", "prompt": "p1", "model": "gpt-5-nano", "temperature": 1.0, "max_tokens": 32768, "reasoning": "medium", "input_tokens": 2026, "output_tokens": 5753} 
WITH
post_counts AS (
  SELECT OwnerUserId AS UserId,
         COUNT(*) AS PostCount,
         COUNT(*) FILTER (WHERE PostTypeId = 1) AS QuestionCount,
         MAX(LastActivityDate) AS LastActivityDate
  FROM Posts
  GROUP BY OwnerUserId
),
comment_counts AS (
  SELECT UserId, COUNT(*) AS CommentCount
  FROM Comments
  GROUP BY UserId
),
badge_counts AS (
  SELECT UserId, COUNT(*) AS BadgesCount
  FROM Badges
  GROUP BY UserId
),
vote_sums AS (
  SELECT UserId,
         SUM(CASE WHEN VoteTypeId = 2 THEN 1 ELSE 0 END) AS UpvotesCast,
         SUM(CASE WHEN VoteTypeId = 3 THEN 1 ELSE 0 END) AS DownvotesCast,
         SUM(BountyAmount) AS TotalBounty
  FROM Votes
  GROUP BY UserId
)
SELECT
  u.Id AS UserId,
  u.DisplayName,
  COALESCE(u.Location, 'Unknown') AS Location,
  u.Reputation,
  u.CreationDate,
  u.LastAccessDate,
  COALESCE(pc.PostCount, 0) AS PostCount,
  COALESCE(pc.QuestionCount, 0) AS QuestionCount,
  COALESCE(cc.CommentCount, 0) AS CommentCount,
  COALESCE(bc.BadgesCount, 0) AS BadgesCount,
  COALESCE(vs.UpvotesCast, 0) AS UpvotesCast,
  COALESCE(vs.DownvotesCast, 0) AS DownvotesCast,
  COALESCE(vs.TotalBounty, 0) AS TotalBounty,
  pc.LastActivityDate,
  (2 * COALESCE(pc.PostCount, 0) + 3 * COALESCE(cc.CommentCount, 0) + COALESCE(vs.TotalBounty, 0)) AS EngagementScore,
  ROW_NUMBER() OVER (PARTITION BY COALESCE(u.Location, 'Unknown') ORDER BY u.Reputation DESC, u.Id) AS LocationRank,
  ROW_NUMBER() OVER (ORDER BY (2 * COALESCE(pc.PostCount, 0) + 3 * COALESCE(cc.CommentCount, 0) + COALESCE(vs.TotalBounty, 0)) DESC) AS OverallRank
FROM Users u
LEFT JOIN post_counts pc ON pc.UserId = u.Id
LEFT JOIN comment_counts cc ON cc.UserId = u.Id
LEFT JOIN badge_counts bc ON bc.UserId = u.Id
LEFT JOIN vote_sums vs ON vs.UserId = u.Id
ORDER BY EngagementScore DESC
LIMIT 400;