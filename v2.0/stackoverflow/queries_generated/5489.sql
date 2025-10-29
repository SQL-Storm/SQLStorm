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
  WHERE p.PostTypeId = 1 -- Questions
    AND p.CreationDate >= NOW() - INTERVAL '30 days'
),
top_tags AS (
  SELECT
    unnest(string_to_array(substring(p.Tags, 2, length(p.Tags)-2), '><')) AS TagName,
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
  WHERE v.CreationDate >= NOW() - INTERVAL '14 days'
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
    e.Upvotes,
    e.Downvotes,
    e.ModeratorVotes,
    (e.Upvotes - e.Downvotes) AS NetScore,
    (SELECT COUNT(*) FROM Comments c WHERE c.PostId = rp.PostId) AS CommentCountForPost,
    (SELECT AVG(v.BountyAmount) FROM Votes v WHERE v.PostId = rp.PostId) AS AvgBounty
  FROM tag_encoding rp
  LEFT JOIN endorsement e ON rp.PostId = e.PostId
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
    c.NetScore,
    c.CommentCountForPost,
    c.AvgBounty,
    ROW_NUMBER() OVER (
      ORDER BY
        NetScore DESC NULLS LAST,
        ViewCount DESC NULLS LAST,
        CommentCountForPost DESC NULLS LAST,
        AvgBounty DESC NULLS LAST,
        CreationDate ASC
    ) AS rn
  FROM recent_questions c
  LEFT JOIN endors e ON c.Id = e.PostId
  LEFT JOIN endorsement en ON c.Id = en.PostId
  LEFT JOIN complex_calc co ON co.PostId = c.Id
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