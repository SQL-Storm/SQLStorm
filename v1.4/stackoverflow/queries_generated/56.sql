-- {"query": "56.sql", "dataset": "stackoverflow", "version": "v1.4", "prompt": "p1", "model": "gpt-5-nano", "temperature": 1.0, "max_tokens": 32768, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 838} 
WITH recent_questions AS (
  SELECT
    p.Id AS PostId,
    p.Title,
    p.Tags,
    p.CreationDate,
    p.Score,
    p.ViewCount,
    p.OwnerUserId,
    p.LastActivityDate,
    p.FavoriteCount,
    p.CommentCount,
    (SELECT COUNT(*) FROM Posts a WHERE a.ParentId = p.Id) AS ChildCount,
    (SELECT MAX(v.CreationDate) FROM Votes v WHERE v.PostId = p.Id AND v.VoteTypeId = 2) AS LastUpVoteDate
  FROM Posts p
  WHERE p.PostTypeId = 1
),
tag_popularity AS (
  SELECT
    unnest(string_to_array(substr(t.Tags, 2, length(t.Tags)-2), '><')) AS TagName,
    SUM(t.Score) AS TagScore,
    SUM(t.ViewCount) AS TagViews,
    COUNT(*) AS TagPostCount,
    MAX(t.LastActivityDate) AS LastActivity
  FROM Posts t
  WHERE t.PostTypeId = 1
  GROUP BY TagName
),
complex_derived AS (
  SELECT
    r.PostId,
    r.Title,
    r.CreationDate,
    r.ViewCount,
    r.Score,
    r.CommentCount,
    r.FavoriteCount,
    r.ChildCount,
    r.LastUpVoteDate,
    COALESCE(vt.TotalUpvotes, 0) AS TotalUpvotes,
    COALESCE(vt.TotalDownvotes, 0) AS TotalDownvotes,
    CASE
      WHEN r.OwnerUserId IS NULL THEN 'anonymous'
      ELSE (SELECT DisplayName FROM Users u WHERE u.Id = r.OwnerUserId)
    END AS OwnerDisplayNameAlias,
    COALESCE(NULLIF(r.Tags, ''), '<no-tags>') AS TagsSnapshot
  FROM recent_questions r
  LEFT JOIN (
    SELECT
      p.Id AS PostId,
      SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS TotalUpvotes,
      SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS TotalDownvotes
    FROM Posts p
    LEFT JOIN Votes v ON v.PostId = p.Id
    GROUP BY p.Id
  ) vt ON vt.PostId = r.PostId
),
windowed AS (
  SELECT
    c.*,
    ROW_NUMBER() OVER (PARTITION BY OwnerUserId ORDER BY CreationDate DESC) AS rn_by_user,
    RANK() OVER (ORDER BY (Score + Coalesce(ViewCount,0)/10.0) DESC, LastActivityDate DESC) AS overall_rank
  FROM complex_derived c
)
SELECT
  w.PostId,
  w.Title,
  w.TagsSnapshot,
  w.CreationDate,
  w.ViewCount,
  w.Score,
  w.CommentCount,
  w.FavoriteCount,
  w.ChildCount,
  w.LastUpVoteDate,
  w.TotalUpvotes,
  w.TotalDownvotes,
  w.OwnerDisplayNameAlias,
  w.LastActivityDate,
  w.overall_rank,
  CASE
    WHEN w.TotalUpvotes > 50 AND w.TotalDownvotes < 5 THEN true
    ELSE false
  END AS HighlyActive,
  CASE
    WHEN w.rn_by_user <= 3 THEN 'Top per user'
    WHEN w.overall_rank <= 10 THEN 'Top 10 overall'
    ELSE 'Other'
  END AS RankingCategory
FROM windowed w
LEFT JOIN LATERAL (
  SELECT array_agg(t.Name) AS TagNames
  FROM unnest(string_to_array(substr(w.TagsSnapshot, 2, length(w.TagsSnapshot)-2), '><')) AS t(Name)
  JOIN Tags tg ON tg.TagName = t.Name
  WHERE tg.IsModeratorOnly = 0
) z ON true
WHERE w.overall_rank <= 100
ORDER BY w.overall_rank, w.CreationDate DESC;