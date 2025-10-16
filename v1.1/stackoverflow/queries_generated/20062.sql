-- {"query": "20062.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-pro", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 1282} 

WITH UserPostMetrics AS (
  SELECT
    p.OwnerUserId,
    COUNT(p.Id) AS TotalPosts,
    SUM(CASE WHEN p.PostTypeId = 1 THEN 1 ELSE 0 END) AS QuestionCount,
    SUM(CASE WHEN p.PostTypeId = 2 THEN 1 ELSE 0 END) AS AnswerCount,
    SUM(p.Score) AS TotalScore,
    AVG(p.Score) AS AverageScore,
    SUM(p.ViewCount) AS TotalViews,
    MIN(p.CreationDate) AS FirstPostDate,
    MAX(p.CreationDate) AS LastPostDate,
    SUM(p.FavoriteCount) AS TotalFavorites
  FROM Posts p
  WHERE
    p.OwnerUserId IS NOT NULL
    AND p.PostTypeId IN (1, 2)
  GROUP BY
    p.OwnerUserId
  HAVING
    COUNT(p.Id) > 20 AND SUM(CASE WHEN p.PostTypeId = 2 THEN 1 ELSE 0 END) > 5
), AnswerDetails AS (
  SELECT
    p.Id,
    p.OwnerUserId,
    p.Score,
    p.CreationDate,
    q.Tags,
    q.ViewCount AS QuestionViewCount,
    q.AnswerCount AS QuestionAnswerCount,
    q.AcceptedAnswerId,
    -- Calculate time between user's consecutive answers
    EXTRACT(EPOCH FROM (p.CreationDate - LAG(p.CreationDate, 1) OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate))) AS SecondsToNextAnswer,
    -- Rank answers by score for each user
    ROW_NUMBER() OVER (PARTITION BY p.OwnerUserId ORDER BY p.Score DESC, p.CreationDate DESC) AS AnswerRank
  FROM Posts p
  JOIN Posts q ON p.ParentId = q.Id
  WHERE
    p.PostTypeId = 2 -- Answers
    AND p.OwnerUserId IS NOT NULL
), UserTopTags AS (
  SELECT
    OwnerUserId,
    -- This subquery simulates unnesting tags and finding the most frequent one for a user's answers
    (
        SELECT TagName FROM (
            SELECT unnest(string_to_array(substring(Tags, 2, length(Tags)-2), '><')) AS TagName
            FROM AnswerDetails ad_inner
            WHERE ad_inner.OwnerUserId = ad_outer.OwnerUserId
        ) AS UserTags
        GROUP BY TagName
        ORDER BY COUNT(*) DESC, TagName
        LIMIT 1
    ) AS PrimaryTag
  FROM AnswerDetails ad_outer
  GROUP BY OwnerUserId
)
SELECT
  u.Id AS UserId,
  u.DisplayName,
  u.Reputation,
  u.Age,
  upm.TotalPosts,
  upm.AverageScore,
  DENSE_RANK() OVER (ORDER BY upm.AverageScore DESC, u.Reputation DESC) AS ScoreRank,
  COALESCE(b.GoldBadges, 0) AS GoldBadges,
  COALESCE(b.SilverBadges, 0) AS SilverBadges,
  utt.PrimaryTag,
  -- Correlated subquery to count comments on posts that are not their own
  (
    SELECT COUNT(*)
    FROM Comments c
    WHERE c.UserId = u.Id AND c.PostId NOT IN (SELECT p_inner.Id FROM Posts p_inner WHERE p_inner.OwnerUserId = u.Id)
  ) AS CommentsOnOthersPosts,
  -- Correlated subquery to check if the user has ever received a 'Fanatic' badge
  CASE WHEN EXISTS (SELECT 1 FROM Badges b_inner WHERE b_inner.UserId = u.Id AND b_inner.Name = 'Fanatic')
    THEN 'Yes'
    ELSE 'No'
  END AS IsFanatic,
  -- Complex 'Influence' calculation using various metrics
  (
    LOG(u.Reputation) * upm.AverageScore + (COALESCE(b.GoldBadges, 0) * 100)
    + (SELECT AVG(ad.Score) FROM AnswerDetails ad WHERE ad.OwnerUserId = u.Id AND ad.AnswerRank <= 5) -- Avg score of top 5 answers
    - EXTRACT(EPOCH FROM (CURRENT_TIMESTAMP - upm.LastPostDate)) / (3600*24*30) -- Penalty for inactivity in months
  ) AS InfluenceScore,
  REPLACE(u.Location, ',', ';') AS StandardizedLocation
FROM Users u
JOIN UserPostMetrics upm ON u.Id = upm.OwnerUserId
LEFT JOIN UserTopTags utt ON u.Id = utt.OwnerUserId
-- Using a subquery in a JOIN clause to pre-aggregate badge counts
LEFT JOIN (
  SELECT
    UserId,
    SUM(CASE WHEN Class = 1 THEN 1 ELSE 0 END) AS GoldBadges,
    SUM(CASE WHEN Class = 2 THEN 1 ELSE 0 END) AS SilverBadges
  FROM Badges
  GROUP BY UserId
) b ON u.Id = b.UserId
WHERE
  u.Reputation > (SELECT AVG(Reputation) FROM Users) -- Only users with above-average reputation
  AND upm.AnswerCount > upm.QuestionCount -- Users who provide more answers than questions
  AND u.CreationDate < (CURRENT_TIMESTAMP - INTERVAL '5 year')
  AND u.AboutMe IS NOT NULL
  AND LENGTH(u.AboutMe) > 100
ORDER BY
  InfluenceScore DESC NULLS LAST, u.Reputation DESC
LIMIT 100;

