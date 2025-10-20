-- {"query": "136.sql", "dataset": "stackoverflow", "version": "v1.4", "prompt": "p1", "model": "gpt-5-nano", "temperature": 1.0, "max_tokens": 32768, "reasoning": "low", "input_tokens": 2026, "output_tokens": 1937} 
WITH
-- Base set of candidate questions (PostTypeId = 1)
CandidateQuestions AS (
  SELECT
    p.Id AS PostId,
    p.Title,
    p.Tags,
    p.CreationDate,
    p.LastActivityDate,
    p.Score,
    p.ViewCount,
    p.AcceptedAnswerId,
    p.OwnerUserId,
    p.AnswerCount,
    p.ParentId
  FROM Posts p
  WHERE p.PostTypeId = 1
),
-- Per-post vote aggregates
VoteAgg AS (
  SELECT
    v.PostId,
    SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS UpVotes,
    SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS DownVotes,
    COUNT(*) AS VoteCount,
    SUM(CASE WHEN v.VoteTypeId = 6 THEN 1 ELSE 0 END) AS CloseVotes,
    SUM(CASE WHEN v.VoteTypeId = 8 THEN 1 ELSE 0 END) AS BountyVotes
  FROM Votes v
  GROUP BY v.PostId
),
-- Recent activity ranking (using window function)
RankedActivity AS (
  SELECT
    pq.PostId,
    pq.Title,
    pq.Tags,
    pq.CreationDate,
    pq.LastActivityDate,
    pq.Score,
    pq.ViewCount,
    pq.AcceptedAnswerId,
    pq.OwnerUserId,
    pq.AnswerCount,
    ROW_NUMBER() OVER (
      PARTITION BY pq.OwnerUserId
      ORDER BY COALESCE(pq.LastActivityDate, pq.CreationDate) DESC,
               pq.Score DESC,
               pq.ViewCount DESC
    ) AS rn_by_author
  FROM CandidateQuestions pq
),
-- Badge counts for the post owner (outer-joined to allow users without badges)
OwnerBadges AS (
  SELECT
    u.Id AS UserId,
    COUNT(*) FILTER (WHERE b.Class = 1) AS GoldBadges,
    COUNT(*) FILTER (WHERE b.Class = 2) AS SilverBadges,
    COUNT(*) FILTER (WHERE b.Class = 3) AS BronzeBadges
  FROM Users u
  LEFT JOIN Badges b ON b.UserId = u.Id
  GROUP BY u.Id
),
-- Subquery to compute tag count from the Tags string (StackOverflow style: <tag1><tag2>...)
TagCount AS (
  SELECT
    r.PostId,
    CASE
      WHEN r.Tags IS NULL OR r.Tags = '' THEN 0
      ELSE array_length(string_to_array(substring(r.Tags FROM 2 FOR char_length(r.Tags) - 2), '><'), 1)
    END AS TagCount
  FROM RankedActivity r
),
-- Correlated subquery: number of comments per post (for benchmarking NULL and aggregates)
CommentCountPerPost AS (
  SELECT
    p.Id AS PostId,
    COALESCE((SELECT COUNT(*) FROM Comments c WHERE c.PostId = p.Id), 0) AS CommentCount
  FROM Posts p
  WHERE p.PostTypeId = 1
),
-- Optional: build a compact activity histogram using a set operator
ActivityHistogram AS (
  SELECT PostId, CommentCount
  FROM CommentCountPerPost
  UNION ALL
  SELECT PostId, (COALESCE(ViewCount,0) / 100) AS CommentCount  -- synthetic secondary metric for benchmarking
  FROM Posts
  WHERE PostTypeId = 1
  LIMIT 1000
)
SELECT
  R.PostId,
  R.Title,
  R.CreationDate,
  R.LastActivityDate,
  R.Score,
  R.ViewCount,
  R.AnswerCount,
  R.OwnerUserId,
  U.DisplayName AS OwnerDisplayName,
  U.Reputation,
  COALESCE(OB.GoldBadges, 0) AS GoldBadges,
  COALESCE(OB.SilverBadges, 0) AS SilverBadges,
  COALESCE(OB.BronzeBadges, 0) AS BronzeBadges,
  TC.TagCount,
  VC.UpVotes,
  VC.DownVotes,
  VC.VoteCount,
  CC.CommentCount
FROM RankedActivity R
LEFT JOIN Users U ON R.OwnerUserId = U.Id
LEFT JOIN OwnerBadges OB ON OB.UserId = U.Id
LEFT JOIN VoteAgg VC ON VC.PostId = R.PostId
LEFT JOIN TagCount TC ON TC.PostId = R.PostId
LEFT JOIN CommentCountPerPost CC ON CC.PostId = R.PostId
ORDER BY R.LastActivityDate DESC NULLS LAST
LIMIT 200;