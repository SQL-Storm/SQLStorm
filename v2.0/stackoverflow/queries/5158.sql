-- {"query": "5158.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-5-nano", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 744}
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
    p.ContentLicense
  FROM Posts p
  WHERE p.PostTypeId = 1
    AND p.CreationDate >= CAST('2024-10-01 12:34:56' AS timestamp) - INTERVAL '30 days'
),
tag_popularity AS (
  SELECT
    t.tag,
    COUNT(*) AS question_count,
    AVG(p.Score) AS avg_score,
    SUM(p.ViewCount) AS total_views
  FROM Posts p
  JOIN recent_questions rq ON rq.PostId = p.Id
  CROSS JOIN LATERAL (
    SELECT unnest(string_to_array(substr(p.Tags, 2, length(p.Tags)-2), '><')) AS tag
  ) t
  WHERE p.Tags IS NOT NULL
  GROUP BY t.tag
),
recent_votes AS (
  SELECT
    v.PostId,
    v.VoteTypeId,
    v.UserId,
    v.CreationDate,
    u.DisplayName AS VoterName
  FROM Votes v
  LEFT JOIN Users u ON u.Id = v.UserId
  WHERE v.CreationDate >= CAST('2024-10-01 12:34:56' AS timestamp) - INTERVAL '14 days'
    AND v.VoteTypeId IN (2, 3, 10, 11, 12, 16)
),
closed_questions AS (
  SELECT
    p.Id AS PostId,
    ps.Name AS CloseReason,
    p.ClosedDate
  FROM Posts p
  JOIN PostHistory ph ON ph.PostId = p.Id
  LEFT JOIN CloseReasonTypes ps ON
    -- try to convert ph.Comment to integer safely: keep non-integer values from matching
    (CASE WHEN ph.Comment ~ '^[0-9]+$' THEN CAST(ph.Comment AS INTEGER) ELSE NULL END) = ps.Id
  WHERE p.PostTypeId = 1
    AND p.ClosedDate IS NOT NULL
),
complex_summary AS (
  SELECT
    rq.PostId,
    rq.Title,
    rq.CreationDate,
    rq.Score,
    rq.ViewCount,
    rq.OwnerUserId,
    rq.LastActivityDate,
    rq.CommentCount,
    rq.AnswerCount,
    rq.FavoriteCount,
    rg.tag AS TopTag,
    rv.VoteTypeId AS RecentVoteType,
    rv.VoterName,
    rc.CloseReason
  FROM recent_questions rq
  LEFT JOIN (
    SELECT tag, MAX(question_count) AS max_cnt
    FROM tag_popularity
    GROUP BY tag
  ) t ON true
  LEFT JOIN tag_popularity rg ON rg.tag = (
    SELECT t2.tag
    FROM tag_popularity t2
    ORDER BY t2.question_count DESC
    LIMIT 1
  )
  LEFT JOIN recent_votes rv ON rv.PostId = rq.PostId
  LEFT JOIN Users u ON u.Id = rq.OwnerUserId
  LEFT JOIN closed_questions rc ON rc.PostId = rq.PostId
  GROUP BY
    rq.PostId,
    rq.Title,
    rq.CreationDate,
    rq.Score,
    rq.ViewCount,
    rq.OwnerUserId,
    rq.LastActivityDate,
    rq.CommentCount,
    rq.AnswerCount,
    rq.FavoriteCount,
    rg.tag,
    rv.VoteTypeId,
    rv.VoterName,
    rc.CloseReason
)
SELECT
  cs.PostId,
  cs.Title,
  cs.CreationDate,
  cs.Score,
  cs.ViewCount,
  cs.OwnerUserId,
  cs.LastActivityDate,
  cs.CommentCount,
  cs.AnswerCount,
  cs.FavoriteCount,
  cs.TopTag,
  cs.RecentVoteType,
  cs.VoterName,
  cs.CloseReason
FROM complex_summary cs
ORDER BY cs.CreationDate DESC
LIMIT 200;