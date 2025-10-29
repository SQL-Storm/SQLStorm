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
  WHERE p.CreationDate >= CAST('2024-10-01' AS date) - INTERVAL '180 days'
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
    (
      (CASE WHEN r.ViewCount > 0 THEN r.Score * 1.0 / NULLIF(r.ViewCount, 0) ELSE 0 END)
      + (CASE WHEN r.AnswerCount > 0 THEN r.AnswerCount * 2.5 ELSE 0 END)
      + (CASE WHEN EXTRACT(EPOCH FROM (CAST('2024-10-01 12:34:56' AS timestamp) - r.CreationDate)) < 86400 THEN 5 ELSE 0 END)
    ) AS PopularityScore
  FROM RecentTopPosts r
),
TopTags AS (
  SELECT
    ts.TagName,
    COUNT(*) AS TagPostCount,
    AVG(ts.PopularityScore) AS AvgPopularity
  FROM (
    SELECT
      unnest(string_to_array(substr(t.Tags, 2, length(t.Tags)-2), '><')) AS TagName,
      t.PostId,
      t.PopularityScore
    FROM CorrelatedStats t
  ) AS ts
  CROSS JOIN LATERAL (
    SELECT (CASE WHEN ts.TagName IS NOT NULL THEN ts.PopularityScore ELSE 0 END) AS PopularityScore
  ) AS dummy
  GROUP BY ts.TagName
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
    first_tag.TagName AS PrimaryTag,
    ROW_NUMBER() OVER (PARTITION BY first_tag.TagName ORDER BY c.PopularityScore DESC, c.LastActivityDate DESC) AS TagRank
  FROM CorrelatedStats c
  LEFT JOIN Posts p ON p.Id = c.PostId
  LEFT JOIN LATERAL (
    SELECT unnest(string_to_array(substr(p.Tags, 2, length(p.Tags)-2), '><')) AS TagName
  ) AS t ON TRUE
  LEFT JOIN Users u ON u.Id = p.OwnerUserId
  LEFT JOIN LATERAL (
    SELECT TagName
    FROM (SELECT unnest(string_to_array(substr(p.Tags, 2, length(p.Tags)-2), '><')) AS TagName) s
    ORDER BY TagName
    LIMIT 1
  ) AS first_tag ON TRUE
)
SELECT
  f.PostId,
  f.Title,
  f.PrimaryTag,
  f.TagRank,
  COALESCE(f.ViewCount, 0) AS Views,
  f.PopularityScore
FROM Final f
GROUP BY
  f.PostId,
  f.Title,
  f.PrimaryTag,
  f.TagRank,
  f.ViewCount,
  f.PopularityScore
ORDER BY f.PopularityScore DESC
LIMIT 100;