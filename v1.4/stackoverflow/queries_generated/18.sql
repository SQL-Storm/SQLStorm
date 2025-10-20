-- {"query": "18.sql", "dataset": "stackoverflow", "version": "v1.4", "prompt": "p1", "model": "gpt-5-nano", "temperature": 1.0, "max_tokens": 32768, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 813} 
WITH
RecentActivePosts AS (
  SELECT
    p.Id,
    p.PostTypeId,
    p.Title,
    p.Tags,
    p.OwnerUserId,
    p.CreationDate,
    p.LastActivityDate,
    p.ViewCount,
    p.Score,
    p.CommentCount,
    p.AnswerCount,
    p.FavoriteCount,
    p.ContentLicense
  FROM Posts p
  WHERE p.CreationDate >= NOW() - INTERVAL '180 days'
),
TopAuthors AS (
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
    u.AboutMe,
    ROW_NUMBER() OVER (ORDER BY u.Reputation DESC, u.UpVotes DESC) AS rn
  FROM Users u
  WHERE u.Reputation IS NOT NULL
),
TagInsights AS (
  SELECT
    t.TagName,
    t.Count,
    t.ExcerptPostId,
    t.WikiPostId,
    p.Id AS PostId,
    p.Title AS PostTitle,
    p.OwnerUserId AS PostOwner,
    p.CreationDate AS PostCreated
  FROM Tags t
  LEFT JOIN Posts p ON t.WikiPostId = p.Id OR t.ExcerptPostId = p.Id
  WHERE t.IsModeratorOnly = 0
),
LinkSummary AS (
  SELECT
    pl.PostId,
    COUNT(*) AS LinkCount,
    STRING_AGG(CAST(lt.Id AS varchar), ',') AS LinkTypeIds
  FROM PostLinks pl
  JOIN LinkTypes lt ON pl.LinkTypeId = lt.Id
  GROUP BY pl.PostId
),
VotesSummary AS (
  SELECT
    v.PostId,
    SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS UpVotes,
    SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS DownVotes,
    SUM(CASE WHEN v.VoteTypeId = 9 THEN 1 ELSE 0 END) AS BountyVotes,
    COUNT(*) AS VoteCount
  FROM Votes v
  GROUP BY v.PostId
),
CorrelatedPairs AS (
  SELECT
    rp.Id AS RelatedPostId,
    rp.Title AS RelatedTitle,
    rp.OwnerUserId AS RelatedOwner
  FROM Posts rp
  JOIN VoteTypes vt ON vt.Id = 2
  WHERE rp.PostTypeId = 1
)
SELECT
  RAP.Id AS PostId,
  RAP.Title AS PostTitle,
  RAP.OwnerUserId,
  RAP.CreationDate,
  RAP.LastActivityDate,
  RAP.ViewCount,
  RAP.Score,
  RAP.CommentCount,
  RAP.AnswerCount,
  RAP.FavoriteCount,
  RAP.ContentLicense,
  TI.TagName AS TopTag,
  TI.Count AS TagCount,
  TI.PostCreated,
  LS.LinkCount,
  LS.LinkTypeIds,
  VS.UpVotes AS NetUpVotes,
  VS.DownVotes AS NetDownVotes,
  VS.BountyVotes,
  UA.DisplayName AS OwnerDisplayName,
  UA.Reputation,
  UA.LastAccessDate,
  UA.Location,
  UA.AboutMe,
  CA RelatedPostInfo
FROM RecentActivePosts RAP
LEFT JOIN TopAuthors UA ON RAP.OwnerUserId = UA.UserId
LEFT JOIN TagInsights TI ON 1=1
LEFT JOIN LinkSummary LS ON RAP.Id = LS.PostId
LEFT JOIN VotesSummary VS ON RAP.Id = VS.PostId
LEFT JOIN CorrelatedPairs CP ON RAP.Id = CP.RelatedPostId
LEFT JOIN LATERAL (
  SELECT
    CP.RelatedOwner,
    CP.RelatedTitle
) AS CA(RelatedPostInfo)
ORDER BY RAP.LastActivityDate DESC
LIMIT 100;