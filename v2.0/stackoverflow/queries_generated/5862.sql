-- {"query": "5862.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-5-nano", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 863} 
WITH
-- recent popular posts with complex aggregation
TopPosts AS (
  SELECT
    p.Id AS PostId,
    p.Title,
    p.CreationDate,
    p.Score,
    p.ViewCount,
    p.OwnerUserId,
    p.Tags,
    -- total upvotes and downvotes from Votes
    SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS UpVotesFromVotes,
    SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS DownVotesFromVotes,
    -- time-weighted activity from LastActivityDate
    EXTRACT(EPOCH FROM (CURRENT_TIMESTAMP - p.LastActivityDate)) AS SecondsSinceLastActivity,
    -- comment activity
    COALESCE((SELECT COUNT(*) FROM Comments c WHERE c.PostId = p.Id), 0) AS CommentCountTotal,
    -- number of linked posts (excluding self)
    COALESCE((SELECT COUNT(*) FROM PostLinks pl WHERE pl.PostId = p.Id), 0) AS LinkCount
  FROM Posts p
  LEFT JOIN Votes v ON v.PostId = p.Id
  WHERE p.PostTypeId = 1 -- only questions
    AND p.ClosedDate IS NULL
  GROUP BY
    p.Id, p.Title, p.CreationDate, p.Score, p.ViewCount, p.OwnerUserId, p.Tags, p.LastActivityDate
),
-- derive a composite score combining multiple signals
ScoreRank AS (
  SELECT
    tp.*,
    -- tag weight: parse tags array-like string and count tags, with a simple heuristic
    (CASE
       WHEN tp.Tags IS NULL THEN 0
       ELSE (CARDINALITY(string_to_array(substring(tp.Tags, 2, length(tp.Tags)-2), '"><'))::int)
     END) AS TagCountEstimate,
    -- normalized popularity score
    (tp.Score * 2.0 + tp.CommentCountTotal * 0.5 + tp.ViewCount * 0.01
     + COALESCE(tp.UpVotesFromVotes,0) * 0.7 - COALESCE(tp.DownVotesFromVotes,0) * 0.4) AS RawPopularity
  FROM TopPosts tp
),
-- windowed ranking per day with ties handling
Ranked AS (
  SELECT
    sp.*,
    ROW_NUMBER() OVER (
      PARTITION BY DATE(p.CreationDate)
      ORDER BY RawPopularity DESC, TagCountEstimate DESC, tp.LastActivityDate DESC
    ) AS rn
  FROM ScoreRank sp
  JOIN Posts p ON p.Id = sp.PostId
),
-- worst-case set operation: union with a derived table of highly discussed posts
UnionSet AS (
  SELECT * FROM Ranked WHERE rn <= 100
  UNION ALL
  SELECT
    rp.*,
    ROW_NUMBER() OVER (ORDER BY rp.RawPopularity DESC) AS rn
  FROM (
    SELECT
      p.Id AS PostId,
      p.Title,
      p.CreationDate,
      p.Score,
      p.ViewCount,
      p.OwnerUserId,
      p.Tags,
      (SELECT COUNT(*) FROM Comments c WHERE c.PostId = p.Id) AS CommentCountTotal,
      (SELECT COUNT(*) FROM PostLinks pl WHERE pl.PostId = p.Id) AS LinkCount,
      p.LastActivityDate,
      0 AS UpVotesFromVotes,
      0 AS DownVotesFromVotes,
      0 AS TagCountEstimate,
      0 AS RawPopularity
    FROM Posts p
    WHERE p.PostTypeId = 1
  ) rp
)
SELECT
  us.PostId,
  us.Title,
  us.CreationDate,
  us.Score,
  us.ViewCount,
  us.OwnerUserId,
  us.Tags,
  us.CommentCountTotal,
  us.LinkCount,
  us.LastActivityDate,
  us.UpVotesFromVotes,
  us.DownVotesFromVotes,
  us.TagCountEstimate,
  us.RawPopularity,
  us.rn
FROM UnionSet us
ORDER BY us.rn, us.LastActivityDate DESC
LIMIT 500;