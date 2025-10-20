-- {"query": "50072.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "gemini-2.5-pro", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2074, "output_tokens": 1237} 

WITH PopularTags AS (
  -- Step 1: Identify the top 5 most prolific tags to focus the analysis.
  SELECT TagName
  FROM Tags
  ORDER BY Count DESC
  LIMIT 5
), AnswerStats AS (
  -- Step 2: Calculate metrics for answers related to the popular tags.
  -- This includes total score, number of accepted answers, and average response time.
  SELECT
    a.OwnerUserId,
    SUM(a.Score) AS TotalAnswerScore,
    COUNT(q.AcceptedAnswerId) FILTER (WHERE q.AcceptedAnswerId = a.Id) AS AcceptedAnswerCount,
    AVG(EXTRACT(EPOCH FROM (a.CreationDate - q.CreationDate))) AS AvgTimeToAnswerSeconds
  FROM Posts AS a
  JOIN Posts AS q ON a.ParentId = q.Id
  WHERE a.PostTypeId = 2 -- It's an answer
    AND q.PostTypeId = 1 -- Its parent is a question
    AND a.OwnerUserId IS NOT NULL
    -- Correlated subquery to filter for questions with at least one popular tag.
    AND EXISTS (
      SELECT 1
      FROM string_to_array(substring(q.Tags, 2, length(q.Tags) - 2), '><') AS t(tag)
      WHERE t.tag IN (SELECT TagName FROM PopularTags)
    )
  GROUP BY a.OwnerUserId
), UserBadges AS (
  -- Step 3: Aggregate counts of Gold and Silver badges for each user.
  SELECT
    UserId,
    COUNT(*) FILTER (WHERE Class = 1) AS GoldBadges,
    COUNT(*) FILTER (WHERE Class = 2) AS SilverBadges
  FROM Badges
  GROUP BY UserId
), CommentContributions AS (
  -- Step 4: Aggregate scores from helpful comments on posts within popular tags.
  SELECT
    c.UserId,
    SUM(c.Score) AS TotalCommentScore
  FROM Comments AS c
  JOIN Posts AS p ON c.PostId = p.Id
  WHERE c.UserId IS NOT NULL AND c.Score > 0
    -- This correlated subquery is complex as it must check tags for both questions and answers.
    AND EXISTS (
      SELECT 1
      FROM Posts q
      WHERE (p.Id = q.Id OR p.ParentId = q.Id)
        AND q.PostTypeId = 1
        AND EXISTS (
          SELECT 1
          FROM string_to_array(substring(q.Tags, 2, length(q.Tags) - 2), '><') AS t(tag)
          WHERE t.tag IN (SELECT TagName FROM PopularTags)
        )
    )
  GROUP BY c.UserId
), CombinedScores AS (
  -- Step 5: Combine all user metrics using a full outer join to include all contributing users.
  -- Calculate a composite "PowerScore" from various weighted metrics.
  SELECT
    COALESCE(ans.OwnerUserId, b.UserId, com.UserId) AS UserId,
    (
      (COALESCE(ans.TotalAnswerScore, 0) * 1.5) +
      (COALESCE(ans.AcceptedAnswerCount, 0) * 25) +
      (COALESCE(b.GoldBadges, 0) * 100) +
      (COALESCE(b.SilverBadges, 0) * 40) +
      (COALESCE(com.TotalCommentScore, 0) * 0.5) -
      -- Apply a small penalty based on the average time to answer in days.
      (COALESCE(ans.AvgTimeToAnswerSeconds, 0) / 86400.0)
    ) AS PowerScore
  FROM AnswerStats ans
  FULL OUTER JOIN UserBadges b ON ans.OwnerUserId = b.UserId
  FULL OUTER JOIN CommentContributions com ON COALESCE(ans.OwnerUserId, b.UserId) = com.UserId
), RankedUsers AS (
  -- Step 6: Rank users based on their calculated PowerScore using a window function.
  SELECT
    UserId,
    PowerScore,
    RANK() OVER (ORDER BY PowerScore DESC) AS UserRank
  FROM CombinedScores
  WHERE UserId IS NOT NULL
)
-- Step 7: Final Selection - Join back to get user details and display the top 100 ranked "Power Users".
SELECT
  ru.UserRank,
  u.DisplayName,
  u.Reputation,
  CAST(ru.PowerScore AS aS numeric(10, 2)) AS PowerScore,
  u.CreationDate AS MemberSince,
  ans.TotalAnswerScore,
  ans.AcceptedAnswerCount,
  b.GoldBadges,
  b.SilverBadges,
  com.TotalCommentScore,
  -- Format the average response time for readability.
  TO_CHAR((ans.AvgTimeToAnswerSeconds * INTERVAL '1 second'), 'DD"d" HH24"h" MI"m"') AS AvgResponseTime
FROM RankedUsers ru
JOIN Users u ON ru.UserId = u.Id
LEFT JOIN AnswerStats ans ON ru.UserId = ans.OwnerUserId
LEFT JOIN UserBadges b ON ru.UserId = b.UserId
LEFT JOIN CommentContributions com ON ru.UserId = com.UserId
WHERE ru.UserRank <= 100 AND u.Reputation > 1000
ORDER BY ru.UserRank, u.Reputation DESC;
