-- {"query": "5084.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-5-nano", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 787} 
WITH
RecentTopPosts AS (
  SELECT
    p.Id AS PostId,
    p.Title,
    p.CreationDate,
    p.OwnerUserId,
    p.ViewCount,
    p.Score,
    p.Tags,
    p.LastActivityDate,
    ROW_NUMBER() OVER (PARTITION BY p.OwnerUserId ORDER BY p.Score DESC, p.ViewCount DESC) AS rn_owner
  FROM Posts p
  WHERE p.PostTypeId = 1 -- Questions
    AND p.CreationDate >= NOW() - INTERVAL '180 days'
),
PopularTagMetrics AS (
  SELECT
    t.TagName,
    COUNT(*) AS PostCount,
    AVG(p.Score) AS AvgScore,
    MAX(p.Score) AS MaxScore,
    SUM(p.ViewCount) AS ViewSum
  FROM Posts p
  JOIN unnest(string_to_array(p.Tags, '><')) AS t(TagName)
    ON true
  WHERE p.PostTypeId = 1
  GROUP BY t.TagName
),
CrossJoined AS (
  SELECT
    r.PostId,
    r.Title,
    r.CreationDate,
    r.OwnerUserId,
    r.ViewCount,
    r.Score,
    r.Tags,
    r.LastActivityDate,
    l.Name AS LinkType,
    v.CreationDate AS VoteDate,
    uu.Reputation AS UserReputation,
    COALESCE(b.Class, 0) AS BadgeCountForOwner
  FROM RecentTopPosts r
  LEFT JOIN PostLinks pl ON pl.PostId = r.PostId
  LEFT JOIN LinkTypes l ON l.Id = pl.LinkTypeId
  LEFT JOIN Votes v ON v.PostId = r.PostId AND v.VoteTypeId = 2
  LEFT JOIN Users uu ON uu.Id = r.OwnerUserId
  LEFT JOIN (
      SELECT UserId, COUNT(*) AS Class
      FROM Badges
      GROUP BY UserId
  ) b ON b.UserId = r.OwnerUserId
),
AggWindow AS (
  SELECT
    PostId,
    Title,
    CreationDate,
    OwnerUserId,
    ViewCount,
    Score,
    Tags,
    LastActivityDate,
    LinkType,
    VoteDate,
    UserReputation,
    BadgeCountForOwner,
    -- Window over recent activity to create a moving average of score over last 7 days per user
    AVG(Score) OVER (PARTITION BY OwnerUserId ORDER BY CreationDate ROWS BETWEEN 6 PRECEDING AND CURRENT ROW) AS AvgScoreLast7
  FROM CrossJoined
),
Final AS (
  SELECT
    PostId,
    Title,
    CreationDate,
    OwnerUserId,
    ViewCount,
    Score,
    Tags,
    LastActivityDate,
    LinkType,
    VoteDate,
    UserReputation,
    BadgeCountForOwner,
    AvgScoreLast7,
    -- A few advanced computations
    CASE
      WHEN ViewCount > 1000 THEN 'Hot'
      WHEN Score >= 10 THEN 'Popular'
      ELSE 'Normal'
    END AS StatusCategory,
    CASE
      WHEN Tags IS NOT NULL THEN
        (SELECT STRING_AGG(t.TagName, ',') FROM unnest(string_to_array(Tags, '><')) AS t(TagName))
      ELSE NULL
    END AS TagList
  FROM AggWindow
)
SELECT
  PostId,
  Title,
  CreationDate,
  OwnerUserId,
  ViewCount,
  Score,
  Tags,
  LastActivityDate,
  LinkType,
  VoteDate,
  UserReputation,
  BadgeCountForOwner,
  AvgScoreLast7,
  StatusCategory,
  TagList
FROM Final
WHERE StatusCategory <> 'Normal'
ORDER BY Score DESC, ViewCount DESC
LIMIT 200;