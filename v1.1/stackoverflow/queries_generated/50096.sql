-- {"query": "50096.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "gemini-2.5-pro", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2074, "output_tokens": 1284} 

WITH QuestionTags AS (
  -- Step 1: Identify questions with popular tags and high scores, and unnest their tags
  -- to create a row for each question-tag combination. This creates the base set for analysis.
  SELECT
    p.Id,
    p.CreationDate,
    p.ViewCount,
    t.Tag
  FROM Posts AS p,
    unnest(string_to_array(substring(p.Tags, 2, length(p.Tags) - 2), '><')) AS t (Tag)
  WHERE
    p.PostTypeId = 1 -- Questions
    AND p.Score > 5
    AND p.AnswerCount > 1
    AND p.ClosedDate IS NULL
    AND p.Tags IS NOT NULL
    AND t.Tag IN ('python', 'java', 'javascript', 'c#', 'sql', 'pandas', 'reactjs', 'spring', 'django', 'c++')
), AnswerMetrics AS (
  -- Step 2: For each user and tag, aggregate metrics from their answers to the questions identified in Step 1.
  -- This includes counting answers, summing scores, and calculating the average time to post an answer.
  SELECT
    a.OwnerUserId,
    qt.Tag,
    COUNT(a.Id) AS AnswerCount,
    SUM(a.Score) AS TotalAnswerScore,
    AVG(a.Score) AS AverageAnswerScore,
    AVG(EXTRACT(EPOCH FROM (a.CreationDate - qt.CreationDate))) / 3600.0 AS AvgHoursToAnswer,
    MAX(a.CreationDate) AS LastAnswerDate
  FROM Posts AS a
  JOIN QuestionTags AS qt
    ON a.ParentId = qt.Id
  WHERE
    a.PostTypeId = 2 -- Answers
    AND a.OwnerUserId IS NOT NULL
    AND a.CreationDate > qt.CreationDate
  GROUP BY
    a.OwnerUserId,
    qt.Tag
), UserBadgeMetrics AS (
  -- Step 3: Independently calculate badge counts for all users. This is done separately
  -- for efficiency and then joined, focusing on influential (Gold/Silver) badges.
  SELECT
    UserId,
    COUNT(*) FILTER (
      WHERE
        Class = 1
    ) AS GoldBadges,
    COUNT(*) FILTER (
      WHERE
        Class = 2
    ) AS SilverBadges
  FROM Badges
  GROUP BY
    UserId
), RankedContributors AS (
  -- Step 4: Combine user data, answer metrics, and badge counts to calculate a composite
  -- "Contributor Score". Then, use a window function to rank users within each tag.
  SELECT
    am.Tag,
    u.Id AS UserId,
    u.DisplayName,
    u.Reputation,
    am.AnswerCount,
    am.TotalAnswerScore,
    am.AvgHoursToAnswer,
    COALESCE(ubm.GoldBadges, 0) AS GoldBadges,
    COALESCE(ubm.SilverBadges, 0) AS SilverBadges,
    (
      -- Composite score heavily weights total score and high-value badges,
      -- while penalizing for slower answer times and rewarding reputation.
      (am.TotalAnswerScore * 0.5) + (am.AnswerCount * 10) + (u.Reputation * 0.1) + (COALESCE(ubm.GoldBadges, 0) * 100) + (COALESCE(ubm.SilverBadges, 0) * 25)
    ) / (1 + am.AvgHoursToAnswer) AS ContributorScore,
    RANK() OVER (PARTITION BY am.Tag ORDER BY (
      (am.TotalAnswerScore * 0.5) + (am.AnswerCount * 10) + (u.Reputation * 0.1) + (COALESCE(ubm.GoldBadges, 0) * 100) + (COALESCE(ubm.SilverBadges, 0) * 25)
    ) / (1 + am.AvgHoursToAnswer) DESC, am.LastAnswerDate DESC) AS RankInTag
  FROM AnswerMetrics AS am
  JOIN Users AS u
    ON am.OwnerUserId = u.Id
  LEFT JOIN UserBadgeMetrics AS ubm
    ON u.Id = ubm.UserId
  WHERE
    u.Reputation > 1000 -- Filter out less established users to focus the analysis
) -- Final Step: Select the top 10 contributors for each tag, including their key metrics
-- and a correlated subquery to find their most recent comment on a post with that tag.
SELECT
  rc.Tag,
  rc.RankInTag,
  rc.DisplayName,
  CAST(rc.ContributorScore AS INT) AS ContributorScore,
  rc.Reputation,
  rc.AnswerCount,
  rc.TotalAnswerScore,
  rc.GoldBadges,
  rc.SilverBadges,
  CAST(rc.AvgHoursToAnswer AS DECIMAL(10, 2)) AS AvgHoursToAnswer,
  (
    SELECT
      c.Text
    FROM Comments c
    JOIN Posts p
      ON c.PostId = p.Id
    WHERE
      c.UserId = rc.UserId
      AND p.Tags LIKE '%' || rc.Tag || '%'
    ORDER BY
      c.CreationDate DESC
    LIMIT 1
  ) AS LatestRelevantComment
FROM RankedContributors AS rc
WHERE
  rc.RankInTag <= 10
ORDER BY
  rc.Tag,
  rc.RankInTag;
