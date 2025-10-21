WITH
PostsBase AS (
  SELECT
    p.Id AS PostId,
    p.Title,
    p.PostTypeId,
    p.OwnerUserId,
    p.CreationDate,
    p.LastActivityDate,
    p.Score,
    p.ViewCount,
    p.AnswerCount,
    p.CommentCount,
    p.FavoriteCount,
    p.Tags,
    p.Body,
    p.AcceptedAnswerId,
    p.ClosedDate,
    p.LastEditorUserId,
    p.LastEditDate,
    CASE WHEN p.Tags IS NULL OR p.Tags = '' THEN 0
         ELSE array_length(string_to_array(substring(p.Tags, 2, length(p.Tags)-2), '><'), 1)
    END AS TagCount,
    CASE WHEN p.Tags IS NULL OR p.Tags = '' THEN NULL
         ELSE (string_to_array(substring(p.Tags, 2, length(p.Tags)-2), '><'))[1]
    END AS FirstTag
  FROM Posts p
  WHERE p.CreationDate >= cast('2024-10-01 12:34:56' as timestamp) - interval '2 years'
),
CommentAgg AS (
  SELECT PostId, COUNT(*) AS CommentCount
  FROM Comments
  GROUP BY PostId
),
UpDown AS (
  SELECT PostId,
         SUM(CASE WHEN VoteTypeId = 2 THEN 1 ELSE 0 END) AS UpVotes,
         SUM(CASE WHEN VoteTypeId = 3 THEN 1 ELSE 0 END) AS DownVotes
  FROM Votes
  GROUP BY PostId
)
SELECT
  pb.PostId,
  pb.Title,
  pb.PostTypeId,
  pb.OwnerUserId,
  ou.DisplayName AS OwnerDisplayName,
  pb.CreationDate,
  pb.LastActivityDate,
  pb.Score,
  pb.ViewCount,
  COALESCE(ca.CommentCount, pb.CommentCount) AS CommentCount,
  pb.FavoriteCount,
  pb.Tags,
  pb.Body,
  pb.AcceptedAnswerId,
  pb.ClosedDate,
  ou.Reputation AS OwnerReputation,
  COALESCE(ud.UpVotes, 0) AS UpVotes,
  COALESCE(ud.DownVotes, 0) AS DownVotes,
  pb.FirstTag,
  pb.TagCount,
  (SELECT COUNT(*) FROM Posts p2 WHERE p2.OwnerUserId = pb.OwnerUserId AND p2.CreationDate >= pb.CreationDate - interval '30 days') AS OwnerRecentPosts,
  (SELECT COALESCE(u3.DisplayName, 'Unknown') FROM Users u3 WHERE u3.Id = pb.LastEditorUserId) AS LastEditorDisplayName,
  (SELECT COUNT(*) FROM Badges b WHERE b.UserId = pb.OwnerUserId AND b.Class = 1) AS GoldBadges,
  ROW_NUMBER() OVER (PARTITION BY pb.OwnerUserId ORDER BY pb.Score DESC, pb.LastActivityDate DESC) AS OwnerPostRank
FROM PostsBase pb
LEFT JOIN Users ou ON pb.OwnerUserId = ou.Id
LEFT JOIN UpDown ud ON pb.PostId = ud.PostId
LEFT JOIN CommentAgg ca ON pb.PostId = ca.PostId

UNION ALL
SELECT
  CAST(-1 AS BIGINT) AS PostId,
  'Benchmark: meta' AS Title,
  CAST(NULL AS SMALLINT) AS PostTypeId,
  CAST(NULL AS INTEGER) AS OwnerUserId,
  CAST(NULL AS TEXT) AS OwnerDisplayName,
  CAST('2024-10-01 12:34:56' AS TIMESTAMP) AS CreationDate,
  CAST('2024-10-01 12:34:56' AS TIMESTAMP) AS LastActivityDate,
  0 AS Score,
  0 AS ViewCount,
  0 AS CommentCount,
  0 AS FavoriteCount,
  CAST(NULL AS TEXT) AS Tags,
  CAST(NULL AS TEXT) AS Body,
  CAST(NULL AS INTEGER) AS AcceptedAnswerId,
  CAST(NULL AS TIMESTAMP) AS ClosedDate,
  CAST(NULL AS INTEGER) AS OwnerReputation,
  0 AS UpVotes,
  0 AS DownVotes,
  CAST(NULL AS TEXT) AS FirstTag,
  CAST(NULL AS INTEGER) AS TagCount,
  CAST(NULL AS INTEGER) AS OwnerRecentPosts,
  CAST(NULL AS TEXT) AS LastEditorDisplayName,
  CAST(NULL AS INTEGER) AS GoldBadges,
  CAST(NULL AS INTEGER) AS OwnerPostRank
;