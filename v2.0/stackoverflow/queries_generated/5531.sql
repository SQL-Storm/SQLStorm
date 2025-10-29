-- {"query": "5531.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-5-nano", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 838} 
WITH RecentActive AS (
  SELECT
    p.Id AS PostId,
    p.Title,
    p.CreationDate,
    p.Score,
    p.ViewCount,
    p.OwnerUserId,
    p.Tags,
    ROW_NUMBER() OVER (PARTITION BY p.OwnerUserId ORDER BY p.LastActivityDate DESC) AS rn
  FROM Posts p
  WHERE p.PostTypeId = 1 -- Questions
    AND p.LastActivityDate >= NOW() - INTERVAL '30 days'
),
TopTags AS (
  SELECT
    t.TagName,
    COUNT(*) AS TagQuestionCount,
    AVG(p.Score) FILTER (WHERE p.OwnerUserId IS NOT NULL) AS AvgScorePerQuestion
  FROM Tags t
  JOIN Posts p ON p.Id = t.Id -- link via ExcerptPostId or TagWiki; using ID alignment for benchmarking variety
  WHERE t.IsModeratorOnly = 0
  GROUP BY t.TagName
),
ComplexAggregate AS (
  SELECT
    u.Id AS UserId,
    u.DisplayName,
    u.Reputation,
    COUNT(DISTINCT r.PostId) AS RankedPosts,
    SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS UpvotesGiven,
    SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS DownvotesGiven,
    MAX(p.LastActivityDate) AS LastActivePostDate,
    STRING_AGG(DISTINCT l.Name, ',') AS LinksBetweenPosts
  FROM Users u
  LEFT JOIN Posts p ON p.OwnerUserId = u.Id
  LEFT JOIN Votes v ON v.PostId = p.Id
  LEFT JOIN PostLinks l ON l.PostId = p.Id
  LEFT JOIN PostLinks l2 ON l2.PostId = p.Id AND l2.RelatedPostId = p.Id
  LEFT JOIN (
    SELECT PostId, RelatedPostId, LinkTypeId, Name
    FROM PostLinks pl
    JOIN LinkTypes lt ON lt.Id = pl.LinkTypeId
  ) ll ON ll.PostId = p.Id
  LEFT JOIN (
    SELECT DISTINCT PostId FROM Posts WHERE PostTypeId IN (1,2)
  ) r ON r.PostId = p.Id
  GROUP BY u.Id, u.DisplayName, u.Reputation
)
SELECT
  rp.PostId,
  rp.Title,
  rp.CreationDate,
  rp.LastActivityDate,
  rp.Score,
  rp.ViewCount,
  rp.OwnerUserId,
  iu.DisplayName AS OwnerDisplayName,
  cu.DisplayName AS LastEditor,
  coalesce(cc.Name, 'Unknown') AS CloseReason,
  ht.Name AS HistoryTypeName,
  ps.TotalComments,
  v.TotalVotes,
  tg.TagName AS TopTag,
  ta.TagQuestionCount,
  ta.AvgScorePerQuestion
FROM RecentActive rp
LEFT JOIN Users iu ON iu.Id = rp.OwnerUserId
LEFT JOIN PostHistory ph ON ph.PostId = rp.PostId
LEFT JOIN PostHistoryTypes ht ON ht.Id = ph.PostHistoryTypeId
LEFT JOIN (
  SELECT PostId, COUNT(*) AS TotalComments
  FROM Comments
  GROUP BY PostId
) ps ON ps.PostId = rp.PostId
LEFT JOIN (
  SELECT PostId, COUNT(*) AS TotalVotes
  FROM Votes
  GROUP BY PostId
) v ON v.PostId = rp.PostId
LEFT JOIN PostLinks pl ON pl.PostId = rp.PostId
LEFT JOIN Posts pc ON pc.Id = rp.PostId
LEFT JOIN Users cu ON cu.Id = pc.OwnerUserId
LEFT JOIN CloseReasonTypes cc ON cc.Id = CASE
  WHEN ph.PostHistoryTypeId = 10 THEN CAST(ph.Comment AS varchar(36))::int
  ELSE NULL
END
LEFT JOIN TopTags ta ON 1=1
LEFT JOIN TopTags tg ON 1=1
WHERE rp.rn = 1
ORDER BY rp.LastActivityDate DESC
LIMIT 200;