WITH
recent_questions AS (
  SELECT
    p.Id AS PostId,
    p.Title,
    p.CreationDate,
    p.Score,
    p.ViewCount,
    p.Tags,
    p.OwnerUserId,
    p.LastActivityDate,
    ROW_NUMBER() OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate DESC) AS rn
  FROM Posts p
  WHERE p.PostTypeId = 1
),
top_contributors AS (
  SELECT
    u.Id AS UserId,
    u.DisplayName,
    u.Reputation,
    SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS UpVotes,
    SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS DownVotes,
    COUNT(DISTINCT p.Id) AS QuestionCount,
    AVG(p.Score) AS AvgQuestionScore
  FROM Users u
  LEFT JOIN Posts p ON p.OwnerUserId = u.Id
  LEFT JOIN Votes v ON v.PostId = p.Id
  WHERE p.PostTypeId = 1
  GROUP BY u.Id, u.DisplayName, u.Reputation
),
tag_prefixs AS (
  SELECT
    t.TagName,
    t.Count,
    t.ExcerptPostId,
    t.WikiPostId
  FROM Tags t
  WHERE t.IsModeratorOnly = false
),
correlated_comments AS (
  SELECT
    c.PostId,
    c.UserId,
    c.Score,
    c.Text,
    c.CreationDate,
    p.Title,
    p.OwnerUserId
  FROM Comments c
  JOIN Posts p ON p.Id = c.PostId
  WHERE c.Text ~ '.*(performance|benchmark|test|stress).*'
),
complex_post_history AS (
  SELECT
    ph.Id,
    ph.PostId,
    ph.PostHistoryTypeId,
    ph.UserId,
    ph.CreationDate,
    ph.Text,
    ph.Comment
  FROM PostHistory ph
  WHERE ph.PostHistoryTypeId IN (10, 16, 52, 53, 66)
),
combined AS (
  SELECT
    rq.PostId,
    rq.Title,
    rq.CreationDate AS PostCreationDate,
    rq.LastActivityDate,
    tc.DisplayName AS LastEditorName,
    tc.Reputation AS LastEditorRep,
    v.UserId AS VoterUserId,
    vt.Name AS VoteType,
    tc2.Reputation AS OwnerRep,
    qc.Score AS CommentScore
  FROM recent_questions rq
  LEFT JOIN Posts p2 ON p2.Id = rq.PostId
  LEFT JOIN Users tc ON tc.Id = p2.OwnerUserId
  LEFT JOIN Votes v ON v.PostId = rq.PostId
  LEFT JOIN VoteTypes vt ON vt.Id = v.VoteTypeId
  LEFT JOIN Users tc2 ON tc2.Id = p2.OwnerUserId
  LEFT JOIN correlated_comments qc ON qc.PostId = rq.PostId
)
SELECT
  c.PostId,
  c.Title,
  c.PostCreationDate,
  c.LastActivityDate,
  c.LastEditorName,
  c.LastEditorRep,
  c.VoterUserId,
  c.VoteType,
  c.OwnerRep,
  c.CommentScore
FROM combined c
LEFT JOIN top_contributors tc ON tc.UserId = (
  SELECT p.OwnerUserId FROM Posts p WHERE p.Id = c.PostId
)
WHERE c.LastActivityDate > CAST('2024-10-01 12:34:56' AS timestamp) - INTERVAL '30' DAY
GROUP BY
  c.PostId,
  c.Title,
  c.PostCreationDate,
  c.LastActivityDate,
  c.LastEditorName,
  c.LastEditorRep,
  c.VoterUserId,
  c.VoteType,
  c.OwnerRep,
  c.CommentScore,
  tc.UserId,
  tc.DisplayName,
  tc.Reputation,
  tc.UpVotes,
  tc.DownVotes,
  tc.QuestionCount,
  tc.AvgQuestionScore
ORDER BY c.PostCreationDate DESC
LIMIT 100;