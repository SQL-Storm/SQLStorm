-- {"query": "6037.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p1", "model": "gpt-5-nano", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 1045} 
WITH
RecentActivePosts AS (
  SELECT
    p.Id,
    p.Title,
    p.OwnerUserId,
    p.CreationDate,
    p.LastActivityDate,
    p.ViewCount,
    p.Score,
    p.PostTypeId,
    p.Tags,
    p.ParentId,
    p.AcceptedAnswerId,
    p.CommentCount,
    p.FavoriteCount,
    p.Body,
    p.LastEditorUserId,
    p.LastEditDate,
    p.ContentLicense
  FROM Posts p
  WHERE p.LastActivityDate >= NOW() - INTERVAL '30 days'
),
TopAuthors AS (
  SELECT
    u.Id AS UserId,
    u.DisplayName,
    u.Reputation,
    u.CreationDate,
    u.LastAccessDate,
    u.Views,
    u.UpVotes,
    u.DownVotes,
    u.Location,
    u.AccountId,
    ROW_NUMBER() OVER (ORDER BY u.Reputation DESC, u.UpVotes DESC) AS rn
  FROM Users u
  WHERE u.Reputation > 1000
),
TagStats AS (
  SELECT
    t.TagName,
    t.Count,
    CAST(t.Count AS numeric) / NULLIF((SELECT COUNT(*) FROM Posts WHERE PostTypeId = 1), 0) AS tag_popularity
  FROM Tags t
  WHERE t.IsModeratorOnly = 0
),
ComplexFilters AS (
  SELECT
    pr.Id AS PostId,
    pr.Title,
    pr.OwnerUserId,
    pr.CreationDate,
    pr.LastActivityDate,
    pr.ViewCount,
    pr.Score,
    pr.Tags,
    pr.CommentCount,
    COALESCE(vs.TotalUpvotes, 0) AS TotalUpvotesForPost,
    COALESCE(vs.TotalDownvotes, 0) AS TotalDownvotesForPost,
    CASE
      WHEN pr.OwnerUserId IS NOT NULL THEN u.DisplayName
      ELSE pr.OwnerDisplayName
    END AS DisplayNameAlias,
    CASE
      WHEN pr.ParentId IS NULL THEN 'Root'
      ELSE 'Child'
    END AS PostRole
  FROM Posts pr
  LEFT JOIN (
    SELECT
      PostId,
      SUM(CASE WHEN VT.Id = 2 THEN 1 ELSE 0 END) AS TotalUpvotes,
      SUM(CASE WHEN VT.Id = 3 THEN 1 ELSE 0 END) AS TotalDownvotes
    FROM Votes V
    JOIN VoteTypes VT ON V.VoteTypeId = VT.Id
    GROUP BY PostId
  ) vs ON pr.Id = vs.PostId
  LEFT JOIN Users u ON pr.OwnerUserId = u.Id
  WHERE pr.PostTypeId IN (1, 2) -- questions and answers
    AND pr.Score > -5
    AND pr.ViewCount > 0
    AND pr.LastActivityDate >= NOW() - INTERVAL '60 days'
),
Aggregated AS (
  SELECT
    cr.PostId,
    cr.Title,
    cr.OwnerUserId,
    cr.CreationDate,
    cr.LastActivityDate,
    cr.ViewCount,
    cr.Score,
    cr.Tags,
    cr.CommentCount,
    cr.TotalUpvotesForPost,
    cr.TotalDownvotesForPost,
    cr.DisplayNameAlias,
    cr.PostRole,
    pg.LastEditorDisplayName,
    pg.LastEditDate,
    pg.ContentLicense
  FROM ComplexFilters cr
  LEFT JOIN Posts lg ON cr.PostId = lg.Id
  LEFT JOIN (
    SELECT
      p.Id,
      p.LastEditorDisplayName,
      p.LastEditDate,
      p.ContentLicense
    FROM Posts p
  ) pg ON cr.PostId = pg.Id
),
Windowed AS (
  SELECT
    a.*,
    ROW_NUMBER() OVER (
      PARTITION BY a.OwnerUserId
      ORDER BY a.LastActivityDate DESC, a.Score DESC
    ) AS rn_owner
  FROM Aggregated a
)
SELECT
  w.PostId,
  w.Title,
  w.OwnerUserId,
  w.DisplayNameAlias,
  w.LastActivityDate,
  w.ViewCount,
  w.Score,
  w.Tags,
  w.CommentCount,
  w.TotalUpvotesForPost,
  w.TotalDownvotesForPost,
  w.PostRole,
  w.LastEditorDisplayName,
  w.LastEditDate,
  w.ContentLicense,
  ra.rn AS rank_in_recent,
  ta.rn AS rank_in_top_authors,
  ts.tag_popularity
FROM Windowed w
LEFT JOIN (
  SELECT Id, ROW_NUMBER() OVER (ORDER BY LastActivityDate DESC) AS rn
  FROM PostHistory
  WHERE PostHistoryTypeId = 16 -- Community Owned
) ra ON w.PostId = ra.Id
LEFT JOIN TopAuthors ta ON w.OwnerUserId = ta.UserId
LEFT JOIN TagStats ts ON w.Tags LIKE '%' || ts.TagName || '%' 
WHERE w.rn_owner <= 50
ORDER BY w.LastActivityDate DESC, w.Score DESC
LIMIT 100;