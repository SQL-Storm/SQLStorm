-- {"query": "5724.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-5-nano", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 722}
WITH
TopAnsweredQuestions AS (
  SELECT
    p.Id AS QuestionId,
    p.Title,
    p.CreationDate,
    p.ViewCount,
    p.Score,
    p.OwnerUserId,
    p.Tags,
    p.AnswerCount,
    p.CommentCount,
    ROW_NUMBER() OVER (ORDER BY p.ViewCount DESC, p.Score DESC, p.CreationDate DESC) AS rn
  FROM Posts p
  WHERE p.PostTypeId = 1 -- Question
    AND p.ClosedDate IS NULL
),
RecentActivity AS (
  SELECT
    q.QuestionId,
    q.Title,
    q.CreationDate,
    q.ViewCount,
    q.Score,
    q.OwnerUserId,
    q.Tags,
    q.AnswerCount,
    q.CommentCount,
    u.Reputation,
    u.DisplayName,
    u.Location,
    CASE
      WHEN u.Reputation IS NULL THEN 0
      ELSE LOG(1 + u.Reputation) * 1000 / (EXTRACT(EPOCH FROM (CAST('2024-10-01 12:34:56' AS timestamp) - q.CreationDate)) / 3600.0 + 1)
    END AS ActivityScore
  FROM TopAnsweredQuestions q
  JOIN Users u ON u.Id = q.OwnerUserId
),
JoinedViews AS (
  SELECT
    r.QuestionId,
    r.Title,
    r.CreationDate AS CreateDate,
    r.ViewCount,
    r.Score,
    r.OwnerUserId,
    r.Tags,
    r.AnswerCount,
    r.CommentCount,
    u.DisplayName AS OwnerName,
    u.Reputation,
    v.UserId AS VotedUserId,
    v.VoteTypeId,
    v.CreationDate AS VoteDate
  FROM RecentActivity r
  LEFT JOIN Posts p ON p.Id = r.QuestionId
  LEFT JOIN Votes v ON v.PostId = p.Id
  LEFT JOIN Users u ON u.Id = r.OwnerUserId
),
TagFocus AS (
  SELECT
    TagName AS Tag,
    COUNT(*) AS TagCount
  FROM (
    SELECT unnest(string_to_array(substr(p.Tags, 2, length(p.Tags)-2), '><')) AS TagName
    FROM Posts p
    WHERE p.Tags IS NOT NULL
  ) t
  GROUP BY TagName
  ORDER BY TagCount DESC
  LIMIT 5
)
SELECT
  q.QuestionId,
  q.Title,
  q.CreationDate,
  q.ViewCount,
  q.Score,
  q.OwnerUserId,
  u.DisplayName AS OwnerName,
  u.Reputation,
  q.Tags,
  q.AnswerCount,
  q.CommentCount,
  v.VoteDate AS LastVoteDate,
  v.VoteTypeId AS LastVoteTypeId,
  (v.VoteTypeId = 2) AS HasRecentUpvote,
  CASE
    WHEN q.ViewCount > 1000 THEN 'HIGH'
    WHEN q.ViewCount > 100 THEN 'MEDIUM'
    ELSE 'LOW'
  END AS CreatedHeat,
  q.rn
FROM TopAnsweredQuestions q
LEFT JOIN Users u ON u.Id = q.OwnerUserId
LEFT JOIN LATERAL (
  SELECT v.PostId, v.VoteTypeId, v.CreationDate AS VoteDate, v.UserId
  FROM Votes v
  WHERE v.PostId = q.QuestionId
  ORDER BY v.CreationDate DESC
  LIMIT 1
) v ON true
ORDER BY q.rn
FETCH FIRST 100 ROWS ONLY;