WITH
RecentTopPosts AS (
  SELECT
    p.Id AS PostId,
    p.Title,
    p.Body,
    p.CreationDate,
    p.OwnerUserId,
    p.Score,
    p.ViewCount,
    p.Tags,
    p.LastActivityDate,
    p.AnswerCount,
    p.CommentCount,
    p.FavoriteCount,
    p.PostTypeId,
    ROW_NUMBER() OVER (PARTITION BY CAST(p.CreationDate AS DATE)
                       ORDER BY p.Score DESC, p.ViewCount DESC, p.LastActivityDate DESC) AS DayRank
  FROM Posts p
  WHERE p.PostTypeId = 1
    AND p.CreationDate >= CAST('2024-10-01 12:34:56' AS TIMESTAMP) - INTERVAL '30 days'
    AND p.OwnerUserId IS NOT NULL
),
TopTags AS (
  SELECT
    t.TagName AS Tag,
    SUM(r.Score) AS TotalScore,
    AVG(r.Score) AS AvgScore,
    COUNT(*) AS QCount
  FROM RecentTopPosts r
  JOIN LATERAL unnest(string_to_array(r.Tags, '><')) AS t(TagName) ON TRUE
  WHERE r.Tags IS NOT NULL
  GROUP BY t.TagName
),
TagActivity AS (
  SELECT
    t.TagName,
    COUNT(*) AS Questions,
    SUM(p.ViewCount) AS TotalViews,
    SUM(p.AnswerCount) AS TotalAnswers,
    MAX(p.LastActivityDate) AS LastActive
  FROM Posts p
  JOIN LATERAL unnest(string_to_array(p.Tags, '><')) AS t(TagName) ON TRUE
  WHERE p.PostTypeId = 1
  GROUP BY t.TagName
),
AggStats AS (
  SELECT
    tt.Tag AS Tag,
    tt.TotalScore,
    tt.AvgScore,
    tt.QCount,
    ta.Questions,
    ta.TotalViews,
    ta.TotalAnswers,
    ta.LastActive
  FROM TopTags tt
  JOIN TagActivity ta ON ta.TagName = tt.Tag
)
SELECT
  a.Tag,
  a.TotalScore,
  a.AvgScore,
  a.QCount,
  a.Questions,
  a.TotalViews,
  a.TotalAnswers,
  a.LastActive,
  u.DisplayName AS Owner,
  u.Reputation
FROM AggStats a
LEFT JOIN LATERAL (
  SELECT u2.Id, u2.DisplayName, u2.Reputation
  FROM Users u2
  WHERE u2.Id = (
    SELECT p2.OwnerUserId
    FROM Posts p2
    WHERE p2.Tags IS NOT NULL
      AND p2.Tags LIKE '%' || a.Tag || '%'
      AND p2.OwnerUserId IS NOT NULL
    LIMIT 1
  )
  ORDER BY u2.Reputation DESC
  LIMIT 1
) AS u ON TRUE
WHERE a.Questions > 0
ORDER BY a.TotalScore DESC
LIMIT 100;