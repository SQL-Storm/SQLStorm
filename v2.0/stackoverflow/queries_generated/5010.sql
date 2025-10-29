-- {"query": "5010.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-5-nano", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 872} 
WITH
RecentPosts AS (
  SELECT
    p.Id,
    p.PostTypeId,
    p.Title,
    p.Body,
    p.CreationDate,
    p.OwnerUserId,
    p.LastActivityDate,
    p.Tags,
    p.ViewCount,
    p.Score,
    p.CommentCount,
    p.AnswerCount,
    p.FavoriteCount,
    p.ParentId,
    p.AcceptedAnswerId
  FROM Posts p
  WHERE p.CreationDate >= now() - INTERVAL '180 days'
),
TopVoted AS (
  SELECT
    p.Id,
    p.Title,
    p.Score,
    p.ViewCount,
    ROW_NUMBER() OVER (ORDER BY p.Score DESC, p.ViewCount DESC, p.CreationDate DESC) AS rn
  FROM Posts p
  WHERE p.PostTypeId = 1 -- Questions
    AND p.Score IS NOT NULL
),
UserActivity AS (
  SELECT
    u.Id AS UserId,
    u.DisplayName,
    u.Reputation,
    COUNT(*) FILTER (WHERE v.VoteTypeId = 2) AS UpVotesGiven,
    COUNT(*) FILTER (WHERE v.VoteTypeId = 3) AS DownVotesGiven,
    MAX(v.CreationDate) AS LastVoteDate
  FROM Users u
  LEFT JOIN Votes v ON v.UserId = u.Id
  GROUP BY u.Id, u.DisplayName, u.Reputation
),
TagStats AS (
  SELECT
    t.TagName,
    t.Count,
    AVG(p.Score) AS AvgPostScore,
    MAX(p.Score) AS MaxScore
  FROM Tags t
  LEFT JOIN Posts p ON p.Id = t.ExcerptPostId
  GROUP BY t.TagName, t.Count
),
Linkage AS (
  SELECT
    pl.PostId,
    pl.RelatedPostId,
    lt.Name AS LinkTypeName,
    pl.CreationDate AS LinkCreation
  FROM PostLinks pl
  JOIN LinkTypes lt ON lt.Id = pl.LinkTypeId
  WHERE pl.RelatedPostId <> pl.PostId
),
RecentTagMentions AS (
  SELECT
    t.TagName,
    COUNT(*) AS MentionCount
  FROM Unnest(string_to_array(p.Tags, '>')) AS tag_unit
  CROSS JOIN LATERAL (
    SELECT trim(both '><' FROM tag_unit) AS TagName
  ) AS t0
  GROUP BY t.TagName
)
SELECT
  rp.Id AS PostId,
  rp.Title AS PostTitle,
  rp.CreationDate AS PostCreation,
  rp.LastActivityDate AS LastActivity,
  rp.OwnerUserId,
  u.DisplayName AS OwnerDisplayName,
  u.Reputation AS OwnerReputation,
  tar.rn AS TopRank,
  tv.Score AS TopScore,
  tv.rn AS TopQuestionRank,
  ua.UserId AS ActiveUserId,
  ua.DisplayName AS ActiveUserName,
  ua.Reputation AS ActiveUserRep,
  ts.TagName,
  ts.AvgPostScore,
  ts.MaxScore,
  lnk.LinkTypeName,
  lnk.LinkCreation,
  rp.ViewCount,
  rp.Score,
  rp.AnswerCount,
  rp.CommentCount,
  rp.FavoriteCount
FROM RecentPosts rp
LEFT JOIN TopVoted tv ON tv.Id = rp.Id
LEFT JOIN LATERAL
  (SELECT rv.Id, rv.DisplayName, rv.Reputation
   FROM Users rv
   WHERE rv.Id = rp.OwnerUserId) AS u ON TRUE
LEFT JOIN UserActivity ua ON ua.UserId = rp.OwnerUserId
LEFT JOIN TagStats ts ON ts.TagName = substring(rp.Tags FROM 2 FOR char_length(rp.Tags)-2)
LEFT JOIN Linkage lnk ON lnk.PostId = rp.Id
LEFT JOIN RecentTagMentions rtm ON rtm.TagName = substring(rp.Tags FROM 2 FOR char_length(rp.Tags)-2)
WHERE rp.PostTypeId = 1
  AND rp.CreationDate >= (SELECT MIN(CreationDate) FROM Posts)
ORDER BY rp.LastActivityDate DESC, rp.CreationDate DESC
LIMIT 100;