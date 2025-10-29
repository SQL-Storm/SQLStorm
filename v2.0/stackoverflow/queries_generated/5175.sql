-- {"query": "5175.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-5-nano", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 1216} 
WITH
recent_users AS (
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
    u.ProfileImageUrl,
    u.EmailHash,
    u.AccountId,
    ROW_NUMBER() OVER (ORDER BY u.Reputation DESC, u.CreationDate DESC) AS rn
  FROM Users u
),
popular_tags AS (
  SELECT
    t.TagName,
    t.Count,
    t.ExcerptPostId,
    t.WikiPostId,
    ROW_NUMBER() OVER (PARTITION BY t.TagName ORDER BY t.Count DESC) AS rn_tag
  FROM Tags t
  WHERE t.IsModeratorOnly = 0
),
post_summary AS (
  SELECT
    p.Id,
    p.PostTypeId,
    p.Title,
    p.Body,
    p.CreationDate,
    p.OwnerUserId,
    p.OwnerDisplayName,
    p.LastActivityDate,
    p.Score,
    p.ViewCount,
    p.Tags,
    p.AnswerCount,
    p.CommentCount,
    p.FavoriteCount,
    p.ParentId,
    p.AcceptedAnswerId,
    p.ContentLicense,
    ROW_NUMBER() OVER (PARTITION BY p.PostTypeId ORDER BY p.CreationDate DESC) AS rn_post
  FROM Posts p
  WHERE p.PostTypeId IN (1,2) -- questions and answers
),
recent_votes AS (
  SELECT
    v.Id,
    v.PostId,
    v.VoteTypeId,
    v.UserId,
    v.CreationDate,
    v.BountyAmount,
    ROW_NUMBER() OVER (PARTITION BY v.PostId ORDER BY v.CreationDate DESC) AS rn_vote
  FROM Votes v
  WHERE v.CreationDate >= NOW() - INTERVAL '30 days'
),
link_activity AS (
  SELECT
    pl.PostId,
    pl.RelatedPostId,
    l.Name AS LinkTypeName,
    pl.CreationDate,
    ROW_NUMBER() OVER (PARTITION BY pl.PostId ORDER BY pl.CreationDate DESC) AS rn_link
  FROM PostLinks pl
  JOIN LinkTypes l ON pl.LinkTypeId = l.Id
),
tag_related AS (
  SELECT
    t.TagName,
    t.Count,
    t.ExcerptPostId,
    t.WikiPostId,
    t.IsModeratorOnly
  FROM Tags t
  WHERE t.IsModeratorOnly = 0
)
SELECT
  ur.Id AS UserId,
  ur.DisplayName AS UserName,
  ur.Reputation,
  ur.CreationDate AS UserCreationDate,
  ur.LastAccessDate AS UserLastAccess,
  ur.Location,
  ur.Views,
  ur.UpVotes,
  ur.DownVotes,
  ur.ProfileImageUrl,
  ur.EmailHash,
  ur.AccountId,
  ps.Id AS PostId,
  ps.PostTypeId,
  pt.Name AS PostTypeName,
  ps.Title,
  ps.Body,
  ps.Tags,
  ps.CreationDate AS PostCreationDate,
  ps.LastActivityDate AS PostLastActivity,
  ps.Score,
  ps.ViewCount,
  ps.ParentId,
  ps.AcceptedAnswerId,
  ps.ContentLicense,
  ps.AnswerCount,
  ps.CommentCount,
  ps.FavoriteCount,
  rvr.RN_Vote AS LastVoteTypeForPost,
  rv.UserId AS VoterUserId,
  rv.VoteTypeId AS LastVoteTypeId,
  rv.CreationDate AS LastVoteDate,
  GROUP_CONCAT(DISTINCT ll.Name) AS LinkedOrRelatedTypes,
  ta.TagName AS TopTagName,
  ta.Count AS TagCount,
  ta.ExcerptPostId AS TagExcerptPostId
FROM recent_users ur
LEFT JOIN Posts ps ON ps.OwnerUserId = ur.Id
LEFT JOIN PostTypes pt ON ps.PostTypeId = pt.Id
LEFT JOIN post_summary psu ON ps.Id = psu.Id
LEFT JOIN (SELECT Id, PostTypeId, Title, Body, CreationDate, LastActivityDate, Score, ViewCount, Tags, AnswerCount, CommentCount, FavoriteCount, ParentId, AcceptedAnswerId, ContentLicense FROM Posts) ps2 ON ps.Id = ps2.Id
LEFT JOIN recent_votes rv ON rv.PostId = ps.Id
LEFT JOIN (SELECT PostId, MAX(CreationDate) AS LastVoteDate FROM Votes GROUP BY PostId) rvmax ON rvmax.PostId = ps.Id
LEFT JOIN Votes rvr ON rvr.PostId = ps.Id AND rvr.CreationDate = rvmax.LastVoteDate
LEFT JOIN link_activity la ON la.PostId = ps.Id
LEFT JOIN Tags ta ON ta.WikiPostId = ps.Id OR ta.ExcerptPostId = ps.Id
WHERE ur.rn <= 100
  OR ps.Id IS NULL
GROUP BY
  ur.Id, ur.DisplayName, ur.Reputation, ur.CreationDate, ur.LastAccessDate, ur.Location, ur.Views, ur.UpVotes, ur.DownVotes,
  ur.ProfileImageUrl, ur.EmailHash, ur.AccountId,
  ps.Id, ps.PostTypeId, pt.Name, ps.Title, ps.Body, ps.Tags, ps.CreationDate, ps.LastActivityDate, ps.Score,
  ps.ViewCount, ps.ParentId, ps.AcceptedAnswerId, ps.ContentLicense, ps.AnswerCount, ps.CommentCount, ps.FavoriteCount,
  rv.CreationDate, rv.UserId, rv.VoteTypeId, rvr.LastVoteTypeFor, ll.Name, ta.TagName, ta.Count, ta.ExcerptPostId
ORDER BY ur.Reputation DESC, ps.CreationDate DESC
LIMIT 200;