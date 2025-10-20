-- {"query": "131.sql", "dataset": "stackoverflow", "version": "v1.4", "prompt": "p1", "model": "gpt-5-nano", "temperature": 1.0, "max_tokens": 32768, "reasoning": "low", "input_tokens": 2026, "output_tokens": 1810} 
WITH
PostsWithCounts AS (
  SELECT
    p.Id AS PostId,
    p.Title,
    p.PostTypeId,
    p.OwnerUserId,
    p.CreationDate,
    p.LastActivityDate,
    p.Score,
    p.ViewCount,
    p.Tags,
    (SELECT COUNT(*) FROM Comments c WHERE c.PostId = p.Id) AS CommentCount,
    (SELECT COUNT(*) FROM PostLinks pl WHERE pl.PostId = p.Id AND pl.LinkTypeId = 1) AS LinkedCount,
    (SELECT COUNT(*) FROM PostLinks pl WHERE pl.RelatedPostId = p.Id AND pl.LinkTypeId = 1) AS LinkedToCount
  FROM Posts p
  WHERE p.Active = 1 OR p.Active IS NULL -- simulate robustness against NULLs in a workload
),
OwnerStats AS (
  SELECT
    u.Id AS UserId,
    u.DisplayName,
    u.Reputation,
    u.CreationDate AS UserCreationDate,
    u.LastAccessDate,
    ROW_NUMBER() OVER (PARTITION BY u.Id ORDER BY u.Reputation DESC, u.CreationDate DESC) AS rn_by_rep
  FROM Users u
),
TaggedHot AS (
  SELECT
    p.PostId,
    p.OwnerUserId,
    p.Title,
    p.CreationDate,
    p.LastActivityDate,
    p.Score,
    p.ViewCount,
    p.CommentCount,
    p.LinkedCount,
    p.LinkedToCount,
    ot.rn_by_rep,
    CASE
      WHEN p.Score > 0 THEN 1
      ELSE 0
    END AS PositiveScoreFlag
  FROM PostsWithCounts p
  LEFT JOIN OwnerStats ot ON p.OwnerUserId = ot.UserId
  WHERE p.LastActivityDate > p.CreationDate - INTERVAL '7 days'
  WINDOW w AS (ORDER BY p.Score DESC, p.ViewCount DESC)
),
ScoreRank AS (
  SELECT
    th.PostId,
    th.OwnerUserId,
    th.Title,
    th.CreationDate,
    th.LastActivityDate,
    th.Score,
    th.ViewCount,
    th.CommentCount,
    th.LinkedCount,
    th.LinkedToCount,
    th.PositiveScoreFlag,
    ROW_NUMBER() OVER (ORDER BY th.Score DESC NULLS LAST, th.ViewCount DESC NULLS LAST, th.LastActivityDate DESC NULLS LAST) AS ScoreRank
  FROM TaggedHot th
),
RecentTags AS (
  SELECT
    t.PostId,
    t.OwnerUserId,
    t.Title,
    t.CreationDate,
    t.LastActivityDate,
    t.Score,
    t.ViewCount,
    t.CommentCount,
    t.LinkedCount,
    t.LinkedToCount,
    t.ScoreRank,
    STRING_AGG(DISTINCT tag.TagName, ',') FILTER (WHERE tag.TagName IS NOT NULL) AS TagNames
  FROM ScoreRank t
  LEFT JOIN UNNEST(string_to_array(t.Title, ' ')) AS token(tag) ON TRUE
  LEFT JOIN Tags tag ON tag.Id = (
    SELECT id FROM Tags tgs
    WHERE tgs.TagName ILIKE '%' || token.tag || '%'
    LIMIT 1
  )
  GROUP BY
    t.PostId, t.OwnerUserId, t.Title, t.CreationDate, t.LastActivityDate,
    t.Score, t.ViewCount, t.CommentCount, t.LinkedCount, t.LinkedToCount, t.ScoreRank
),
CorrelatedPosts AS (
  SELECT
    r.PostId,
    r.Title,
    r.OwnerUserId,
    r.TagNames,
    r.Score,
    r.ViewCount,
    r.CommentCount,
    r.LinkedCount,
    r.LinkedToCount,
    r.LastActivityDate,
    u.DisplayName AS OwnerDisplayName,
    u.Reputation
  FROM RecentTags r
  LEFT JOIN Users u ON r.OwnerUserId = u.Id
  WHERE r.ScoreRank <= 100
)
SELECT
  cp.PostId,
  cp.Title,
  cp.OwnerDisplayName,
  cp.Reputation,
  cp.Score,
  cp.ViewCount,
  cp.CommentCount,
  cp.LinkedCount,
  cp.LinkedToCount,
  cp.TagNames,
  cp.LastActivityDate
FROM CorrelatedPosts cp
ORDER BY cp.Score DESC NULLS LAST, cp.ViewCount DESC NULLS LAST
LIMIT 200;