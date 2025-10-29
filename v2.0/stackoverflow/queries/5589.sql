-- {"query": "5589.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-5-nano", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 890}
WITH ranked_posts AS (
  SELECT
    p.Id AS PostId,
    p.Title,
    p.CreationDate,
    p.Score,
    p.ViewCount,
    p.Tags,
    p.OwnerUserId,
    p.LastActivityDate,
    p.PostTypeId,
    p.AcceptedAnswerId,
    p.ParentId,
    p.CommentCount,
    p.FavoriteCount,
    p.ContentLicense,
    u.Reputation,
    u.DisplayName AS OwnerDisplayName,
    u.CreationDate AS OwnerCreationDate,
    u.LastAccessDate AS OwnerLastAccessDate,
    u.Location AS OwnerLocation,
    u.Views AS OwnerViews,
    u.UpVotes AS OwnerUpVotes,
    u.DownVotes AS OwnerDownVotes,
    COALESCE(l.LinkedCount, 0) AS RelatedLinkedCount,
    COALESCE(v.UpModCount, 0) AS UpModCount,
    COALESCE(v.DownModCount, 0) AS DownModCount,
    CAST(DATE_PART('day', (TIMESTAMP '2024-10-01 12:34:56') - p.CreationDate) AS integer) AS AgeDays,
    ROW_NUMBER() OVER (PARTITION BY p.PostTypeId ORDER BY p.Score DESC, p.ViewCount DESC) AS rn
  FROM Posts p
  LEFT JOIN Users u ON p.OwnerUserId = u.Id
  LEFT JOIN (
    SELECT PostId, COUNT(*) AS LinkedCount
    FROM PostLinks
    WHERE LinkTypeId = 1
    GROUP BY PostId
  ) l ON p.Id = l.PostId
  LEFT JOIN (
    SELECT PostId,
           SUM(CASE WHEN VoteTypeId = 2 THEN 1 ELSE 0 END) AS UpModCount,
           SUM(CASE WHEN VoteTypeId = 3 THEN 1 ELSE 0 END) AS DownModCount
    FROM Votes
    GROUP BY PostId
  ) v ON p.Id = v.PostId
  WHERE p.PostTypeId IN (1, 2)
),
cte_hist AS (
  SELECT
    rp.PostId,
    rp.Title,
    rp.OwnerDisplayName,
    ph.Id AS HistId,
    ph.PostHistoryTypeId,
    ph.CreationDate AS HistDate,
    ph.Text AS HistText,
    ph.Comment
  FROM ranked_posts rp
  JOIN PostHistory ph ON ph.PostId = rp.PostId
  WHERE ph.PostHistoryTypeId IN (10, 11, 16, 50)
),
cte_tags AS (
  SELECT
    p.Id AS PostId,
    CAST(NULL AS VARCHAR) AS TagName,
    CAST(NULL AS INTEGER) AS Count
  FROM Posts p
  WHERE p.PostTypeId = 1
),
full_posts AS (
  SELECT
    rp.PostId,
    rp.Title,
    rp.OwnerDisplayName,
    rp.Reputation,
    rp.AgeDays,
    rp.Score,
    rp.ViewCount,
    rp.CommentCount,
    rp.FavoriteCount,
    rp.Tags,
    rp.RelatedLinkedCount,
    rp.UpModCount,
    rp.DownModCount,
    rp.rn,
    ph.HistId,
    ph.PostHistoryTypeId,
    ph.HistDate,
    ph.HistText,
    ph.Comment
  FROM ranked_posts rp
  LEFT JOIN cte_hist ph ON ph.PostId = rp.PostId
)
SELECT
  fp.PostId,
  fp.Title,
  fp.OwnerDisplayName,
  fp.Reputation,
  fp.AgeDays,
  fp.Score,
  fp.ViewCount,
  fp.CommentCount,
  fp.FavoriteCount,
  fp.Tags,
  fp.RelatedLinkedCount,
  fp.UpModCount,
  fp.DownModCount,
  fp.rn,
  fp.HistId,
  fp.PostHistoryTypeId,
  fp.HistDate,
  fp.HistText,
  fp.Comment
FROM full_posts fp
WHERE fp.rn <= 100
GROUP BY
  fp.PostId,
  fp.Title,
  fp.OwnerDisplayName,
  fp.Reputation,
  fp.AgeDays,
  fp.Score,
  fp.ViewCount,
  fp.CommentCount,
  fp.FavoriteCount,
  fp.Tags,
  fp.RelatedLinkedCount,
  fp.UpModCount,
  fp.DownModCount,
  fp.rn,
  fp.HistId,
  fp.PostHistoryTypeId,
  fp.HistDate,
  fp.HistText,
  fp.Comment
ORDER BY fp.AgeDays DESC, fp.Score DESC, fp.ViewCount DESC;