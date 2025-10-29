-- {"query": "5268.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-5-nano", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 393} 
SELECT
  u.DisplayName AS UserName,
  COUNT(DISTINCT p.Id) AS PostsCount,
  AVG(p.Score) AS AvgPostScore,
  SUM(CASE WHEN p.PostTypeId = 1 THEN 1 ELSE 0 END) AS QuestionCount,
  SUM(CASE WHEN p.PostTypeId = 2 THEN 1 ELSE 0 END) AS AnswerCount,
  COALESCE(SUM(CASE WHEN b.Name IS NOT NULL THEN 1 ELSE 0 END), 0) AS BadgeCount,
  MAX(p.LastActivityDate) AS LastActive
FROM
  Posts p
  INNER JOIN Users u ON p.OwnerUserId = u.Id
  LEFT JOIN Badges b ON b.UserId = u.Id
  LEFT JOIN Votes v ON v.PostId = p.Id
  LEFT JOIN PostLinks pl ON pl.PostId = p.Id
WHERE
  p.CreationDate >= TIMESTAMP '2020-01-01 00:00:00'
  AND p.CreationDate < TIMESTAMP '2024-01-01 00:00:00'
  AND (p.OwnerUserId IS NOT NULL AND p.OwnerUserId <> -1)
  AND (u.Reputation IS NOT NULL)
  AND (v.CreationDate = (
        SELECT MAX(v2.CreationDate)
        FROM Votes v2
        WHERE v2.PostId = p.Id
      ) OR v.CreationDate IS NULL)
  AND NOT EXISTS (
        SELECT 1
        FROM PostHistory ph
        WHERE ph.PostId = p.Id
          AND ph.PostHistoryTypeId IN (10, 12, 13) -- closed/deleted/undeleted signals
      )
GROUP BY
  u.Id, u.DisplayName
ORDER BY
  LastActive DESC,
  PostsCount DESC
LIMIT 100;