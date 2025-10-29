WITH
RecentActivePostPairs AS (
  SELECT
    p.Id AS PostId,
    p.OwnerUserId,
    p.Title
  FROM Posts p
  WHERE p.CreationDate >= CAST('2024-10-01 12:34:56' AS timestamp) - INTERVAL '180 days'
),
TaggedActivity AS (
  SELECT
    p.Id AS PostId,
    t.TagName,
    p.Score,
    p.ViewCount,
    p.AnswerCount,
    p.CommentCount,
    p.LastActivityDate,
    ROW_NUMBER() OVER (PARTITION BY t.TagName ORDER BY p.LastActivityDate DESC) AS rn
  FROM Posts p
  JOIN LATERAL (
    SELECT UNNEST(string_to_array(SUBSTRING(p.Tags FROM 2 FOR (length(p.Tags)-2)), '><')) AS TagName
  ) t ON TRUE
  WHERE p.PostTypeId = 1
),
TopTags AS (
  SELECT
    TagName,
    AVG(Score) AS AvgScore,
    SUM(ViewCount) AS TotalViews,
    MAX(LastActivityDate) AS LastActive
  FROM TaggedActivity
  GROUP BY TagName
  ORDER BY AvgScore DESC, TotalViews DESC
  LIMIT 20
),
CrossTagMetrics AS (
  SELECT
    tt.TagName,
    tt.AvgScore,
    tt.TotalViews,
    tt.LastActive,
    (SELECT COUNT(*) FROM Posts p WHERE p.PostTypeId = 1 AND POSITION('/' || tt.TagName || '/' IN p.Tags) > 0) AS RelatedQuestionCount,
    (SELECT AVG(COALESCE(v.BountyAmount, 0)) FROM Votes v JOIN Posts ps ON v.PostId = ps.Id WHERE ps.Title LIKE '%' || tt.TagName || '%' AND v.VoteTypeId = 8) AS AvgBounty
  FROM TopTags tt
)
SELECT
  ct.TagName,
  ct.AvgScore,
  ct.TotalViews,
  ct.LastActive,
  ct.RelatedQuestionCount,
  ct.AvgBounty,
  (SELECT STRING_AGG(DISTINCT u.DisplayName, ', ')
   FROM Votes v
   JOIN Posts ps ON v.PostId = ps.Id
   JOIN Users u ON v.UserId = u.Id
   WHERE ps.Title LIKE '%' || ct.TagName || '%'
     AND v.VoteTypeId = 2
     AND u.Id IS NOT NULL) AS TopUpvoters
FROM CrossTagMetrics ct
GROUP BY
  ct.TagName,
  ct.AvgScore,
  ct.TotalViews,
  ct.LastActive,
  ct.RelatedQuestionCount,
  ct.AvgBounty
ORDER BY ct.TotalViews DESC, ct.AvgScore DESC
LIMIT 50;