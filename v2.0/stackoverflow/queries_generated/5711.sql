-- {"query": "5711.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-5-nano", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 1029} 
WITH recent_activity AS (
  SELECT
    p.Id AS PostId,
    p.PostTypeId,
    p.Title,
    p.Tags,
    p.CreationDate,
    p.Score,
    p.ViewCount,
    p.OwnerUserId,
    p.LastActivityDate,
    p.LastEditorUserId,
    p.AcceptedAnswerId,
    p.ParentId,
    p.CommentCount,
    COALESCE(p.FavoriteCount, 0) AS FavoriteCount,
    JSON_EXTRACT_PATH_TEXT(
      SUBSTITUTE(p.Body, E'\"', '\"'),
      '$.length'
    ) AS BodyPreview
  FROM Posts p
  WHERE p.CreationDate >= NOW() - INTERVAL '180 days'
),
owner_info AS (
  SELECT
    u.Id AS UserId,
    u.DisplayName,
    u.Reputation,
    u.AccountId,
    u.CreationDate AS UserCreationDate,
    u.LastAccessDate,
    u.Location,
    u.WebsiteUrl,
    u.AboutMe,
    u.Views,
    u.UpVotes,
    u.DownVotes,
    u.ProfileImageUrl,
    u.EmailHash
  FROM Users u
),
tag_analytics AS (
  SELECT
    t.TagName,
           COUNT(*) AS TagQuestionCount,
           AVG(p.Score) FILTER (WHERE p.PostTypeId = 1) AS AvgQuestionScore,
           AVG(p.ViewCount) AS AvgViewCount
  FROM Tags t
  LEFT JOIN Posts p
    ON p.Id = t.WikiPostId
  GROUP BY t.TagName
),
complex_join AS (
  SELECT
    ro.PostId,
    ro.Title,
    ro.Tags,
    ro.CreationDate,
    ro.Score,
    ro.ViewCount,
    oi.DisplayName AS OwnerDisplayName,
    oi.Reputation,
    oi.Location,
    (
      SELECT COUNT(*) FROM Posts AS a
      WHERE a.OwnerUserId = ro.OwnerUserId
        AND a.PostTypeId = 1
        AND a.CreationDate >= ro.CreationDate - INTERVAL '365 days'
    ) AS OwnerQuestionCount,
    (
      SELECT COUNT(*) FROM Comments c
      WHERE c.PostId = ro.PostId
    ) AS CommentCountForPost,
    (
      SELECT ARRAY_AGG(v.VoteTypeId) FROM Votes v
      WHERE v.PostId = ro.PostId
        AND v.CreationDate >= ro.CreationDate
    ) AS VoteTypesOnPost,
    (
      SELECT COUNT(*) FROM PostLinks pl
      WHERE pl.PostId = ro.PostId
        AND pl.LinkTypeId = 1
    ) AS LinkedPostCount
  FROM recent_activity ro
  LEFT JOIN owner_info oi ON ro.OwnerUserId = oi.UserId
),
warning_window AS (
  SELECT
    cp.PostId,
    cp.OwnerDisplayName,
    cp.OwnerQuestionCount,
    cp.CommentCountForPost,
    cp.LinkedPostCount,
    cp.VoteTypesOnPost,
    CASE
      WHEN pg_score IS NULL THEN ROW(0,0)
      ELSE ROW(SUM(CASE WHEN vtp = 2 THEN 1 ELSE 0 END) OVER (PARTITION BY cp.PostId),
               SUM(CASE WHEN vtp = 3 THEN 1 ELSE 0 END) OVER (PARTITION BY cp.PostId))
    END AS UpDownBalance
  FROM complex_join cp
  LEFT JOIN LATERAL (
    SELECT unnest(cp.VoteTypesOnPost) AS vtp
  ) AS v ON true
  CROSS JOIN (SELECT 1 AS pg_score) AS dummy
)
SELECT
  rp.PostId,
  rp.Title,
  rp.CreationDate,
  rp.ViewCount,
  rp.Score,
  rp.Tags,
  rp.OwnerDisplayName,
  rp.Reputation,
  rp.Location,
  rp.CommentCountForPost,
  rb.TotalUp AS UpVotes,
  rb.TotalDown AS DownVotes,
  wb.UpDownBalance,
  (SELECT STRING_AGG(tt.Name, ',') FROM (
     SELECT DISTINCT vt.Name
     FROM Votes v
     JOIN VoteTypes vt ON vt.Id = v.VoteTypeId
     WHERE v.PostId = rp.PostId
  ) AS tt) AS DistinctVoteTypesOnPost
FROM warning_window wb
JOIN Votes vb ON vb.PostId = wb.PostId
JOIN Posts rp ON rp.Id = wb.PostId
LEFT JOIN (
  SELECT
    vp.PostId,
    SUM(CASE WHEN vt.Id = 2 THEN 1 ELSE 0 END) AS TotalUp,
    SUM(CASE WHEN vt.Id = 3 THEN 1 ELSE 0 END) AS TotalDown
  FROM Votes vp
  JOIN VoteTypes vt ON vt.Id = vp.VoteTypeId
  GROUP BY vp.PostId
) rb ON rb.PostId = rp.Id
ORDER BY rp.CreationDate DESC
LIMIT 100;