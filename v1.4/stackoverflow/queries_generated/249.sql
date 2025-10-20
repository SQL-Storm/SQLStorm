-- {"query": "249.sql", "dataset": "stackoverflow", "version": "v1.4", "prompt": "p1", "model": "gpt-5-nano", "temperature": 1.0, "max_tokens": 32768, "reasoning": "medium", "input_tokens": 2026, "output_tokens": 7701} 
WITH
PeriodPosts AS (
  SELECT p.Id, p.OwnerUserId, p.Title, p.Tags, p.ViewCount, p.Score, p.CreationDate, p.LastActivityDate
  FROM Posts p
  WHERE p.CreationDate >= NOW() - INTERVAL '365 days'
    AND p.OwnerUserId IS NOT NULL
),
UserContrib AS (
  SELECT u.Id AS UserId,
         u.DisplayName,
         u.Reputation,
         COUNT(pp.Id) AS PostCount365,
         COALESCE(SUM(pp.ViewCount),0) AS TotalViews365,
         COALESCE(SUM(pp.Score),0) AS ScoreSum365,
         MAX(pp.LastActivityDate) AS LastActivity365,
         (SELECT COUNT(*) FROM Votes v WHERE v.UserId = u.Id AND v.CreationDate >= NOW() - INTERVAL '365 days') AS VotesCastLastYear
  FROM Users u
  LEFT JOIN PeriodPosts pp ON pp.OwnerUserId = u.Id
  GROUP BY u.Id, u.DisplayName, u.Reputation
),
VotesSum AS (
  SELECT p.OwnerUserId AS UserId,
         SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS UpvotesOnPosts
  FROM Posts p
  LEFT JOIN Votes v ON v.PostId = p.Id
  WHERE p.CreationDate >= NOW() - INTERVAL '365 days'
  GROUP BY p.OwnerUserId
),
CommentsSum AS (
  SELECT p.OwnerUserId AS UserId,
         COUNT(c.Id) AS CommentsOnPosts
  FROM Posts p
  LEFT JOIN Comments c ON c.PostId = p.Id
  WHERE p.CreationDate >= NOW() - INTERVAL '365 days'
  GROUP BY p.OwnerUserId
),
BadgesCount AS (
  SELECT b.UserId,
         COUNT(*) AS BadgeCount
  FROM Badges b
  GROUP BY b.UserId
),
TagSet AS (
  SELECT p.OwnerUserId AS UserId,
         string_to_array(substring(p.Tags, 2, length(p.Tags)-2), '><') AS TagArray
  FROM PeriodPosts p
  WHERE p.Tags IS NOT NULL
  GROUP BY p.OwnerUserId
),
TopTags AS (
  SELECT UserId, UNNEST(TagArray) AS Tag
  FROM TagSet
),
Consolidated AS (
  SELECT uc.UserId,
         uc.DisplayName,
         uc.Reputation,
         uc.PostCount365,
         uc.TotalViews365,
         uc.ScoreSum365,
         uc.LastActivity365,
         COALESCE(vs.UpvotesOnPosts,0) AS UpvotesOnPosts,
         COALESCE(cs.CommentsOnPosts,0) AS CommentsOnPosts,
         COALESCE(bc.BadgeCount,0) AS Badges
  FROM UserContrib uc
  LEFT JOIN VotesSum vs ON vs.UserId = uc.UserId
  LEFT JOIN CommentsSum cs ON cs.UserId = uc.UserId
  LEFT JOIN BadgesCount bc ON bc.UserId = uc.UserId
),
Ranked AS (
  SELECT c.*,
         ROW_NUMBER() OVER (ORDER BY c.Reputation DESC, c.TotalViews365 DESC, c.PostCount365 DESC) AS GlobalRank
  FROM Consolidated c
),
TopUsers AS (
  SELECT * FROM Ranked WHERE GlobalRank <= 150
  UNION ALL
  SELECT * FROM Ranked WHERE GlobalRank > 150 AND GlobalRank <= 250
)
SELECT
  tu.UserId,
  tu.DisplayName,
  tu.Reputation,
  tu.PostCount365,
  tu.TotalViews365,
  tu.ScoreSum365,
  tu.LastActivity365,
  tu.UpvotesOnPosts,
  tu.CommentsOnPosts,
  tu.Badges,
  ARRAY_AGG(DISTINCT t.Tag) FILTER (WHERE t.Tag IS NOT NULL) AS TopTags
FROM TopUsers tu
LEFT JOIN TopTags t ON t.UserId = tu.UserId
GROUP BY
  tu.UserId,
  tu.DisplayName,
  tu.Reputation,
  tu.PostCount365,
  tu.TotalViews365,
  tu.ScoreSum365,
  tu.LastActivity365,
  tu.UpvotesOnPosts,
  tu.CommentsOnPosts,
  tu.Badges
ORDER BY tu.Reputation DESC, tu.TotalViews365 DESC, tu.PostCount365 DESC;