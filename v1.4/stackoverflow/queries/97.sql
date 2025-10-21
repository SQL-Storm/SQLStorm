-- {"query": "97.sql", "dataset": "stackoverflow", "version": "v1.4", "prompt": "p1", "model": "gpt-5-nano", "temperature": 1.0, "max_tokens": 32768, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 550} 
WITH top_posts AS (
  SELECT
    p.Id AS PostId,
    p.Title,
    p.Body,
    p.CreationDate,
    p.OwnerUserId,
    p.ViewCount,
    p.Score,
    p.Tags,
    p.AnswerCount,
    p.CommentCount,
    p.FavoriteCount,
    p.LastActivityDate,
    p.PostTypeId,
    u.DisplayName AS OwnerDisplayName,
    u.Reputation,
    u.AccountId,
    c.Name AS CloseReason
  FROM Posts p
  LEFT JOIN Users u ON p.OwnerUserId = u.Id
  LEFT JOIN PostHistory ph ON ph.PostId = p.Id AND ph.PostHistoryTypeId = 10
  LEFT JOIN CloseReasonTypes c ON CAST(ph.Comment AS VARCHAR(100)) LIKE '%' || CAST(c.Id AS VARCHAR(10)) || '%'
  WHERE p.PostTypeId = 1 -- questions
),
tag_expanded AS (
  SELECT
    tp.*,
    unnest(string_to_array(substr(tp.Tags, 2, length(tp.Tags)-2), '><')) AS TagName
  FROM top_posts tp
),
agg AS (
  SELECT
    TagName,
    COUNT(*) AS QuestionCount,
    AVG(ViewCount) AS AvgViews,
    SUM(CASE WHEN Reputation >= 10000 THEN 1 ELSE 0 END) AS HighRepAsOwners
  FROM tag_expanded te
  GROUP BY TagName
),
recent_activity AS (
  SELECT
    TagName,
    MAX(p.LastActivityDate) AS LastActive
  FROM tag_expanded te
  JOIN Posts p ON p.Id = te.PostId
  GROUP BY TagName
),
complex_calc AS (
  SELECT
    a.TagName,
    a.QuestionCount,
    a.AvgViews,
    a.HighRepAsOwners,
    ra.LastActive,
    CASE
      WHEN a.AvgViews > 1000 THEN 'Hot'
      WHEN a.AvgViews > 100 THEN 'Warm'
      ELSE 'Cold'
    END AS ActivityBand,
    (a.HighRepAsOwners * 1.0) / NULLIF(a.QuestionCount, 0) AS RepPerQuestion
  FROM agg a
  LEFT JOIN recent_activity ra ON ra.TagName = a.TagName
)
SELECT
  cc.TagName,
  cc.QuestionCount,
  cc.AvgViews,
  cc.HighRepAsOwners,
  cc.LastActive,
  cc.ActivityBand,
  cc.RepPerQuestion
FROM complex_calc cc
ORDER BY cc.LastActive DESC NULLS LAST, cc.QuestionCount DESC, cc.RepPerQuestion DESC
LIMIT 200;