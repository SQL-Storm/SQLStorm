-- {"query": "5355.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-5-nano", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 799} 
WITH
  recent_questions AS (
    SELECT
      p.Id AS PostId,
      p.Title,
      p.Tags,
      p.CreationDate,
      p.Score,
      p.ViewCount,
      p.OwnerUserId,
      p.LastActivityDate,
      p.CommentCount,
      p.AnswerCount
    FROM Posts p
    WHERE p.PostTypeId = 1 -- Question
      AND p.CreationDate >= CURRENT_DATE - INTERVAL '90 days'
  ),
  author_stats AS (
    SELECT
      u.Id AS UserId,
      u.DisplayName,
      u.Reputation,
      u.CreationDate AS UserCreationDate,
      u.LastAccessDate,
      u.Views,
      u.UpVotes,
      u.DownVotes,
      u.Location,
      u.ProfileImageUrl,
      COALESCE(b.TotalBadges, 0) AS BadgeCount
    FROM Users u
    LEFT JOIN (
      SELECT UserId, COUNT(*) AS TotalBadges
      FROM Badges
      GROUP BY UserId
    ) b ON b.UserId = u.Id
  ),
  tag_hotness AS (
    SELECT
      t.TagName,
      t.Count,
      t.CreatedAt
    FROM Tags t
    CROSS JOIN LATERAL (
      SELECT NOW() -- dummy to allow potential time-based calculations
    ) AS d
  ),
  enriched AS (
    SELECT
      rq.PostId,
      rq.Title,
      rq.Tags,
      rq.CreationDate,
      rq.Score,
      rq.ViewCount,
      rq.OwnerUserId,
      rq.LastActivityDate,
      rq.CommentCount,
      rq.AnswerCount,
      asrc.DisplayName AS OwnerDisplayName,
      aa.Reputation AS OwnerReputation,
      COALESCE(vs.UpModCount, 0) AS UpModCount
    FROM recent_questions rq
    LEFT JOIN Users asrc ON rq.OwnerUserId = asrc.Id
    LEFT JOIN author_stats aa ON rq.OwnerUserId = aa.UserId
    LEFT JOIN (
      SELECT PostId, COUNT(*) AS UpModCount
      FROM Votes
      WHERE VoteTypeId = 2 -- UpMod
      GROUP BY PostId
    ) vs ON rq.PostId = vs.PostId
  ),
  correlated AS (
    SELECT
      e.PostId,
      e.Title,
      e.Tags,
      e.CreationDate,
      e.Score,
      e.ViewCount,
      e.OwnerUserId,
      e.LastActivityDate,
      e.CommentCount,
      e.AnswerCount,
      e.OwnerDisplayName,
      e.OwnerReputation,
      e.UpModCount,
      (SELECT COUNT(*) FROM Comments c WHERE c.PostId = e.PostId) AS CommentCountTotal,
      (SELECT MAX(c.CreationDate) FROM Comments c WHERE c.PostId = e.PostId) AS LastCommentDate
    FROM enriched e
  ),
  windowed AS (
    SELECT
      c.*,
      ROW_NUMBER() OVER (
        PARTITION BY c.OwnerUserId
        ORDER BY c.LastActivityDate DESC
      ) AS rn_by_author
    FROM correlated c
  )
SELECT
  w.PostId,
  w.Title,
  w.Tags,
  w.CreationDate,
  w.Score,
  w.ViewCount,
  w.OwnerUserId,
  w.OwnerDisplayName,
  w.OwnerReputation,
  w.LastActivityDate,
  w.CommentCount,
  w.AnswerCount,
  w.CommentCountTotal,
  w.LastCommentDate,
  w.UpModCount
FROM windowed w
WHERE w.rn_by_author <= 5
  AND w.ViewCount > 0
  AND (w.Score > 0 OR w.UpModCount > 0)
ORDER BY w.LastActivityDate DESC, w.ViewCount DESC
LIMIT 100;