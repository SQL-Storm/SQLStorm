WITH
recent_posts AS (
  SELECT
    p.Id AS PostId,
    p.OwnerUserId,
    p.Title,
    p.Tags,
    p.CreationDate,
    p.Score,
    p.ViewCount,
    p.LastActivityDate,
    p.PostTypeId,
    p.AcceptedAnswerId,
    p.ParentId,
    p.OwnerDisplayName
  FROM Posts p
  WHERE p.CreationDate >= CAST('2024-10-01 12:34:56' AS timestamp) - INTERVAL '90 days'
),
top_tags AS (
  SELECT
    unnest(string_to_array(substr(p.Tags, 2, length(p.Tags)-2), '><')) AS Tag,
    p.Id AS PostId
  FROM Posts p
  JOIN recent_posts rp ON rp.PostId = p.Id
  WHERE rp.PostTypeId = 1
),
tag_counts AS (
  SELECT Tag, COUNT(*) AS TagPostCount
  FROM top_tags
  GROUP BY Tag
),
user_activity AS (
  SELECT
    u.Id AS UserId,
    u.DisplayName,
    u.Reputation,
    COUNT(DISTINCT rp.PostId) AS PostsCreated,
    SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS UpVotesGiven,
    SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS DownVotesGiven,
    MAX(p.LastActivityDate) AS LastActive
  FROM Users u
  LEFT JOIN Posts p ON p.OwnerUserId = u.Id
  LEFT JOIN Votes v ON v.PostId = p.Id
  LEFT JOIN recent_posts rp ON rp.PostId = p.Id
  GROUP BY u.Id, u.DisplayName, u.Reputation
),
complex_query AS (
  SELECT
    rp.PostId,
    rp.Title,
    rp.OwnerDisplayName,
    rp.CreationDate,
    rp.LastActivityDate,
    rp.Score,
    rp.ViewCount,
    tc.Tag AS PrimaryTag,
    tc2.Tag AS SecondaryTag,
    ca.Title AS AcceptedTitle,
    wv.WorstCase AS WorstCaseValue
  FROM recent_posts rp
  LEFT JOIN (
    SELECT Tag, PostId
    FROM top_tags
  ) tc ON rp.PostId = tc.PostId
  LEFT JOIN (
    SELECT Tag, PostId
    FROM top_tags
  ) tc2 ON rp.PostId = tc2.PostId AND tc2.Tag > tc.Tag
  LEFT JOIN Posts ca ON rp.AcceptedAnswerId = ca.Id
  LEFT JOIN (
    SELECT 1 AS WorstCase
  ) wv ON TRUE
),
outer_join_demo AS (
  SELECT
    pr.PostId,
    pr.Title,
    pr.OwnerDisplayName,
    pr.CreationDate,
    pr.LastActivityDate,
    pr.Score,
    pr.ViewCount,
    pt.Tag AS Tag1,
    p2.Tags,
    p2.OwnerUserId,
    ua.Reputation AS UserReputation,
    ua.PostsCreated,
    ua.UpVotesGiven,
    ua.DownVotesGiven,
    uav.CommentCount AS CommentsCount
  FROM complex_query pr
  LEFT JOIN top_tags pt ON pt.PostId = pr.PostId
  LEFT JOIN Posts p2 ON p2.Id = pr.PostId
  LEFT JOIN user_activity ua ON ua.UserId = p2.OwnerUserId
  LEFT JOIN (
    SELECT PostId, COUNT(*) AS CommentCount
    FROM Comments
    GROUP BY PostId
  ) uav ON uav.PostId = pr.PostId
)
SELECT
  PostId,
  Title,
  OwnerDisplayName,
  CreationDate,
  LastActivityDate,
  Score,
  ViewCount,
  Tag1,
  Tags,
  OwnerUserId,
  UserReputation,
  PostsCreated,
  UpVotesGiven,
  DownVotesGiven,
  CommentsCount
FROM outer_join_demo
ORDER BY LastActivityDate DESC
LIMIT 100;