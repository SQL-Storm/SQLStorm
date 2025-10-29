-- {"query": "5127.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-5-nano", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 1049}
WITH RecentHighImpactPosts AS (
  SELECT
    p.Id,
    p.Title,
    p.Tags,
    p.CreationDate,
    p.OwnerUserId,
    p.Score,
    p.ViewCount,
    p.CommentCount,
    p.AnswerCount,
    p.LastActivityDate,
    p.PostTypeId,
    VW.TotalUpVotes,
    VW.TotalDownVotes,
    COALESCE(UPV.Reputation, 0) AS OwnerReputation
  FROM Posts p
  LEFT JOIN (
    SELECT PostId, SUM(CASE WHEN VoteTypeId = 2 THEN 1 ELSE 0 END) AS TotalUpVotes,
                   SUM(CASE WHEN VoteTypeId = 3 THEN 1 ELSE 0 END) AS TotalDownVotes
    FROM Votes
    GROUP BY PostId
  ) VW ON VW.PostId = p.Id
  LEFT JOIN Users UPV ON UPV.Id = p.OwnerUserId
  WHERE p.PostTypeId = 1 -- questions
    AND p.CreationDate >= CAST('2024-10-01 12:34:56' AS TIMESTAMP) - INTERVAL '90 days'
),
ExpandedLinks AS (
  SELECT
    rp.Id AS RelatedPostId,
    rp.Title AS RelatedPostTitle,
    pl.PostId,
    pl.LinkTypeId,
    lt.Name AS LinkTypeName
  FROM PostLinks pl
  JOIN Posts rp ON rp.Id = pl.RelatedPostId
  JOIN LinkTypes lt ON lt.Id = pl.LinkTypeId
  WHERE pl.PostId IN (SELECT Id FROM RecentHighImpactPosts)
),
TaggedActivity AS (
  SELECT
    p.Id AS PostId,
    p.Title,
    t.TagName,
    t.Count AS TagCount,
    t.WikiPostId
  FROM Tags t
  JOIN Posts p ON p.Id = t.WikiPostId
  WHERE t.IsModeratorOnly = FALSE
),
WindowStats AS (
  SELECT
    rhip.Id,
    rhip.Title,
    rhip.Tags,
    rhip.CreationDate,
    rhip.OwnerUserId,
    rhip.Score,
    rhip.ViewCount,
    rhip.CommentCount,
    rhip.AnswerCount,
    rhip.LastActivityDate,
    rhip.PostTypeId,
    rhip.TotalUpVotes,
    rhip.TotalDownVotes,
    rhip.OwnerReputation,
    ROW_NUMBER() OVER (PARTITION BY (CASE WHEN rhip.PostTypeId = 1 THEN 'Question' ELSE 'Other' END)
                       ORDER BY rhip.Score DESC, rhip.ViewCount DESC, rhip.CreationDate DESC) AS rn
  FROM RecentHighImpactPosts rhip
),
AggregateSummary AS (
  SELECT
    ws.Id,
    ws.Title,
    ws.Tags,
    ws.CreationDate,
    ws.OwnerUserId,
    ws.Score,
    ws.ViewCount,
    ws.CommentCount,
    ws.AnswerCount,
    ws.LastActivityDate,
    ws.PostTypeId,
    ws.TotalUpVotes,
    ws.TotalDownVotes,
    ws.OwnerReputation,
    aa.RelatedPostId,
    aa.RelatedPostTitle,
    ARRAY_AGG(DISTINCT lt.Name) FILTER (WHERE aa.LinkTypeId IS NOT NULL) AS LinkTypesUsed,
    ws.rn
  FROM WindowStats ws
  LEFT JOIN ExpandedLinks aa ON aa.PostId = ws.Id
  LEFT JOIN LATERAL (SELECT DISTINCT ll.LinkTypeId, ll.RelatedPostId
                     FROM ExpandedLinks ll
                     WHERE ll.PostId = ws.Id) AS dummy ON true
  LEFT JOIN LinkTypes lt ON lt.Id = aa.LinkTypeId
  GROUP BY
    ws.Id, ws.Title, ws.Tags, ws.CreationDate, ws.OwnerUserId, ws.Score, ws.ViewCount,
    ws.CommentCount, ws.AnswerCount, ws.LastActivityDate, ws.PostTypeId, ws.TotalUpVotes,
    ws.TotalDownVotes, ws.OwnerReputation, aa.RelatedPostId, aa.RelatedPostTitle, ws.rn
)
SELECT
  a.Id AS PostId,
  a.Title,
  a.Tags,
  a.CreationDate,
  a.OwnerUserId,
  a.Score,
  a.ViewCount,
  a.CommentCount,
  a.AnswerCount,
  a.LastActivityDate,
  a.PostTypeId,
  a.TotalUpVotes,
  a.TotalDownVotes,
  a.OwnerReputation,
  wt.RelatedPostId,
  wt.RelatedPostTitle,
  a.LinkTypesUsed,
  (CASE
    WHEN a.OwnerUserId IS NOT NULL THEN
      (SELECT u.DisplayName FROM Users u WHERE u.Id = a.OwnerUserId)
    ELSE NULL
  END) AS OwnerDisplayName,
  CAST('2024-10-01 12:34:56' AS TIMESTAMP) AS BenchmarkVal
FROM AggregateSummary a
LEFT JOIN LATERAL (
  SELECT rp.RelatedPostId, rp.RelatedPostTitle
  FROM ExpandedLinks rp
  WHERE rp.PostId = a.Id
  ORDER BY rp.RelatedPostId
  LIMIT 5
) wt ON true
WHERE a.rn <= 50
ORDER BY a.Score DESC, a.ViewCount DESC, a.CreationDate DESC
LIMIT 100;