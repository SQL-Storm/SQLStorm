-- {"query": "50084.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "gemini-2.5-pro", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2074, "output_tokens": 1052} 
WITH PopularTags AS (
  SELECT
    TagName
  FROM Tags
  ORDER BY
    Count DESC
  LIMIT 20
), PowerUsers AS (
  SELECT
    U.Id,
    U.DisplayName,
    U.Reputation
  FROM
    Users AS U
    JOIN (
      SELECT
        UserId,
        COUNT(*) AS GoldBadges
      FROM
        Badges
      WHERE
        Class = 1
      GROUP BY
        UserId
    ) AS GB
    ON U.Id = GB.UserId
  WHERE
    U.Reputation > (
      SELECT
        percentile_cont(0.99) WITHIN GROUP (
          ORDER BY
            Reputation
        )
      FROM
        Users
    )
    AND GB.GoldBadges >= 5
    AND U.LastAccessDate > cast('2024-10-01 12:34:56' as timestamp) - INTERVAL '1 year'
), UserAnswersInPopularTags AS (
  SELECT
    A.OwnerUserId,
    A.Id AS AnswerId,
    A.Score AS AnswerScore,
    EXTRACT(EPOCH FROM (A.CreationDate - Q.CreationDate)) / 3600.0 AS HoursToAnswer
  FROM
    Posts AS Q
    JOIN Posts AS A
    ON Q.Id = A.ParentId
    JOIN PowerUsers AS PU
    ON A.OwnerUserId = PU.Id
  WHERE
    Q.PostTypeId = 1
    AND A.PostTypeId = 2
    AND A.CreationDate > Q.CreationDate
    AND EXISTS (
      SELECT
        1
      FROM
        PopularTags AS PT
      WHERE
        Q.Tags LIKE '%<' || PT.TagName || '>%'
    )
), UserStats AS (
  SELECT
    OwnerUserId,
    COUNT(AnswerId) AS TotalAnswersInPopularTags,
    AVG(AnswerScore) AS AvgAnswerScore,
    AVG(HoursToAnswer) AS AvgHoursToAnswer,
    SUM(CASE WHEN AnswerScore > 100 THEN 1 ELSE 0 END) AS HighScoreAnswers,
    MIN(HoursToAnswer) AS FastestAnswerHours,
    percentile_cont(0.5) WITHIN GROUP (
      ORDER BY
        HoursToAnswer
    ) AS MedianHoursToAnswer
  FROM
    UserAnswersInPopularTags
  GROUP BY
    OwnerUserId
), UserRecentActivity AS (
  SELECT
    UserId,
    COUNT(CASE WHEN VoteTypeId = 2 THEN 1 END) AS UpvotesGiven,
    COUNT(CASE WHEN VoteTypeId = 3 THEN 1 END) AS DownvotesGiven,
    COUNT(DISTINCT PostId) AS UniquePostsVotedOn
  FROM
    Votes
  WHERE
    UserId IN (
      SELECT
        Id
      FROM
        PowerUsers
    )
    AND CreationDate > cast('2024-10-01 12:34:56' as timestamp) - INTERVAL '6 months'
  GROUP BY
    UserId
)
SELECT
  PU.DisplayName,
  PU.Reputation,
  US.TotalAnswersInPopularTags,
  US.AvgAnswerScore,
  US.AvgHoursToAnswer,
  US.HighScoreAnswers,
  US.MedianHoursToAnswer,
  URA.UpvotesGiven,
  URA.DownvotesGiven,
  DENSE_RANK() OVER (ORDER BY (US.AvgAnswerScore * LOG(US.TotalAnswersInPopularTags + 1)) DESC, US.MedianHoursToAnswer ASC) AS UserRank,
  (
    SELECT
      STRING_AGG(B.Name, ', ' ORDER BY B.Date)
    FROM
      (
        SELECT
          Name,
          Date
        FROM
          Badges
        WHERE
          UserId = PU.Id
        ORDER BY
          Date DESC
        LIMIT 5
      ) AS B
  ) AS LatestBadges,
  (
    SELECT
      P_sub.Title
    FROM
      Posts AS P_sub
    WHERE
      P_sub.Id = (
        SELECT
          PostId
        FROM
          Votes AS V_sub
        WHERE
          V_sub.UserId = PU.Id
          AND V_sub.VoteTypeId = 2
        ORDER BY
          V_sub.CreationDate DESC
        LIMIT 1
      )
  ) AS LastUpvotedQuestionTitle
FROM
  PowerUsers AS PU
  JOIN UserStats AS US
  ON PU.Id = US.OwnerUserId
  LEFT JOIN UserRecentActivity AS URA
  ON PU.Id = URA.UserId
WHERE
  US.TotalAnswersInPopularTags > 10
ORDER BY
  UserRank,
  PU.Reputation DESC
LIMIT 100;