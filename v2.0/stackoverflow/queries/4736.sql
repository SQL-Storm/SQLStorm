-- {"query": "4736.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-flash-lite", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 807} 
WITH
  AvgPostScore AS (
    SELECT
      PostTypeId,
      AVG(Score) AS AverageScore
    FROM
      Posts
    WHERE
      Score IS NOT NULL
    GROUP BY
      PostTypeId
  ),
  UserPostActivity AS (
    SELECT
      p.OwnerUserId,
      COUNT(p.Id) AS TotalPosts,
      SUM(CASE WHEN p.PostTypeId = 1 THEN 1 ELSE 0 END) AS QuestionCount,
      SUM(CASE WHEN p.PostTypeId = 2 THEN 1 ELSE 0 END) AS AnswerCount,
      AVG(p.Score) AS AveragePostScore
    FROM
      Posts AS p
    WHERE
      p.OwnerUserId IS NOT NULL
    GROUP BY
      p.OwnerUserId
  ),
  HighReputationUsers AS (
    SELECT
      Id,
      DisplayName,
      Reputation,
      (
        SELECT
          COUNT(*)
        FROM
          Badges AS b
        WHERE
          b.UserId = u.Id AND b.Class = 1
      ) AS GoldBadgeCount
    FROM
      Users AS u
    WHERE
      Reputation > 10000
  )
SELECT
  hp.DisplayName AS UserName,
  hp.Reputation,
  hp.GoldBadgeCount,
  upa.TotalPosts,
  upa.QuestionCount,
  upa.AnswerCount,
  COALESCE(upa.AveragePostScore, 0) AS UserAverageScore,
  aps.AverageScore AS AvgScoreForUserPosts,
  CASE
    WHEN hp.GoldBadgeCount > 5 THEN 'Elite'
    WHEN hp.GoldBadgeCount > 0 THEN 'Distinguished'
    ELSE 'Standard'
  END AS UserTier,
  CASE
    WHEN upa.AveragePostScore > 50 THEN 'High Performer'
    WHEN upa.AveragePostScore > 10 THEN 'Solid Contributor'
    ELSE 'Developing'
  END AS PerformanceTier,
  UPPER(
    SUBSTRING(hp.DisplayName FROM 1 FOR 3)
  ) || '-' || LPAD(
    CAST(hp.Reputation AS VARCHAR),
    10,
    '0'
  ) AS CustomIdentifier
FROM
  HighReputationUsers AS hp
LEFT OUTER JOIN
  UserPostActivity AS upa
  ON hp.Id = upa.OwnerUserId
LEFT OUTER JOIN
  AvgPostScore AS aps
  ON upa.QuestionCount > 0 AND upa.AnswerCount > 0 AND upa.TotalPosts > 50 AND upa.AveragePostScore > aps.AverageScore
WHERE
  hp.DisplayName IS NOT NULL AND hp.DisplayName LIKE '%a%'
UNION ALL
SELECT
  'Community' AS UserName,
  0 AS Reputation,
  0 AS GoldBadgeCount,
  COUNT(p.Id) AS TotalPosts,
  SUM(CASE WHEN p.PostTypeId = 1 THEN 1 ELSE 0 END) AS QuestionCount,
  SUM(CASE WHEN p.PostTypeId = 2 THEN 1 ELSE 0 END) AS AnswerCount,
  AVG(p.Score) AS UserAverageScore,
  AVG(p.Score) AS AvgScoreForUserPosts,
  'System' AS UserTier,
  'N/A' AS PerformanceTier,
  'SYS-0000000000' AS CustomIdentifier
FROM
  Posts AS p
WHERE
  p.OwnerUserId IS NULL AND p.CommunityOwnedDate IS NOT NULL
ORDER BY
  Reputation DESC,
  TotalPosts DESC;