-- {"query": "5452.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-5-nano", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 1009} 
WITH ranked_users AS (
  SELECT
    u.Id,
    u.DisplayName,
    u.Reputation,
    u.CreationDate,
    u.LastAccessDate,
    u.Location,
    u.Views,
    u.UpVotes,
    u.DownVotes,
    u.AboutMe,
    ROW_NUMBER() OVER (
      PARTITION BY CASE WHEN u.Location IS NULL THEN 'UNKNOWN' ELSE u.Location END
      ORDER BY u.Reputation DESC, u.UpVotes DESC, u.CreationDate ASC
    ) AS rn_by_location
  FROM Users u
),
recent_badges AS (
  SELECT
    b.UserId,
    b.Name AS BadgeName,
    b.Date,
    b.Class,
    b.TagBased
  FROM Badges b
  WHERE b.Date >= DATEADD(year, -1, CURRENT_TIMESTAMP)
),
top_questions AS (
  SELECT
    p.Id AS QuestionId,
    p.Title,
    p.OwnerUserId,
    p.CreationDate,
    p.Score,
    p.ViewCount,
    p.AnswerCount,
    p.Tags,
    p.LastActivityDate,
    ROW_NUMBER() OVER (
      ORDER BY p.Score DESC, p.ViewCount DESC, p.LastActivityDate DESC
    ) AS rn
  FROM Posts p
  WHERE p.PostTypeId = 1
    AND p.ClosedDate IS NULL
    AND p.OwnerUserId IS NOT NULL
    AND p.OwnerUserId <> -1
),
answers_with_parent AS (
  SELECT
    a.Id AS AnswerId,
    a.ParentId AS QuestionId,
    a.Score AS AnswerScore,
    a.CreationDate AS AnswerDate,
    a.OwnerUserId,
    a.LastActivityDate,
    ROW_NUMBER() OVER (
      PARTITION BY a.ParentId
      ORDER BY a.Score DESC, a.CreationDate ASC
    ) AS rn
  FROM Posts a
  WHERE a.PostTypeId = 2
)
SELECT
  u.Id AS UserId,
  u.DisplayName AS UserName,
  u.Reputation,
  CASE
    WHEN u.Location IS NULL THEN 'Unknown'
    ELSE u.Location
  END AS Location,
  u.CreationDate,
  u.LastAccessDate,
  COUNT(DISTINCT tb.BadgeName) AS BadgeCount,
  STRING_AGG(tb.BadgeName, ',') AS Badges,
  COUNT(DISTINCT rq.QuestionId) AS OpenQuestions,
  MAX(rq.LastActivityDate) AS LastActiveQuestionDate,
  SUM(CASE WHEN a.AnswerScore IS NOT NULL THEN a.AnswerScore ELSE 0 END) AS TotalAnswerScore,
  AVG(p.Score) FILTER (WHERE p.Score IS NOT NULL) AS AvgQuestionScore,
  MAX(p.ViewCount) AS MaxQuestionViews,
  (SELECT COUNT(*) FROM Posts p2 WHERE p2.OwnerUserId = u.Id AND p2.PostTypeId = 1) AS QuestionsOwned,
  (SELECT COUNT(*) FROM Posts p2 WHERE p2.OwnerUserId = u.Id AND p2.PostTypeId = 2) AS AnswersOwned,
  (SELECT COUNT(*) FROM Votes v WHERE v.UserId = u.Id AND v.VoteTypeId = 2) AS UpModVotes,
  (SELECT COUNT(*) FROM Votes v WHERE v.UserId = u.Id AND v.VoteTypeId = 3) AS DownModVotes,
  (SELECT COUNT(*) FROM Votes v WHERE v.UserId = u.Id AND v.VoteTypeId = 8) AS BountyStarts
FROM (
  SELECT * FROM ranked_users ru WHERE ru.rn_by_location = 1
) AS u
LEFT JOIN (
  SELECT UserId, Name AS BadgeName FROM recent_badges
) tb ON tb.UserId = u.Id
LEFT JOIN (
  SELECT OwnerUserId AS UserId, MAX(LastActivityDate) AS LastActivityDate, COUNT(*) AS OpenQuestions, QuestionId
  FROM (
    SELECT p.OwnerUserId, p.Id AS QuestionId, p.LastActivityDate
    FROM Posts p
    WHERE p.PostTypeId = 1
      AND p.ClosedDate IS NULL
  ) q
  GROUP BY OwnerUserId
) rq ON rq.UserId = u.Id
LEFT JOIN (
  SELECT
    a.ParentId AS QuestionId,
    a.OwnerUserId,
    a.Score AS AnswerScore,
    a.CreationDate AS AnswerDate,
    a.LastActivityDate
  FROM answers_with_parent a
) a ON a.OwnerUserId = u.Id
LEFT JOIN Posts p ON p.OwnerUserId = u.Id AND p.PostTypeId = 1
GROUP BY
  u.Id,
  u.DisplayName,
  u.Reputation,
  u.Location,
  u.CreationDate,
  u.LastAccessDate
ORDER BY u.Reputation DESC
LIMIT 100;