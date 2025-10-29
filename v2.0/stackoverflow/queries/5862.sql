-- {"query": "5862.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-5-nano", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 863}
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
    SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS UpVotesFromVotes,
    SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS DownVotesFromVotes,
    EXTRACT(EPOCH FROM (CAST('2024-10-01 12:34:56' AS TIMESTAMP) - p.LastActivityDate)) AS SecondsSinceLastActivity,
    COALESCE((SELECT COUNT(*) FROM Comments c WHERE c.PostId = p.Id), 0) AS CommentCountTotal,
    COALESCE((SELECT COUNT(*) FROM PostLinks pl WHERE pl.PostId = p.Id), 0) AS LinkCount,
    p.LastActivityDate
  FROM Posts p
  LEFT JOIN Votes v ON v.PostId = p.Id
  WHERE p.PostTypeId = 1
    AND p.ClosedDate IS NULL
  GROUP BY
    p.Id, p.Title, p.CreationDate, p.Score, p.ViewCount, p.OwnerUserId, p.Tags, p.LastActivityDate
),
ScoreRank AS (
  SELECT
    tp.PostId,
    tp.Title,
    tp.CreationDate,
    tp.Score,
    tp.ViewCount,
    tp.OwnerUserId,
    tp.Tags,
    tp.UpVotesFromVotes,
    tp.DownVotesFromVotes,
    tp.SecondsSinceLastActivity,
    tp.CommentCountTotal,
    tp.LinkCount,
    tp.LastActivityDate,
    CASE
      WHEN tp.Tags IS NULL THEN 0
      ELSE (
        -- count occurrences of '><' plus 1 as an estimate of tags between angle brackets
        (length(tp.Tags) - length(replace(tp.Tags, '><', ''))) / length('><') + 1
      )
    END AS TagCountEstimate,
    (tp.Score * 2.0 + tp.CommentCountTotal * 0.5 + tp.ViewCount * 0.01
     + COALESCE(tp.UpVotesFromVotes,0) * 0.7 - COALESCE(tp.DownVotesFromVotes,0) * 0.4) AS RawPopularity
  FROM TopPosts tp
),
Ranked AS (
  SELECT
    sp.PostId,
    sp.Title,
    sp.CreationDate,
    sp.Score,
    sp.ViewCount,
    sp.OwnerUserId,
    sp.Tags,
    sp.UpVotesFromVotes,
    sp.DownVotesFromVotes,
    sp.SecondsSinceLastActivity,
    sp.CommentCountTotal,
    sp.LinkCount,
    sp.LastActivityDate,
    sp.TagCountEstimate,
    sp.RawPopularity,
    ROW_NUMBER() OVER (
      PARTITION BY CAST(sp.CreationDate AS DATE)
      ORDER BY sp.RawPopularity DESC, sp.TagCountEstimate DESC, sp.LastActivityDate DESC
    ) AS rn
  FROM ScoreRank sp
),
UnionSet AS (
  SELECT * FROM Ranked WHERE rn <= 100
  UNION ALL
  SELECT
    rp.PostId,
    rp.Title,
    rp.CreationDate,
    rp.Score,
    rp.ViewCount,
    rp.OwnerUserId,
    rp.Tags,
    rp.UpVotesFromVotes,
    rp.DownVotesFromVotes,
    NULL AS SecondsSinceLastActivity,
    rp.CommentCountTotal,
    rp.LinkCount,
    rp.LastActivityDate,
    rp.TagCountEstimate,
    rp.RawPopularity,
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
      0 AS UpVotesFromVotes,
      0 AS DownVotesFromVotes,
      (SELECT COUNT(*) FROM Comments c WHERE c.PostId = p.Id) AS CommentCountTotal,
      (SELECT COUNT(*) FROM PostLinks pl WHERE pl.PostId = p.Id) AS LinkCount,
      p.LastActivityDate,
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