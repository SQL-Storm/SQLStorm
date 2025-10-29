WITH
RecentActivePosts AS (
  SELECT
    p.Id,
    p.PostTypeId,
    p.OwnerUserId,
    p.Title,
    p.Tags,
    p.CreationDate,
    p.LastActivityDate,
    p.Score,
    p.ViewCount,
    p.CommentCount,
    p.AnswerCount
  FROM Posts p
  WHERE p.LastActivityDate > CAST('2024-10-01 12:34:56' AS timestamp) - INTERVAL '30 days'
),
TagAnalytics AS (
  SELECT
    tgn.TagName,
    COUNT(*) AS PostCount,
    AVG(rap.Score) AS AvgScore,
    MAX(rap.ViewCount) AS MaxViews,
    STRING_AGG(DISTINCT u.DisplayName, ',') AS ActiveUsers
  FROM RecentActivePosts rap
  CROSS JOIN LATERAL (
    SELECT unnest(string_to_array(substring(rap.Tags, 2, length(rap.Tags)-2), '><')) AS TagName
  ) AS tgn
  JOIN Tags t ON t.TagName = tgn.TagName
  JOIN Users u ON rap.OwnerUserId = u.Id
  GROUP BY tgn.TagName
),
PopularPostLinks AS (
  SELECT
    rl.PostId,
    rl.RelatedPostId,
    lt.Name AS LinkTypeName,
    p.Title AS RelatedTitle,
    p.OwnerUserId AS RelatedOwner
  FROM PostLinks rl
  JOIN LinkTypes lt ON rl.LinkTypeId = lt.Id
  LEFT JOIN Posts p ON rl.RelatedPostId = p.Id
  WHERE lt.Name IN ('Linked', 'Duplicate')
),
TopUserInfluence AS (
  SELECT
    u.Id AS UserId,
    u.DisplayName,
    SUM(v.BountyAmount) AS TotalBounty,
    SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS UpvotesGiven,
    SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS DownvotesGiven,
    RANK() OVER (ORDER BY SUM(v.BountyAmount) DESC) AS rnk
  FROM Users u
  LEFT JOIN Posts p ON p.OwnerUserId = u.Id
  LEFT JOIN Votes v ON v.PostId = p.Id
  WHERE u.AccountId IS NOT NULL
  GROUP BY u.Id, u.DisplayName
),
WindowedSummary AS (
  SELECT
    rap.Id AS PostId,
    rap.Title,
    rap.OwnerUserId,
    rap.CreationDate,
    rap.LastActivityDate,
    rap.Score,
    rap.ViewCount,
    ROW_NUMBER() OVER (PARTITION BY rap.OwnerUserId ORDER BY rap.LastActivityDate DESC) AS rn_by_user
  FROM RecentActivePosts rap
)
SELECT
  ws.Title AS "PostTitle",
  ws.LastActivityDate,
  ws.Score,
  ws.ViewCount,
  ua.DisplayName AS "Owner",
  ua.Reputation AS "OwnerReputation",
  pa.TotalBounty,
  pa.UpvotesGiven,
  pa.DownvotesGiven,
  vis.TagName,
  vis.PostCount AS "TagPostCount",
  vis.AvgScore AS "TagAvgScore",
  vis.MaxViews AS "TagMaxViews",
  vis.ActiveUsers
FROM WindowedSummary ws
JOIN Users ua ON ws.OwnerUserId = ua.Id
LEFT JOIN TopUserInfluence pa ON ua.Id = pa.UserId
LEFT JOIN LATERAL (
  SELECT
    ta2.TagName,
    ta2.PostCount,
    ta2.AvgScore,
    ta2.MaxViews,
    ta2.ActiveUsers
  FROM TagAnalytics ta2
  ORDER BY ta2.PostCount DESC
  LIMIT 5
) AS vis ON true
WHERE ws.rn_by_user = 1
ORDER BY ws.LastActivityDate DESC
LIMIT 100;