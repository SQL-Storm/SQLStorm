-- {"query": "5218.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-5-nano", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 905}
WITH recent_questions AS (
  SELECT
    p.Id AS PostId,
    p.Title,
    p.CreationDate,
    p.Score,
    p.ViewCount,
    p.Tags,
    p.OwnerUserId,
    p.LastActivityDate,
    p.CommentCount,
    p.AnswerCount,
    p.FavoriteCount,
    p.ContentLicense,
    p.PostTypeId,
    u.Reputation,
    u.DisplayName,
    u.Location
  FROM Posts p
  LEFT JOIN Users u ON p.OwnerUserId = u.Id
  WHERE p.PostTypeId = 1
    AND p.CreationDate >= CAST('2024-10-01 12:34:56' AS timestamp) - INTERVAL '90 days'
),
top_tags AS (
  SELECT
    t.tag,
    COUNT(*) AS question_count
  FROM recent_questions rq,
       LATERAL (
         SELECT UNNEST(STRING_TO_ARRAY(SUBSTRING(rq.Tags FROM 2 FOR CHAR_LENGTH(rq.Tags)-2), '><')) AS tag
       ) AS t
  GROUP BY t.tag
),
tag_demand AS (
  SELECT
    tt.tag,
    tt.question_count,
    RANK() OVER (ORDER BY tt.question_count DESC, tt.tag) AS r
  FROM top_tags tt
  ORDER BY tt.question_count DESC
),
complex_aggregate AS (
  SELECT
    rq.PostId,
    rq.Title,
    rq.OwnerUserId,
    rq.DisplayName,
    rq.Reputation,
    rq.CreationDate,
    rq.LastActivityDate,
    rq.ViewCount,
    rq.Score,
    rq.CommentCount,
    rq.AnswerCount,
    rq.FavoriteCount,
    rq.Tags,
    rq.Location,
    COALESCE((
      SELECT AVG(v.BountyAmount)
      FROM Votes v
      WHERE v.PostId = rq.PostId
        AND v.VoteTypeId = 9
        AND v.creationdate > rq.CreationDate
    ), 0) AS avg_bounty_close
  FROM recent_questions rq
),
availability AS (
  SELECT
    c.PostId,
    c.Text AS Comment,
    c.CreationDate,
    c.UserDisplayName,
    c.UserId
  FROM Comments c
  WHERE c.CreationDate > CAST('2024-10-01 12:34:56' AS timestamp) - INTERVAL '14 days'
),
recent_comments AS (
  SELECT
    p.Id AS PostId,
    c.Text AS comment,
    c.CreationDate,
    c.UserDisplayName
  FROM Posts p
  LEFT JOIN Comments c ON c.PostId = p.Id
  WHERE c.CreationDate > CAST('2024-10-01 12:34:56' AS timestamp) - INTERVAL '7 days'
),
cross_join AS (
  SELECT
    ca.PostId,
    ca.Title,
    ca.OwnerUserId,
    ca.Reputation,
    ca.CreationDate,
    ca.LastActivityDate,
    ca.ViewCount,
    ca.Score,
    ca.CommentCount,
    ca.AnswerCount,
    ca.FavoriteCount,
    ca.Tags,
    ca.Location,
    rc.comment AS recent_comment,
    rc.CreationDate AS comment_date,
    rc.UserDisplayName AS commenter,
    av.Comment AS availability_comment,
    av.CreationDate AS availability_date,
    av.UserDisplayName AS availability_user,
    ca.avg_bounty_close,
    ca.DisplayName
  FROM complex_aggregate ca
  LEFT JOIN availability av ON av.PostId = ca.PostId
  LEFT JOIN recent_comments rc ON rc.PostId = ca.PostId
)
SELECT
  pw.PostId,
  pw.Title,
  pw.OwnerUserId,
  pw.Reputation,
  pw.DisplayName,
  pw.Location,
  pw.CreationDate,
  pw.LastActivityDate,
  pw.ViewCount,
  pw.Score,
  pw.CommentCount,
  pw.AnswerCount,
  pw.FavoriteCount,
  pw.Tags,
  pw.avg_bounty_close,
  STRING_AGG(DISTINCT td.tag, ',') AS popular_tags,
  CASE
    WHEN pw.LastActivityDate > CAST('2024-10-01 12:34:56' AS timestamp) - INTERVAL '7 days' THEN 'Active'
    ELSE 'Dormant'
  END AS activity_status
FROM cross_join pw
LEFT JOIN tag_demand td ON TRUE
GROUP BY
  pw.PostId,
  pw.Title,
  pw.OwnerUserId,
  pw.Reputation,
  pw.DisplayName,
  pw.Location,
  pw.CreationDate,
  pw.LastActivityDate,
  pw.ViewCount,
  pw.Score,
  pw.CommentCount,
  pw.AnswerCount,
  pw.FavoriteCount,
  pw.Tags,
  pw.avg_bounty_close
ORDER BY pw.LastActivityDate DESC
LIMIT 100;