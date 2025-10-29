-- {"query": "5434.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-5-nano", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 965} 
WITH flagged_inactive_users AS (
  SELECT
    u.Id AS UserId,
    u.DisplayName,
    u.Reputation,
    u.CreationDate,
    u.LastAccessDate,
    u.Views,
    u.UpVotes,
    u.DownVotes,
    u.ProfileImageUrl,
    u.EmailHash,
    u.AccountId,
    ROW_NUMBER() OVER (PARTITION BY u.Id ORDER BY u.LastAccessDate DESC) AS rn
  FROM Users u
  LEFT JOIN Posts p ON p.OwnerUserId = u.Id
  LEFT JOIN Votes v ON v.UserId = u.Id
  LEFT JOIN PostHistory ph ON ph.UserId = u.Id
  WHERE u.LastAccessDate < NOW() - INTERVAL '180 days'
    OR (u.Views < 10 AND u.Reputation < 100)
),
recent_high_activity AS (
  SELECT
    u.Id AS UserId,
    COUNT(p.Id) AS post_count,
    MAX(p.CreationDate) AS last_post_date
  FROM Users u
  LEFT JOIN Posts p ON p.OwnerUserId = u.Id
  GROUP BY u.Id
  HAVING COUNT(p.Id) >= 5
),
top_tags AS (
  SELECT
    t.TagName,
    COUNT(*) AS tag_count
  FROM Tags t
  WHERE t.TagName IS NOT NULL
  GROUP BY t.TagName
  ORDER BY tag_count DESC
  LIMIT 5
),
complex_post_insight AS (
  SELECT
    p.Id AS PostId,
    p.Title,
    p.PostTypeId,
    p.Score,
    p.ViewCount,
    p.CreationDate,
    p.LastActivityDate,
    p.OwnerUserId,
    COALESCE(p.AcceptedAnswerId, -1) AS AcceptedAnswerId,
    (SELECT COUNT(*) FROM Comments c WHERE c.PostId = p.Id) AS CommentCount,
    (SELECT COUNT(*) FROM Votes v WHERE v.PostId = p.Id AND v.VoteTypeId = 2) AS UpVotesForPost,
    (SELECT COUNT(*) FROM Votes v WHERE v.PostId = p.Id AND v.VoteTypeId = 3) AS DownVotesForPost,
    STRING_AGG(DISTINCT CAST(tt.Id AS varchar) || ':' || tt.Name, ',') AS VoteTypesAvailable
  FROM Posts p
  LEFT JOIN Votes v ON v.PostId = p.Id
  LEFT JOIN VoteTypes tt ON v.VoteTypeId = tt.Id
  GROUP BY p.Id, p.Title, p.PostTypeId, p.Score, p.ViewCount, p.CreationDate, p.LastActivityDate, p.OwnerUserId, p.AcceptedAnswerId
),
joined_activity AS (
  SELECT
    c.PostId,
    c.Title,
    c.PostTypeId,
    c.Score,
    c.ViewCount,
    c.CreationDate,
    c.LastActivityDate,
    c.OwnerUserId,
    c.AcceptedAnswerId,
    c.CommentCount,
    c.UpVotesForPost,
    c.DownVotesForPost,
    c.VoteTypesAvailable,
    l.RelatedPostId,
    lt.Name AS LinkTypeName
  FROM complex_post_insight c
  LEFT JOIN PostLinks l ON l.PostId = c.PostId
  LEFT JOIN LinkTypes lt ON l.LinkTypeId = lt.Id
),
windowed AS (
  SELECT
    ja.*,
    ROW_NUMBER() OVER (
      PARTITION BY ja.OwnerUserId
      ORDER BY ja.LastActivityDate DESC, ja.Score DESC
    ) AS rn_user
  FROM joined_activity ja
),
final AS (
  SELECT
    w.*,
    ph.PostHistoryTypeId AS HistoryTypeId,
    ph.Text AS HistoryText,
    ph.CreationDate AS HistoryDate,
    ph.UserId AS HistoryUser
  FROM windowed w
  LEFT JOIN PostHistory ph ON ph.PostId = w.PostId
  WHERE w.rn_user <= 3
)
SELECT
  f.PostId,
  f.Title,
  f.PostTypeId,
  f.Score,
  f.ViewCount,
  f.CreationDate,
  f.LastActivityDate,
  f.OwnerUserId,
  f.AcceptedAnswerId,
  f.CommentCount,
  f.UpVotesForPost,
  f.DownVotesForPost,
  f.VoteTypesAvailable,
  f.RelatedPostId,
  f.LinkTypeName,
  f.HistoryTypeId,
  f.HistoryText,
  f.HistoryDate,
  f.HistoryUser
FROM final f
ORDER BY f.LastActivityDate DESC, f.Score DESC
LIMIT 100;