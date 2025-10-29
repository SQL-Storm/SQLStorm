WITH RECURSIVE RecursiveTagCounts AS (
  SELECT
    t.Id AS TagId,
    t.TagName,
    p.Id AS PostId,
    p.CreationDate,
    p.Score,
    1 AS Depth
  FROM Tags t
  JOIN Posts p ON p.Tags LIKE '%' || '<' || t.TagName || '>' || '%'
  WHERE p.PostTypeId = 1

  UNION ALL

  SELECT
    rtc.TagId,
    rtc.TagName,
    pl.RelatedPostId,
    p2.CreationDate,
    p2.Score,
    rtc.Depth + 1
  FROM RecursiveTagCounts rtc
  JOIN PostLinks pl ON pl.PostId = rtc.PostId AND pl.LinkTypeId = 1
  JOIN Posts p2 ON p2.Id = pl.RelatedPostId
  WHERE rtc.Depth < 3
),
UserActivityRanked AS (
  SELECT
    u.Id,
    u.DisplayName,
    COUNT(DISTINCT b.Id) AS BadgeCount,
    COUNT(DISTINCT p.Id) AS PostCount,
    COUNT(DISTINCT c.Id) AS CommentCount,
    RANK() OVER (
      ORDER BY COALESCE(NULLIF(u.Reputation, 0), 0) DESC,
               COUNT(DISTINCT b.Id) DESC,
               COUNT(DISTINCT p.Id) DESC
    ) AS UserRank
  FROM Users u
  LEFT JOIN Badges b ON b.UserId = u.Id AND b.Date > (CAST('2024-10-01' AS date) - INTERVAL '365 days')
  LEFT JOIN Posts p ON p.OwnerUserId = u.Id AND p.CreationDate > (CAST('2024-10-01' AS date) - INTERVAL '365 days')
  LEFT JOIN Comments c ON c.UserId = u.Id AND c.CreationDate > (CAST('2024-10-01' AS date) - INTERVAL '365 days')
  GROUP BY u.Id, u.DisplayName, u.Reputation
),
QuestionWithAnswers AS (
  SELECT
    q.Id AS QuestionId,
    q.Title,
    q.CreationDate AS QuestionCreated,
    q.Score AS QuestionScore,
    q.ViewCount,
    a.Id AS AnswerId,
    a.CreationDate AS AnswerCreated,
    a.Score AS AnswerScore,
    u.DisplayName AS OwnerName,
    (SELECT COUNT(*) FROM Comments c WHERE c.PostId = q.Id) AS QuestionComments,
    (SELECT COUNT(*) FROM Comments c WHERE c.PostId = a.Id) AS AnswerComments
  FROM Posts q
  LEFT JOIN Posts a ON a.ParentId = q.Id AND a.PostTypeId = 2
  LEFT JOIN Users u ON u.Id = q.OwnerUserId
  WHERE q.PostTypeId = 1
),
TaggedQuestions AS (
  SELECT
    t.TagName,
    COUNT(DISTINCT p.Id) AS QuestionCount,
    AVG(p.Score) AS AvgScore,
    SUM(CASE WHEN p.AcceptedAnswerId IS NOT NULL THEN 1 ELSE 0 END) * 1.0 / NULLIF(COUNT(DISTINCT p.Id), 0) AS AcceptanceRate,
    MAX(p.ViewCount) AS MaxViews,
    STRING_AGG(u.DisplayName, ',' ) FILTER (WHERE u.DisplayName IS NOT NULL) AS TopUsersByReputation,
    MAX(u.Reputation) AS MaxReputationForOrdering
  FROM Tags t
  JOIN Posts p ON p.PostTypeId = 1 AND p.Tags LIKE '%' || '<' || t.TagName || '>' || '%'
  LEFT JOIN Users u ON u.Id = p.OwnerUserId
  GROUP BY t.TagName
)
SELECT
  q.QuestionId,
  q.Title,
  q.QuestionCreated,
  q.QuestionScore,
  q.ViewCount,
  q.AnswerId,
  q.AnswerCreated,
  q.AnswerScore,
  COALESCE(q.OwnerName, 'Anonymous') AS OwnerName,
  q.QuestionComments,
  q.AnswerComments,
  u.UserRank,
  u.BadgeCount,
  u.PostCount,
  u.CommentCount,
  t.TagName,
  t.QuestionCount,
  ROUND(CAST(t.AvgScore AS numeric), 2) AS AvgScore,
  ROUND(t.AcceptanceRate * 100, 2) AS AcceptancePercent,
  t.MaxViews,
  SUBSTRING(t.TopUsersByReputation FROM 1 FOR 100) AS TopUsersByReputationSnippet,
  rtc.Depth AS TagRelationDepth,
  rtc.Score AS RelatedPostScore,
  rtc.CreationDate AS RelatedPostDate
FROM QuestionWithAnswers q
LEFT JOIN UserActivityRanked u ON u.Id = (
  SELECT OwnerUserId FROM Posts WHERE Id = q.QuestionId
)
LEFT JOIN LATERAL (
  SELECT TagName, QuestionCount, AvgScore, AcceptanceRate, MaxViews, TopUsersByReputation
  FROM TaggedQuestions t
  WHERE q.Title IS NOT NULL
  ORDER BY MaxReputationForOrdering DESC
  LIMIT 1
) t ON true
LEFT JOIN RecursiveTagCounts rtc ON rtc.PostId = q.QuestionId AND rtc.TagId = (
  SELECT Id FROM Tags WHERE TagName = t.TagName LIMIT 1
)
WHERE q.QuestionScore > 5
  AND (q.AnswerScore IS NULL OR q.AnswerScore > 0)
  AND (u.UserRank BETWEEN 1 AND 100 OR u.UserRank IS NULL)
ORDER BY u.UserRank NULLS LAST, q.QuestionScore DESC, rtc.Depth
LIMIT 100;