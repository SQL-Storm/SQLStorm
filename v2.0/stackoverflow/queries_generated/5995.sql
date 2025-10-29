-- {"query": "5995.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-5-nano", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 699} 
WITH recent_user_activity AS (
  SELECT
    u.Id AS UserId,
    u.DisplayName,
    u.Reputation,
    u.CreationDate,
    u.LastAccessDate,
    u.Location,
    u.AboutMe,
    u.Views,
    u.UpVotes,
    u.DownVotes,
    u.ProfileImageUrl,
    u.EmailHash,
    u.AccountId,
    ROW_NUMBER() OVER (PARTITION BY u.Id ORDER BY u.LastAccessDate DESC) AS rn
  FROM Users u
),
top_tags AS (
  SELECT
    t.TagName,
    t.Count,
    t.ExcerptPostId,
    t.WikiPostId,
    ROW_NUMBER() OVER (ORDER BY t.Count DESC, t.TagName) AS rn
  FROM Tags t
  WHERE t.IsModeratorOnly = 0
),
hot_questions AS (
  SELECT
    p.Id AS PostId,
    p.Title,
    p.Tags,
    p.Score,
    p.ViewCount,
    p.CreationDate,
    p.LastActivityDate,
    p.OwnerUserId,
    p.AnswerCount,
    p.CommentCount
  FROM Posts p
  WHERE p.PostTypeId = 1 -- Questions
    AND p.ClosedDate IS NULL
),
aggregated AS (
  SELECT
    uq.UserId,
    uq.DisplayName,
    uq.Reputation,
    qt.TagName,
    COUNT(DISTINCT a.PostId) AS AnswerCountByUser,
    SUM(a.Score) AS ScoreFromAnswers,
    AVG(DATEDIFF(second, p.CreationDate, p.LastActivityDate)) AS AvgActivitySpanSeconds
  FROM hot_questions h
  LEFT JOIN Posts p ON p.OwnerUserId = h.OwnerUserId
  LEFT JOIN Posts a ON a.ParentId = h.PostId AND a.PostTypeId = 2 -- Answers to the question
  LEFT JOIN Users uq ON uq.Id = h.OwnerUserId
  LEFT JOIN (
    SELECT p.Id AS PostId, UNNEST(string_to_array(p.Tags, '>')) AS TagName
    FROM Posts p
  ) t ON t.PostId = h.PostId
  GROUP BY uq.UserId, uq.DisplayName, uq.Reputation, qt.TagName
)
SELECT
  rua.UserId,
  rua.DisplayName,
  rua.Reputation,
  rua.LastAccessDate,
  rup.TagName,
  COALESCE(agg.AnswerCountByUser, 0) AS AnswerCountByUser,
  COALESCE(agg.ScoreFromAnswers, 0) AS ScoreFromAnswers,
  COALESCE(agg.AvgActivitySpanSeconds, 0) AS AvgActivitySpanSeconds,
  (CASE
     WHEN rua.Location IS NOT NULL THEN rua.Location
     ELSE 'Unknown'
   END) AS UserLocation,
  (CASE
     WHEN rua.AboutMe IS NOT NULL THEN LEFT(rua.AboutMe, 200)
     ELSE NULL
   END) AS ShortBio
FROM recent_user_activity rua
LEFT JOIN aggregated agg ON agg.UserId = rua.UserId
LEFT JOIN (
  SELECT DISTINCT TagName
  FROM Tags
  WHERE IsModeratorOnly = 0
) rup ON rup.TagName IS NOT NULL
WHERE rua.rn = 1
ORDER BY rua.Reputation DESC, rua.LastAccessDate DESC
LIMIT 100;