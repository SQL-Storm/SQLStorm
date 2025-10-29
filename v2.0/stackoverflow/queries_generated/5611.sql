-- {"query": "5611.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-5-nano", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 984} 
WITH
-- 1) Top users by reputation with some derived metrics and NULL-safe expressions
TopUsers AS (
  SELECT
    u.Id AS UserId,
    u.DisplayName,
    u.Reputation,
    u.CreationDate,
    u.LastAccessDate,
    COALESCE(u.Location, 'Unknown') AS Location,
    u.Views,
    u.UpVotes,
    u.DownVotes,
    u.ProfileImageUrl,
    u.EmailHash,
    u.AccountId,
    -- derived: ratio of upvotes to total votes (handle division by zero)
    CASE WHEN (u.UpVotes + u.DownVotes) = 0 THEN NULL
         ELSE CAST(u.UpVotes AS float) / NULLIF(CAST(u.UpVotes + u.DownVotes AS float), 0) END AS UpvoteShare,
    -- flag: 5 most recent badges of the user (if any)
    (SELECT COALESCE(COUNT(*),0)
     FROM Badges b
     WHERE b.UserId = u.Id) AS BadgeCount
  FROM Users u
),
-- 2) Recent activity window per user: last 5 posts by creation date
RecentActivity AS (
  SELECT
    p.Id AS PostId,
    p.OwnerUserId,
    p.Title,
    p.PostTypeId,
    p.CreationDate,
    ROW_NUMBER() OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate DESC) AS rn
  FROM Posts p
  WHERE p.CreationDate >= CURRENT_DATE - INTERVAL '90 days'
),
-- 3) Post interactions: counts per user in the last 90 days (views, comments, votes)
UserInteractions AS (
  SELECT
    ra.OwnerUserId AS UserId,
    COUNT(DISTINCT ra.PostId) AS RecentPosts,
    SUM(p.ViewCount) AS TotalViews,
    SUM(CASE WHEN c.Id IS NOT NULL THEN 1 ELSE 0 END) AS CommentCountLast90,
    SUM(CASE WHEN v.Id IS NOT NULL THEN 1 ELSE 0 END) AS VoteCountLast90
  FROM RecentActivity ra
  LEFT JOIN Posts p ON p.Id = ra.PostId
  LEFT JOIN Comments c ON c.PostId = ra.PostId AND c.CreationDate >= CURRENT_DATE - INTERVAL '90 days'
  LEFT JOIN Votes v ON v.PostId = ra.PostId AND v.CreationDate >= CURRENT_DATE - INTERVAL '90 days'
  GROUP BY ra.OwnerUserId
),
-- 4) Complex sample: join posts with their tags (for questions) and categorize by tag presence
TaggedQuestions AS (
  SELECT
    p.Id AS PostId,
    p.Title,
    t.TagName,
    t.Count AS TagCount
  FROM Posts p
  JOIN UNNEST(string_to_array(REPLACE(REPLACE(p.Tags, '<',''),'>',''), ',') ) AS t(TagName) -- split tags, null-safe
      ON TRUE
  WHERE p.PostTypeId = 1
),
-- 5) Windowed ranking of posts by score per user (dense rank)
ScoreRank AS (
  SELECT
    p.Id AS PostId,
    p.OwnerUserId,
    p.Score,
    p.CreationDate,
    DENSE_RANK() OVER (PARTITION BY p.OwnerUserId ORDER BY p.Score DESC, p.CreationDate DESC) AS ScoreRank
  FROM Posts p
  WHERE p.Score IS NOT NULL
),
-- 6) Full outer-ish combination: combine recent activity with user base and interaction metrics
BenchmarkFrame AS (
  SELECT
    tu.UserId,
    tu.DisplayName,
    tu.Reputation,
    tu.Location,
    ru.RecentPosts,
    ru.TotalViews,
    ru.CommentCountLast90,
    ru.VoteCountLast90,
    ru.BadgeCount,
    sr.PostId AS TopPostId,
    sr.ScoreRank,
    pr.rn AS ActivityRank
  FROM TopUsers tu
  LEFT JOIN UserInteractions ru ON ru.UserId = tu.UserId
  LEFT JOIN ScoreRank sr ON sr.OwnerUserId = tu.UserId
  LEFT JOIN RecentActivity pr ON pr.OwnerUserId = tu.UserId AND pr.rn = 1
)
SELECT
  bf.UserId,
  bf.DisplayName,
  bf.Reputation,
  bf.Location,
  bf.RecentPosts,
  bf.TotalViews,
  bf.CommentCountLast90,
  bf.VoteCountLast90,
  bf.BadgeCount,
  bf.TopPostId,
  bf.ScoreRank,
  bf.ActivityRank
FROM BenchmarkFrame bf
ORDER BY bf.Reputation DESC NULLS LAST, bf.TotalViews DESC NULLS LAST
LIMIT 100;