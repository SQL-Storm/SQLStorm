-- {"query": "50051.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "gemini-2.5-pro", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2074, "output_tokens": 1375} 

WITH TaggedQuestions AS (
  -- Find all non-closed questions with a 'sql' tag and positive score created after 2015
  SELECT
    p.Id,
    p.OwnerUserId,
    p.CreationDate AS QuestionCreationDate,
    p.ViewCount,
    EXTRACT(YEAR FROM p.CreationDate) AS QuestionYear
  FROM Posts AS p
  WHERE
    p.PostTypeId = 1 -- Question
    AND p.Tags LIKE '%<sql>%'
    AND p.ClosedDate IS NULL
    AND p.Score > 0
    AND p.CreationDate > '2015-01-01'
), AnswerContributions AS (
  -- Find all answers to the above questions, calculate time-to-answer
  SELECT
    a.OwnerUserId,
    tq.Id AS QuestionId,
    a.Score AS AnswerScore,
    tq.QuestionYear,
    tq.ViewCount AS QuestionViewCount,
    EXTRACT(EPOCH FROM (a.CreationDate - tq.QuestionCreationDate)) / 3600 AS HoursToAnswer
  FROM Posts AS a
  JOIN TaggedQuestions AS tq
    ON a.ParentId = tq.Id
  WHERE
    a.PostTypeId = 2 -- Answer
    AND a.OwnerUserId IS NOT NULL
), UserYearlyStats AS (
  -- Aggregate user contributions per year for the 'sql' tag
  SELECT
    ac.OwnerUserId,
    ac.QuestionYear,
    SUM(ac.AnswerScore) AS TotalAnswerScore,
    COUNT(ac.QuestionId) AS TotalAnswers,
    SUM(ac.QuestionViewCount) AS TotalQuestionViewCount,
    AVG(ac.HoursToAnswer) AS AvgHoursToAnswer,
    STDDEV(ac.HoursToAnswer) AS StdDevHoursToAnswer
  FROM AnswerContributions AS ac
  GROUP BY
    ac.OwnerUserId,
    ac.QuestionYear
), BadgeStats AS (
  -- Calculate badge counts per user per year
  SELECT
    b.UserId,
    EXTRACT(YEAR FROM b.Date) AS BadgeYear,
    COUNT(*) FILTER (WHERE b.Class = 1) AS GoldBadges,
    COUNT(*) FILTER (WHERE b.Class = 2) AS SilverBadges,
    COUNT(*) FILTER (WHERE b.Class = 3) AS BronzeBadges
  FROM Badges AS b
  GROUP BY
    b.UserId,
    BadgeYear
), UserActivityLag AS (
    -- For each user, find the date of their previous comment to calculate activity frequency
    SELECT
        c.UserId,
        c.CreationDate,
        LAG(c.CreationDate, 1) OVER (PARTITION BY c.UserId ORDER BY c.CreationDate) AS PreviousCommentDate
    FROM Comments AS c
    WHERE c.UserId IS NOT NULL
), AvgCommentFrequency AS (
    -- Calculate the average time between comments for each user
    SELECT
        UserId,
        AVG(EXTRACT(EPOCH FROM (CreationDate - PreviousCommentDate))) / 86400.0 AS AvgDaysBetweenComments
    FROM UserActivityLag
    WHERE PreviousCommentDate IS NOT NULL
    GROUP BY UserId
), RankedUsers AS (
  -- Combine all stats, calculate a composite "influence score", and rank users per year
  SELECT
    uys.OwnerUserId,
    u.DisplayName,
    u.Reputation,
    uys.QuestionYear,
    (
      uys.TotalAnswerScore * 10 + 
      (COALESCE(bs.GoldBadges, 0) * 100) + 
      (COALESCE(bs.SilverBadges, 0) * 25) + 
      (uys.TotalQuestionViewCount / 1000) - 
      (uys.AvgHoursToAnswer * 2)
    ) AS InfluenceScore,
    uys.TotalAnswers,
    uys.AvgHoursToAnswer,
    uys.StdDevHoursToAnswer,
    COALESCE(acf.AvgDaysBetweenComments, -1) AS AvgDaysBetweenComments,
    ROW_NUMBER() OVER (PARTITION BY uys.QuestionYear ORDER BY (
      uys.TotalAnswerScore * 10 + 
      (COALESCE(bs.GoldBadges, 0) * 100) + 
      (COALESCE(bs.SilverBadges, 0) * 25) + 
      (uys.TotalQuestionViewCount / 1000) - 
      (uys.AvgHoursToAnswer * 2)
    ) DESC, uys.TotalAnswers DESC) AS YearlyRank
  FROM UserYearlyStats AS uys
  JOIN Users AS u
    ON uys.OwnerUserId = u.Id
  LEFT JOIN BadgeStats AS bs
    ON uys.OwnerUserId = bs.UserId AND uys.QuestionYear = bs.BadgeYear
  LEFT JOIN AvgCommentFrequency AS acf
    ON uys.OwnerUserId = acf.UserId
  WHERE
    uys.TotalAnswers > 5
)
-- Final selection: Top 10 most influential 'sql' tag contributors for each year
-- Also include a correlated subquery to find their most recent post edit date.
SELECT
  ru.QuestionYear,
  ru.YearlyRank,
  ru.DisplayName,
  ru.Reputation,
  CAST(ru.InfluenceScore AS INT) AS InfluenceScore,
  ru.TotalAnswers,
  ru.AvgHoursToAnswer,
  ru.AvgDaysBetweenComments,
  (
    SELECT MAX(ph.CreationDate)
    FROM PostHistory AS ph
    WHERE ph.UserId = ru.OwnerUserId AND ph.PostHistoryTypeId IN (4, 5, 6) -- Edit Title, Body, or Tags
  ) AS LastPostEditDate
FROM RankedUsers AS ru
WHERE
  ru.YearlyRank <= 10
ORDER BY
  ru.QuestionYear DESC,
  ru.YearlyRank ASC;
