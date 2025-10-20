-- {"query": "187.sql", "dataset": "stackoverflow", "version": "v1.4", "prompt": "p1", "model": "gpt-5-nano", "temperature": 1.0, "max_tokens": 32768, "reasoning": "low", "input_tokens": 2026, "output_tokens": 2099} 
WITH
RecentQuestions AS (
  SELECT
    p.Id AS PostId,
    p.Title,
    p.Tags,
    p.CreationDate,
    p.Score,
    p.ViewCount,
    p.OwnerUserId,
    p.LastActivityDate,
    p.AcceptedAnswerId
  FROM Posts p
  WHERE p.PostTypeId = 1
    AND p.ClosedDate IS NULL
    AND p.CreationDate >= (CURRENT_TIMESTAMP - INTERVAL '365 days')
),
RecentAnswers AS (
  SELECT
    p.Id AS PostId,
    p.ParentId AS QuestionId,
    p.Score,
    p.ViewCount,
    p.OwnerUserId,
    p.CreationDate,
    p.LastActivityDate
  FROM Posts p
  WHERE p.PostTypeId = 2
    AND p.CreationDate >= (CURRENT_TIMESTAMP - INTERVAL '365 days')
),
VoteAgg AS (
  SELECT
    v.PostId,
    SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS UpVotes,
    SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS DownVotes,
    SUM(CASE WHEN v.VoteTypeId = 6 THEN 1 ELSE 0 END) AS CloseVotes,
    SUM(CASE WHEN v.VoteTypeId = 8 THEN 1 ELSE 0 END) AS BountyStarts,
    SUM(v.BountyAmount) AS BountyAmount
  FROM Votes v
  GROUP BY v.PostId
),
CommentCount AS (
  SELECT
    c.PostId,
    COUNT(*) AS CommentCount
  FROM Comments c
  GROUP BY c.PostId
),
OwnerInfo AS (
  SELECT
    u.Id AS UserId,
    u.DisplayName,
    u.Reputation,
    u.CreationDate,
    u.LastAccessDate,
    u.Location,
    u.ProfileImageUrl
  FROM Users u
),
TagArray AS (
  SELECT
    rp.PostId,
    CASE
      WHEN rp.Title IS NOT NULL THEN
        COALESCE(string_to_array(substring(rp.Tags, 2, length(rp.Tags) - 2), '><'), ARRAY[]::varchar[])
      ELSE ARRAY[]::varchar[]
    END AS TagsArray
  FROM RecentQuestions rp
),
Leaderboard AS (
  SELECT
    rq.PostId,
    rq.Title,
    rq.Tags,
    rq.CreationDate,
    rq.ViewCount,
    rq.Score,
    COALESCE(va.UpVotes, 0) AS UpVotes,
    COALESCE(va.DownVotes, 0) AS DownVotes,
    (COALESCE(va.UpVotes, 0) - COALESCE(va.DownVotes, 0)) AS NetVotes,
    COALESCE(cc.CommentCount, 0) AS CommentCount,
    oi.UserId,
    oi.DisplayName AS OwnerDisplayName,
    oi.Reputation,
    rq.LastActivityDate,
    (CASE
       WHEN rq.AcceptedAnswerId IS NOT NULL THEN true
       ELSE false
     END) AS HasAcceptedAnswer,
    ROW_NUMBER() OVER (
      PARTITION BY rq.OwnerUserId
      ORDER BY (COALESCE(va.UpVotes, 0) - COALESCE(va.DownVotes, 0)) DESC,
               rq.ViewCount DESC,
               rq.CreationDate DESC
    ) AS rn
  FROM RecentQuestions rq
  LEFT JOIN VoteAgg va ON va.PostId = rq.PostId
  LEFT JOIN CommentCount cc ON cc.PostId = rq.PostId
  LEFT JOIN OwnerInfo oi ON oi.UserId = rq.OwnerUserId
  LEFT JOIN TagArray ta ON ta.PostId = rq.PostId
),
AnsweredStatus AS (
  SELECT
    ra.QuestionId,
    ra.PostId,
    ra.Score,
    ra.ViewCount,
    ra.OwnerUserId,
    ra.CreationDate,
    ra.LastActivityDate,
    COALESCE(va.UpVotes, 0) AS UpVotes,
    COALESCE(va.DownVotes, 0) AS DownVotes,
    (COALESCE(va.UpVotes, 0) - COALESCE(va.DownVotes, 0)) AS NetVotes,
    COALESCE(cc.CommentCount, 0) AS CommentCount,
    oi.DisplayName AS OwnerDisplayName,
    oi.Reputation,
    ta.TagsArray,
    (CASE
       WHEN ra.QuestionId IS NULL THEN false
       ELSE true
     END) AS HasActivity
  FROM RecentAnswers ra
  LEFT JOIN VoteAgg va ON va.PostId = ra.PostId
  LEFT JOIN CommentCount cc ON cc.PostId = ra.PostId
  LEFT JOIN OwnerInfo oi ON oi.UserId = ra.OwnerUserId
  LEFT JOIN TagArray ta ON ta.PostId = ra.QuestionId
)
SELECT
  'QuestionBenchmark' AS BenchmarkTag,
  l.PostId,
  l.Title,
  l.Tags,
  l.CreationDate,
  l.ViewCount,
  l.Score,
  l.UpVotes,
  l.DownVotes,
  l.NetVotes,
  l.CommentCount,
  l.OwnerDisplayName,
  l.Reputation,
  l.LastActivityDate,
  l.HasAcceptedAnswer,
  l.rn
FROM Leaderboard l
WHERE l.rn <= 100
UNION ALL
SELECT
  'AnswerBenchmark' AS BenchmarkTag,
  a.PostId,
  NULL AS Title,
  NULL AS Tags,
  a.CreationDate,
  a.ViewCount,
  a.Score,
  a.UpVotes,
  a.DownVotes,
  a.NetVotes,
  a.CommentCount,
  a.OwnerDisplayName,
  a.Reputation,
  a.LastActivityDate,
  a.HasActivity AS HasAcceptedAnswer,
  ROW_NUMBER() OVER (
    PARTITION BY a.QuestionId
    ORDER BY a.NetVotes DESC, a.ViewCount DESC, a.CreationDate DESC
  ) AS rn
FROM AnsweredStatus a
WHERE a.rn <= 100;