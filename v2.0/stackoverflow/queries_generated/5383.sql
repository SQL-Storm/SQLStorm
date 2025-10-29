-- {"query": "5383.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-5-nano", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 975} 
WITH TopQuestions AS (
  SELECT
    p.Id AS PostId,
    p.Title,
    p.Tags,
    p.CreationDate,
    p.Score,
    p.ViewCount,
    p.OwnerUserId,
    COALESCE(p.AnswerCount, 0) AS AnswerCount,
    p.CommentCount,
    p.LastActivityDate,
    p.Body,
    p.FavoriteCount,
    u.DisplayName AS OwnerDisplayName,
    u.Reputation,
    u.CreationDate AS OwnerCreationDate,
    v1.Name AS UpVoteType
  FROM Posts p
  LEFT JOIN Users u ON p.OwnerUserId = u.Id
  LEFT JOIN PostHistory ph ON ph.PostId = p.Id AND ph.PostHistoryTypeId = 1
  LEFT JOIN VoteTypes v1 ON 1=1
  WHERE p.PostTypeId = 1
    AND p.ClosedDate IS NULL
),
TaggedHot AS (
  SELECT
    tq.PostId,
    tq.Title,
    tq.OwnerUserId,
    tq.OwnerDisplayName,
    tq.Reputation,
    tq.CreationDate,
    tq.ViewCount,
    tq.Score,
    tq.AnswerCount,
    tq.CommentCount,
    tq.LastActivityDate,
    tq.Body,
    tq.Tags,
    ROW_NUMBER() OVER (
      PARTITION BY tq.OwnerUserId
      ORDER BY tq.Score * 2 + tq.ViewCount + tq.AnswerCount DESC, tq.CreationDate
    ) AS rn
  FROM TopQuestions tq
  WHERE EXISTS (
    SELECT 1
    FROM unnest(string_to_array(substr(tq.Tags, 2, length(tq.Tags)-2), '><')) AS t(tag)
    WHERE t.tag IN (SELECT TagName FROM Tags WHERE IsModeratorOnly = 0)
  )
),
Aggregates AS (
  SELECT
    ph1.PostId,
    ph1.UserId,
    ph1.RevisionGUID,
    ph1.CreationDate AS RevisionDate,
    ph1.Text AS RevisionText,
    ph1.Comment AS RevisionComment,
    pv.BountyAmount,
    pv.VoteTypeId,
    pv.CreationDate AS VoteDate,
    (CASE WHEN pv.VoteTypeId = 2 THEN 1 ELSE 0 END) AS IsUpvote,
    (CASE WHEN pv.VoteTypeId = 3 THEN 1 ELSE 0 END) AS IsDownvote
  FROM PostHistory ph1
  LEFT JOIN Votes pv ON pv.PostId = ph1.PostId AND pv.CreationDate = ph1.CreationDate
  WHERE ph1.PostHistoryTypeId IN (2,5,6,10,11)
),
ComplexQuery AS (
  SELECT
    a.PostId,
    a.OwnerUserId,
    a.OwnerDisplayName,
    a.RevisionDate,
    a.RevisionText,
    a.RevisionComment,
    SUM(COALESCE(a.BountyAmount,0)) OVER (PARTITION BY a.PostId) AS TotalBounty,
    SUM(a.IsUpvote) OVER (PARTITION BY a.PostId) AS UpvotesOnRevision,
    SUM(a.IsDownvote) OVER (PARTITION BY a.PostId) AS DownvotesOnRevision,
    COUNT(*) OVER (PARTITION BY a.OwnerUserId) AS PostsByUser
  FROM Aggregates a
),
Final AS (
  SELECT
    cq.PostId,
    cq.OwnerUserId,
    cq.OwnerDisplayName,
    cq.RevisionDate,
    cq.RevisionText,
    cq.RevisionComment,
    cq.TotalBounty,
    cq.UpvotesOnRevision,
    cq.DownvotesOnRevision,
    cq.PostsByUser,
    t.hrn
  FROM ComplexQuery cq
  LEFT JOIN (
    SELECT
      PostId,
      ROW_NUMBER() OVER (PARTITION BY PostId ORDER BY RevisionDate DESC) AS hrn
    FROM Aggregates
  ) t ON t.PostId = cq.PostId
)
SELECT
  f.PostId,
  f.OwnerUserId,
  f.OwnerDisplayName,
  f.RevisionDate,
  f.RevisionText,
  f.RevisionComment,
  f.TotalBounty,
  f.UpvotesOnRevision,
  f.DownvotesOnRevision,
  f.PostsByUser,
  ph.Name AS HistoryTypeName,
  v.Name AS VoteTypeName
FROM Final f
LEFT JOIN PostHistory ph ON ph.PostId = f.PostId AND ph.Id = f.RevisionDate
LEFT JOIN Votes v ON v.PostId = f.PostId AND v.VoteTypeId = ph.Id
ORDER BY f.PostId, f.RevisionDate DESC
LIMIT 100;