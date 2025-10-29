-- {"query": "5957.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-5-nano", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 926} 
WITH
RecentActivePosts AS (
  SELECT
    p.Id,
    p.PostTypeId,
    p.Title,
    p.Tags,
    p.CreationDate,
    p.OwnerUserId,
    p.ViewCount,
    p.Score,
    p.CommentCount,
    p.AnswerCount,
    p.LastActivityDate,
    p.LastEditDate
  FROM Posts p
  WHERE p.CreationDate > NOW() - INTERVAL '30 days'
),
TopVoted AS (
  SELECT
    p.Id,
    p.Title,
    p.Score,
    p.ViewCount,
    p.OwnerUserId,
    p.LastActivityDate,
    ROW_NUMBER() OVER (ORDER BY p.Score DESC, p.LastActivityDate DESC) AS rn
  FROM Posts p
  WHERE p.PostTypeId = 1 -- questions
    AND p.Score IS NOT NULL
),
UserStats AS (
  SELECT
    u.Id AS UserId,
    u.DisplayName,
    u.Reputation,
    u.CreationDate,
    u.LastAccessDate,
    u.Views,
    u.UpVotes,
    u.DownVotes,
    (SELECT COUNT(*) FROM Badges b WHERE b.UserId = u.Id AND b.Class = 1) AS GoldBadges,
    (SELECT COUNT(*) FROM Badges b WHERE b.UserId = u.Id AND b.Class = 2) AS SilverBadges,
    (SELECT COUNT(*) FROM Badges b WHERE b.UserId = u.Id AND b.Class = 3) AS BronzeBadges
  FROM Users u
),
TagTopicDynamics AS (
  SELECT
    t.TagName,
    COUNT(p.Id) FILTER (WHERE p.PostTypeId = 1) AS QuestionCount,
    AVG(p.ViewCount) AS AvgViews,
    MAX(p.Score) AS MaxScore
  FROM Posts p
  JOIN LATERAL (
    SELECT unnest(string_to_array(substr(p.Tags, 2, length(p.Tags)-2), '><')) AS TagName
  ) AS tsv ON TRUE
  WHERE p.PostTypeId = 1
  GROUP BY t.TagName
),
JoinedActivity AS (
  SELECT
    r.Id AS PostId,
    r.Title,
    r.Score,
    r.ViewCount,
    r.OwnerUserId,
    u.DisplayName AS OwnerName,
    COALESCE(c.CommentCount, 0) AS CommentCount,
    COALESCE(vv.UpModCount, 0) AS UpModCount
  FROM RecentActivePosts r
  LEFT JOIN Users u ON r.OwnerUserId = u.Id
  LEFT JOIN (
    SELECT PostId, COUNT(*) AS CommentCount
    FROM Comments
    GROUP BY PostId
  ) c ON c.PostId = r.Id
  LEFT JOIN (
    SELECT p.PostId, COUNT(*) AS UpModCount
    FROM Votes v
    JOIN VoteTypes vt ON v.VoteTypeId = vt.Id
    WHERE vt.Name = 'UpMod'
    GROUP BY p.PostId
  ) vv ON vv.PostId = r.Id
),
CompareTop AS (
  SELECT
    t.Id,
    t.Title,
    t.Score,
    t.ViewCount,
    t.OwnerUserId,
    t.LastActivityDate,
    t.rn
  FROM TopVoted t
  WHERE t.rn <= 100
),
JoinedWatched AS (
  SELECT
    a.PostId,
    a.Title,
    a.Score,
    a.ViewCount,
    a.OwnerUserId,
    a.OwnerName,
    a.CommentCount,
    a.UpModCount,
    LEAD(a.Score) OVER (ORDER BY a.Score DESC) AS NextScore,
    LAG(a.Score) OVER (ORDER BY a.Score DESC) AS PrevScore
  FROM JoinedActivity a
)
SELECT
  j.PostId,
  j.Title,
  j.Score,
  j.ViewCount,
  j.OwnerUserId,
  j.OwnerName,
  j.CommentCount,
  j.UpModCount,
  j.NextScore,
  j.PrevScore,
  u.Reputation,
  u.CreationDate AS UserCreationDate,
  u.LastAccessDate AS UserLastAccessDate
FROM JoinedWatched j
LEFT JOIN Users u ON j.OwnerUserId = u.Id
WHERE j.Score IS NOT NULL
  AND (j.Score > 0 OR j.NextScore IS NOT NULL)
ORDER BY j.Score DESC, j.LastActivityDate DESC
LIMIT 200;