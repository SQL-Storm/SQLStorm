-- {"query": "5644.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-5-nano", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 734} 
SELECT
  u.Id AS UserId,
  u.DisplayName AS DisplayName,
  u.Reputation,
  u.CreationDate AS UserCreationDate,
  u.LastAccessDate,
  u.Location,
  COALESCE(u.AboutMe, '') AS AboutMe,
  COALESCE(u.Views, 0) AS Views,
  COALESCE(u.UpVotes, 0) AS UpVotes,
  COALESCE(u.DownVotes, 0) AS DownVotes,
  COUNT(DISTINCT p.Id) FILTER (WHERE p.PostTypeId = 1) AS QuestionCount,
  COUNT(DISTINCT a.Id) FILTER (WHERE a.PostTypeId = 2) AS AnswerCount,
  COUNT(DISTINCT b.Id) AS BadgeCount,
  MAX(CASE WHEN b.Class = 1 THEN b.Date END) AS GoldBadgeDate,
  MAX(CASE WHEN b.Class = 2 THEN b.Date END) AS SilverBadgeDate,
  MAX(CASE WHEN b.Class = 3 THEN b.Date END) AS BronzeBadgeDate,
  -- Complex correlated subquery: average acceptance latency for user's questions (time from creation to first accepted answer)
  (
    SELECT AVG(EXTRACT(EPOCH FROM (aa.CreationDate - p.CreationDate)) / 3600.0)
    FROM Posts p
    JOIN Posts aa ON aa.Id = p.AcceptedAnswerId
    WHERE p.PostTypeId = 1
      AND p.OwnerUserId = u.Id
      AND p.AcceptedAnswerId IS NOT NULL
  ) AS AverageHoursToAcceptAnswer,
  -- Windowed ranking: user's top tags by total score across their questions, ordered within user
  FIRST_VALUE(t.Name) OVER (
    PARTITION BY u.Id
    ORDER BY SUM(COALESCE(p.Score,0)) OVER (PARTITION BY u.Id, t.Name DESC)
    ROWS BETWEEN UNBOUNDED PRECEDING AND UNBOUNDED FOLLOWING
  ) AS TopTagName,
  -- Combined metric: qualification score from posts + badges + activity
  (
    COALESCE((SELECT SUM(Score) FROM Posts WHERE OwnerUserId = u.Id),0)
    + COALESCE((SELECT SUM(Class) FROM Badges WHERE UserId = u.Id),0)
    + COALESCE((SELECT SUM(Views) FROM Users u2 WHERE u2.Id = u.Id),0)
  ) AS CompositeScore
FROM Users u
LEFT JOIN Posts p ON p.OwnerUserId = u.Id AND p.PostTypeId = 1
LEFT JOIN Posts a ON a.OwnerUserId = u.Id AND a.PostTypeId = 2
LEFT JOIN Badges b ON b.UserId = u.Id
LEFT JOIN LATERAL (
  SELECT t.Id, t.TagName
  FROM Tags t
  JOIN Posts ps ON ps.Id = t.ExcerptPostId
  WHERE ps.OwnerUserId = u.Id
  GROUP BY t.Id, t.TagName
  ORDER BY SUM(COALESCE(ps.Score,0)) DESC
  LIMIT 1
) t ON true
GROUP BY
  u.Id,
  u.DisplayName,
  u.Reputation,
  u.CreationDate,
  u.LastAccessDate,
  u.Location,
  u.AboutMe,
  u.Views,
  u.UpVotes,
  u.DownVotes,
  GoldBadgeDate,
  SilverBadgeDate,
  BronzeBadgeDate,
  TopTagName
ORDER BY CompositeScore DESC
LIMIT 100;