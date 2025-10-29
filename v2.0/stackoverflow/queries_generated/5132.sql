-- {"query": "5132.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-5-nano", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 849} 
WITH
RecentHot AS (
  SELECT
    p.Id AS PostId,
    p.Title,
    p.CreationDate,
    p.ViewCount,
    p.Score,
    p.OwnerUserId,
    p.Tags,
    p.LastActivityDate,
    COUNT(v.Id) AS VoteCount
  FROM Posts p
  LEFT JOIN Votes v ON v.PostId = p.Id AND v.VoteTypeId IN (2,3)
  WHERE p.PostTypeId = 1 -- questions
    AND p.ClosedDate IS NULL
  GROUP BY p.Id, p.Title, p.CreationDate, p.ViewCount, p.Score, p.OwnerUserId, p.Tags, p.LastActivityDate
),
TagStats AS (
  SELECT
    t.TagName,
    COUNT(*) AS TagQuestionCount,
    AVG(p.Score) AS AvgQuestionScore,
    SUM(p.ViewCount) AS TotalViews
  FROM Posts p
  JOIN UNNEST(string_to_array(substr(p.Tags, 2, length(p.Tags)-2), '><')) AS t(TagName)
  WHERE p.PostTypeId = 1
  GROUP BY t.TagName
),
UserActivity AS (
  SELECT
    u.Id AS UserId,
    u.DisplayName,
    u.Reputation,
    u.AccountId,
    COUNT(p.Id) FILTER (WHERE p.PostTypeId = 1) AS Questions,
    COUNT(p.Id) FILTER (WHERE p.PostTypeId = 2) AS Answers,
    COUNT(c.Id) AS CommentsMade,
    AVG(p.Score) AS AvgPostScore,
    MAX(p.LastActivityDate) AS LastActive
  FROM Users u
  LEFT JOIN Posts p ON p.OwnerUserId = u.Id
  LEFT JOIN Comments c ON c.UserId = u.Id
  GROUP BY u.Id, u.DisplayName, u.Reputation, u.AccountId
),
CorrelatedInsights AS (
  SELECT
    rh.PostId,
    rh.Title,
    rh.ViewCount,
    rh.Score,
    rh.VoteCount,
    us.LastActive,
    us.Reputation AS UserReputation,
    CASE
      WHEN rh.ViewCount > 1000 THEN 'High-Visibility'
      WHEN rh.Score < 0 THEN 'Low-Score'
      ELSE 'Moderate'
    END AS VisibilityBucket
  FROM RecentHot rh
  LEFT JOIN UserActivity us ON us.UserId = rh.OwnerUserId
),
ComplexAggregate AS (
  SELECT
    ci.PostId,
    ci.Title,
    ci.ViewCount,
    ci.Score,
    ci.VoteCount,
    ci.LastActive,
    ci.UserReputation,
    ci.VisibilityBucket,
    (ci.ViewCount * 0.5 + ci.Score * 2) AS EngagementScore,
    (SELECT AVG(v.BountyAmount) FROM Votes v WHERE v.PostId = ci.PostId AND v.BountyAmount IS NOT NULL) AS AvgBounty
  FROM CorrelatedInsights ci
)
SELECT
  ca.PostId,
  ca.Title,
  ca.ViewCount,
  ca.Score AS PostScore,
  ca.VoteCount,
  ca.LastActive,
  ca.UserReputation,
  ca.VisibilityBucket,
  ca.EngagementScore,
  ca.AvgBounty,
  ts.TagName,
  ts.TagQuestionCount,
  ts.AvgQuestionScore,
  ts.TotalViews,
  a.DisplayName AS LastEditor,
  a2.DisplayName AS OwnerDisplay
FROM ComplexAggregate ca
LEFT JOIN LATERAL (
  SELECT t.TagName
  FROM UNNEST(string_to_array(substr((SELECT Tags FROM Posts WHERE Id = ca.PostId), 2, length((SELECT Tags FROM Posts WHERE Id = ca.PostId))-2), '><')) AS TagName
  LIMIT 1
) AS ts ON TRUE
LEFT JOIN Posts p2 ON p2.Id = ca.PostId
LEFT JOIN Users a ON a.Id = p2.LastEditorUserId
LEFT JOIN Users a2 ON a2.Id = p2.OwnerUserId
ORDER BY ca.EngagementScore DESC NULLS LAST
LIMIT 100;