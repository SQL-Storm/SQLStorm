-- {"query": "363.sql", "dataset": "stackoverflow", "version": "v1.4", "prompt": "p1", "model": "gpt-5-nano", "temperature": 1.0, "max_tokens": 32768, "reasoning": "high", "input_tokens": 2026, "output_tokens": 24559} 
WITH
UserStats AS (
  SELECT
    u.Id AS UserId,
    COALESCE(u.DisplayName, 'User-' || u.Id) AS DisplayName,
    u.Reputation,
    u.Location,
    u.LastAccessDate,
    COUNT(p.Id) AS TotalPosts,
    COALESCE(SUM(p.Score), 0) AS TotalScore
  FROM Users u
  LEFT JOIN Posts p ON p.OwnerUserId = u.Id
  GROUP BY u.Id, u.DisplayName, u.Reputation, u.Location, u.LastAccessDate
),
TopTagCounts AS (
  SELECT p.OwnerUserId AS UserId, t.TagName, COUNT(*) AS TagPostCount
  FROM Posts p
  CROSS JOIN LATERAL unnest(string_to_array(substring(p.Tags, 2, length(p.Tags) - 2), '><')) AS t(TagName)
  WHERE p.PostTypeId = 1
  GROUP BY p.OwnerUserId, t.TagName
),
TopTagCountsRank AS (
  SELECT UserId, TagName, TagPostCount,
         ROW_NUMBER() OVER (PARTITION BY UserId ORDER BY TagPostCount DESC, TagName) AS rn
  FROM TopTagCounts
),
TopTagPivot AS (
  SELECT UserId,
         MAX(CASE WHEN rn = 1 THEN TagName END) AS TopTagName1,
         MAX(CASE WHEN rn = 1 THEN TagPostCount END) AS TopTagCount1,
         MAX(CASE WHEN rn = 2 THEN TagName END) AS TopTagName2,
         MAX(CASE WHEN rn = 2 THEN TagPostCount END) AS TopTagCount2,
         MAX(CASE WHEN rn = 3 THEN TagName END) AS TopTagName3,
         MAX(CASE WHEN rn = 3 THEN TagPostCount END) AS TopTagCount3
  FROM TopTagCountsRank
  GROUP BY UserId
),
Set1 AS (
  SELECT
    s.UserId,
    s.DisplayName,
    s.Reputation,
    s.Location,
    s.LastAccessDate,
    s.TotalPosts,
    s.TotalScore,
    (SELECT p.Title
     FROM Posts p
     WHERE p.OwnerUserId = s.UserId
     ORDER BY p.LastActivityDate DESC, p.Id DESC
     LIMIT 1) AS MostRecentPostTitle,
    (SELECT p.LastActivityDate
     FROM Posts p
     WHERE p.OwnerUserId = s.UserId
     ORDER BY p.LastActivityDate DESC, p.Id DESC
     LIMIT 1) AS MostRecentActivity,
    PT.TopTagName1 AS TopTag1Name,
    PT.TopTagCount1 AS TopTag1Count,
    PT.TopTagName2 AS TopTag2Name,
    PT.TopTagCount2 AS TopTag2Count,
    PT.TopTagName3 AS TopTag3Name,
    PT.TopTagCount3 AS TopTag3Count,
    'R1' AS Source
  FROM UserStats s
  LEFT JOIN TopTagPivot PT ON PT.UserId = s.UserId
  ORDER BY s.Reputation DESC, s.TotalScore DESC
  LIMIT 100
),
Set2 AS (
  SELECT
    s.UserId,
    s.DisplayName,
    s.Reputation,
    s.Location,
    s.LastAccessDate,
    s.TotalPosts,
    s.TotalScore,
    (SELECT p.Title
     FROM Posts p
     WHERE p.OwnerUserId = s.UserId
     ORDER BY p.LastActivityDate DESC, p.Id DESC
     LIMIT 1) AS MostRecentPostTitle,
    (SELECT p.LastActivityDate
     FROM Posts p
     WHERE p.OwnerUserId = s.UserId
     ORDER BY p.LastActivityDate DESC, p.Id DESC
     LIMIT 1) AS MostRecentActivity,
    PT.TopTagName1 AS TopTag1Name,
    PT.TopTagCount1 AS TopTag1Count,
    PT.TopTagName2 AS TopTag2Name,
    PT.TopTagCount2 AS TopTag2Count,
    PT.TopTagName3 AS TopTag3Name,
    PT.TopTagCount3 AS TopTag3Count,
    'S2' AS Source
  FROM UserStats s
  LEFT JOIN TopTagPivot PT ON PT.UserId = s.UserId
  ORDER BY s.TotalPosts DESC, s.Reputation DESC
  LIMIT 100
)
SELECT * FROM Set1
UNION ALL
SELECT * FROM Set2
ORDER BY UserId, Source;