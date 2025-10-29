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
    CASE WHEN p.AcceptedAnswerId IS NOT NULL THEN 1 ELSE 0 END AS HasAcceptedAnswer,
    ROW_NUMBER() OVER (PARTITION BY p.OwnerUserId ORDER BY p.LastActivityDate DESC) AS rn
  FROM Posts p
  WHERE p.CreationDate >= (TIMESTAMP '2024-10-01 12:34:56' - INTERVAL '30' DAY)
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
  FROM RecentActive pg,
  LATERAL (
    SELECT regexp_split_to_table(substr(pg.Tags, 2, length(pg.Tags) - 2), '><') AS TagName
  ) t
  WHERE pg.PostTypeId IN (1, 4, 5)
),
Agg AS (
  SELECT
    o.OwnerUserId,
    u.DisplayName AS OwnerDisplayName,
    COUNT(*) FILTER (WHERE o.HasAcceptedAnswer = 1) AS QuestionsWithAccepted,
    SUM(o.Score) AS TotalScore,
    AVG(NULLIF(o.Score, 0)) AS AvgScore,
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
  LEFT JOIN PostLinks pl ON pl.PostId IN (SELECT ra.PostId FROM RecentActive ra WHERE ra.OwnerUserId = w.OwnerUserId)
  LEFT JOIN LinkTypes l ON l.Id = 1
  GROUP BY
    w.OwnerUserId,
    w.OwnerDisplayName,
    w.QuestionsWithAccepted,
    w.TotalScore,
    w.TotalViews,
    w.LastActive,
    w.RollingScore,
    l.Name
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
ORDER BY c.TotalScore DESC
FETCH FIRST 100 ROWS ONLY;