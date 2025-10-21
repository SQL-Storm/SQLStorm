-- {"query": "223.sql", "dataset": "stackoverflow", "version": "v1.4", "prompt": "p1", "model": "gpt-5-nano", "temperature": 1.0, "max_tokens": 32768, "reasoning": "medium", "input_tokens": 2026, "output_tokens": 8925} 
WITH
QuestionStats AS (
  SELECT
    u.Id AS UserId,
    u.DisplayName AS DisplayName,
    u.Reputation,
    'Question' AS PostType,
    COUNT(p.Id) AS PostCount,
    MAX(p.CreationDate) AS LastActivityDate,
    AVG(p.Score) AS AvgPostScore,
    (
      SELECT string_agg(TagName, ',')
      FROM (
        SELECT t.TagName
        FROM Tags t
        WHERE EXISTS (
          SELECT 1
          FROM Posts pp
          WHERE pp.OwnerUserId = u.Id
            AND pp.PostTypeId = 1
            AND pp.Tags LIKE '%' || '<' || t.TagName || '>' || '%'
        )
        ORDER BY t.Count DESC
        LIMIT 3
      ) AS tlist
    ) AS TopTags,
    (SELECT COUNT(*) FROM Comments c WHERE c.UserId = u.Id) AS CommentCountByUser
  FROM Users u
  LEFT JOIN Posts p ON p.OwnerUserId = u.Id AND p.PostTypeId = 1
  GROUP BY u.Id, u.DisplayName, u.Reputation
),
AnswerStats AS (
  SELECT
    u.Id AS UserId,
    u.DisplayName AS DisplayName,
    u.Reputation,
    'Answer' AS PostType,
    COUNT(p.Id) AS PostCount,
    MAX(p.CreationDate) AS LastActivityDate,
    AVG(p.Score) AS AvgPostScore,
    NULL AS TopTags,
    (SELECT COUNT(*) FROM Comments c WHERE c.UserId = u.Id) AS CommentCountByUser
  FROM Users u
  LEFT JOIN Posts p ON p.OwnerUserId = u.Id AND p.PostTypeId = 2
  GROUP BY u.Id, u.DisplayName, u.Reputation
),
Combined AS (
  SELECT * FROM QuestionStats
  UNION ALL
  SELECT * FROM AnswerStats
)
SELECT
  UserId,
  DisplayName,
  Reputation,
  PostType,
  PostCount,
  LastActivityDate,
  AvgPostScore,
  TopTags,
  CommentCountByUser,
  ROW_NUMBER() OVER (PARTITION BY PostType ORDER BY Reputation DESC) AS RankByType
FROM Combined
ORDER BY PostType, RankByType;