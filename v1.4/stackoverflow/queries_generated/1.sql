-- {"query": "1.sql", "dataset": "stackoverflow", "version": "v1.4", "prompt": "p1", "model": "gpt-5-nano", "temperature": 1.0, "max_tokens": 32768, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 860} 
WITH
RecentHot AS (
  SELECT
    p.Id AS PostId,
    p.Title,
    p.Tags,
    p.OwnerUserId,
    p.CreationDate,
    p.Score,
    p.ViewCount,
    p.LastActivityDate,
    ARRAY_AGG(vt.Name) FILTER (WHERE v.IsAnswered IS TRUE) AS TagNames
  FROM
    Posts p
  LEFT JOIN LATERAL (
    SELECT DISTINCT vt.Name
    FROM Votes v
    JOIN VoteTypes vt ON vt.Id = v.VoteTypeId
    WHERE v.PostId = p.Id
      AND vt.Name IN ('UpMod', 'AcceptedByOriginator')
  ) v ON true
  LEFT JOIN LATERAL (
    SELECT true AS IsAnswered
  ) v2 ON true
  WHERE
    p.PostTypeId = 1 -- questions
    AND p.ClosedDate IS NULL
  GROUP BY p.Id
),
Expanded AS (
  SELECT
    ph.Id AS HistoryId,
    ph.PostId,
    ph.PostHistoryTypeId,
    ph.CreationDate AS HistoryDate,
    ph.UserId AS EditorUserId,
    ph.UserDisplayName AS EditorDisplayName,
    ph.Comment,
    ph.Text
  FROM PostHistory ph
  WHERE ph.PostHistoryTypeId IN (10, 16, 50, 52, 53) -- close, community bump, hot network flags, etc.
),
Joined AS (
  SELECT
    rh.PostId,
    rh.Title,
    rh.Tags,
    rh.OwnerUserId,
    rh.CreationDate AS PostDate,
    rh.Score,
    rh.ViewCount,
    rh.LastActivityDate,
    ph.HistoryDate,
    ph.EditorUserId,
    ph.EditorDisplayName,
    ph.Comment,
    ph.Text
  FROM RecentHot rh
  LEFT JOIN Expanded ph ON ph.PostId = rh.PostId
),
Wider AS (
  SELECT
    j.PostId,
    j.Title,
    j.Tags,
    j.OwnerUserId,
    u.DisplayName AS OwnerDisplayName,
    u.Reputation,
    j.PostDate,
    j.Score,
    j.ViewCount,
    j.LastActivityDate,
    (SELECT COUNT(*) FROM Comments c WHERE c.PostId = j.PostId) AS CommentCount,
    (SELECT COUNT(*) FROM Posts p2 WHERE p2.ParentId = j.PostId) AS AnswerCount,
    ARRAY_AGG(DISTINCT vt.Name) FILTER (WHERE vt.Name IS NOT NULL) AS EditVoteTypes
  FROM Joined j
  LEFT JOIN Users u ON u.Id = j.OwnerUserId
  LEFT JOIN Votes v ON v.PostId = j.PostId
  LEFT JOIN VoteTypes vt ON vt.Id = v.VoteTypeId
  GROUP BY
    j.PostId, j.Title, j.Tags, j.OwnerUserId, u.DisplayName, u.Reputation, j.PostDate,
    j.Score, j.ViewCount, j.LastActivityDate, j.Comment
)
SELECT
  w.PostId,
  w.Title,
  w.Tags,
  w.OwnerDisplayName,
  w.Reputation AS OwnerReputation,
  w.PostDate,
  w.Score,
  w.ViewCount,
  w.LastActivityDate,
  w.CommentCount,
  w.AnswerCount,
  w.EditVoteTypes,
  -- sample derived metrics and complex expressions
  (CASE WHEN w.ViewCount > 1000 THEN 'HighVisibility' ELSE 'Normal' END) AS VisibilityBand,
  (COALESCE(w.Reputation, 0) + COALESCE((SELECT AVG(Reputation) FROM Users), 0)) AS CompositeInfluence,
  (SELECT COUNT(*) FROM Badges b WHERE b.UserId = (SELECT OwnerUserId FROM Posts p WHERE p.Id = w.PostId) AND b.Class = 1) AS GoldBadgesForOwner,
  EXISTS (SELECT 1 FROM PostLinks pl WHERE pl.PostId = w.PostId AND pl.RelatedPostId <> w.PostId) AS HasRelatedLinks
FROM Wider w
ORDER BY w.LastActivityDate DESC, w.Score DESC
LIMIT 100;