-- {"query": "5927.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-5-nano", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 767} 
WITH
  -- recent activity per post
  RecentActivity AS (
    SELECT
      p.Id AS PostId,
      MAX(p.LastActivityDate) AS LastActivityDate,
      MAX(p.ViewCount) AS MaxViewCount,
      MAX(p.Score) AS MaxScore
    FROM Posts p
    GROUP BY p.Id
  ),
  -- average metrics per post type
  TypeStats AS (
    SELECT
      pt.Id AS PostTypeId,
      AVG(p.Score) FILTER (WHERE p.Score IS NOT NULL) AS AvgScore,
      AVG(p.ViewCount) FILTER (WHERE p.ViewCount IS NOT NULL) AS AvgViews,
      COUNT(*) AS NPosts
    FROM Posts p
    JOIN PostTypes pt ON p.PostTypeId = pt.Id
    GROUP BY pt.Id
  ),
  -- complex correlation: posts with correlated tags and author reputation distribution
  TagAuthorDist AS (
    SELECT
      t.TagName,
      u.Reputation,
      COUNT(*) AS Cnt
    FROM Posts p
    JOIN UNNEST(string_to_array(p.Tags, '><')) AS t_tag(tag) ON TRUE
    JOIN Tags t ON t.TagName = trim(both ' ' FROM substr(t_tag.tag, 2, length(t_tag.tag)-2))
    JOIN Users u ON p.OwnerUserId = u.Id
    GROUP BY t.TagName, u.Reputation
  ),
  -- window functions: ranking posts by activity and score per day
  Ranked AS (
    SELECT
      p.Id,
      p.Title,
      p.CreationDate,
      p.Score,
      p.ViewCount,
      ROW_NUMBER() OVER (
        PARTITION BY DATE(p.CreationDate)
        ORDER BY p.ViewCount DESC, p.Score DESC NULLS LAST
      ) AS DayRank,
      RANK() OVER (
        ORDER BY p.LastActivityDate DESC, p.Score DESC
      ) AS OverallRank
    FROM Posts p
  ),
  -- set operation: union of top questions and top answers by score
  TopQuestions AS (
    SELECT Id, Title, Score, ViewCount, CreationDate
    FROM Posts
    WHERE PostTypeId = 1
    ORDER BY Score DESC
    LIMIT 100
  ),
  TopAnswers AS (
    SELECT Id, Title, Score, ViewCount, CreationDate
    FROM Posts
    WHERE PostTypeId = 2
    ORDER BY Score DESC
    LIMIT 100
  ),
  TopQA AS (
    (SELECT * FROM TopQuestions)
    UNION ALL
    (SELECT * FROM TopAnswers)
  )
SELECT
  r.PostId,
  r.Title,
  r.CreationDate,
  r.Score,
  r.ViewCount,
  r.DayRank,
  r.OverallRank,
  ta.TagName AS TagRelated,
  ta.Reputation AS AuthorReputation,
  ts.AvgScore AS PostTypeAvgScore,
  ts.AvgViews AS PostTypeAvgViews,
  ra.MaxViewCount AS PostMaxViews,
  ra.MaxScore AS PostMaxScore
FROM Ranked r
LEFT JOIN PostLinks pl ON pl.PostId = r.Id
LEFT JOIN (SELECT unnest(string_to_array(p.Tags, '><')) AS TagName, p.Id
           FROM Posts p) t ON t.Id = r.Id
LEFT JOIN TagAuthorDist ta ON ta.TagName = COALESCE(t.TagName, '')
LEFT JOIN TypeStats ts ON ts.PostTypeId = (SELECT PostTypeId FROM Posts p WHERE p.Id = r.Id)
LEFT JOIN RecentActivity ra ON ra.PostId = r.Id
WHERE r.OverallRank <= 500
ORDER BY r.OverallRank, r.DayRank;