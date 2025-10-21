-- {"query": "50003.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "gemini-2.5-pro", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2074, "output_tokens": 918} 
WITH TaggedAnswers AS (
  -- Find all answers to questions with the 'javascript' tag
  SELECT
    a.Id AS AnswerId,
    a.OwnerUserId,
    a.Score,
    a.CreationDate,
    a.CommentCount
  FROM Posts AS a
  JOIN Posts AS q
    ON a.ParentId = q.Id
  WHERE a.PostTypeId = 2 -- Answer
  AND q.PostTypeId = 1 -- Question
  AND q.Tags LIKE '%<javascript>%' AND a.OwnerUserId IS NOT NULL
), UserTagStats AS (
  -- Aggregate overall statistics for users who have answered 'javascript' questions
  SELECT
    ta.OwnerUserId,
    COUNT(ta.AnswerId) AS TotalAnswers,
    SUM(ta.Score) AS TotalScore
  FROM TaggedAnswers AS ta
  GROUP BY
    ta.OwnerUserId
), ExpertCandidates AS (
  -- Identify users who meet the criteria for being a 'javascript expert'
  SELECT
    u.Id AS UserId
  FROM Users AS u
  JOIN UserTagStats AS uts
    ON u.Id = uts.OwnerUserId
  WHERE
    u.Reputation > 75000 AND uts.TotalAnswers > 100 AND u.Id IN (
      -- Must have at least one gold badge related to tags
      SELECT
        b.UserId
      FROM Badges AS b
      WHERE
        b.Class = 1 AND b.TagBased = '1'
    )
), YearlyPerformance AS (
  -- Calculate annual performance metrics for the expert candidates
  SELECT
    EXTRACT(YEAR FROM ta.CreationDate) AS AnswerYear,
    ec.UserId,
    SUM(ta.Score) AS AnnualScore,
    AVG(ta.Score) AS AvgAnnualScore,
    COUNT(ta.AnswerId) AS AnnualAnswerCount,
    SUM(ta.CommentCount) AS AnnualCommentCount,
    COUNT(pl.Id) AS TimesCitedAsRelated
  FROM TaggedAnswers AS ta
  JOIN ExpertCandidates AS ec
    ON ta.OwnerUserId = ec.UserId
  LEFT JOIN PostLinks AS pl
    ON ta.AnswerId = pl.RelatedPostId AND pl.LinkTypeId = 1 -- 'Linked' type
  GROUP BY
    AnswerYear,
    ec.UserId
), RankedExperts AS (
  -- Rank the experts within each year based on their performance
  SELECT
    yp.AnswerYear,
    yp.UserId,
    yp.AnnualScore,
    yp.AvgAnnualScore,
    yp.AnnualAnswerCount,
    yp.TimesCitedAsRelated,
    ROW_NUMBER() OVER (PARTITION BY yp.AnswerYear ORDER BY yp.AnnualScore DESC, yp.AnnualAnswerCount DESC) AS YearlyRank,
    LAG(yp.AnnualScore, 1, 0) OVER (PARTITION BY yp.UserId ORDER BY yp.AnswerYear) AS PreviousYearScore
  FROM YearlyPerformance AS yp
)
-- Final selection of the top 5 experts per year, along with additional user details and a correlated subquery
SELECT
  re.AnswerYear,
  re.YearlyRank,
  u.DisplayName,
  u.Reputation,
  re.AnnualScore,
  re.AnnualScore - re.PreviousYearScore AS ScoreGrowth,
  re.AvgAnnualScore,
  re.AnnualAnswerCount,
  re.TimesCitedAsRelated,
  (
    -- Find the post where this expert made their most upvoted comment
    SELECT
      c.PostId
    FROM Comments AS c
    WHERE
      c.UserId = re.UserId
    ORDER BY
      c.Score DESC,
      c.CreationDate DESC
    LIMIT 1
  ) AS TopCommentPostId
FROM RankedExperts AS re
JOIN Users AS u
  ON re.UserId = u.Id
WHERE
  re.YearlyRank <= 5 AND re.AnswerYear BETWEEN 2015 AND 2023
ORDER BY
  re.AnswerYear DESC,
  re.YearlyRank ASC;