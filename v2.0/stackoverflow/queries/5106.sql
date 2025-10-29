WITH
TopQuestions AS (
  SELECT
    p.Id AS PostId,
    p.Title,
    p.CreationDate,
    p.ViewCount,
    p.Score,
    p.OwnerUserId,
    p.Tags,
    p.LastActivityDate,
    p.AnswerCount,
    p.CommentCount,
    p.FavoriteCount,
    COALESCE(u.Location, '') AS OwnerLocation,
    u.Reputation,
    u.DisplayName AS OwnerDisplayName
  FROM Posts p
  JOIN Users u ON p.OwnerUserId = u.Id
  WHERE p.PostTypeId = 1
    AND p.CreationDate >= CAST('2024-10-01 12:34:56' AS TIMESTAMP) - INTERVAL '365 days'
),
RecentEdits AS (
  SELECT
    ph.PostId,
    ph.CreationDate AS EditDate,
    ph.UserId AS EditorUserId,
    ph.UserDisplayName AS EditorDisplayName,
    ph.PostHistoryTypeId,
    ph.Comment,
    ph.Text
  FROM PostHistory ph
  WHERE ph.PostHistoryTypeId IN (4,5,6,16,50)
),
TagMetrics AS (
  SELECT
    t.TagName,
    t.Count AS TagCount,
    t.ExcerptPostId,
    t.WikiPostId,
    t.IsModeratorOnly
  FROM Tags t
  WHERE t.IsModeratorOnly = FALSE
),
tmap AS (
  SELECT
    p.Id AS PostId,
    TRIM(tag) AS TagName
  FROM Posts p,
  LATERAL (
    SELECT UNNEST(STRING_TO_ARRAY(SUBSTRING(p.Tags FROM 2 FOR CHAR_LENGTH(p.Tags)-2), '><')) AS tag
  ) s
),
Joined AS (
  SELECT
    tq.PostId,
    tq.Title,
    tq.CreationDate AS PostCreated,
    tq.ViewCount,
    tq.Score,
    tq.OwnerUserId,
    tq.OwnerDisplayName,
    tq.Reputation,
    tq.AnswerCount,
    tq.CommentCount,
    rq.EditDate,
    rq.EditorUserId,
    rq.EditorDisplayName,
    rm.TagName,
    rm.TagCount,
    pv.CreationDate AS VoteDate,
    pv.VoteTypeId,
    pv.UserId AS VoterUserId,
    uv.Reputation AS VoterReputation,
    pv.Id AS VoteId
  FROM TopQuestions tq
  LEFT JOIN RecentEdits rq ON rq.PostId = tq.PostId
  LEFT JOIN tmap ON tmap.PostId = tq.PostId
  LEFT JOIN TagMetrics rm ON rm.TagName = tmap.TagName
  LEFT JOIN Votes pv ON pv.PostId = tq.PostId
  LEFT JOIN Users uv ON pv.UserId = uv.Id
  WHERE tq.OwnerUserId IS NOT NULL
  GROUP BY
    tq.PostId,
    tq.Title,
    tq.CreationDate,
    tq.ViewCount,
    tq.Score,
    tq.OwnerUserId,
    tq.OwnerDisplayName,
    tq.Reputation,
    tq.AnswerCount,
    tq.CommentCount,
    rq.EditDate,
    rq.EditorUserId,
    rq.EditorDisplayName,
    rm.TagName,
    rm.TagCount,
    pv.CreationDate,
    pv.VoteTypeId,
    pv.UserId,
    uv.Reputation,
    pv.Id
)
SELECT
  PostId,
  Title,
  PostCreated,
  ViewCount,
  Score,
  OwnerDisplayName,
  Reputation AS OwnerReputation,
  AnswerCount,
  CommentCount,
  COALESCE(EditDate, PostCreated) AS LastActiveDate,
  COALESCE(EditorDisplayName, OwnerDisplayName) AS LastEditor,
  CASE WHEN VoteTypeId = 2 THEN 1 ELSE 0 END AS UpvoteFlag,
  CASE WHEN VoteTypeId = 3 THEN 1 ELSE 0 END AS DownvoteFlag,
  TagName,
  TagCount,
  CASE WHEN VoteId IS NOT NULL THEN VoteTypeId ELSE NULL END AS VoteSchema,
  COALESCE(VoterReputation, 0) AS VoterReputation
FROM Joined
ORDER BY PostCreated DESC
LIMIT 200;