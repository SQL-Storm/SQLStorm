-- {"query": "355.sql", "dataset": "stackoverflow", "version": "v1.4", "prompt": "p1", "model": "gpt-5-nano", "temperature": 1.0, "max_tokens": 32768, "reasoning": "high", "input_tokens": 2026, "output_tokens": 17861} 
WITH
  UserState AS (
    SELECT
      u.Id AS UserId,
      u.DisplayName,
      u.Reputation,
      COUNT(p.Id) AS PostCount,
      COALESCE(AVG(p.Score), 0) AS AvgPostScore,
      SUM(CASE WHEN p.PostTypeId = 1 AND p.AcceptedAnswerId IS NOT NULL THEN 1 ELSE 0 END) AS AcceptedQuestionCount,
      SUM((SELECT COUNT(*) FROM Comments c WHERE c.PostId = p.Id)) AS TotalCommentCount,
      SUM(
        CASE
          WHEN p.PostTypeId = 1 AND p.Tags IS NOT NULL THEN
            COALESCE(array_length(string_to_array(substring(p.Tags, 2, length(p.Tags) - 2), '><'), 1), 0)
          ELSE 0
        END
      ) AS TagCountTotal
    FROM Users u
    LEFT JOIN Posts p ON p.OwnerUserId = u.Id
    GROUP BY u.Id, u.DisplayName, u.Reputation
  ),
  NameExtended AS (
    SELECT
      UserId,
      DisplayName,
      Reputation,
      UPPER(LEFT(COALESCE(DisplayName, 'Unknown'), 3)) AS NamePrefix,
      PostCount,
      AvgPostScore,
      AcceptedQuestionCount,
      TotalCommentCount,
      TagCountTotal
    FROM UserState
  ),
  Benchmark AS (
    SELECT
      UserId,
      DisplayName,
      NamePrefix,
      Reputation,
      PostCount,
      AvgPostScore,
      AcceptedQuestionCount,
      TotalCommentCount,
      TagCountTotal,
      (0.6 * AvgPostScore) + (0.25 * LN(1.0 + PostCount)) + (0.15 * CASE WHEN AcceptedQuestionCount > 0 THEN 1 ELSE 0 END) AS Score,
      'Benchmark' AS ScoreSource
    FROM NameExtended
  ),
  Activity AS (
    SELECT
      UserId,
      DisplayName,
      NamePrefix,
      Reputation,
      PostCount,
      AvgPostScore,
      AcceptedQuestionCount,
      TotalCommentCount,
      TagCountTotal,
      (0.5 * AvgPostScore) + (0.3 * LN(1.0 + PostCount)) + (0.2 * CASE WHEN TotalCommentCount > 0 THEN 1 ELSE 0 END) AS Score,
      'Activity' AS ScoreSource
    FROM NameExtended
  ),
  Combined AS (
    SELECT * FROM Benchmark
    UNION ALL
    SELECT * FROM Activity
  ),
  Ranked AS (
    SELECT
      *,
      ROW_NUMBER() OVER (PARTITION BY ScoreSource ORDER BY Score DESC, Reputation DESC, UserId) AS rn
    FROM Combined
  )
SELECT
  UserId,
  DisplayName,
  NamePrefix,
  Reputation,
  PostCount,
  AvgPostScore,
  AcceptedQuestionCount,
  TotalCommentCount,
  TagCountTotal,
  Score,
  ScoreSource
FROM Ranked
WHERE rn <= 100
ORDER BY ScoreSource, Score DESC, rn;