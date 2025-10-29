-- {"query": "5435.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-5-nano", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 1009}
WITH
RecentActivePosts AS (
  SELECT
    p.Id,
    p.OwnerUserId,
    p.Title,
    p.CreationDate,
    p.ViewCount,
    p.Score,
    p.Tags,
    p.PostTypeId,
    p.ParentId,
    p.AcceptedAnswerId,
    p.LastActivityDate
  FROM Posts p
  WHERE p.PostTypeId IN (1, 2)
),
UserStats AS (
  SELECT
    u.Id AS UserId,
    u.DisplayName,
    u.Reputation,
    u.CreationDate AS UserCreationDate,
    u.LastAccessDate,
    u.Views,
    u.UpVotes,
    u.DownVotes,
    u.Location,
    u.AboutMe,
    u.ProfileImageUrl,
    COUNT(DISTINCT CASE WHEN v.VoteTypeId = 2 THEN v.PostId END) AS UpVotesGiven,
    COUNT(DISTINCT CASE WHEN v.VoteTypeId = 3 THEN v.PostId END) AS DownVotesGiven,
    SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS UpModVotesReceived,
    SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS DownModVotesReceived
  FROM Users u
  LEFT JOIN Votes v ON v.UserId = u.Id
  GROUP BY u.Id, u.DisplayName, u.Reputation, u.CreationDate, u.LastAccessDate, u.Views, u.UpVotes, u.DownVotes, u.Location, u.AboutMe, u.ProfileImageUrl
),
TagUsage AS (
  SELECT
    t.TagName
  FROM Tags t
  WHERE t.IsModeratorOnly = FALSE AND t.IsRequired = FALSE
),
TopTagWikis AS (
  SELECT
    t.TagName,
    t.Count,
    t.ExcerptPostId,
    t.WikiPostId
  FROM Tags t
  WHERE t.WikiPostId IS NOT NULL
  ORDER BY t.Count DESC
  LIMIT 5
),
Combined AS (
  SELECT
    rap.Id AS PostId,
    rap.Title,
    rap.CreationDate,
    rap.ViewCount,
    rap.Score,
    rap.Tags,
    rap.PostTypeId,
    ra.Id AS AcceptedAnswerId,
    rap.OwnerUserId,
    ra.LastActivityDate,
    u.DisplayName AS OwnerDisplayName,
    u.Reputation,
    u.Location,
    pv.UpVotes AS OwnerUpVotes,
    pv.DownVotes AS OwnerDownVotes,
    CASE
      WHEN pv.Reputation IS NULL THEN 0
      ELSE pv.Reputation
    END AS ReputationBucket
  FROM RecentActivePosts rap
  LEFT JOIN Posts ra ON rap.AcceptedAnswerId = ra.Id
  LEFT JOIN Users u ON rap.OwnerUserId = u.Id
  LEFT JOIN (
    SELECT v.UserId AS UserId,
           SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS UpVotes,
           SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS DownVotes,
           SUM(COALESCE(uu.Reputation, 0)) AS Reputation
    FROM Votes v
    JOIN Users uu ON v.UserId = uu.Id
    GROUP BY v.UserId
  ) pv ON pv.UserId = rap.OwnerUserId
  WHERE rap.LastActivityDate > (CAST('2024-10-01 12:34:56' AS TIMESTAMP) - INTERVAL '30' DAY)
),
Computed AS (
  SELECT
    c.*,
    HEIGHTS.count AS Depth
  FROM Combined c
  CROSS JOIN LATERAL (
    SELECT 1 AS count
  ) AS HEIGHTS
),
Final AS (
  SELECT
    a.PostId,
    a.Title,
    a.CreationDate,
    a.ViewCount,
    a.Score,
    a.Tags,
    a.PostTypeId,
    a.AcceptedAnswerId,
    a.OwnerUserId,
    a.OwnerDisplayName,
    a.Reputation,
    a.Location,
    a.OwnerUpVotes,
    a.OwnerDownVotes,
    a.ReputationBucket,
    pc.CountComment AS CommentCount,
    VOT.dk AS TotalVotes
  FROM Combined a
  LEFT JOIN (
    SELECT PostId, COUNT(*) AS CountComment
    FROM Comments
    GROUP BY PostId
  ) pc ON pc.PostId = a.PostId
  LEFT JOIN (
    SELECT PostId, SUM(BountyAmount) AS dk
    FROM Votes
    GROUP BY PostId
  ) VOT ON VOT.PostId = a.PostId
)
SELECT
  PostId,
  Title,
  CreationDate,
  ViewCount,
  Score,
  Tags,
  PostTypeId,
  COALESCE(AcceptedAnswerId, -1) AS AcceptedAnswerId,
  OwnerUserId,
  OwnerDisplayName,
  Reputation,
  Location,
  OwnerUpVotes,
  OwnerDownVotes,
  ReputationBucket,
  CommentCount,
  TotalVotes
FROM Final
ORDER BY CreationDate DESC, TotalVotes DESC
OFFSET 0 ROWS
FETCH FIRST 100 ROWS ONLY;