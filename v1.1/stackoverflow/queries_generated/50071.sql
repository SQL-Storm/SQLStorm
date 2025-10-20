-- {"query": "50071.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "gemini-2.5-pro", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2074, "output_tokens": 942} 

WITH
  -- CTE to find all answers to 'sql'-tagged questions posted in the last year
  RelevantAnswers AS (
    SELECT
      a.Id,
      a.OwnerUserId,
      a.Score,
      a.CreationDate,
      q.Title AS QuestionTitle,
      q.Tags AS QuestionTags,
      q.ViewCount AS QuestionViewCount
    FROM Posts AS a
    JOIN Posts AS q
      ON a.ParentId = q.Id
    WHERE
      a.PostTypeId = 2 -- Answer
      AND q.PostTypeId = 1 -- Question
      AND a.OwnerUserId IS NOT NULL
      AND a.CreationDate >= (CURRENT_TIMESTAMP - interval '1 year')
      AND q.Tags LIKE '%<sql>%'
  ),
  -- CTE to aggregate user statistics from their relevant answers
  UserAnswerStats AS (
    SELECT
      ra.OwnerUserId,
      COUNT(*) AS AnswerCount,
      AVG(ra.Score) AS AverageAnswerScore,
      MAX(ra.CreationDate) AS LastAnswerDate,
      SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS TotalUpvotesReceived,
      SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS TotalDownvotesReceived,
      SUM(CASE WHEN v.VoteTypeId = 9 THEN v.BountyAmount ELSE 0 END) AS TotalBountyWon
    FROM RelevantAnswers AS ra
    LEFT JOIN Votes AS v
      ON ra.Id = v.PostId
    GROUP BY
      ra.OwnerUserId
    HAVING
      COUNT(*) >= 5 AND AVG(ra.Score) > 0
  ),
  -- CTE to find the title of the question for each user's highest-scoring answer
  TopUserAnswer AS (
    SELECT
      OwnerUserId,
      QuestionTitle AS TopScoringQuestionTitle,
      Score AS TopScore
    FROM (SELECT
      OwnerUserId,
      QuestionTitle,
      Score,
      ROW_NUMBER() OVER (PARTITION BY OwnerUserId ORDER BY Score DESC, CreationDate DESC) AS rn
    FROM RelevantAnswers) AS Ranked
    WHERE
      rn = 1
  ),
  -- CTE to correlate user activity with tag-specific badges
  UserBadges AS (
    SELECT
      UserId,
      COUNT(*) AS SqlRelatedBadgeCount,
      MAX(Date) AS LastBadgeDate
    FROM Badges
    WHERE
      TagBased = B'1'
      AND LOWER(Name) IN ('sql', 'tsql', 'plsql', 'mysql', 'postgresql', 'sql-server', 'oracle')
    GROUP BY
      UserId
  )
-- Final query to assemble the report
SELECT
  u.Id AS UserId,
  u.DisplayName,
  u.Reputation,
  u.Location,
  s.AnswerCount,
  s.AverageAnswerScore,
  s.TotalUpvotesReceived,
  s.TotalBountyWon,
  b.SqlRelatedBadgeCount,
  t.TopScoringQuestionTitle,
  (
    SELECT
      AVG(c.Score)
    FROM Comments AS c
    WHERE
      c.UserId = u.Id AND c.PostId IN (SELECT Id FROM RelevantAnswers WHERE OwnerUserId = u.Id)
  ) AS AverageCommentScoreOnOwnAnswers,
  DENSE_RANK() OVER (PARTITION BY COALESCE(u.Location, 'Unknown') ORDER BY s.TotalUpvotesReceived DESC, s.AnswerCount DESC) AS RankInLocation
FROM Users AS u
JOIN UserAnswerStats AS s
  ON u.Id = s.OwnerUserId
JOIN TopUserAnswer AS t
  ON u.Id = t.OwnerUserId
LEFT JOIN UserBadges AS b
  ON u.Id = b.UserId
WHERE
  u.Reputation > (
    SELECT
      AVG(Reputation)
    FROM Users
  )
  AND u.CreationDate < (CURRENT_TIMESTAMP - interval '2 years')
ORDER BY
  s.TotalUpvotesReceived DESC,
  s.AnswerCount DESC,
  u.Reputation DESC
LIMIT 200;
