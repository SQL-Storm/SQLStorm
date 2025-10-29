-- {"query": "5848.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-5-nano", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 906} 
WITH
RecentPostActivity AS (
  SELECT
    p.Id AS PostId,
    p.PostTypeId,
    p.OwnerUserId,
    p.Title,
    p.CreationDate,
    p.LastActivityDate,
    p.Score,
    p.ViewCount,
    p.Tags,
    p.Body,
    p.AnswerCount,
    p.CommentCount,
    p.FavoriteCount,
    p.ParentId,
    p.AcceptedAnswerId
  FROM Posts p
  WHERE p.CreationDate >= NOW() - INTERVAL '90 days'
),
TopTags AS (
  SELECT
    unnest(string_to_array(substring(p.Tags, 2, length(p.Tags)-2), '><')) AS TagName,
    p.Id AS PostId,
    p.Score
  FROM Posts p
  WHERE p.PostTypeId = 1
    AND p.Tags IS NOT NULL
),
TagScore AS (
  SELECT
    t.TagName,
    COUNT(*) AS PostCount,
    AVG(p.Score) AS AvgScore,
    MAX(p.LastActivityDate) AS LastActive
  FROM TopTags t
  JOIN Posts p ON p.Id = t.PostId
  GROUP BY t.TagName
  ORDER BY PostCount DESC, AvgScore DESC
  LIMIT 25
),
UserReputationWindow AS (
  SELECT
    u.Id AS UserId,
    u.DisplayName,
    u.Reputation,
    u.CreationDate,
    u.LastAccessDate,
    u.Views,
    u.UpVotes,
    u.DownVotes,
    u.Location,
    u.AccountId,
    ROW_NUMBER() OVER (ORDER BY u.Reputation DESC, u.LastAccessDate DESC) AS rn
  FROM Users u
  WHERE u.LastAccessDate >= NOW() - INTERVAL '365 days'
),
RecentVotes AS (
  SELECT
    v.PostId,
    v.VoteTypeId,
    v.UserId,
    v.CreationDate,
    v.BountyAmount
  FROM Votes v
  WHERE v.CreationDate >= NOW() - INTERVAL '90 days'
),
QualifiedPosts AS (
  SELECT
    rp.PostId,
    rp.Title,
    rp.OwnerUserId,
    rp.CreationDate,
    rp.LastActivityDate,
    rp.Score,
    rp.ViewCount,
    rp.Tags,
    rp.Body,
    rv.VoteTypeId,
    rv.UserId AS VoterUserId,
    rv.CreationDate AS VoteDate
  FROM RecentPostActivity rp
  LEFT JOIN RecentVotes rv ON rv.PostId = rp.PostId
  WHERE rp.Score >= 0
),
ComplexDerived AS (
  SELECT
    q.PostId,
    q.Title,
    q.CreationDate,
    q.LastActivityDate,
    q.Score,
    q.ViewCount,
    q.Tags,
    q.Body,
    CASE
      WHEN q.Tags IS NULL THEN NULL
      ELSE (SELECT STRING_AGG(TagName, ',')
            FROM TopTags
            WHERE TopTags.PostId = q.PostId)
    END AS TagList,
    CASE
      WHEN q.OwnerUserId IS NULL THEN 'Guest'
      ELSE (SELECT DisplayName FROM Users WHERE Id = q.OwnerUserId)
    END AS OwnerName,
    (SELECT COUNT(*) FROM Comments c WHERE c.PostId = q.PostId) AS CommentCount,
    (SELECT COUNT(*) FROM Votes v WHERE v.PostId = q.PostId AND v.VoteTypeId = 2) AS UpVotesFromPost,
    (SELECT COUNT(*) FROM Votes v WHERE v.PostId = q.PostId AND v.VoteTypeId = 3) AS DownVotesFromPost
  FROM QualifiedPosts q
)
SELECT
  c.PostId,
  c.Title,
  c.OwnerName,
  c.CreationDate,
  c.LastActivityDate,
  c.Score,
  c.ViewCount,
  c.TagList,
  c.CommentCount,
  c.UpVotesFromPost,
  c.DownVotesFromPost,
  ROW_NUMBER() OVER (PARTITION BY c.OwnerName ORDER BY c.Score DESC, c.LastActivityDate DESC) AS OwnerRank,
  (SELECT AVG(Score) FROM Posts p2 WHERE p2.OwnerUserId = c.PostId) AS DummyAvgScore
FROM ComplexDerived c
ORDER BY c.LastActivityDate DESC, c.Score DESC
LIMIT 100;