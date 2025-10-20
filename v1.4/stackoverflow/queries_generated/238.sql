-- {"query": "238.sql", "dataset": "stackoverflow", "version": "v1.4", "prompt": "p1", "model": "gpt-5-nano", "temperature": 1.0, "max_tokens": 32768, "reasoning": "medium", "input_tokens": 2026, "output_tokens": 6315} 
WITH
HighPosts AS (
  SELECT
    p.Id AS PostId,
    p.Title,
    p.Score,
    p.ViewCount,
    p.CreationDate,
    p.LastActivityDate,
    p.OwnerUserId,
    u.DisplayName AS OwnerDisplayName,
    u.Reputation,
    p.CommentCount,
    COALESCE(v.UpVotes, 0) AS UpVotes,
    COALESCE(v.DownVotes, 0) AS DownVotes,
    ROW_NUMBER() OVER (PARTITION BY p.OwnerUserId ORDER BY p.LastActivityDate DESC) AS UserPostRank,
    COALESCE( (SELECT AVG(length(c.Text)) FROM Comments c WHERE c.PostId = p.Id), 0) AS AvgCommentLength,
    LEFT(u.DisplayName, 2) AS OwnerInitials,
    COALESCE(PL.Linked, '') AS LinkedInfo,
    CASE WHEN p.LastActivityDate IS NULL THEN NULL ELSE p.LastActivityDate END AS LastAct
  FROM Posts p
  JOIN Users u ON p.OwnerUserId = u.Id
  LEFT JOIN (
     SELECT PostId, SUM(CASE WHEN VoteTypeId = 2 THEN 1 ELSE 0 END) AS UpVotes,
            SUM(CASE WHEN VoteTypeId = 3 THEN 1 ELSE 0 END) AS DownVotes
     FROM Votes
     GROUP BY PostId
  ) v ON v.PostId = p.Id
  LEFT JOIN (
     SELECT pl.PostId, STRING_AGG(CAST(pl.RelatedPostId AS text) || '(' || lt.Name || ')', ',') AS Linked
     FROM PostLinks pl
     JOIN LinkTypes lt ON pl.LinkTypeId = lt.Id
     GROUP BY pl.PostId
  ) PL ON PL.PostId = p.Id
  WHERE p.PostTypeId = 1
    AND p.LastActivityDate >= now() - interval '1 year'
),
LowPosts AS (
  SELECT
    p.Id AS PostId,
    p.Title,
    p.Score,
    p.ViewCount,
    p.CreationDate,
    p.LastActivityDate,
    p.OwnerUserId,
    u.DisplayName AS OwnerDisplayName,
    u.Reputation,
    p.CommentCount,
    COALESCE(v.UpVotes, 0) AS UpVotes,
    COALESCE(v.DownVotes, 0) AS DownVotes,
    ROW_NUMBER() OVER (PARTITION BY p.OwnerUserId ORDER BY p.LastActivityDate DESC) AS UserPostRank,
    COALESCE( (SELECT AVG(length(c.Text)) FROM Comments c WHERE c.PostId = p.Id), 0) AS AvgCommentLength,
    LEFT(u.DisplayName, 2) AS OwnerInitials,
    COALESCE(PL.Linked, '') AS LinkedInfo
  FROM Posts p
  JOIN Users u ON p.OwnerUserId = u.Id
  LEFT JOIN (
     SELECT PostId, SUM(CASE WHEN VoteTypeId = 2 THEN 1 ELSE 0 END) AS UpVotes,
            SUM(CASE WHEN VoteTypeId = 3 THEN 1 ELSE 0 END) AS DownVotes
     FROM Votes
     GROUP BY PostId
  ) v ON v.PostId = p.Id
  LEFT JOIN (
     SELECT pl.PostId, STRING_AGG(CAST(pl.RelatedPostId AS text) || '(' || lt.Name || ')', ',') AS Linked
     FROM PostLinks pl
     JOIN LinkTypes lt ON pl.LinkTypeId = lt.Id
     GROUP BY pl.PostId
  ) PL ON PL.PostId = p.Id
  WHERE p.PostTypeId = 1
    AND p.LastActivityDate < now() - interval '2 years'
)
SELECT
  'Q' AS Source,
  PostId,
  Title,
  OwnerDisplayName AS Owner,
  Score,
  ViewCount,
  CreationDate,
  LastActivityDate,
  UpVotes,
  DownVotes,
  CommentCount,
  UserPostRank,
  AvgCommentLength,
  OwnerInitials,
  LinkedInfo
FROM HighPosts
UNION ALL
SELECT
  'L' AS Source,
  PostId,
  Title,
  OwnerDisplayName AS Owner,
  Score,
  ViewCount,
  CreationDate,
  LastActivityDate,
  UpVotes,
  DownVotes,
  CommentCount,
  UserPostRank,
  AvgCommentLength,
  OwnerInitials,
  LinkedInfo
FROM LowPosts
ORDER BY LastActivityDate DESC NULLS LAST
LIMIT 200;