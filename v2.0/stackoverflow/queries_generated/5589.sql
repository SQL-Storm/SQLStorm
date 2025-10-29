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
    -- number of related posts via links (Linked/Duplicate)
    COALESCE(l.LinkedCount, 0) AS RelatedLinkedCount,
    -- number of votes by type for correlation
    COALESCE(v.UpModCount, 0) AS UpModCount,
    COALESCE(v.DownModCount, 0) AS DownModCount,
    -- window: days since creation and last activity
    DATE_DIFF('day', p.CreationDate, CURRENT_TIMESTAMP) AS AgeDays,
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
    SELECT PostId, SUM(CASE WHEN VoteTypeId = 2 THEN 1 ELSE 0 END) AS UpModCount,
                   SUM(CASE WHEN VoteTypeId = 3 THEN 1 ELSE 0 END) AS DownModCount
    FROM Votes
    GROUP BY PostId
  ) v ON p.Id = v.PostId
  WHERE p.PostTypeId IN (1, 2) -- Questions and Answers
),
cte_hist AS (
  SELECT
    p.PostId,
    p.Title,
    p.OwnerDisplayName,
    ph.Id AS HistId,
    ph.PostHistoryTypeId,
    ph.CreationDate AS HistDate,
    ph.Text AS HistText,
    ph.Comment
  FROM ranked_posts rp
  JOIN PostHistory ph ON ph.PostId = rp.PostId
  WHERE ph.PostHistoryTypeId IN (10, 11, 16, 50) -- Close, Reopen, CommunityOwned, CommunityBump
),
cte_tags AS (
  SELECT
    p.Id AS PostId,
    t.TagName,
    t.Count
  FROM Posts p
  LEFT JOIN Tags t ON t.Id = (
    SELECT CAST(JSON_VALUE(p.Tags, '$.tagid') AS int)
    -- placeholder for tag extraction; actual Tags column is a string; using LIKE to approximate
  )
  WHERE p.PostTypeId = 1
),
full AS (
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
  ORDER BY rp.rn, rp.PostId
)
SELECT
  PostId,
  Title,
  OwnerDisplayName,
  Reputation,
  AgeDays,
  Score,
  ViewCount,
  CommentCount,
  FavoriteCount,
  Tags,
  RelatedLinkedCount,
  UpModCount,
  DownModCount,
  rn,
  HistId,
  PostHistoryTypeId,
  HistDate,
  HistText,
  Comment
FROM full
WHERE rn <= 100
ORDER BY AgeDays DESC, Score DESC, ViewCount DESC;