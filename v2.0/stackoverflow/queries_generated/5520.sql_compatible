WITH recent_questions AS (
  SELECT
    p.Id AS PostId,
    p.Title,
    p.CreationDate,
    p.Score,
    p.ViewCount,
    p.Tags,
    p.OwnerUserId,
    p.LastActivityDate,
    p.CommentCount,
    p.AnswerCount,
    p.FavoriteCount,
    p.ParentId,
    p.PostTypeId,
    u.Reputation AS OwnerReputation,
    u.DisplayName AS OwnerDisplayName
  FROM Posts p
  LEFT JOIN Users u ON p.OwnerUserId = u.Id
  WHERE p.PostTypeId = 1
    AND p.CreationDate >= CAST('2024-10-01 12:34:56' AS timestamp) - INTERVAL '30 days'
),
tag_metrics AS (
  SELECT
    t.TagName,
    t.Count AS TagCount,
    AVG(p.Score) AS AvgQuestionScore,
    SUM(CASE WHEN p.ViewCount > 1000 THEN 1 ELSE 0 END) AS PopularQuestionCount
  FROM Tags t
  LEFT JOIN Posts p ON p.Tags LIKE '%' || t.TagName || '%'
  WHERE t.IsModeratorOnly = FALSE
  GROUP BY t.TagName, t.Count
),
complex_filter AS (
  SELECT
    q.PostId,
    q.Title,
    q.CreationDate,
    q.OwnerDisplayName,
    q.OwnerReputation,
    q.Score,
    q.ViewCount,
    q.TagList,
    q.OwnerUserId,
    ROW_NUMBER() OVER (
      PARTITION BY q.OwnerUserId
      ORDER BY q.Score DESC, q.ViewCount DESC, q.CreationDate
    ) AS rn,
    COUNT(*) OVER () AS total_owner_questions
  FROM (
    SELECT
      r.PostId,
      r.Title,
      r.CreationDate,
      r.OwnerDisplayName,
      r.OwnerReputation,
      r.Score,
      r.ViewCount,
      r.Tags AS TagList,
      r.OwnerUserId
    FROM recent_questions r
    LEFT JOIN LATERAL (
      SELECT unnest(string_to_array(substring(r.Tags, 2, length(r.Tags)-2), '><')) AS tg
    ) AS t ON true
  ) q
),
benchmark AS (
  SELECT
    c.PostId,
    c.Title,
    c.CreationDate,
    c.OwnerDisplayName,
    c.OwnerReputation,
    c.Score,
    c.ViewCount,
    c.TagList,
    c.rn,
    c.total_owner_questions,
    SUM(c.ViewCount) OVER (
      PARTITION BY date_trunc('day', c.CreationDate)
      ORDER BY c.CreationDate
      ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW
    ) AS ViewsTodayRunningTotal,
    (SELECT COUNT(*) FROM Comments cm WHERE cm.PostId = c.PostId) AS CommentCountOnPost
  FROM complex_filter c
  WHERE c.rn = 1
)
SELECT
  'BenchmarkQuery' AS Label,
  b.PostId,
  b.Title,
  b.CreationDate,
  b.OwnerDisplayName,
  b.OwnerReputation,
  b.Score,
  b.ViewCount,
  b.TagList,
  b.ViewsTodayRunningTotal,
  b.CommentCountOnPost,
  t.TagName AS TopTag,
  t.TagCount AS TagPopularity,
  t.AvgQuestionScore
FROM benchmark b
LEFT JOIN LATERAL (
  SELECT
    t.TagName,
    t.Count AS TagCount,
    AVG(p.Score) AS AvgQuestionScore
  FROM (
    SELECT p.Id, unnest(string_to_array(substring(p.Tags, 2, length(p.Tags)-2), '><')) AS tg
    FROM Posts p
    WHERE p.Id = b.PostId
  ) s
  JOIN Tags t ON t.TagName = s.tg
  JOIN Posts p ON p.Id = b.PostId
  GROUP BY t.TagName, t.Count
  ORDER BY t.Count DESC
  LIMIT 1
) AS t ON true
ORDER BY b.CreationDate DESC
LIMIT 1;