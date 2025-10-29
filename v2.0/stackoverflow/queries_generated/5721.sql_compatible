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
    p.AnswerCount,
    p.FavoriteCount,
    p.ParentId,
    p.AcceptedAnswerId
  FROM Posts p
  WHERE p.CreationDate >= CAST('2024-10-01 12:34:56' AS timestamp) - INTERVAL '180 days'
),
TopTags AS (
  SELECT
    tgn.TagName AS TagName,
    COUNT(*) AS TagPostCount,
    AVG(rap.Score) AS AvgPostScore,
    SUM(rap.ViewCount) AS SumViews
  FROM RecentActivePosts rap
  CROSS JOIN LATERAL unnest(string_to_array(rap.Tags, '<>')) AS tgn(TagName)
  GROUP BY tgn.TagName
  ORDER BY SumViews DESC
  LIMIT 10
),
TagActivity AS (
  SELECT
    t.TagName,
    COUNT(*) FILTER (WHERE p.PostTypeId = 1) AS Questions,
    COUNT(*) FILTER (WHERE p.PostTypeId = 2) AS Answers,
    SUM(p.ViewCount) AS TotalViews,
    AVG(p.Score) AS AvgScore
  FROM RecentActivePosts p
  CROSS JOIN LATERAL unnest(string_to_array(p.Tags, '<>')) AS tgn(TagName)
  JOIN TopTags t ON t.TagName = tgn.TagName
  GROUP BY t.TagName
),
CorrelatedStats AS (
  SELECT
    p.Id AS PostId,
    p.Title,
    p.OwnerUserId,
    u.DisplayName AS OwnerName,
    p.CreationDate,
    p.LastActivityDate,
    p.Score,
    p.ViewCount,
    v1.Name AS VoteTypeName,
    v.CreationDate AS VoteDate,
    CASE
      WHEN p.OwnerUserId IS NULL THEN 'Unknown'
      WHEN u.Reputation < 100 THEN 'Low'
      WHEN u.Reputation < 1000 THEN 'Medium'
      ELSE 'High'
    END AS OwnerReputationBand,
    (SELECT COUNT(*) FROM Votes v2 WHERE v2.PostId = p.Id) AS TotalVotes,
    (SELECT STRING_AGG(vt.Name, ',')
     FROM Votes v3
     JOIN VoteTypes vt ON v3.VoteTypeId = vt.Id
     WHERE v3.PostId = p.Id) AS AllVoteTypes
  FROM RecentActivePosts p
  LEFT JOIN Users u ON p.OwnerUserId = u.Id
  LEFT JOIN Votes v ON v.PostId = p.Id AND v.VoteTypeId IN (2,3)
  LEFT JOIN VoteTypes v1 ON v.VoteTypeId = v1.Id
  ORDER BY p.LastActivityDate DESC, p.Id
  LIMIT 50
),
ExposedAggregates AS (
  SELECT
    ct.TagName,
    SUM(ct.Questions) AS TotalQuestions,
    SUM(ct.Answers) AS TotalAnswers,
    SUM(ct.TotalViews) AS TotalViewsAcrossPosts,
    AVG(ct.AvgScore) AS AvgPostScore
  FROM TagActivity ct
  GROUP BY ct.TagName
)
SELECT
  ta.TagName,
  ta.Questions,
  ta.Answers,
  ta.TotalViews,
  ta.AvgScore,
  ra.PostId,
  ra.Title,
  ra.OwnerName,
  ra.CreationDate,
  ra.LastActivityDate,
  ra.Score,
  ra.ViewCount,
  ra.VoteTypeName,
  ra.VoteDate,
  ra.OwnerReputationBand,
  ra.TotalVotes,
  ra.AllVoteTypes,
  ea.TotalQuestions AS TopTagQuestions,
  ea.TotalAnswers AS TopTagAnswers,
  ea.TotalViewsAcrossPosts AS TopTagTotalViews
FROM TagActivity ta
CROSS JOIN CorrelatedStats ra
LEFT JOIN ExposedAggregates ea ON ta.TagName = ea.TagName
ORDER BY ta.TagName, ra.LastActivityDate DESC, ra.PostId
LIMIT 200;