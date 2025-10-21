WITH recent_top_users AS (
  SELECT
    u.Id,
    u.DisplayName,
    u.Reputation,
    u.CreationDate,
    u.LastAccessDate,
    ROW_NUMBER() OVER (ORDER BY u.Reputation DESC, u.LastAccessDate DESC) AS rn
  FROM Users u
  WHERE u.AccountId IS NOT NULL
),
top_questions AS (
  SELECT
    p.Id AS PostId,
    p.Title,
    p.CreationDate,
    p.OwnerUserId,
    p.Score,
    p.ViewCount,
    p.Tags,
    p.LastActivityDate,
    p.PostTypeId,
    COUNT(c.Id) AS CommentCount,
    SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS UpVotes,
    SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS DownVotes
  FROM Posts p
  LEFT JOIN Comments c ON c.PostId = p.Id
  LEFT JOIN Votes v ON v.PostId = p.Id
  WHERE p.PostTypeId = 1 -- Questions
    AND p.CreationDate >= cast('2024-10-01 12:34:56' as timestamp) - INTERVAL '180 days'
  GROUP BY
    p.Id,
    p.Title,
    p.CreationDate,
    p.OwnerUserId,
    p.Score,
    p.ViewCount,
    p.Tags,
    p.LastActivityDate,
    p.PostTypeId
),
hot_keywords AS (
  SELECT
    t.TagName,
    t.Count,
    t.IsModeratorOnly,
    t.IsRequired
  FROM Tags t
  WHERE t.IsModeratorOnly = FALSE
),
complex_metrics AS (
  SELECT
    q.PostId,
    q.Title,
    q.CreationDate,
    q.OwnerUserId,
    u.DisplayName AS OwnerDisplayName,
    q.Score,
    q.ViewCount,
    q.LastActivityDate,
    q.CommentCount,
    q.UpVotes,
    q.DownVotes,
    STRING_AGG(CONCAT('#', TRIM(REGEXP_REPLACE(q.Tags, '<|>|,', ''))), ',') FILTER (WHERE q.Tags IS NOT NULL) AS TagList,
    hd.TotalEdits,
    rd.TotalReverts,
    CASE
      WHEN q.CommentCount > 0 AND q.UpVotes > q.DownVotes THEN 'Active'
      WHEN q.UpVotes = q.DownVotes THEN 'Balanced'
      ELSE 'Dormant'
    END AS ActivityStatus
  FROM top_questions q
  LEFT JOIN Users u ON u.Id = q.OwnerUserId
  LEFT JOIN (
    SELECT p.Id, COUNT(*) AS TotalEdits
    FROM Posts p
    JOIN PostHistory ph ON ph.PostId = p.Id
    WHERE ph.PostHistoryTypeId IN (4,5,6,10,11,12,13,14,15,16)
    GROUP BY p.Id
  ) hd ON hd.Id = q.PostId
  LEFT JOIN (
    SELECT p.Id, COUNT(*) AS TotalReverts
    FROM Posts p
    JOIN PostHistory ph ON ph.PostId = p.Id
    WHERE ph.PostHistoryTypeId IN (11, 12, 13)
    GROUP BY p.Id
  ) rd ON rd.Id = q.PostId
  GROUP BY
    q.PostId,
    q.Title,
    q.CreationDate,
    q.OwnerUserId,
    u.DisplayName,
    q.Score,
    q.ViewCount,
    q.LastActivityDate,
    q.CommentCount,
    q.UpVotes,
    q.DownVotes,
    q.Tags,
    hd.TotalEdits,
    rd.TotalReverts
),
outer_joined AS (
  SELECT
    ct.PostId,
    ct.Title,
    ct.CreationDate,
    ct.OwnerUserId,
    ct.OwnerDisplayName,
    ct.Score,
    ct.ViewCount,
    ct.LastActivityDate,
    ct.CommentCount,
    ct.UpVotes,
    ct.DownVotes,
    ct.TagList,
    ct.TotalEdits,
    ct.TotalReverts,
    ct.ActivityStatus,
    CAST(pl.RelatedPostId AS integer) AS RelatedPostId,
    lt.Name AS LinkTypeName
  FROM complex_metrics ct
  LEFT JOIN PostLinks pl ON pl.PostId = ct.PostId
  LEFT JOIN LinkTypes lt ON lt.Id = pl.LinkTypeId
),
windowed AS (
  SELECT
    o.*,
    ROW_NUMBER() OVER (PARTITION BY OwnerUserId ORDER BY LastActivityDate DESC) AS rn_per_owner
  FROM outer_joined o
),
selected AS (
  SELECT *
  FROM windowed
  WHERE rn_per_owner = 1
)
SELECT
  s.PostId,
  s.Title,
  s.OwnerDisplayName,
  s.OwnerUserId,
  s.CreationDate,
  s.LastActivityDate,
  s.Score,
  s.ViewCount,
  s.CommentCount,
  s.UpVotes,
  s.DownVotes,
  s.TagList,
  s.TotalEdits,
  s.TotalReverts,
  s.ActivityStatus,
  s.RelatedPostId,
  s.LinkTypeName
FROM selected s
ORDER BY s.LastActivityDate DESC, s.Score DESC
LIMIT 100;