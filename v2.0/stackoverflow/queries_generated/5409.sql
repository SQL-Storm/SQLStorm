-- {"query": "5409.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-5-nano", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 579} 
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
    -- rank per day by score and view count
    ROW_NUMBER() OVER (PARTITION BY CAST(p.CreationDate AS DATE)
                       ORDER BY p.Score DESC, p.ViewCount DESC, p.LastActivityDate DESC) AS DayRank
  FROM Posts p
  WHERE p.PostTypeId = 1 -- questions
    AND p.CreationDate >= NOW() - INTERVAL '30 days'
    AND p.OwnerUserId IS NOT NULL
),
TopTags AS (
  SELECT
    t.TagName AS Tag,
    SUM(p.Score) AS TotalScore,
    AVG(p.Score) AS AvgScore,
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
  JOIN TagActivity ta USING (TagName)
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
  SELECT u.Id, u.DisplayName, u.Reputation
  FROM Users u
  WHERE u.Id = (SELECT OwnerUserId FROM Posts p WHERE p.Tags LIKE '%' || a.Tag || '%' LIMIT 1)
  ORDER BY u.Reputation DESC
  LIMIT 1
) AS u ON TRUE
WHERE a.Questions > 0
ORDER BY a.TotalScore DESC
LIMIT 100;