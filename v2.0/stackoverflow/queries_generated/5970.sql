-- {"query": "5970.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-5-nano", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 909} 
WITH
TopPosts AS (
  SELECT
    p.Id AS PostId,
    p.Title,
    p.CreationDate,
    p.Score,
    p.ViewCount,
    p.OwnerUserId,
    p.Tags,
    p.PostTypeId,
    p.AnswerCount,
    p.CommentCount,
    p.FavoriteCount,
    p.LastActivityDate,
    p.ContentLicense,
    ROW_NUMBER() OVER (PARTITION BY p.PostTypeId ORDER BY p.Score DESC, p.ViewCount DESC, p.CreationDate DESC) AS rn_type
  FROM Posts p
  LEFT JOIN Users u ON p.OwnerUserId = u.Id
  WHERE p.PostTypeId IN (1,2) -- Questions and Answers
    AND p.CreationDate >= NOW() - INTERVAL '365 days'
),
ScoreBuckets AS (
  SELECT
    tp.PostId,
    tp.Title,
    tp.CreationDate,
    tp.Score,
    tp.ViewCount,
    tp.OwnerUserId,
    tp.Tags,
    tp.PostTypeId,
    tp.AnswerCount,
    tp.CommentCount,
    tp.FavoriteCount,
    tp.LastActivityDate,
    tp.ContentLicense,
    CASE
      WHEN tp.Score >= 100 THEN 'A+'
      WHEN tp.Score >= 50  THEN 'A'
      WHEN tp.Score >= 20  THEN 'B'
      WHEN tp.Score >= 0   THEN 'C'
      ELSE 'D'
    END AS ScoreTier
  FROM TopPosts tp
  WHERE tp.rn_type = 1
),
CorrelatedStats AS (
  SELECT
    sp.PostId,
    sp.Title,
    sp.Score,
    sp.ViewCount,
    sp.OwnerUserId,
    sp.Tags,
    sp.ScoreTier,
    u.Reputation,
    u.CreationDate AS UserCreationDate,
    u.LastAccessDate,
    b.Name AS BadgeName,
    b.Date AS BadgeDate,
    wt.Name AS VoteTypeName,
    vh.BountyAmount,
    (SELECT COUNT(*) FROM Comments c WHERE c.PostId = sp.PostId) AS CommentCountForPost,
    (SELECT AVG(CASE WHEN v.VoteTypeId = 2 THEN 1.0 ELSE 0 END) FROM Votes v WHERE v.PostId = sp.PostId) AS UpvoteRatio
  FROM ScoreBuckets sp
  LEFT JOIN Users u ON sp.OwnerUserId = u.Id
  LEFT JOIN Badges b ON b.UserId = u.Id
    AND b.Date = (SELECT MAX(Date) FROM Badges b2 WHERE b2.UserId = u.Id)
  LEFT JOIN Votes v ON v.PostId = sp.PostId
    AND v.VoteTypeId IN (2,3)
  LEFT JOIN VoteTypes wt ON v.VoteTypeId = wt.Id
  LEFT JOIN LATERAL (
      SELECT SUM(CASE WHEN v2.VoteTypeId = 14 THEN v2.BountyAmount ELSE 0 END) AS BountyAmount
      FROM Votes v2
      WHERE v2.PostId = sp.PostId
    ) vh ON true
  WHERE sp.Score >= 0
),
Windowed AS (
  SELECT
    cs.PostId,
    cs.Title,
    cs.Score,
    cs.ViewCount,
    cs.OwnerUserId,
    cs.Tags,
    cs.ScoreTier,
    cs.Reputation,
    cs.UserCreationDate,
    cs.LastAccessDate,
    cs.BadgeName,
    cs.BadgeDate,
    cs.VoteTypeName,
    cs.BountyAmount,
    cs.CommentCountForPost,
    cs.UpvoteRatio,
    ROW_NUMBER() OVER (PARTITION BY cs.ScoreTier ORDER BY cs.Reputation DESC, cs.ViewCount DESC) AS rn_win
  FROM CorrelatedStats cs
)
SELECT
  w.PostId,
  w.Title,
  w.Score,
  w.ViewCount,
  w.OwnerUserId,
  w.Tags,
  w.ScoreTier,
  w.Reputation,
  w.UserCreationDate,
  w.LastAccessDate,
  w.BadgeName,
  w.BadgeDate,
  w.VoteTypeName,
  w.BountyAmount,
  w.CommentCountForPost,
  w.UpvoteRatio
FROM Windowed w
WHERE w.rn_win <= 5
ORDER BY w.ScoreTier, w.Reputation DESC, w.ViewCount DESC
;