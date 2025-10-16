-- {"query": "20058.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-pro", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 1432} 
WITH QuestionTagMap AS (
  -- Step 1: Create a mapping from each question ID to its individual tags,
  -- focusing only on popular tags to reduce the working set size.
  SELECT
    p.Id AS QuestionId,
    p.CreationDate AS QuestionCreationDate,
    p.AcceptedAnswerId,
    p.ViewCount,
    unnest(string_to_array(substring(p.Tags, 2, length(p.Tags) - 2), '><')) AS TagName
  FROM Posts p
  WHERE
    p.PostTypeId = 1 -- Questions
    AND p.AnswerCount > 2
    AND p.Tags IS NOT NULL
    AND p.Tags != ''
    AND p.OwnerUserId IS NOT NULL
), UserAnswerStats AS (
  -- Step 2: Aggregate statistics for each user's answers within each tag.
  SELECT
    a.OwnerUserId,
    qtm.TagName,
    COUNT(a.Id) AS AnswerCount,
    SUM(a.Score) AS TotalScoreInTag,
    SUM(CASE WHEN a.Id = qtm.AcceptedAnswerId THEN 1 ELSE 0 END) AS AcceptedAnswerCount,
    AVG(EXTRACT(EPOCH FROM (a.CreationDate - qtm.QuestionCreationDate))) AS AvgTimeToAnswerSec,
    SUM(qtm.ViewCount) AS TotalQuestionViewsForAnswers
  FROM Posts a
  JOIN QuestionTagMap qtm
    ON a.ParentId = qtm.QuestionId
  WHERE
    a.PostTypeId = 2 -- Answers
    AND a.OwnerUserId IS NOT NULL
    AND qtm.TagName IN (
      SELECT
        TagName
      FROM Tags
      WHERE
        Count > 5000
      ORDER BY
        Count DESC
      LIMIT 20
    )
  GROUP BY
    a.OwnerUserId,
    qtm.TagName
  HAVING
    COUNT(a.Id) > 10 -- Only consider users with a significant number of answers in a tag.
), UserTagBadges AS (
  -- Step 3: Count tag-based badges for each user and tag.
  SELECT
    UserId,
    Name AS TagName,
    COUNT(CASE WHEN Class = 1 THEN 1 END) AS GoldBadges,
    COUNT(CASE WHEN Class = 2 THEN 1 END) AS SilverBadges,
    COUNT(CASE WHEN Class = 3 THEN 1 END) AS BronzeBadges
  FROM Badges
  WHERE
    TagBased = '1'
  GROUP BY
    UserId,
    Name
)
-- Final Step: Combine user stats, badge counts, and user info to rank "experts" and analyze their performance.
SELECT
  u.DisplayName,
  u.Reputation,
  s.TagName,
  s.AnswerCount,
  s.TotalScoreInTag,
  CAST(s.AcceptedAnswerCount AS decimal) / s.AnswerCount AS AcceptedRatio,
  s.AvgTimeToAnswerSec / 3600.0 AS AvgTimeToAnswerHours,
  -- Use COALESCE for users who have stats but no tag-specific badges.
  COALESCE(b.GoldBadges, 0) AS GoldTagBadges,
  COALESCE(b.SilverBadges, 0) AS SilverTagBadges,
  -- Rank users within each tag based on a weighted score of total score and accepted answers.
  RANK() OVER (PARTITION BY s.TagName ORDER BY (s.TotalScoreInTag * 0.7 + s.AcceptedAnswerCount * 15 * 0.3) DESC) AS ExpertRankInTag,
  -- Compare user's total score to the average score of all ranked users in that tag.
  s.TotalScoreInTag - AVG(s.TotalScoreInTag) OVER (PARTITION BY s.TagName) AS ScoreVsTagAverage,
  -- A complex CASE statement to categorize the user's expertise level in the tag.
  CASE
    WHEN (RANK() OVER (PARTITION BY s.TagName ORDER BY (s.TotalScoreInTag * 0.7 + s.AcceptedAnswerCount * 15 * 0.3) DESC) <= 10) OR COALESCE(b.GoldBadges, 0) > 0 THEN 'Guru'
    WHEN (RANK() OVER (PARTITION BY s.TagName ORDER BY (s.TotalScoreInTag * 0.7 + s.AcceptedAnswerCount * 15 * 0.3) DESC) <= 100) OR COALESCE(b.SilverBadges, 0) > 2 THEN 'Specialist'
    ELSE 'Contributor'
  END AS UserTier,
  -- Correlated subquery: find the title of the highest-scored question the user answered in this tag.
  (
    SELECT
      p_sub.Title
    FROM Posts p_sub
    JOIN Posts a_sub
      ON p_sub.Id = a_sub.ParentId
    WHERE
      a_sub.OwnerUserId = u.Id AND p_sub.Id IN (
        SELECT
          qtm_sub.QuestionId
        FROM QuestionTagMap qtm_sub
        WHERE
          qtm_sub.TagName = s.TagName
      )
    ORDER BY
      p_sub.Score DESC,
      p_sub.ViewCount DESC
    LIMIT 1
  ) AS TopQuestionAnsweredTitle,
  -- String manipulation and date arithmetic
  'Profile: ' || u.WebsiteUrl || ' | Member for ' || CAST(EXTRACT(YEAR FROM age(cast('2024-10-01 12:34:56' as timestamp), u.CreationDate)) AS varchar) || ' years' AS UserProfileSummary
FROM UserAnswerStats s
JOIN Users u
  ON s.OwnerUserId = u.Id
LEFT JOIN UserTagBadges b
  ON s.OwnerUserId = b.UserId
  AND s.TagName = b.TagName
WHERE
  -- Filter out users with low reputation relative to the global average of active users.
  u.Reputation > (
    SELECT
      AVG(Reputation) * 1.2
    FROM Users
    WHERE
      LastAccessDate > cast('2024-10-01 12:34:56' as timestamp) - interval '1 year' AND Reputation > 100
  )
  AND u.DisplayName NOT LIKE 'user%'
ORDER BY
  s.TagName,
  ExpertRankInTag;