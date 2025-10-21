-- {"query": "20070.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p1", "model": "gemini-2.5-pro", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 1556} 

WITH UserActivitySummary AS (
  SELECT
    u.Id AS UserId,
    u.DisplayName,
    u.Reputation,
    u.CreationDate AS UserCreationDate,
    u.Location,
    COUNT(DISTINCT p.Id) AS TotalPosts,
    SUM(CASE WHEN p.PostTypeId = 1 THEN 1 ELSE 0 END) AS QuestionCount,
    SUM(CASE WHEN p.PostTypeId = 2 THEN 1 ELSE 0 END) AS AnswerCount,
    SUM(p.Score) AS TotalPostScore,
    SUM(p.ViewCount) AS TotalViewCount,
    SUM(p.FavoriteCount) AS TotalFavoriteCount,
    (
      SELECT COUNT(*)
      FROM Votes v
      WHERE
        v.UserId = u.Id AND v.VoteTypeId IN (2, 3)
    ) AS TotalVotesCast,
    (
      SELECT STRING_AGG(b.Name, ', ' ORDER BY b.Class, b.Date)
      FROM Badges b
      WHERE
        b.UserId = u.Id AND b.Class = 1
      GROUP BY
        b.UserId
    ) AS GoldBadges
  FROM Users u
  LEFT JOIN Posts p
    ON u.Id = p.OwnerUserId
  WHERE
    u.CreationDate BETWEEN '2015-01-01' AND '2020-12-31' AND u.Reputation > 1000 AND p.CommunityOwnedDate IS NULL
  GROUP BY
    u.Id,
    u.DisplayName,
    u.Reputation,
    u.CreationDate,
    u.Location
  HAVING
    SUM(CASE WHEN p.PostTypeId = 2 THEN 1 ELSE 0 END) > SUM(CASE WHEN p.PostTypeId = 1 THEN 1 ELSE 0 END)
), QuestionAnalysis AS (
  SELECT
    q.Id AS QuestionId,
    q.OwnerUserId,
    q.CreationDate AS QuestionCreationDate,
    q.Score AS QuestionScore,
    q.Tags,
    MIN(a.CreationDate) AS FirstAnswerDate,
    (
      SELECT aa.CreationDate
      FROM Posts aa
      WHERE
        aa.Id = q.AcceptedAnswerId
    ) AS AcceptedAnswerDate,
    COUNT(a.Id) AS NumAnswers,
    AVG(a.Score) AS AvgAnswerScore
  FROM Posts q
  LEFT JOIN Posts a
    ON q.Id = a.ParentId AND a.PostTypeId = 2
  WHERE
    q.PostTypeId = 1 AND q.ClosedDate IS NULL AND q.AnswerCount > 0
  GROUP BY
    q.Id,
    q.OwnerUserId,
    q.CreationDate,
    q.Score,
    q.Tags,
    q.AcceptedAnswerId
), UserContributionsRanked AS (
  SELECT
    uas.UserId,
    uas.DisplayName,
    uas.Reputation,
    uas.UserCreationDate,
    COALESCE(uas.Location, 'Unknown') AS Location,
    uas.TotalPosts,
    uas.QuestionCount,
    uas.AnswerCount,
    uas.TotalPostScore,
    uas.TotalViewCount,
    uas.TotalVotesCast,
    uas.GoldBadges,
    q.QuestionId,
    q.QuestionCreationDate,
    q.QuestionScore,
    q.Tags,
    EXTRACT(EPOCH FROM (q.FirstAnswerDate - q.QuestionCreationDate)) / 3600 AS HoursToFirstAnswer,
    EXTRACT(EPOCH FROM (q.AcceptedAnswerDate - q.QuestionCreationDate)) / 86400 AS DaysToAcceptedAnswer,
    RANK() OVER (PARTITION BY uas.Location ORDER BY uas.Reputation DESC) AS RankInLocation,
    LAG(q.QuestionCreationDate, 1, q.QuestionCreationDate) OVER (PARTITION BY uas.UserId ORDER BY q.QuestionCreationDate) AS PreviousQuestionDate,
    (
      SELECT AVG(c.Score)
      FROM Comments c
      WHERE
        c.PostId = q.QuestionId
    ) AS AvgCommentScoreOnQuestion
  FROM UserActivitySummary uas
  JOIN QuestionAnalysis q
    ON uas.UserId = q.OwnerUserId
  WHERE
    q.NumAnswers > 2
  UNION ALL
  SELECT
    u.Id,
    u.DisplayName,
    u.Reputation,
    u.CreationDate,
    'Orphaned User',
    0,
    0,
    0,
    0,
    0,
    0,
    NULL,
    NULL,
    NULL,
    NULL,
    NULL,
    NULL,
    NULL,
    NULL,
    NULL,
    NULL
  FROM Users u
  WHERE
    u.Reputation < 10 AND NOT EXISTS (
      SELECT 1
      FROM Posts p
      WHERE
        p.OwnerUserId = u.Id
    ) AND u.Id BETWEEN 5000 AND 10000
)
SELECT
  ucr.DisplayName,
  ucr.Reputation,
  ucr.Location,
  ucr.RankInLocation,
  ucr.TotalPosts,
  ucr.TotalPostScore / NULLIF(ucr.TotalPosts, 0) AS AvgScorePerPost,
  CASE
    WHEN ucr.DaysToAcceptedAnswer < 1 THEN 'Highly Responsive'
    WHEN ucr.DaysToAcceptedAnswer BETWEEN 1 AND 7 THEN 'Moderately Responsive'
    WHEN ucr.DaysToAcceptedAnswer > 7 THEN 'Slow Response'
    ELSE 'No Accepted Answer'
  END AS Responsiveness,
  ucr.GoldBadges,
  ucr.Tags,
  ucr.AvgCommentScoreOnQuestion,
  REPLACE(LOWER(SUBSTRING(ucr.Tags, 2, 15)), '><', '-') AS PrimaryTag,
  EXTRACT(EPOCH FROM (ucr.QuestionCreationDate - ucr.PreviousQuestionDate)) / 86400 AS DaysSinceLastQuestion
FROM UserContributionsRanked ucr
WHERE
  (
    ucr.RankInLocation <= 10 OR ucr.Reputation > (
      SELECT percentile_cont(0.95) WITHIN GROUP (ORDER BY Reputation)
      FROM Users
    )
  ) AND ucr.Location != 'Orphaned User' AND ucr.QuestionScore > (
    SELECT AVG(Score)
    FROM Posts
    WHERE
      PostTypeId = 1 AND CreationDate > ucr.UserCreationDate
  )
ORDER BY
  ucr.Location,
  ucr.RankInLocation,
  DaysSinceLastQuestion DESC
LIMIT 200;
