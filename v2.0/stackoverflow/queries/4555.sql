-- {"query": "4555.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-flash-lite", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 1381}
WITH
  RankedPostEdits AS (
    SELECT
      ph.PostId,
      ph.PostHistoryTypeId,
      ph.UserId,
      ph.CreationDate,
      ROW_NUMBER() OVER (PARTITION BY ph.PostId, ph.PostHistoryTypeId ORDER BY ph.CreationDate DESC) AS rn
    FROM PostHistory ph
    WHERE
      ph.PostHistoryTypeId IN (4, 5, 6)
  ),
  LatestEdits AS (
    SELECT
      rpe.PostId,
      rpe.UserId AS LastEditorUserId,
      rpe.CreationDate AS LastEditDate
    FROM RankedPostEdits rpe
    WHERE
      rpe.rn = 1
  ),
  UserPostCounts AS (
    SELECT
      p.OwnerUserId,
      COUNT(p.Id) AS TotalPostsOwned,
      SUM(CASE WHEN p.PostTypeId = 1 THEN 1 ELSE 0 END) AS QuestionsOwned,
      SUM(CASE WHEN p.PostTypeId = 2 THEN 1 ELSE 0 END) AS AnswersOwned
    FROM Posts p
    WHERE
      p.OwnerUserId IS NOT NULL AND p.OwnerUserId > 0
    GROUP BY
      p.OwnerUserId
  ),
  PostVoteAnalysis AS (
    SELECT
      p.Id AS PostId,
      COUNT(CASE WHEN v.VoteTypeId = 2 THEN 1 END) AS UpVoteCount,
      COUNT(CASE WHEN v.VoteTypeId = 3 THEN 1 END) AS DownVoteCount,
      COUNT(CASE WHEN v.VoteTypeId = 5 THEN 1 END) AS FavoriteCount
    FROM Posts p
    LEFT JOIN Votes v
      ON p.Id = v.PostId
    GROUP BY
      p.Id
  ),
  CommunityContent AS (
    SELECT
      p.Id AS PostId,
      p.CommunityOwnedDate
    FROM Posts p
    WHERE
      p.CommunityOwnedDate IS NOT NULL
  )
SELECT
  COALESCE(p.Id, cc.PostId) AS PostIdentifier,
  pt.Name AS PostTypeName,
  u.DisplayName AS OwnerDisplayName,
  u.DisplayName AS LastEditorDisplayName,
  le.LastEditDate,
  p.Title,
  p.Tags,
  p.Score,
  pva.UpVoteCount,
  pva.DownVoteCount,
  pva.FavoriteCount,
  upc.TotalPostsOwned,
  upc.QuestionsOwned,
  upc.AnswersOwned,
  CASE
    WHEN cc.PostId IS NOT NULL THEN 'Community Owned'
    WHEN p.ClosedDate IS NOT NULL THEN 'Closed'
    WHEN p.ParentId IS NOT NULL THEN 'Answer'
    ELSE 'Question'
  END AS PostStatusCategory,
  CASE
    WHEN p.OwnerUserId IS NOT NULL THEN u.Reputation
    ELSE 0
  END AS OwnerReputation,
  CASE
    WHEN p.OwnerUserId IS NOT NULL THEN u.CreationDate
    ELSE TIMESTAMP '1970-01-01 00:00:00'
  END AS OwnerCreationDate,
  (
    SELECT
      COUNT(*)
    FROM Comments c
    WHERE
      c.PostId = COALESCE(p.Id, cc.PostId) AND c.CreationDate > COALESCE(p.LastActivityDate, cc.CommunityOwnedDate)
  ) AS CommentsAfterLastActivity,
  COALESCE(p.AnswerCount, 0) AS AnswerCount,
  COALESCE(p.CommentCount, 0) AS CommentCount,
  COALESCE(p.FavoriteCount, 0) AS PostFavoriteCount,
  COALESCE(p.ViewCount, 0) AS PostViewCount,
  'Post Performance Metric' AS MetricType
FROM Posts p
FULL OUTER JOIN CommunityContent cc
  ON p.Id = cc.PostId
LEFT JOIN PostTypes pt
  ON p.PostTypeId = pt.Id
LEFT JOIN Users u
  ON p.OwnerUserId = u.Id
LEFT JOIN LatestEdits le
  ON COALESCE(p.Id, cc.PostId) = le.PostId
LEFT JOIN UserPostCounts upc
  ON COALESCE(p.OwnerUserId, u.Id) = upc.OwnerUserId
LEFT JOIN PostVoteAnalysis pva
  ON COALESCE(p.Id, cc.PostId) = pva.PostId
WHERE
  pt.Name IN ('Question', 'Answer') AND COALESCE(p.Score, 0) > 0

UNION

SELECT
  NULL AS PostIdentifier,
  'Tag Wiki Excerpt' AS PostTypeName,
  NULL AS OwnerDisplayName,
  NULL AS LastEditorDisplayName,
  NULL AS LastEditDate,
  t.TagName AS Title,
  t.TagName AS Tags,
  p.Score,
  pva.UpVoteCount,
  pva.DownVoteCount,
  pva.FavoriteCount,
  NULL AS TotalPostsOwned,
  NULL AS QuestionsOwned,
  NULL AS AnswersOwned,
  'Tag Information' AS PostStatusCategory,
  NULL AS OwnerReputation,
  NULL AS OwnerCreationDate,
  (
    SELECT
      COUNT(*)
    FROM Comments c
    WHERE
      c.PostId = p.Id AND c.CreationDate > p.LastActivityDate
  ) AS CommentsAfterLastActivity,
  NULL AS AnswerCount,
  p.CommentCount,
  NULL AS PostFavoriteCount,
  p.ViewCount AS PostViewCount,
  'Tag Performance Metric' AS MetricType
FROM Posts p
JOIN Tags t
  ON p.Id = t.ExcerptPostId
LEFT JOIN PostVoteAnalysis pva
  ON p.Id = pva.PostId
WHERE
  t.ExcerptPostId IS NOT NULL AND p.Score > 0
ORDER BY
  PostIdentifier NULLS LAST,
  MetricType;