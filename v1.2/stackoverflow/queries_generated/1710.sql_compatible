WITH UserAnalytics AS (
  SELECT
    u.Id AS UserId,
    u.DisplayName,
    u.Reputation,
    u.CreationDate,
    AVG(COALESCE(p.Score, 0)) FILTER (WHERE p.PostTypeId = 1) AS AvgQuestionScore,
    AVG(COALESCE(p.Score, 0)) FILTER (WHERE p.PostTypeId = 2) AS AvgAnswerScore,
    COALESCE(SUM(CASE WHEN v.VoteTypeId = 8 THEN v.BountyAmount ELSE 0 END), 0) AS TotalBountyStarted,
    GREATEST(
      MAX(p.CreationDate),
      MAX(v.CreationDate),
      MAX(b.Date),
      u.LastAccessDate
    ) AS LastActiveDate,
    u.Views,
    u.UpVotes,
    u.DownVotes,
    u.Location,
    COUNT(b.ID) AS BadgeCount,
    COUNT(*) FILTER (WHERE p.PostTypeId = 1) AS QuestionCount,
    COUNT(*) FILTER (WHERE p.PostTypeId = 2) AS AnswerCount
  FROM Users u
  LEFT JOIN Posts p ON p.OwnerUserId = u.Id
  LEFT JOIN Votes v ON v.UserId = u.Id
  LEFT JOIN Badges b ON b.UserId = u.Id
  GROUP BY
    u.Id,
    u.DisplayName,
    u.Reputation,
    u.CreationDate,
    u.LastAccessDate,
    u.Views,
    u.UpVotes,
    u.DownVotes,
    u.Location
)
SELECT *
FROM UserAnalytics;