-- {"query": "142.sql", "dataset": "stackoverflow", "version": "v1.4", "prompt": "p1", "model": "gpt-5-nano", "temperature": 1.0, "max_tokens": 32768, "reasoning": "low", "input_tokens": 2026, "output_tokens": 2080} 
WITH per_user AS (
  SELECT
    u.Id AS UserId,
    u.DisplayName,
    u.Reputation,
    COUNT(*) FILTER (WHERE p.PostTypeId = 1) AS QuestionCount,
    SUM(COALESCE(p.Score, 0)) AS TotalQuestionScore,
    (SELECT COUNT(*) FROM Posts pr WHERE pr.OwnerUserId = u.Id) AS TotalPostsByUser,
    (SELECT MAX(v.CreationDate)
     FROM Votes v
     JOIN Posts pv ON pv.Id = v.PostId
     WHERE pv.OwnerUserId = u.Id) AS LastVoteDate
  FROM Users u
  LEFT JOIN Posts p ON p.OwnerUserId = u.Id
  GROUP BY u.Id, u.DisplayName, u.Reputation
),
most_active AS (
  SELECT
    pu.UserId,
    pu.DisplayName,
    pu.Reputation,
    pu.QuestionCount,
    pu.TotalQuestionScore,
    pu.TotalPostsByUser,
    pu.LastVoteDate,
    ROW_NUMBER() OVER (ORDER BY pu.TotalQuestionScore DESC NULLS LAST) AS rn
  FROM per_user pu
)
SELECT
  UserId,
  DisplayName,
  Reputation,
  QuestionCount,
  TotalQuestionScore,
  TotalPostsByUser,
  LastVoteDate,
  rn
FROM most_active
WHERE rn <= 50
ORDER BY rn;