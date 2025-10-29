-- {"query": "5854.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-5-nano", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 769} 
WITH
recent_questions AS (
  SELECT
    p.Id AS PostId,
    p.Title,
    p.Tags,
    p.CreationDate,
    p.Score,
    p.ViewCount,
    p.OwnerUserId,
    p.OwnerDisplayName,
    p.LastActivityDate,
    p.CommentCount,
    p.FavoriteCount,
    p.AnswerCount,
    p.ContentLicense,
    ROW_NUMBER() OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate DESC) AS rn
  FROM Posts p
  WHERE p.PostTypeId = 1
    AND p.DeletionDate IS NULL
),
top_users AS (
  SELECT
    u.Id AS UserId,
    u.DisplayName,
    u.Reputation,
    u.CreationDate,
    u.LastAccessDate,
    u.Views,
    u.UpVotes,
    u.DownVotes,
    u.AccountId,
    u.Location,
    u.WebsiteUrl,
    u.AboutMe,
    u.ProfileImageUrl,
    ROW_NUMBER() OVER (ORDER BY u.Reputation DESC, u.UpVotes DESC, u.Views DESC) AS rn
  FROM Users u
  WHERE u.Reputation > 1000
),
tag_popularity AS (
  SELECT
    t.TagName,
    SUM(t.Count) AS TagCount
  FROM Tags t
  WHERE t.TagName IS NOT NULL
  GROUP BY t.TagName
),
edge_cases AS (
  SELECT
    q.PostId,
    q.Title,
    q.Tags,
    q.CreationDate,
    q.Score,
    q.ViewCount,
    q.OwnerUserId,
    q.OwnerDisplayName,
    q.LastActivityDate,
    q.CommentCount,
    q.FavoriteCount,
    q.AnswerCount,
    q.ContentLicense,
    tu.UserId AS TopUserId,
    tu.DisplayName AS TopUserName,
    tu.Reputation AS TopUserRep,
    tc.TagName,
    tc.TagCount
  FROM recent_questions q
  LEFT JOIN top_users tu ON q.OwnerUserId = tu.UserId
  LEFT JOIN LATERAL (
    SELECT unnest(string_to_array(substr(q.Tags, 2, length(q.Tags)-2), '><')) AS TagName
  ) AS t ON true
  LEFT JOIN tag_popularity tc ON tc.TagName = t.TagName
  WHERE q.rn = 1
)
SELECT
  eu.PostId,
  eu.Title,
  eu.Tags,
  eu.CreationDate AS PostCreationDate,
  eu.Score,
  eu.ViewCount,
  eu.OwnerUserId,
  eu.OwnerDisplayName,
  eu.LastActivityDate,
  eu.CommentCount,
  eu.FavoriteCount,
  eu.AnswerCount,
  eu.ContentLicense,
  eu.TopUserId,
  eu.TopUserName,
  eu.TopUserRep,
  eu.TagName,
  eu.TagCount,
  (eu.Score * 1.0 / NULLIF(eu.ViewCount,0)) AS ScorePerView,
  (EXISTS (
     SELECT 1
     FROM Votes v
     WHERE v.PostId = eu.PostId
       AND v.VoteTypeId = 2
       AND v.UserId = eu.TopUserId
  )) AS UpvoteFromTopUser,
  (EXISTS (
     SELECT 1
     FROM Votes v
     WHERE v.PostId = eu.PostId
       AND v.VoteTypeId = 3
       AND v.UserId = eu.TopUserId
  )) AS DownvoteFromTopUser
FROM edge_cases eu
ORDER BY eu.TopUserRep DESC NULLS LAST, eu.Score DESC, eu.PostId
LIMIT 200;