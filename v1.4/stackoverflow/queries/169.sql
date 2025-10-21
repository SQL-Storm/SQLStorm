-- {"query": "169.sql", "dataset": "stackoverflow", "version": "v1.4", "prompt": "p1", "model": "gpt-5-nano", "temperature": 1.0, "max_tokens": 32768, "reasoning": "low", "input_tokens": 2026, "output_tokens": 1536} 
WITH recent_posts AS (
  SELECT
    p.Id,
    p.PostTypeId,
    p.Title,
    p.Tags,
    p.CreationDate,
    p.LastActivityDate,
    p.ViewCount,
    p.Score,
    p.OwnerUserId,
    p.OwnerDisplayName,
    COALESCE(u.Reputation, 0) AS OwnerReputation,
    COALESCE(p.AnswerCount, 0) AS AnswerCount
  FROM Posts p
  LEFT JOIN Users u ON p.OwnerUserId = u.Id
  WHERE p.CreationDate >= (cast('2024-10-01' as date) - INTERVAL '1 year')
    AND p.PostTypeId IN (1, 2) -- Questions and Answers
),
linked_counts AS (
  SELECT
    pl.PostId,
    COUNT(*) AS LinkCount,
    MAX(pl.CreationDate) AS LastLinkDate
  FROM PostLinks pl
  GROUP BY pl.PostId
),
vote_sums AS (
  SELECT
    v.PostId,
    SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS Upvotes,
    SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS Downvotes,
    SUM(v.BountyAmount) AS Bounty
  FROM Votes v
  GROUP BY v.PostId
),
agg AS (
  SELECT
    rp.Id,
    rp.PostTypeId,
    rp.Title,
    rp.Tags,
    rp.CreationDate,
    rp.LastActivityDate,
    rp.ViewCount,
    rp.Score,
    rp.OwnerUserId,
    rp.OwnerDisplayName,
    rp.OwnerReputation,
    COALESCE(lc.LinkCount, 0) AS LinkCount,
    COALESCE(vs.Upvotes, 0) AS Upvotes,
    COALESCE(vs.Downvotes, 0) AS Downvotes,
    COALESCE(vs.Bounty, 0) AS Bounty,
    rp.AnswerCount
  FROM recent_posts rp
  LEFT JOIN linked_counts lc ON rp.Id = lc.PostId
  LEFT JOIN vote_sums vs ON rp.Id = vs.PostId
),
ranked AS (
  SELECT
    a.*,
    ROW_NUMBER() OVER (
      PARTITION BY a.PostTypeId
      ORDER BY
        (a.Score + a.Upvotes - a.Downvotes) * LOG(LEAST(a.ViewCount + 2, 1000000)) DESC,
        a.LastActivityDate DESC,
        a.CreationDate ASC
    ) AS rn
  FROM agg a
)
SELECT
  r.Id,
  r.PostTypeId,
  CASE
    WHEN r.PostTypeId = 1 THEN 'Question'
    WHEN r.PostTypeId = 2 THEN 'Answer'
    ELSE 'Other'
  END AS PostKind,
  r.Title,
  r.Tags,
  r.CreationDate,
  r.LastActivityDate,
  r.ViewCount,
  r.Score,
  r.OwnerUserId,
  r.OwnerDisplayName,
  r.OwnerReputation,
  r.LinkCount,
  r.Upvotes,
  r.Downvotes,
  r.Bounty,
  r.AnswerCount,
  r.rn,
  (SELECT COUNT(*) FROM Comments c WHERE c.PostId = r.Id) AS CommentCount,
  (CASE
     WHEN r.OwnerUserId IS NULL THEN true
     ELSE false
   END) AS IsCommunityOwned
FROM ranked r
WHERE r.rn = 1
  AND r.LastActivityDate IS NOT NULL
UNION ALL
SELECT
  a.Id,
  a.PostTypeId,
  CASE
    WHEN a.PostTypeId = 1 THEN 'Question'
    WHEN a.PostTypeId = 2 THEN 'Answer'
    ELSE 'Other'
  END AS PostKind,
  a.Title,
  a.Tags,
  a.CreationDate,
  a.LastActivityDate,
  a.ViewCount,
  a.Score,
  a.OwnerUserId,
  a.OwnerDisplayName,
  a.OwnerReputation,
  a.LinkCount,
  a.Upvotes,
  a.Downvotes,
  a.Bounty,
  a.AnswerCount,
  a.rn,
  (SELECT COUNT(*) FROM Comments c WHERE c.PostId = a.Id) AS CommentCount,
  (CASE
     WHEN a.OwnerUserId IS NULL THEN true
     ELSE false
   END) AS IsCommunityOwned
FROM ranked a
WHERE a.PostTypeId = 2
  AND a.rn = 1
ORDER BY PostKind, LastActivityDate DESC
;