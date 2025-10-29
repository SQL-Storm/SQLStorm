-- {"query": "5348.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-5-nano", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 852}
WITH
RecentActivePosts AS (
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
    p.AnswerCount,
    p.CommentCount,
    p.FavoriteCount,
    p.ParentId,
    p.AcceptedAnswerId,
    p.Body
  FROM Posts p
  WHERE p.CreationDate >= TIMESTAMP '2019-01-01 00:00:00'
),
TaggedActivity AS (
  SELECT
    rap.PostId,
    rap.Title,
    rap.OwnerUserId,
    rap.Score,
    rap.ViewCount,
    rap.Tags,
    rap.LastActivityDate,
    COALESCE(vt.TotalVotes,0) AS TotalVotes,
    COALESCE(upv.UpVotes,0) AS UpVotes,
    COALESCE(dnv.DownVotes,0) AS DownVotes,
    u.DisplayName,
    u.Reputation,
    u.CreationDate AS UserCreationDate,
    row_number() OVER (ORDER BY rap.LastActivityDate DESC, rap.Score DESC) AS rn
  FROM RecentActivePosts rap
  LEFT JOIN (
    SELECT PostId, SUM(CASE WHEN VoteTypeId = 2 THEN 1 ELSE 0 END) AS TotalVotes
    FROM Votes
    GROUP BY PostId
  ) vt ON vt.PostId = rap.PostId
  LEFT JOIN (
    SELECT PostId, SUM(CASE WHEN VoteTypeId = 2 THEN 1 ELSE 0 END) AS UpVotes
    FROM Votes
    GROUP BY PostId
  ) upv ON upv.PostId = rap.PostId
  LEFT JOIN (
    SELECT PostId, SUM(CASE WHEN VoteTypeId = 3 THEN 1 ELSE 0 END) AS DownVotes
    FROM Votes
    GROUP BY PostId
  ) dnv ON dnv.PostId = rap.PostId
  LEFT JOIN Users u ON u.Id = rap.OwnerUserId
),
CorrelatedComments AS (
  SELECT
    ta.PostId,
    COUNT(c.Id) AS CommentCount,
    STRING_AGG(c.Text, ' || ') AS AllComments,
    MAX(c.CreationDate) AS LastCommentDate
  FROM TaggedActivity ta
  LEFT JOIN Comments c ON c.PostId = ta.PostId
  GROUP BY ta.PostId
),
PostLinkage AS (
  SELECT
    cl.PostId,
    COUNT(*) AS LinkCount,
    STRING_AGG(CAST(lt.Name AS VARCHAR(100)) || ':' || CAST(cl.RelatedPostId AS VARCHAR(20)), ' | ') AS LinkDetails
  FROM PostLinks cl
  LEFT JOIN LinkTypes lt ON lt.Id = cl.LinkTypeId
  GROUP BY cl.PostId
),
TagSummary AS (
  SELECT
    t.TagName,
    t.Count,
    t.IsModeratorOnly,
    t.IsRequired,
    p.Id AS PostId
  FROM Tags t
  LEFT JOIN Posts p ON p.Id = t.WikiPostId OR p.Id = t.Id
  WHERE t.Count > 0
)
SELECT
  ra.PostId,
  ra.Title,
  ra.OwnerUserId,
  ra.DisplayName AS OwnerDisplayName,
  ra.Reputation,
  ra.UserCreationDate,
  ra.LastActivityDate,
  ra.Score,
  ra.ViewCount,
  ra.Tags,
  ra.TotalVotes,
  ra.UpVotes,
  ra.DownVotes,
  ca.CommentCount,
  ca.AllComments,
  ca.LastCommentDate,
  pl.LinkCount,
  pl.LinkDetails,
  ts.TagName,
  ts.Count AS TagCount,
  ts.IsModeratorOnly,
  ts.IsRequired
FROM TaggedActivity ra
LEFT JOIN CorrelatedComments ca ON ca.PostId = ra.PostId
LEFT JOIN PostLinkage pl ON pl.PostId = ra.PostId
LEFT JOIN TagSummary ts ON ts.PostId = ra.PostId
WHERE ra.rn <= 100
ORDER BY ra.LastActivityDate DESC, ra.Score DESC, ra.ViewCount DESC;