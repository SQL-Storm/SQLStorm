-- {"query": "5106.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-5-nano", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 743} 
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
    COALESCE(p.Location, '') AS OwnerLocation,
    u.Reputation,
    u.DisplayName AS OwnerDisplayName
  FROM Posts p
  JOIN Users u ON p.OwnerUserId = u.Id
  WHERE p.PostTypeId = 1
    AND p.CreationDate >= NOW() - INTERVAL '365 days'
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
  WHERE ph.PostHistoryTypeId IN (4,5,6,16,50) -- edits, community ownership, etc.
),
TagMetrics AS (
  SELECT
    t.TagName,
    t.Count AS TagCount,
    t.ExcerptPostId,
    t.WikiPostId,
    t.IsModeratorOnly
  FROM Tags t
  WHERE t.IsModeratorOnly = 0
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
    pv.VoteDate,
    pv.VoteTypeId,
    pv.UserId AS VoterUserId,
    uv.Reputation AS VoterReputation
  FROM TopQuestions tq
  LEFT JOIN RecentEdits rq ON rq.PostId = tq.PostId
  LEFT JOIN (SELECT unnest(string_to_array(replace(tq.Tags, '<',''), '><')) AS TagName, tq.Id AS PostId
             FROM Posts tq) AS tmap ON tmap.PostId = tq.PostId
  LEFT JOIN TagMetrics rm ON rm.TagName = ANY(string_to_array(substr(tq.Tags, 2, length(tq.Tags)-2), '><'))
  LEFT JOIN Votes pv ON pv.PostId = tq.PostId
  LEFT JOIN Users uv ON pv.UserId = uv.Id
  WHERE tq.OwnerUserId IS NOT NULL
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
  CASE
    WHEN VoteTypeId = 2 THEN 1
    ELSE 0
  END AS UpvoteFlag,
  CASE
    WHEN VoteTypeId = 3 THEN 1
    ELSE 0
  END AS DownvoteFlag,
  TagName,
  TagCount,
  CASE WHEN pv.Id IS NOT NULL THEN pv.VoteTypeId ELSE NULL END AS VoteSchema,
  COALESCE(VoterReputation, 0) AS VoterReputation
FROM Joined
ORDER BY PostCreated DESC
LIMIT 200;