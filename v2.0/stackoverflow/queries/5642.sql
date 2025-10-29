-- {"query": "5642.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-5-nano", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 736}
WITH
recent_questions AS (
  SELECT
    p.Id AS PostId,
    p.Title,
    p.Tags,
    p.CreationDate,
    p.ViewCount,
    p.Score,
    p.OwnerUserId,
    p.LastActivityDate,
    p.CommentCount,
    p.FavoriteCount,
    p.AnswerCount
  FROM Posts p
  WHERE p.PostTypeId = 1
    AND p.CreationDate >= CAST('2024-10-01 12:34:56' AS timestamp) - INTERVAL '180 days'
),
badges_per_user AS (
  SELECT
    b.UserId,
    COUNT(*) AS BadgeCount,
    STRING_AGG(b.Name, ', ' ORDER BY b.Date DESC) AS Badges
  FROM Badges b
  GROUP BY b.UserId
),
best_answers AS (
  SELECT
    a.Id AS AnswerId,
    a.ParentId AS QuestionId,
    a.Score AS AnswerScore,
    a.OwnerUserId AS AnswererId,
    u.Reputation AS AnswererRep,
    a.CreationDate AS AnswerDate
  FROM Posts a
  JOIN Posts q ON a.ParentId = q.Id
  JOIN Users u ON a.OwnerUserId = u.Id
  WHERE a.PostTypeId = 2
),
tag_warmth AS (
  SELECT
    t.TagName AS tag,
    COUNT(*) AS question_count,
    AVG(q.Score) AS avg_question_score
  FROM (
    SELECT
      unnest(string_to_array(substring(p.Tags FROM 2 FOR (char_length(p.Tags)-2)), '><')) AS TagName,
      p.Score
    FROM Posts p
    WHERE p.PostTypeId = 1
      AND p.CreationDate >= CAST('2024-10-01 12:34:56' AS timestamp) - INTERVAL '365 days'
  ) q
  JOIN Tags t ON LOWER(q.TagName) = LOWER(t.TagName)
  GROUP BY t.TagName
),
latest_activity AS (
  SELECT
    p.Id AS PostId,
    p.LastActivityDate,
    p.OwnerUserId,
    ROW_NUMBER() OVER (PARTITION BY p.OwnerUserId ORDER BY p.LastActivityDate DESC) AS rn
  FROM Posts p
  WHERE p.LastActivityDate IS NOT NULL
)
SELECT
  rq.PostId,
  rq.Title,
  rq.Tags,
  rq.CreationDate AS QuestionCreated,
  rq.ViewCount,
  rq.Score AS QuestionScore,
  rq.OwnerUserId,
  rq.LastActivityDate,
  rq.CommentCount,
  rq.FavoriteCount,
  rq.AnswerCount,
  bpu.BadgeCount AS OwnerBadgeCount,
  bpu.Badges AS OwnerBadges,
  ba.AnswerId,
  ba.AnswerScore,
  ba.AnswererId,
  ru.Reputation AS AnswererReputation,
  la.LastActivityDate AS UserLastActive,
  tw.tag AS TrendTag,
  tw.question_count,
  tw.avg_question_score,
  lai.rn AS IsLatestActivityForUser
FROM recent_questions rq
LEFT JOIN badges_per_user bpu ON rq.OwnerUserId = bpu.UserId
LEFT JOIN best_answers ba ON rq.PostId = ba.QuestionId
LEFT JOIN Users ru ON ba.AnswererId = ru.Id
LEFT JOIN latest_activity la ON rq.OwnerUserId = la.OwnerUserId AND la.rn = 1
LEFT JOIN tag_warmth tw ON TRUE
LEFT JOIN latest_activity lai ON rq.OwnerUserId = lai.OwnerUserId
WHERE
  rq.OwnerUserId IS NOT NULL
ORDER BY rq.CreationDate DESC
LIMIT 100;