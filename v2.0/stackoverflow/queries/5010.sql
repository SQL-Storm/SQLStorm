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
  WHERE p.CreationDate >= CAST('2024-10-01 12:34:56' AS timestamp) - INTERVAL '180 days'
),
TopVoted AS (
  SELECT
    p.Id,
    p.Title,
    p.Score,
    p.ViewCount,
    ROW_NUMBER() OVER (ORDER BY p.Score DESC NULLS LAST, p.ViewCount DESC NULLS LAST, p.CreationDate DESC) AS rn,
    p.CreationDate
  FROM Posts p
  WHERE p.PostTypeId = 1
    AND p.Score IS NOT NULL
),
UserActivity AS (
  SELECT
    u.Id AS UserId,
    u.DisplayName,
    u.Reputation,
    COUNT(CASE WHEN v.VoteTypeId = 2 THEN 1 END) AS UpVotesGiven,
    COUNT(CASE WHEN v.VoteTypeId = 3 THEN 1 END) AS DownVotesGiven,
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
  FROM (
    SELECT
      rp.Id AS source_post_id,
      REPLACE(REPLACE(REGEXP_REPLACE(rp.Tags, '^<|>$', '', 'g'), '><', '|'), '||', '|') AS tags_pipe
    FROM Posts rp
    WHERE rp.Tags IS NOT NULL
  ) src
  CROSS JOIN LATERAL (
    SELECT tag_unit
    FROM (
      SELECT regexp_split_to_table(src.tags_pipe, '\|') AS tag_unit
    ) s
  ) split_tags
  CROSS JOIN LATERAL (
    SELECT trim(both '<>' FROM split_tags.tag_unit) AS TagName
  ) t
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
  tv.rn AS TopRank,
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
   WHERE rv.Id = rp.OwnerUserId) u ON TRUE
LEFT JOIN UserActivity ua ON ua.UserId = rp.OwnerUserId
LEFT JOIN TagStats ts ON ts.TagName = CASE WHEN rp.Tags IS NOT NULL THEN SUBSTRING(rp.Tags FROM 2 FOR CHAR_LENGTH(rp.Tags)-2) ELSE NULL END
LEFT JOIN Linkage lnk ON lnk.PostId = rp.Id
LEFT JOIN RecentTagMentions rtm ON rtm.TagName = CASE WHEN rp.Tags IS NOT NULL THEN SUBSTRING(rp.Tags FROM 2 FOR CHAR_LENGTH(rp.Tags)-2) ELSE NULL END
WHERE rp.PostTypeId = 1
  AND rp.CreationDate >= (SELECT MIN(p2.CreationDate) FROM Posts p2)
ORDER BY rp.LastActivityDate DESC, rp.CreationDate DESC
LIMIT 100;