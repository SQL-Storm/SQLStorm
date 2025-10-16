-- {"query": "26034.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "llama-3.3-instruct", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 650} 
WITH RankedPosts AS (
  SELECT 
    p.Id,
    p.Score,
    p.ViewCount,
    p.Title,
    p.Tags,
    p.AcceptedAnswerId,
    ROW_NUMBER() OVER (ORDER BY p.Score DESC, p.ViewCount DESC) AS RowNum
  FROM 
    Posts p
  WHERE 
    p.PostTypeId = 1
    AND p.ClosedDate IS NULL
    AND p.Score > 0
),
Top10Posts AS (
  SELECT 
    Id,
    Score,
    ViewCount,
    Title,
    Tags,
    AcceptedAnswerId
  FROM 
    RankedPosts
  WHERE 
    RowNum <= 10
),
UserStats AS (
  SELECT 
    u.Id,
    u.Reputation,
    COUNT(b.Id) AS BadgeCount,
    SUM(CASE WHEN b.Class = 1 THEN 1 ELSE 0 END) AS GoldBadges,
    SUM(CASE WHEN b.Class = 2 THEN 1 ELSE 0 END) AS SilverBadges,
    SUM(CASE WHEN b.Class = 3 THEN 1 ELSE 0 END) AS BronzeBadges
  FROM 
    Users u
  LEFT JOIN 
    Badges b ON u.Id = b.UserId
  GROUP BY 
    u.Id, u.Reputation
),
PostVotes AS (
  SELECT 
    p.Id,
    SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS UpVotes,
    SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS DownVotes
  FROM 
    Posts p
  LEFT JOIN 
    Votes v ON p.Id = v.PostId
  GROUP BY 
    p.Id
)
SELECT 
  tp.Id,
  tp.Score,
  tp.ViewCount,
  tp.Title,
  tp.Tags,
  tp.AcceptedAnswerId,
  us.Reputation,
  us.BadgeCount,
  us.GoldBadges,
  us.SilverBadges,
  us.BronzeBadges,
  pv.UpVotes,
  pv.DownVotes,
  COALESCE(pv.UpVotes - pv.DownVotes, 0) AS VoteBalance,
  CASE 
    WHEN tp.AcceptedAnswerId IS NOT NULL THEN 'Answered'
    ELSE 'Unanswered'
  END AS AnswerStatus,
  ROW_NUMBER() OVER (ORDER BY tp.Score DESC, tp.ViewCount DESC) AS RowNum,
  LAG(tp.Score, 1) OVER (ORDER BY tp.Score DESC, tp.ViewCount DESC) AS PrevScore,
  LEAD(tp.Score, 1) OVER (ORDER BY tp.Score DESC, tp.ViewCount DESC) AS NextScore
FROM 
  Top10Posts tp
JOIN 
  UserStats us ON tp.AcceptedAnswerId = us.Id
JOIN 
  PostVotes pv ON tp.Id = pv.Id
LEFT JOIN 
  PostLinks pl ON tp.Id = pl.PostId
WHERE 
  pl.LinkTypeId = 1
  AND pl.RelatedPostId IN (SELECT Id FROM Top10Posts)
ORDER BY 
  tp.Score DESC, tp.ViewCount DESC;