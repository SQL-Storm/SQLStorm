-- {"query": "6075.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-5-nano", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 810} 
WITH

-- 1) Rank questions by score and activity, including windowed aggregates
TopQuestions AS (
  SELECT
    p.Id AS PostId,
    p.Title,
    p.CreationDate,
    p.Score,
    p.ViewCount,
    p.AnswerCount,
    p.CommentCount,
    p.Tags,
    p.OwnerUserId,
    p.LastActivityDate,
    ROW_NUMBER() OVER (
      ORDER BY
        p.Score DESC,
        p.ViewCount DESC,
        p.LastActivityDate DESC
    ) AS rn
  FROM Posts p
  WHERE p.PostTypeId = 1  -- Questions
    AND p.ClosedDate IS NULL
),

-- 2) Compute user reputation deciles and badge richness for question owners
UserStats AS (
  SELECT
    u.Id AS UserId,
    u.DisplayName,
    u.Reputation,
    NTILE(10) OVER (ORDER BY u.Reputation ASC) AS ReputationDecile,
    COUNT(b.Id) FILTER (WHERE b.Class = 1) AS GoldBadges,
    COUNT(b.Id) FILTER (WHERE b.Class = 2) AS SilverBadges,
    COUNT(b.Id) FILTER (WHERE b.Class = 3) AS BronzeBadges,
    COUNT(*) AS TotalBadges
  FROM Users u
  LEFT JOIN Badges b ON b.UserId = u.Id
  GROUP BY u.Id, u.DisplayName, u.Reputation
),

-- 3) Correlated subquery: for each top question, fetch most recent editor
RecentEditor AS (
  SELECT
    t.PostId,
    t.LastEditorDisplayName AS EditorName,
    t.LastEditDate AS EditorDate
  FROM TopQuestions t
  LEFT JOIN LATERAL (
    SELECT
      MAX(p2.LastEditDate) AS LastEdit
    FROM Posts p2
    WHERE p2.Id = t.PostId
  ) le ON true
  -- The actual editor info is already in Posts; keep for demonstration
  -- (no extra join needed; reuse t.EditorName if present)
  LIMIT 0
)

SELECT
  tq.PostId,
  tq.Title,
  tq.CreationDate AS CreationDate,
  tq.Score,
  tq.ViewCount,
  tq.AnswerCount,
  tq.CommentCount,
  tq.Tags,
  uq.UserId AS OwnerUserId,
  uq.DisplayName AS OwnerDisplayName,
  sud.Reputation,
  sud.ReputationDecile,
  sud.GoldBadges,
  sud.SilverBadges,
  sud.BronzeBadges,
  sud.TotalBadges,
  tq.LastActivityDate,
  COALESCE(vt.UpCount, 0) AS UpvotesMinusDownvotes,
  STRING_AGG(vc.VoteTypeName, ', ' ORDER BY vc.VoteTypeName) AS VoteTypes
FROM TopQuestions tq
LEFT JOIN Users uq ON uq.Id = tq.OwnerUserId
LEFT JOIN UserStats sud ON sud.UserId = uq.Id
LEFT JOIN (
  SELECT
    v.PostId,
    SUM(CASE WHEN vt.Id = 2 THEN 1 ELSE 0 END) AS UpCount,
    SUM(CASE WHEN vt.Id = 3 THEN 1 ELSE 0 END) AS DownCount
  FROM Votes v
  JOIN VoteTypes vt ON vt.Id = v.VoteTypeId
  GROUP BY v.PostId
) vt ON vt.PostId = tq.PostId
LEFT JOIN (
  SELECT
    v.PostId,
    vt.Name AS VoteTypeName
  FROM Votes v
  JOIN VoteTypes vt ON vt.Id = v.VoteTypeId
  WHERE v.PostId IN (SELECT Id FROM Posts WHERE PostTypeId = 1)
) vc ON vc.PostId = tq.PostId
WHERE tq.rn <= 100  -- limit to top 100 for benchmarking variety
ORDER BY tq.rn;