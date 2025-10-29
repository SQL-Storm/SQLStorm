WITH TopQuestioners AS (
  SELECT
    u.Id AS UserId,
    u.DisplayName,
    u.Reputation,
    COUNT(p.Id) AS QuestionCount,
    SUM(p.Score) AS ScoreSum,
    AVG(p.ViewCount) AS AvgViews
  FROM Users u
  JOIN Posts p ON p.OwnerUserId = u.Id
  WHERE p.PostTypeId = 1
    AND p.CreationDate >= CAST('2024-10-01 12:34:56' AS timestamp) - INTERVAL '180 days'
  GROUP BY u.Id, u.DisplayName, u.Reputation
),
TaggedActivity AS (
  SELECT
    p.OwnerUserId AS UserId,
    t.TagName,
    COUNT(*) AS TagQuestionCount
  FROM Posts p
  JOIN LATERAL (
    SELECT unnest(string_to_array(substr(p.Tags, 2, length(p.Tags)-2), '><')) AS TagName
  ) t ON TRUE
  WHERE p.PostTypeId = 1
    AND p.CreationDate >= CAST('2024-10-01 12:34:56' AS timestamp) - INTERVAL '365 days'
  GROUP BY p.OwnerUserId, t.TagName
),
Engagement AS (
  SELECT
    p.OwnerUserId AS UserId,
    COUNT(*) AS AnswerCount,
    SUM(p.ViewCount) AS TotalViews,
    SUM(p.Score) AS TotalScore
  FROM Posts p
  WHERE p.PostTypeId = 2
    AND p.CreationDate >= CAST('2024-10-01 12:34:56' AS timestamp) - INTERVAL '365 days'
  GROUP BY p.OwnerUserId
),
RecentBounties AS (
  SELECT
    v.UserId,
    SUM(v.BountyAmount) AS TotalBounty
  FROM Votes v
  WHERE v.VoteTypeId = 8
    AND v.CreationDate >= CAST('2024-10-01 12:34:56' AS timestamp) - INTERVAL '180 days'
  GROUP BY v.UserId
),
Combined AS (
  SELECT
    u.Id AS UserId,
    u.DisplayName,
    COALESCE(tq.QuestionCount, 0) AS QuestionCount_Last180,
    COALESCE(tq.ScoreSum, 0) AS ScoreSum_Last180,
    COALESCE(tq.AvgViews, 0) AS AvgQuestionViews_Last180,
    COALESCE(ta.TagQuestionCount, 0) AS TagParticipation_Last365,
    COALESCE(e.AnswerCount, 0) AS AnswerCount_Last365,
    COALESCE(e.TotalViews, 0) AS TotalAnswerViews_Last365,
    COALESCE(e.TotalScore, 0) AS TotalAnswerScore_Last365,
    COALESCE(rb.TotalBounty, 0) AS TotalBounty_Last180
  FROM Users u
  LEFT JOIN TopQuestioners tq ON tq.UserId = u.Id
  LEFT JOIN Engagement e ON e.UserId = u.Id
  LEFT JOIN TaggedActivity ta ON ta.UserId = u.Id
  LEFT JOIN RecentBounties rb ON rb.UserId = u.Id
  GROUP BY
    u.Id,
    u.DisplayName,
    COALESCE(tq.QuestionCount, 0),
    COALESCE(tq.ScoreSum, 0),
    COALESCE(tq.AvgViews, 0),
    COALESCE(ta.TagQuestionCount, 0),
    COALESCE(e.AnswerCount, 0),
    COALESCE(e.TotalViews, 0),
    COALESCE(e.TotalScore, 0),
    COALESCE(rb.TotalBounty, 0)
)
SELECT
  UserId,
  DisplayName,
  QuestionCount_Last180,
  ScoreSum_Last180,
  AvgQuestionViews_Last180,
  TagParticipation_Last365,
  AnswerCount_Last365,
  TotalAnswerViews_Last365,
  TotalAnswerScore_Last365,
  TotalBounty_Last180
FROM Combined
WHERE QuestionCount_Last180 > 0
   OR TagParticipation_Last365 > 0
ORDER BY
  TotalAnswerScore_Last365 DESC,
  QuestionCount_Last180 DESC,
  TotalBounty_Last180 DESC
LIMIT 100;