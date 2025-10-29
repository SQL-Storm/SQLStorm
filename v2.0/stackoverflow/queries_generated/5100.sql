-- {"query": "5100.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-5-nano", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 750} 
WITH RecentActive AS (
  SELECT
    p.Id AS PostId,
    p.Title,
    p.PostTypeId,
    p.CreationDate,
    p.LastActivityDate,
    p.Score,
    p.ViewCount,
    p.OwnerUserId,
    p.Tags,
    p.AnswerCount,
    p.CommentCount,
    p.FavoriteCount,
    CASE
      WHEN p.AcceptedAnswerId IS NOT NULL THEN 1 ELSE 0
    END AS HasAcceptedAnswer,
    ROW_NUMBER() OVER (PARTITION BY p.OwnerUserId ORDER BY p.LastActivityDate DESC) AS rn
  FROM Posts p
  WHERE p.CreationDate >= NOW() - INTERVAL '30 days'
),
TagAdj AS (
  SELECT
    pg.PostId,
    pg.Title,
    pg.PostTypeId,
    pg.CreationDate,
    pg.LastActivityDate,
    pg.Score,
    pg.ViewCount,
    pg.OwnerUserId,
    t.TagName AS PrimaryTag,
    pg.AnswerCount,
    pg.CommentCount,
    pg.FavoriteCount,
    pg.HasAcceptedAnswer
  FROM RecentActive pg
  LEFT JOIN LATERAL (
    SELECT unnest(string_to_array(substr(pg.Tags, 2, length(pg.Tags)-2), '><')) AS TagName
  ) t ON TRUE
  WHERE pg.PostTypeId = 1 OR pg.PostTypeId = 4 OR pg.PostTypeId = 5
),
Agg AS (
  SELECT
    o.OwnerUserId,
    u.DisplayName AS OwnerDisplayName,
    COUNT(*) FILTER (WHERE o.HasAcceptedAnswer = 1) AS QuestionsWithAccepted,
    SUM(o.Score) AS TotalScore,
    AVG(NULLIF(o.Score,0)) AS AvgScore,
    SUM(o.ViewCount) AS TotalViews,
    MAX(o.LastActivityDate) AS LastActive
  FROM RecentActive o
  LEFT JOIN Users u ON o.OwnerUserId = u.Id
  GROUP BY o.OwnerUserId, u.DisplayName
),
Windowed AS (
  SELECT
    a.OwnerUserId,
    a.OwnerDisplayName,
    a.QuestionsWithAccepted,
    a.TotalScore,
    a.TotalViews,
    a.LastActive,
    SUM(a.TotalScore) OVER (ORDER BY a.TotalViews DESC ROWS BETWEEN 4 PRECEDING AND CURRENT ROW) AS RollingScore
  FROM Agg a
),
Complex AS (
  SELECT
    w.OwnerUserId,
    w.OwnerDisplayName,
    w.QuestionsWithAccepted,
    w.TotalScore,
    w.TotalViews,
    w.LastActive,
    w.RollingScore,
    l.Name AS LastViewedLinkType,
    CASE
      WHEN w.TotalViews > 100000 THEN 'HighTraffic'
      WHEN w.TotalViews > 10000 THEN 'ModerateTraffic'
      ELSE 'LowTraffic'
    END AS TrafficBucket,
    (SELECT COUNT(*) FROM Badges b WHERE b.UserId = w.OwnerUserId) AS BadgeCount
  FROM Windowed w
  LEFT JOIN PostLinks pl ON pl.PostId IN (SELECT PostId FROM RecentActive WHERE OwnerUserId = w.OwnerUserId)
  LEFT JOIN LinkTypes l ON l.Id = 1 -- assume Linked type for demonstration
)
SELECT
  c.OwnerUserId,
  c.OwnerDisplayName,
  c.QuestionsWithAccepted,
  c.TotalScore,
  c.TotalViews,
  c.LastActive,
  c.RollingScore,
  c.TrafficBucket,
  c.BadgeCount
FROM Complex c
ORDER BY c.TotalScore DESC NULLS LAST
LIMIT 100;