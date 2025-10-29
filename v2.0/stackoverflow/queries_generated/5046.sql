-- {"query": "5046.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-5-nano", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 706} 
WITH
RecentActivePosts AS (
  SELECT
    p.Id AS PostId,
    p.OwnerUserId,
    p.Title,
    p.Tags,
    p.CreationDate,
    p.LastActivityDate,
    p.Score,
    p.ViewCount,
    p.AnswerCount,
    p.CommentCount,
    p.FavoriteCount,
    p.PostTypeId,
    p.ParentId,
    p.AcceptedAnswerId
  FROM Posts p
  WHERE p.CreationDate >= NOW() - INTERVAL '90 days'
),
TopTags AS (
  SELECT
    t.TagName,
    t.Count AS TagCount
  FROM Tags t
  WHERE t.IsModeratorOnly = 0
),
UserActivity AS (
  SELECT
    u.Id AS UserId,
    u.DisplayName,
    u.Reputation,
    u.AccountId,
    COUNT(v.Id) FILTER (WHERE v.VoteTypeId = 2) AS UpVotesGiven,
    COUNT(v.Id) FILTER (WHERE v.VoteTypeId = 3) AS DownVotesGiven,
    MAX(v.CreationDate) AS LastVoteDate
  FROM Users u
  LEFT JOIN Votes v ON v.UserId = u.Id
  GROUP BY u.Id, u.DisplayName, u.Reputation, u.AccountId
),
TagFollowerJoin AS (
  SELECT
    u.UserId,
    t.TagName
  FROM Users u
  JOIN Badges b ON b.UserId = u.Id AND b.Name = 'TagFollower'
  JOIN Tags t ON t.TagName = b.Name
),
ConcurrentEngagement AS (
  SELECT
    p.PostId,
    p.OwnerUserId,
    p.Title,
    p.Score,
    p.ViewCount,
    p.AnswerCount,
    p.CommentCount,
    ROW_NUMBER() OVER (PARTITION BY p.OwnerUserId ORDER BY p.LastActivityDate DESC) AS rn
  FROM RecentActivePosts p
  WHERE p.LastActivityDate IS NOT NULL
)
SELECT
  rp.PostId,
  rp.Title AS PostTitle,
  rp.Tags,
  rp.Score AS PostScore,
  rp.ViewCount,
  rp.AnswerCount,
  rp.CommentCount,
  ru.UserId,
  ru.DisplayName AS OwnerDisplayName,
  ru.Reputation,
  ru.LastVoteDate,
  t.TagName AS HighlightTag,
  ta.TagCount
FROM ConcurrentEngagement rp
LEFT JOIN UserActivity ru ON ru.UserId = rp.OwnerUserId
LEFT JOIN TopTags ta ON ta.TagName = ANY(string_to_array(substring(rp.Tags, 2, length(rp.Tags)-2), '><'))
LEFT JOIN (
  SELECT DISTINCT ON (PostId) PostId, RelatedPostId
  FROM PostLinks
  WHERE LinkTypeId = 1
  ORDER BY PostId, CreationDate DESC
) pl ON pl.PostId = rp.PostId
LEFT JOIN PostLinks pl2 ON pl2.PostId = rp.PostId AND pl2.RelatedPostId IS NOT NULL
LEFT JOIN Tags t ON t.Id = (SELECT id FROM Tags t2 WHERE t2.TagName = ANY(string_to_array(substring(rp.Tags, 2, length(rp.Tags)-2), '><')) LIMIT 1)
WHERE rp.rn = 1
  AND rp.OwnerUserId IS NOT NULL
ORDER BY rp.LastActivityDate DESC
LIMIT 100;