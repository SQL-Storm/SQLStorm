-- {"query": "5489.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-5-nano", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 819}
WITH recent_questions AS (
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
    p.Body,
    p.ContentLicense,
    u.Reputation,
    u.DisplayName AS OwnerDisplayName,
    u.Location,
    u.AccountId,
    u.Views
  FROM Posts p
  LEFT JOIN Users u ON p.OwnerUserId = u.Id
  WHERE p.PostTypeId = 1
    AND p.CreationDate >= CAST('2024-10-01 12:34:56' AS TIMESTAMP) - INTERVAL '30' DAY
),
top_tags AS (
  SELECT
    unnest(string_to_array(substring(p.Tags FROM 2 FOR (char_length(p.Tags)-2)), '><')) AS TagName,
    p.Id AS PostId
  FROM Posts p
  WHERE p.PostTypeId = 1
),
recent_votes AS (
  SELECT
    v.PostId,
    v.VoteTypeId,
    v.UserId,
    v.CreationDate,
    COALESCE(v.BountyAmount, 0) AS BountyAmount
  FROM Votes v
  WHERE v.CreationDate >= CAST('2024-10-01 12:34:56' AS TIMESTAMP) - INTERVAL '14' DAY
),
tag_encoding AS (
  SELECT
    t.PostId,
    t.TagName,
    COUNT(*) AS TagVotes
  FROM top_tags t
  GROUP BY t.PostId, t.TagName
),
endorsement AS (
  SELECT
    rv.PostId,
    SUM(CASE WHEN rv.VoteTypeId = 2 THEN 1 ELSE 0 END) AS Upvotes,
    SUM(CASE WHEN rv.VoteTypeId = 3 THEN 1 ELSE 0 END) AS Downvotes,
    SUM(CASE WHEN rv.VoteTypeId = 14 THEN 1 ELSE 0 END) AS ModeratorVotes
  FROM recent_votes rv
  GROUP BY rv.PostId
),
complex_calc AS (
  SELECT
    rp.PostId,
    rp.TagName,
    rp.TagVotes,
    COALESCE(e.Upvotes, 0) AS Upvotes,
    COALESCE(e.Downvotes, 0) AS Downvotes,
    COALESCE(e.ModeratorVotes, 0) AS ModeratorVotes,
    (COALESCE(e.Upvotes, 0) - COALESCE(e.Downvotes, 0)) AS NetScore,
    (SELECT COUNT(*) FROM Comments c WHERE c.PostId = rp.PostId) AS CommentCountForPost,
    (SELECT AVG(v.BountyAmount) FROM Votes v WHERE v.PostId = rp.PostId) AS AvgBounty
  FROM tag_encoding rp
  LEFT JOIN endorsement e ON rp.PostId = e.PostId
  GROUP BY
    rp.PostId,
    rp.TagName,
    rp.TagVotes,
    e.Upvotes,
    e.Downvotes,
    e.ModeratorVotes
),
ranking AS (
  SELECT
    c.PostId,
    c.Title,
    c.Tags,
    c.CreationDate,
    c.ViewCount,
    c.Reputation,
    c.OwnerDisplayName,
    c.Location,
    c.AccountId,
    COALESCE(en.Upvotes,0) - COALESCE(en.Downvotes,0) AS NetScore,
    (SELECT COUNT(*) FROM Comments cc WHERE cc.PostId = c.PostId) AS CommentCountForPost,
    (SELECT AVG(vv.BountyAmount) FROM Votes vv WHERE vv.PostId = c.PostId) AS AvgBounty,
    ROW_NUMBER() OVER (
      ORDER BY
        (COALESCE(en.Upvotes,0) - COALESCE(en.Downvotes,0)) DESC,
        c.ViewCount DESC,
        (SELECT COUNT(*) FROM Comments cc2 WHERE cc2.PostId = c.PostId) DESC,
        (SELECT AVG(vv2.BountyAmount) FROM Votes vv2 WHERE vv2.PostId = c.PostId) DESC,
        c.CreationDate ASC
    ) AS rn
  FROM recent_questions c
  LEFT JOIN endorsement en ON c.PostId = en.PostId
  LEFT JOIN complex_calc co ON co.PostId = c.PostId
  GROUP BY
    c.PostId,
    c.Title,
    c.Tags,
    c.CreationDate,
    c.ViewCount,
    c.Reputation,
    c.OwnerDisplayName,
    c.Location,
    c.AccountId,
    en.Upvotes,
    en.Downvotes
)
SELECT
  r.PostId,
  r.Title,
  r.Tags,
  r.CreationDate,
  r.ViewCount,
  r.Reputation,
  r.OwnerDisplayName,
  r.Location,
  r.AccountId,
  r.NetScore,
  r.CommentCountForPost AS CommentCount,
  r.AvgBounty,
  r.rn AS Rank
FROM ranking r
WHERE r.rn <= 100
ORDER BY r.rn;