-- {"query": "5379.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-5-nano", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 908}
WITH
RecentActivePosts AS (
  SELECT
    p.Id AS PostId,
    p.Title,
    p.OwnerUserId,
    p.CreationDate,
    p.Score,
    p.ViewCount,
    p.Tags,
    p.LastActivityDate,
    p.PostTypeId,
    COALESCE(p.AcceptedAnswerId, -1) AS AnswerId
  FROM Posts p
  WHERE p.CreationDate >= CAST('2024-10-01 12:34:56' AS timestamp) - INTERVAL '90 days'
),
TopCommenters AS (
  SELECT
    c.PostId,
    c.UserId,
    u.DisplayName AS UserName,
    COUNT(*) AS CommentCount,
    SUM(CASE WHEN c.Score > 0 THEN 1 ELSE 0 END) AS PositiveComments
  FROM Comments c
  JOIN Users u ON c.UserId = u.Id
  GROUP BY c.PostId, c.UserId, u.DisplayName
),
TagCooccurrence AS (
  SELECT
    s1.TagName AS TagA,
    s2.TagName AS TagB,
    COUNT(*) AS Cooccurrence
  FROM (
    SELECT unnest(string_to_array(substring(p.Tags, 2, length(p.Tags) - 2), '<>')) AS TagName
    FROM Posts p
    WHERE p.Id IN (SELECT PostId FROM RecentActivePosts)
  ) s1
  CROSS JOIN (
    SELECT unnest(string_to_array(substring(p.Tags, 2, length(p.Tags) - 2), '<>')) AS TagName
    FROM Posts p
    WHERE p.Id IN (SELECT PostId FROM RecentActivePosts)
  ) s2
  WHERE s1.TagName < s2.TagName
  GROUP BY s1.TagName, s2.TagName
),
RecentVotes AS (
  SELECT
    v.PostId,
    v.VoteTypeId,
    v.UserId,
    v.CreationDate,
    v.BountyAmount
  FROM Votes v
  WHERE v.CreationDate >= CAST('2024-10-01 12:34:56' AS timestamp) - INTERVAL '60 days'
),
ScoreDynamics AS (
  SELECT
    rp.PostId,
    rp.Title,
    rp.OwnerUserId,
    rp.CreationDate,
    rp.LastActivityDate,
    rp.Score,
    rp.ViewCount,
    rp.Tags,
    SUM(CASE WHEN rv.VoteTypeId = 2 THEN 1 ELSE 0 END) AS UpvotesInLast60,
    SUM(CASE WHEN rv.VoteTypeId = 3 THEN 1 ELSE 0 END) AS DownvotesInLast60,
    SUM(CASE WHEN rv.VoteTypeId = 16 THEN 1 ELSE 0 END) AS ModeratorVotesInLast60
  FROM RecentActivePosts rp
  LEFT JOIN RecentVotes rv ON rv.PostId = rp.PostId
  GROUP BY rp.PostId, rp.Title, rp.OwnerUserId, rp.CreationDate, rp.LastActivityDate, rp.Score, rp.ViewCount, rp.Tags
),
WindowedPosts AS (
  SELECT
    sd.*,
    ROW_NUMBER() OVER (
      PARTITION BY sd.OwnerUserId
      ORDER BY sd.LastActivityDate DESC, sd.Score DESC
    ) AS rn_by_owner
  FROM ScoreDynamics sd
),
TopOwners AS (
  SELECT *
  FROM WindowedPosts
  WHERE rn_by_owner <= 5
),
Aggregated AS (
  SELECT
    t.PostId,
    t.Title,
    t.OwnerUserId,
    u.DisplayName AS OwnerName,
    t.LastActivityDate,
    t.Score,
    t.ViewCount,
    t.Tags,
    t.UpvotesInLast60,
    t.DownvotesInLast60,
    t.ModeratorVotesInLast60,
    COALESCE(b.Name, 'None') AS BadgeName
  FROM TopOwners t
  LEFT JOIN Users u ON t.OwnerUserId = u.Id
  LEFT JOIN Badges b ON b.UserId = u.Id
  WHERE b.Id IS NULL
)
SELECT
  a.PostId,
  a.Title,
  a.OwnerName,
  a.LastActivityDate,
  a.Score,
  a.ViewCount,
  a.Tags,
  a.UpvotesInLast60,
  a.DownvotesInLast60,
  a.ModeratorVotesInLast60,
  a.BadgeName
FROM Aggregated a
ORDER BY a.LastActivityDate DESC, a.Score DESC
LIMIT 100;