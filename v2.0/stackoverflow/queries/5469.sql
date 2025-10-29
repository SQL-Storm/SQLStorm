-- {"query": "5469.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-5-nano", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 385}
SELECT
  u.Id AS UserId,
  u.DisplayName AS UserName,
  u.Reputation,
  COUNT(DISTINCT p.Id) AS PostCount,
  SUM(CASE WHEN p.PostTypeId = 1 THEN 1 ELSE 0 END) AS QuestionCount,
  SUM(CASE WHEN p.PostTypeId = 2 THEN 1 ELSE 0 END) AS AnswerCount,
  AVG(p.Score) AS AvgPostScore,
  MAX(p.LastActivityDate) AS LastActive,
  ARRAY_AGG(DISTINCT t.TagName) FILTER (WHERE t.TagName IS NOT NULL) AS TagsUsed,
  v.LastVoteDate,
  COALESCE(b.TotalBadges, 0) AS BadgeCount
FROM
  Users u
  LEFT JOIN Posts p ON p.OwnerUserId = u.Id
  LEFT JOIN PostHistory ph ON ph.PostId = p.Id
  LEFT JOIN (
    SELECT UserId, MAX(CreationDate) AS LastVoteDate FROM Votes GROUP BY UserId
  ) v ON v.UserId = u.Id
  LEFT JOIN (
    SELECT UserId, COUNT(*) AS TotalBadges
    FROM Badges
    GROUP BY UserId
  ) b ON b.UserId = u.Id
  LEFT JOIN (
    SELECT p_inner.Id AS post_id, TRIM(BOTH '<>' FROM UNNEST(STRING_TO_ARRAY(p_inner.Tags, '><'))) AS ttag
    FROM Posts p_inner
  ) t2 ON t2.post_id = p.Id
  LEFT JOIN Tags t ON t.TagName = t2.ttag
WHERE
  u.Id IS NOT NULL
GROUP BY
  u.Id, u.DisplayName, u.Reputation, v.LastVoteDate, b.TotalBadges
HAVING
  COUNT(p.Id) > 0
ORDER BY
  u.Reputation DESC,
  UserName ASC
LIMIT 100;