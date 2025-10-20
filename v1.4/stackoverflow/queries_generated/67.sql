-- {"query": "67.sql", "dataset": "stackoverflow", "version": "v1.4", "prompt": "p1", "model": "gpt-5-nano", "temperature": 1.0, "max_tokens": 32768, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 848} 
WITH
RecentTopPosts AS (
  SELECT
    p.Id AS PostId,
    p.Title,
    p.CreationDate,
    p.Score,
    p.ViewCount,
    p.OwnerUserId,
    p.Tags,
    ROW_NUMBER() OVER (PARTITION BY p.OwnerUserId ORDER BY p.Score DESC, p.CreationDate DESC) AS rn_owner
  FROM Posts p
  WHERE p.PostTypeId = 1 -- Questions
),
AggStats AS (
  SELECT
    p.Id AS PostId,
    p.Title,
    p.CreationDate,
    p.Score,
    p.ViewCount,
    p.OwnerUserId,
    p.Tags,
    COALESCE(vs.UpVotesLast30, 0) AS UpVotesLast30,
    COALESCE(vs.DownVotesLast30, 0) AS DownVotesLast30,
    COALESCE(cm.CommentCountLast30, 0) AS CommentCountLast30,
    CASE
      WHEN p.ParentId IS NULL THEN 'Question'
      ELSE 'Answer'
    END AS PostKind
  FROM Posts p
  LEFT JOIN (
    SELECT
      PostId,
      SUM(CASE WHEN VoteTypeId = 2 THEN 1 ELSE 0 END) AS UpVotesLast30,
      SUM(CASE WHEN VoteTypeId = 3 THEN 1 ELSE 0 END) AS DownVotesLast30
    FROM Votes
    WHERE CreationDate >= NOW() - INTERVAL '30 days'
    GROUP BY PostId
  ) v ON v.PostId = p.Id
  LEFT JOIN (
    SELECT
      PostId,
      COUNT(*) AS CommentCountLast30
    FROM Comments
    WHERE CreationDate >= NOW() - INTERVAL '30 days'
    GROUP BY PostId
  ) cm ON cm.PostId = p.Id
  WHERE p.PostTypeId = 1
),
FilteredTop AS (
  SELECT
    a.PostId,
    a.Title,
    a.CreationDate,
    a.Score,
    a.ViewCount,
    a.OwnerUserId,
    a.Tags,
    a.UpVotesLast30,
    a.DownVotesLast30,
    a.CommentCountLast30,
    a.PostKind
  FROM AggStats a
  WHERE a.UpVotesLast30 - a.DownVotesLast30 > 5
    OR a.CommentCountLast30 > 3
),
CrossRef AS (
  SELECT
    f.PostId,
    f.Title,
    f.CreationDate,
    f.Score,
    f.ViewCount,
    u.DisplayName AS OwnerName,
    u.Reputation,
    f.Tags,
    f.UpVotesLast30,
    f.DownVotesLast30,
    f.CommentCountLast30,
    f.PostKind,
    -- correlated subquery: average owner reputation of users who posted answers to this question
    (SELECT AVG(u2.Reputation)
     FROM Posts p2
     JOIN Users u2 ON p2.OwnerUserId = u2.Id
     WHERE p2.ParentId = f.PostId AND p2.PostTypeId = 2) AS AvgAnswerOwnerRep
  FROM FilteredTop f
  LEFT JOIN Users u ON f.OwnerUserId = u.Id
),
Windowed AS (
  SELECT
    cr.*,
    ROW_NUMBER() OVER (
      ORDER BY cr.ViewCount DESC,
               cr.UpVotesLast30 - cr.DownVotesLast30 DESC,
               cr.CreationDate DESC
    ) AS rn
  FROM CrossRef cr
)
SELECT
  w.PostId,
  w.Title,
  w.CreationDate,
  w.Score,
  w.ViewCount,
  w.OwnerName,
  w.Reputation AS OwnerReputation,
  w.Tags,
  w.UpVotesLast30,
  w.DownVotesLast30,
  w.CommentCountLast30,
  w.PostKind,
  w.AvgAnswerOwnerRep
FROM Windowed w
WHERE w.rn <= 100
ORDER BY w.ViewCount DESC, w.AvgAnswerOwnerRep DESC NULLS LAST, w.CreationDate DESC
;