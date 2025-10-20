-- {"query": "47.sql", "dataset": "stackoverflow", "version": "v1.4", "prompt": "p1", "model": "gpt-5-nano", "temperature": 1.0, "max_tokens": 32768, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 958} 
WITH
recent_questions AS (
  SELECT
    p.Id,
    p.Title,
    p.OwnerUserId,
    p.CreationDate,
    p.Score,
    p.ViewCount,
    p.Tags,
    p.LastActivityDate,
    p.CommentCount,
    p.AcceptedAnswerId,
    p.ParentId,
    p.LastEditorUserId,
    p.LastEditDate,
    p.ContentLicense
  FROM Posts p
  WHERE p.PostTypeId = 1 -- Question
    AND p.CreationDate >= NOW() - INTERVAL '7 days'
),
tag_stat AS (
  SELECT
    tr.TagName,
    COUNT(*) AS question_count,
    AVG(t.score) AS avg_score
  FROM (
    SELECT id, unnest(string_to_array(substr(Tags, 2, length(Tags)-2), '><')) AS TagName
    FROM Posts
    WHERE PostTypeId = 1
      AND CreationDate >= NOW() - INTERVAL '7 days'
  ) t
  JOIN Tags tr ON tr.TagName = t.TagName
  GROUP BY tr.TagName
),
hot_keywords AS (
  SELECT
    w.TagName,
    w.question_count,
    w.avg_score,
    w.total_views
  FROM (
    SELECT
      tag_name AS TagName,
      COUNT(*) AS question_count,
      AVG(score) AS avg_score,
      SUM(ViewCount) AS total_views
    FROM (
      SELECT
        unnest(string_to_array(substr(Tags, 2, length(Tags)-2), '><')) AS tag_name,
        p.Score,
        p.ViewCount
      FROM Posts p
      WHERE p.PostTypeId = 1
        AND p.CreationDate >= NOW() - INTERVAL '30 days'
    ) q
    GROUP BY tag_name
  ) w
),
complex_query AS (
  SELECT
    q.Id AS QuestionId,
    q.Title,
    q.CreationDate,
    q.ViewCount,
    q.Score AS QuestionScore,
    -- compute a composite popularity metric
    (COALESCE(vs.Upvotes,0) - COALESCE(vs.Downvotes,0)) * 1.0
      + COALESCE(vs.BountyAmount,0) AS PopularityMetric,
    u.DisplayName AS Owner,
    CASE
      WHEN q.LastActivityDate > NOW() - INTERVAL '1 day' THEN 'Active within 1 day'
      ELSE 'Dormant'
    END AS ActivityBand,
    posters.RecentEditor
  FROM recent_questions q
  LEFT JOIN (
    SELECT
      p.OwnerUserId,
      SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS Upvotes,
      SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS Downvotes,
      SUM(v.BountyAmount) AS BountyAmount
    FROM Posts p
    LEFT JOIN Votes v ON v.PostId = p.Id
    GROUP BY p.OwnerUserId
  ) vs ON vs.OwnerUserId = q.OwnerUserId
  LEFT JOIN Users u ON u.Id = q.OwnerUserId
  LEFT JOIN (
    SELECT
      p.Id AS PostId,
      MAX(u1.DisplayName) AS RecentEditor
    FROM Posts p
    LEFT JOIN Votes v ON v.PostId = p.Id
    LEFT JOIN Users u1 ON u1.Id = p.LastEditorUserId
    GROUP BY p.Id
  ) posters ON posters.PostId = q.Id
  WHERE
    q.Title IS NOT NULL
    AND q.CommentCount >= 0
    -- be fancy: compute a deterministic ordering using a set of correlated expressions
    AND (CAST(LEFT(q.Title, 100) AS VARCHAR) REGEXP '^[A-Za-z0-9 .,&-]+$')
)
SELECT
  cq.QuestionId,
  cq.Title,
  cq.CreationDate,
  cq.ViewCount,
  cq.QuestionScore,
  cq.PopularityMetric,
  cq.Owner,
  cq.ActivityBand,
  cq.RecentEditor,
  ht.Name AS HistoryType
FROM complex_query cq
LEFT JOIN LATERAL (
  SELECT h.Name
  FROM PostHistory ph
  JOIN PostHistoryTypes h ON h.Id = ph.PostHistoryTypeId
  WHERE ph.PostId = cq.QuestionId
  ORDER BY ph.CreationDate DESC
  LIMIT 1
) ht ON true
ORDER BY cq.PopularityMetric DESC NULLS LAST, cq.CreationDate DESC
LIMIT 100;