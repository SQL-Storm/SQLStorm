-- {"query": "5487.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-5-nano", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 1054} 
WITH top_questions AS (
  SELECT
    p.Id AS PostId,
    p.Title,
    p.Tags,
    p.CreationDate,
    p.Score,
    p.ViewCount,
    p.OwnerUserId,
    p.LastActivityDate,
    p.CommentCount,
    p.AnswerCount,
    p.FavoriteCount,
    p.ContentLicense,
    u.DisplayName AS OwnerDisplayName,
    u.Reputation,
    u.CreationDate AS OwnerCreationDate,
    u.Location,
    u.UpVotes,
    u.DownVotes,
    ROW_NUMBER() OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate DESC) AS rn
  FROM Posts p
  JOIN Users u ON p.OwnerUserId = u.Id
  WHERE p.PostTypeId = 1 -- Questions
    AND p.ClosedDate IS NULL
    AND p.ViewCount > 0
),
recent_comments AS (
  SELECT
    c.PostId,
    COUNT(*) AS CommentCountLast24h
  FROM Comments c
  WHERE c.CreationDate >= NOW() - INTERVAL '24 HOURS'
  GROUP BY c.PostId
),
recent_votes AS (
  SELECT
    v.PostId,
    SUM(CASE WHEN vt.Name IN ('UpMod','AcceptedByOriginator') THEN 1
             WHEN vt.Name = 'DownMod' THEN -1
             ELSE 0 END) AS NetScore24h
  FROM Votes v
  JOIN VoteTypes vt ON v.VoteTypeId = vt.Id
  WHERE v.CreationDate >= NOW() - INTERVAL '24 HOURS'
  GROUP BY v.PostId
),
 cross_linked AS (
  SELECT
    pl.PostId,
    pl.RelatedPostId,
    lt.Name AS LinkType
  FROM PostLinks pl
  JOIN LinkTypes lt ON pl.LinkTypeId = lt.Id
  WHERE lt.Name IN ('Linked','Duplicate')
),
tag_score AS (
  SELECT
    t.TagName,
    t.Id AS TagId,
    COUNT(p.Id) AS PostCount,
    SUM(p.Score) AS TotalScore
  FROM Posts p
  JOIN LATERAL string_to_array(substring(p.Tags, 2, length(p.Tags)-2), '><') AS ta(tag) ON TRUE
  JOIN Tags t ON ta.tag = t.TagName
  GROUP BY t.TagName, t.Id
),
badge_activity AS (
  SELECT
    b.UserId,
    COUNT(*) AS BadgeCount,
    SUM(CASE WHEN b.Class = 1 THEN 1 ELSE 0 END) AS GoldBadges
  FROM Badges b
  GROUP BY b.UserId
)
SELECT
  q.Id AS QuestionId,
  q.Title,
  q.OwnerDisplayName,
  q.OwnerUserId,
  q.Reputation,
  q.CreationDate AS QuestionCreation,
  q.LastActivityDate,
  q.ViewCount,
  q.Score,
  COALESCE(rc.CommentCountLast24h, 0) AS CommentsLast24h,
  COALESCE(rv.NetScore24h, 0) AS NetVotesLast24h,
  COALESCE(cc.CommentCount, 0) AS CommentCountAll,
  COALESCE(pivot.TotalScore, 0) AS TagsTotalScore,
  bact.GoldBadges,
  bact.BadgeCount,
  CASE
    WHEN q.Tags IS NULL THEN NULL
    ELSE ARRAY_AGG(DISTINCT t2.TagName) END AS TagNames
FROM
  top_questions q
  LEFT JOIN recent_comments rc ON rc.PostId = q.PostId
  LEFT JOIN recent_votes rv ON rv.PostId = q.PostId
  LEFT JOIN (SELECT unnest(string_to_array(substring(q.Tags, 2, length(q.Tags)-2), '><')) AS TagName FROM Posts q WHERE q.Id = q.Id) AS t ON TRUE
  LEFT JOIN (SELECT t.TagName, SUM(p.Score) AS TotalScore
             FROM Posts p
             JOIN LATERAL string_to_array(substring(p.Tags, 2, length(p.Tags)-2), '><') AS ta(tag) ON TRUE
             JOIN Tags t ON ta.tag = t.TagName
             GROUP BY t.TagName) AS pivot ON TRUE
  LEFT JOIN (
      SELECT p.OwnerUserId, SUM(p.Score) AS TotalScore
      FROM Posts p
      GROUP BY p.OwnerUserId
  ) AS owner_score ON owner_score.OwnerUserId = q.OwnerUserId
  LEFT JOIN badge_activity bact ON bact.UserId = q.OwnerUserId
WHERE q.rn = 1
GROUP BY
  q.Id, q.Title, q.OwnerDisplayName, q.OwnerUserId, q.Reputation,
  q.CreationDate, q.LastActivityDate, q.ViewCount, q.Score,
  rc.CommentCountLast24h, rv.NetScore24h, cc.CommentCount,
  pivot.TotalScore, bact.GoldBadges, bact.BadgeCount
ORDER BY q.CreationDate DESC
LIMIT 10;