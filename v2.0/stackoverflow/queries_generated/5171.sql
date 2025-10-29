-- {"query": "5171.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-5-nano", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 712} 
WITH
RecentTopPosts AS (
  SELECT
    p.Id,
    p.Title,
    p.Tags,
    p.CreationDate,
    p.OwnerUserId,
    p.ViewCount,
    p.Score,
    p.CommentCount,
    p.AnswerCount,
    p.LastActivityDate,
    p.PostTypeId
  FROM Posts p
  WHERE p.CreationDate >= CURRENT_DATE - INTERVAL '180 days'
),
CorrelatedStats AS (
  SELECT
    r.Id AS PostId,
    r.Title,
    r.Tags,
    r.CreationDate,
    r.ViewCount,
    r.Score,
    r.CommentCount,
    r.AnswerCount,
    r.LastActivityDate,
    -- compute a dynamic popularity score using multiple factors
    (CASE WHEN r.ViewCount > 0 THEN r.Score * 1.0 / NULLIF(r.ViewCount,0) ELSE 0 END)
    + (CASE WHEN r.AnswerCount > 0 THEN r.AnswerCount * 2.5 ELSE 0 END)
    + (CASE WHEN EXTRACT(EPOCH FROM (CURRENT_TIMESTAMP - r.CreationDate)) < 86400 THEN 5 ELSE 0 END) AS PopularityScore
  FROM RecentTopPosts r
),
TopTags AS (
  SELECT
    t.TagName,
    COUNT(*) AS TagPostCount,
    AVG(ts.PopularityScore) AS AvgPopularity
  FROM (
    SELECT
      unnest(string_to_array(substr(t.Tags, 2, length(t.Tags)-2), '><')) AS TagName,
      t.Id AS PostId,
      ts.PopularityScore
    FROM CorrelatedStats t
  ) AS ts
  CROSS JOIN LATERAL (
    SELECT (CASE WHEN ts.TagName IS NOT NULL THEN ts.PopularityScore ELSE 0 END) AS PopularityScore
  ) AS _
  GROUP BY t.TagName
),
Final AS (
  SELECT
    c.PostId,
    c.Title,
    c.Tags,
    c.CreationDate,
    c.ViewCount,
    c.Score,
    c.CommentCount,
    c.AnswerCount,
    c.LastActivityDate,
    c.PopularityScore,
    u.DisplayName AS OwnerDisplayName,
    u.Reputation,
    -- include a window-ranked view of related posts by same first tag for correlation
    first_tag.TagName AS PrimaryTag,
    ROW_NUMBER() OVER (PARTITION BY first_tag.TagName ORDER BY c.PopularityScore DESC, c.LastActivityDate DESC) AS TagRank
  FROM CorrelatedStats c
  LEFT JOIN Posts p ON p.Id = c.PostId
  LEFT JOIN LATERAL (
    SELECT unnest(string_to_array(substr(p.Tags, 2, length(p.Tags)-2), '><')) AS TagName
  ) AS t ON true
  LEFT JOIN Users u ON u.Id = p.OwnerUserId
  LEFT JOIN LATERAL (
    SELECT TagName
    FROM (SELECT unnest(string_to_array(substr(p.Tags, 2, length(p.Tags)-2), '><')) AS TagName) s
    ORDER BY TagName
    LIMIT 1
  ) AS first_tag ON true
)
SELECT
  f.PostId,
  f.Title,
  f.PrimaryTag,
  f.TagRank,
  f.Views ?? 0
FROM Final f
ORDER BY f.PopularityScore DESC
LIMIT 100;