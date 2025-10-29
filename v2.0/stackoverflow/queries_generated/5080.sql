-- {"query": "5080.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-5-nano", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 683} 
WITH
HighlyActiveQuestions AS (
  SELECT
    p.Id AS PostId,
    p.Title,
    p.OwnerUserId,
    p.CreationDate,
    p.Score,
    p.ViewCount,
    p.Tags,
    p.AnswerCount,
    p.CommentCount,
    p.LastActivityDate,
    p.FavoriteCount
  FROM Posts p
  WHERE p.PostTypeId = 1 -- Questions
    AND p.ViewCount > 1000
),
RecentActivity AS (
  SELECT
    p.Id AS PostId,
    p.Title,
    p.OwnerUserId,
    p.CreationDate,
    p.LastActivityDate,
    p.Score
  FROM Posts p
  WHERE p.PostTypeId = 1
    AND p.LastActivityDate > NOW() - interval '7 days'
),
TagEngagement AS (
  SELECT
    t.TagName,
    COUNT(p.Id) AS QuestionCount,
    SUM(p.ViewCount) AS TotalViews,
    AVG(p.Score) AS AvgScore
  FROM Posts p
  JOIN LATERAL (
      SELECT unnest(string_to_array(substring(p.Tags, 2, length(p.Tags) - 2), '><')) AS TagName
  ) AS tg ON TRUE
  JOIN Tags t ON t.TagName = tg.TagName
  WHERE p.PostTypeId = 1
  GROUP BY t.TagName
),
CrossJoinSummary AS (
  SELECT
    q.PostId,
    q.Title,
    q.OwnerUserId,
    q.CreationDate AS QuestionCreated,
    o.DisplayName AS OwnerDisplayName,
    u.Reputation,
    v1.VoteCountUp AS UpVotes,
    v2.VoteCountDown AS DownVotes,
    b.Class AS BadgeClass,
    b.Date AS BadgeDate,
    h.Name AS HistoryType
  FROM HighlyActiveQuestions q
  LEFT JOIN Users u ON u.Id = q.OwnerUserId
  LEFT JOIN Votes v ON v.PostId = q.PostId
  LEFT JOIN (
    SELECT UserId, COUNT(*) AS VoteCountUp
    FROM Votes
    WHERE VoteTypeId = 2
    GROUP BY UserId
  ) v1 ON v1.UserId = q.OwnerUserId
  LEFT JOIN (
    SELECT UserId, COUNT(*) AS VoteCountDown
    FROM Votes
    WHERE VoteTypeId = 3
    GROUP BY UserId
  ) v2 ON v2.UserId = q.OwnerUserId
  LEFT JOIN Badges b ON b.UserId = q.OwnerUserId
  LEFT JOIN PostHistory h ON h.PostId = q.PostId
  WHERE h.PostHistoryTypeId IN (10, 11, 16)
),
Windowed AS (
  SELECT
    *, ROW_NUMBER() OVER (PARTITION BY PostId ORDER BY BadgeDate DESC NULLS LAST) AS rn
  FROM CrossJoinSummary
)
SELECT
  PostId,
  Title,
  OwnerUserId,
  OwnerDisplayName,
  Reputation,
  QuestionCreated,
  LastActivityDate,
  UpVotes,
  DownVotes,
  BadgeClass,
  BadgeDate,
  HistoryType
FROM Windowed
WHERE rn = 1
ORDER BY LastActivityDate DESC NULLS LAST
LIMIT 100;