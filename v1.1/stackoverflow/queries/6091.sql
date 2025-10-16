WITH
RecentUserActivity AS (
  SELECT
    u.Id AS UserId,
    u.DisplayName,
    u.Reputation,
    u.LastAccessDate,
    u.CreationDate,
    COUNT(p.Id) FILTER (WHERE p.CreationDate > CAST('2024-10-01 12:34:56' AS TIMESTAMP) - INTERVAL '180 days') AS RecentPosts,
    SUM(COALESCE(p.Score, 0)) FILTER (WHERE p.PostTypeId = 1) AS QuestionScoreSum,
    SUM(COALESCE(v.BountyAmount, 0)) AS TotalBountyGiven,
    ROW_NUMBER() OVER (ORDER BY u.Reputation DESC, u.LastAccessDate DESC) AS rn
  FROM Users u
  LEFT JOIN Posts p ON p.OwnerUserId = u.Id
  LEFT JOIN Votes v ON v.PostId = p.Id AND v.VoteTypeId IN (2,10)
  GROUP BY u.Id, u.DisplayName, u.Reputation, u.LastAccessDate, u.CreationDate
),
PostTags AS (
  -- split tags like '<tag1><tag2>' into rows in a dialect-portable way
  SELECT
    p2.Id AS pid,
    TRIM(BOTH '<>' FROM tag) AS TagName
  FROM Posts p2,
  LATERAL (
    SELECT value AS tag
    FROM (
      -- replace '><' with a delimiter and then split by that delimiter
      SELECT UNNEST(string_to_array(REPLACE(REPLACE(p2.Tags, '><', '|'), '<', ''), '|')) AS value
    ) s
  ) t
),
PostEngagement AS (
  SELECT
    p.Id AS PostId,
    p.OwnerUserId,
    p.PostTypeId,
    p.CreationDate,
    p.LastActivityDate,
    p.Score,
    p.ViewCount,
    ARRAY_AGG(DISTINCT t.TagName) AS TagsList,
    COUNT(c.Id) AS CommentCount,
    COUNT(v.Id) AS VoteCount,
    MAX(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS HasUpvote,
    MAX(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS HasDownvote,
    CASE
      WHEN p.PostTypeId = 1 THEN (COALESCE(p.Score,0) * 2) + COALESCE(p.ViewCount,0) + COALESCE(COUNT(c.Id),0)
      ELSE COALESCE(p.Score,0) + COALESCE(p.ViewCount,0)
    END AS EngagementScore
  FROM Posts p
  LEFT JOIN PostLinks pl ON pl.PostId = p.Id
  LEFT JOIN Comments c ON c.PostId = p.Id
  LEFT JOIN Votes v ON v.PostId = p.Id
  LEFT JOIN PostTags t ON t.pid = p.Id
  GROUP BY p.Id, p.OwnerUserId, p.PostTypeId, p.CreationDate, p.LastActivityDate, p.Score, p.ViewCount
),
TopPostsPerUser AS (
  SELECT
    pe.PostId,
    pe.OwnerUserId,
    pe.EngagementScore,
    pe.ViewCount,
    pe.CommentCount,
    pe.VoteCount,
    ROW_NUMBER() OVER (PARTITION BY pe.OwnerUserId ORDER BY pe.EngagementScore DESC, pe.ViewCount DESC) AS post_rank
  FROM PostEngagement pe
),
UserTopPost AS (
  SELECT
    ru.UserId,
    ru.DisplayName,
    ru.Reputation,
    ru.LastAccessDate,
    ru.CreationDate,
    tp.PostId AS TopPostId,
    tp.EngagementScore AS TopEngagement
  FROM RecentUserActivity ru
  LEFT JOIN TopPostsPerUser tp
    ON tp.OwnerUserId = ru.UserId AND tp.post_rank = 1
),
FinalResult AS (
  SELECT
    utu.UserId,
    utu.DisplayName,
    utu.Reputation,
    utu.LastAccessDate,
    utu.CreationDate,
    utu.TopPostId,
    utu.TopEngagement,
    CASE
      WHEN utu.TopPostId IS NULL THEN NULL
      ELSE (SELECT p.Title FROM Posts p WHERE p.Id = utu.TopPostId)
    END AS TopPostTitle,
    (SELECT COUNT(*) FROM Posts p2 WHERE p2.OwnerUserId = utu.UserId) AS PostCountByUser,
    (SELECT AVG(pe2.EngagementScore) FROM PostEngagement pe2 WHERE pe2.OwnerUserId = utu.UserId) AS AvgEngagementPerPost
  FROM UserTopPost utu
  LEFT JOIN Posts p ON p.Id = utu.TopPostId
)
SELECT
  fr.UserId,
  fr.DisplayName,
  fr.Reputation,
  fr.LastAccessDate,
  fr.CreationDate,
  fr.TopPostId,
  fr.TopEngagement,
  fr.TopPostTitle,
  fr.PostCountByUser,
  fr.AvgEngagementPerPost
FROM FinalResult fr
WHERE
  fr.Reputation > 1000
  OR (fr.TopEngagement IS NOT NULL AND fr.TopEngagement > 500)
ORDER BY fr.Reputation DESC NULLS LAST, fr.TopEngagement DESC NULLS LAST
LIMIT 100;