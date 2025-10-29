-- {"query": "5684.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-5-nano", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 971}
WITH recent_posts AS (
  SELECT
    p.Id AS PostId,
    p.PostTypeId,
    p.OwnerUserId,
    p.Title,
    p.Tags,
    p.CreationDate,
    p.LastActivityDate,
    p.Score,
    p.ViewCount,
    p.CommentCount,
    p.AnswerCount,
    p.FavoriteCount,
    p.ContentLicense,
    p.ParentId,
    p.AcceptedAnswerId,
    p.LastEditorUserId,
    p.LastEditDate,
    p.OwnerDisplayName,
    p.LastEditorDisplayName
  FROM Posts p
  WHERE p.CreationDate >= CAST('2024-10-01 12:34:56' AS TIMESTAMP) - INTERVAL '60 days'
),
tag_stats AS (
  SELECT
    tag_extracted.TagName,
    COUNT(*) AS tag_question_count,
    AVG(p.Score) AS avg_score,
    SUM(p.ViewCount) AS total_views
  FROM (
    SELECT unnest(string_to_array(substring(p.Tags, 2, length(p.Tags) - 2), '><')) AS TagName, p.Id
    FROM Posts p
    WHERE p.PostTypeId = 1
      AND p.CreationDate >= CAST('2024-10-01 12:34:56' AS TIMESTAMP) - INTERVAL '60 days'
  ) AS tag_extracted
  JOIN Posts p ON p.Id = tag_extracted.Id
  GROUP BY tag_extracted.TagName
  ORDER BY tag_question_count DESC
  LIMIT 20
),
complex_pred AS (
  SELECT
    rp.PostId,
    rp.Title,
    rp.CreationDate,
    rp.Score,
    rp.ViewCount,
    rp.CommentCount,
    rp.AnswerCount,
    rr.Count AS related_posts,
    COALESCE(b.Name, 'None') AS badge_name,
    rp.OwnerUserId
  FROM recent_posts rp
  LEFT JOIN (
    SELECT PostId, COUNT(*) AS Count
    FROM PostLinks
    WHERE LinkTypeId = 1
    GROUP BY PostId
  ) rr ON rr.PostId = rp.PostId
  LEFT JOIN Badges b ON b.UserId = rp.OwnerUserId
  WHERE rp.Score > 0
    AND (rp.ViewCount > 100 OR rp.CommentCount > 5)
),
windowed AS (
  SELECT
    cp.PostId,
    cp.Title,
    cp.CreationDate,
    cp.Score,
    cp.ViewCount,
    cp.CommentCount,
    cp.AnswerCount,
    cp.related_posts,
    cp.badge_name,
    cp.OwnerUserId,
    ROW_NUMBER() OVER (PARTITION BY cp.PostId ORDER BY cp.CreationDate DESC) AS rn
  FROM complex_pred cp
),
outer_join_demo AS (
  SELECT
    w.PostId,
    w.Title,
    w.CreationDate,
    w.Score,
    w.ViewCount,
    w.CommentCount,
    w.AnswerCount,
    w.related_posts,
    w.badge_name,
    w.OwnerUserId,
    u.Reputation,
    u.DisplayName,
    v.TotalVotes
  FROM windowed w
  LEFT JOIN Users u ON u.Id = w.OwnerUserId
  LEFT JOIN (
    SELECT PostId, COUNT(*) AS TotalVotes
    FROM Votes
    WHERE CreationDate >= CAST('2024-10-01 12:34:56' AS TIMESTAMP) - INTERVAL '90 days'
    GROUP BY PostId
  ) v ON v.PostId = w.PostId
  WHERE w.rn = 1
    AND (u.Reputation IS NOT NULL)
),
final_series AS (
  SELECT
    oj.PostId,
    oj.Title,
    oj.CreationDate,
    oj.Score,
    oj.ViewCount,
    oj.CommentCount,
    oj.AnswerCount,
    oj.related_posts,
    oj.badge_name,
    oj.Reputation,
    oj.DisplayName,
    oj.TotalVotes,
    oj.OwnerUserId,
    (oj.Score * 1.0 / NULLIF(oj.ViewCount, 0)) AS score_per_view,
    CASE
      WHEN oj.TotalVotes IS NULL THEN 0
      ELSE array_length(string_to_array(oj.badge_name, ','), 1)
    END AS badge_name_length
  FROM outer_join_demo oj
)
SELECT
  fs.PostId,
  fs.Title,
  fs.CreationDate,
  fs.Score,
  fs.ViewCount,
  fs.CommentCount,
  fs.AnswerCount,
  fs.related_posts,
  fs.badge_name,
  fs.Reputation,
  fs.DisplayName,
  fs.TotalVotes,
  fs.score_per_view,
  fs.badge_name_length,
  (
    SELECT AVG(p2.Score)
    FROM Posts p2
    WHERE p2.OwnerUserId = fs.OwnerUserId
      AND p2.CreationDate >= CAST('2024-10-01 12:34:56' AS TIMESTAMP) - INTERVAL '90 days'
  ) AS avg_owner_score_90d
FROM final_series fs
JOIN Posts p ON p.Id = fs.PostId
JOIN Users u ON u.Id = p.OwnerUserId
ORDER BY fs.score_per_view DESC NULLS LAST, fs.TotalVotes DESC NULLS LAST
LIMIT 100;