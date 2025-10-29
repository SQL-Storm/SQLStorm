-- {"query": "5425.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-5-nano", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 884} 
WITH TopUsers AS (
  SELECT
    u.Id AS UserId,
    u.DisplayName,
    u.Reputation,
    u.CreationDate,
    u.LastAccessDate,
    u.Location,
    COUNT(DISTINCT p.Id) AS PostCount,
    SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS UpvotesCast,
    SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS DownvotesCast,
    MAX(p.LastActivityDate) AS LastActivityDate
  FROM Users u
  LEFT JOIN Posts p ON p.OwnerUserId = u.Id
  LEFT JOIN Votes v ON v.PostId = p.Id
  GROUP BY u.Id, u.DisplayName, u.Reputation, u.CreationDate, u.LastAccessDate, u.Location
),
QualifiedPosts AS (
  SELECT
    p.Id AS PostId,
    p.PostTypeId,
    p.Title,
    p.Tags,
    p.CreationDate,
    p.LastActivityDate,
    p.Score,
    p.ViewCount,
    p.OwnerUserId,
    p.AcceptedAnswerId,
    ROW_NUMBER() OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate DESC) AS rn_by_owner
  FROM Posts p
  WHERE p.PostTypeId IN (1, 2) -- Questions and Answers
),
CorrelationCTE AS (
  SELECT
    tp.PostId,
    tp.PostTypeId,
    tp.Title,
    tp.Tags,
    tp.CreationDate,
    tp.LastActivityDate,
    tp.Score,
    tp.ViewCount,
    tp.OwnerUserId,
    tp.AcceptedAnswerId,
    tp.rn_by_owner,
    u.DisplayName AS OwnerDisplayName,
    u.Reputation AS OwnerReputation,
    (SELECT AVG(v2.BountyAmount) FROM Votes v2 WHERE v2.PostId = tp.PostId) AS AvgBounty,
    (SELECT COUNT(*) FROM PostLinks pl WHERE pl.PostId = tp.PostId) AS RelatedLinks,
    (SELECT COUNT(*) FROM Comments c WHERE c.PostId = tp.PostId) AS CommentCount,
    (SELECT string_agg(t.TagName, ',') FROM Tags t JOIN Posts p2 ON p2.Id = tp.PostId WHERE p2.Id = tp.PostId AND t.TagName IS NOT NULL) AS TagSummary
  FROM QualifiedPosts tp
  LEFT JOIN TopUsers u ON tp.OwnerUserId = u.UserId
  WHERE tp.rn_by_owner = 1
),
JoinedCTE AS (
  SELECT
    c.*,
    (CASE WHEN c.PostTypeId = 1 THEN 'Question' ELSE 'Answer' END) AS PostKind,
    (CASE WHEN c.AcceptedAnswerId IS NOT NULL THEN 1 ELSE 0 END) AS HasAccepted
  FROM CorrelationCTE c
),
MedianStats AS (
  SELECT
    PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY Score) AS MedianScore,
    PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY ViewCount) AS MedianViews
  FROM Posts
  WHERE PostTypeId IN (1,2)
),
Final AS (
  SELECT
    jc.PostId,
    jc.PostTypeId,
    jc.PostKind,
    jc.Title,
    jc.Tags,
    jc.CreationDate,
    jc.LastActivityDate,
    jc.Score,
    jc.ViewCount,
    jc.OwnerUserId,
    jc.OwnerDisplayName,
    jc.OwnerReputation,
    jc.AcceptedAnswerId,
    jc.AvgBounty,
    jc.RelatedLinks,
    jc.CommentCount,
    jc.TagSummary,
    mc.MedianScore,
    mc.MedianViews,
    CASE
      WHEN jc.Score >= mc.MedianScore AND jc.ViewCount >= mc.MedianViews THEN 'Hot'
      WHEN jc.Score < mc.MedianScore AND jc.ViewCount < mc.MedianViews THEN 'Cold'
      ELSE 'Moderate'
    END AS Status
  FROM JoinedCTE jc
  CROSS JOIN MedianStats mc
)
SELECT
  *
FROM Final
ORDER BY Status, ViewCount DESC NULLS LAST
LIMIT 100;