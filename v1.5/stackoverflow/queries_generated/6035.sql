-- {"query": "6035.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p1", "model": "gpt-5-nano", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 758} 
WITH
RecentTopPosts AS (
  SELECT
    p.Id AS PostId,
    p.Title,
    p.Tags,
    p.OwnerUserId,
    p.CreationDate,
    p.Score,
    p.ViewCount,
    p.CommentCount,
    pv.RankWithinOwner,
    pv.WindowEnd
  FROM Posts p
  LEFT JOIN (
    SELECT
      OwnerUserId,
      CreationDate,
      ROW_NUMBER() OVER (PARTITION BY OwnerUserId ORDER BY CreationDate DESC) AS RankWithinOwner,
      MAX(CREATIONDATE) OVER (PARTITION BY OwnerUserId) AS WindowEnd
    FROM Posts
  ) pv ON pv.OwnerUserId = p.OwnerUserId
  WHERE p.PostTypeId = 1 -- Questions
    AND p.CreationDate >= NOW() - INTERVAL '90 days'
),
ActiveTags AS (
  SELECT
    t.TagName,
    t.Count,
    t.ExcerptPostId,
    t.WikiPostId,
    t.IsModeratorOnly
  FROM Tags t
  WHERE t.IsModeratorOnly = 0
),
TopLinkClusters AS (
  SELECT
    pl.PostId,
    pl.RelatedPostId,
    lt.Name AS LinkTypeName
  FROM PostLinks pl
  JOIN LinkTypes lt ON pl.LinkTypeId = lt.Id
  WHERE lt.Name IN ('Linked', 'Duplicate')
),
UserStats AS (
  SELECT
    u.Id AS UserId,
    u.DisplayName,
    u.Reputation,
    u.CreationDate AS UserSince,
    u.LastAccessDate,
    u.Views,
    u.UpVotes,
    u.DownVotes,
    u.Location
  FROM Users u
),
ScoreDelta AS (
  SELECT
    v.PostId,
    SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS UpvotesReceived,
    SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS DownvotesReceived,
    SUM(CASE WHEN v.VoteTypeId IN (2,3) THEN 1 ELSE 0 END) AS TotalVotes
  FROM Votes v
  GROUP BY v.PostId
),
Combined AS (
  SELECT
    rtp.PostId,
    rtp.Title,
    rtp.Tags,
    rtp.OwnerUserId,
    ru.DisplayName AS OwnerDisplayName,
    ru.Reputation,
    rtp.CreationDate,
    rtp.ViewCount,
    rtp.Score,
    sc.TotalVotes,
    sc.UpvotesReceived,
    sc.DownvotesReceived,
    ac.Count AS AnswerCount,
    COALESCE(ltc.LinkTypeName, '') AS PrimaryLinkType,
    utc.TagName,
    utc.IsModeratorOnly
  FROM RecentTopPosts rtp
  LEFT JOIN UserStats ru ON ru.UserId = rtp.OwnerUserId
  LEFT JOIN ScoreDelta sc ON sc.PostId = rtp.PostId
  LEFT JOIN Posts a ON a.ParentId = rtp.PostId
  LEFT JOIN TopLinkClusters ltc ON ltc.PostId = rtp.PostId
  LEFT JOIN ActiveTags utc ON utc.ExcerptPostId = rtp.PostId
  WHERE 1=1
)
SELECT
  PostId,
  Title,
  OwnerDisplayName,
  CreatorReputation := Reputation,
  CreationDate,
  ViewCount,
  Score,
  TotalVotes,
  UpvotesReceived,
  DownvotesReceived,
  AnswerCount,
  PrimaryLinkType,
  TagName,
  IsModeratorOnly
FROM Combined
ORDER BY Score DESC, TotalVotes DESC
LIMIT 100;