-- {"query": "6008.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p1", "model": "gpt-5-nano", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 812} 
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
    p.FavoriteCount
  FROM Posts p
  WHERE p.PostTypeId = 1 -- Questions
    AND p.CreationDate >= cast('2024-10-01 12:34:56' as timestamp) - INTERVAL '90 days'
),
recent_activity AS (
  SELECT
    rq.PostId,
    rq.Title,
    rq.Tags,
    rq.CreationDate,
    rq.Score,
    rq.ViewCount,
    rq.OwnerUserId,
    rq.LastActivityDate,
    rq.CommentCount,
    rq.AnswerCount,
    rq.FavoriteCount,
    u.Reputation,
    u.DisplayName,
    u.Location,
    COUNT(v.Id) FILTER (WHERE v.VoteTypeId = 2) AS UpVotesPlaced,
    COUNT(v.Id) FILTER (WHERE v.VoteTypeId = 3) AS DownVotesPlaced,
    MAX(CASE WHEN v.VoteTypeId = 2 THEN v.CreationDate END) AS LastUpvoteDate,
    MAX(CASE WHEN v.VoteTypeId = 3 THEN v.CreationDate END) AS LastDownvoteDate
  FROM recent_questions rq
  LEFT JOIN Users u ON rq.OwnerUserId = u.Id
  LEFT JOIN Votes v ON rq.PostId = v.PostId
  GROUP BY
    rq.PostId, rq.Title, rq.Tags, rq.CreationDate, rq.Score, rq.ViewCount,
    rq.OwnerUserId, rq.LastActivityDate, rq.CommentCount, rq.AnswerCount,
    rq.FavoriteCount, u.Reputation, u.DisplayName, u.Location
),
comments AS (
  SELECT
    ra.PostId,
    COUNT(c.Id) AS CommentCountAll,
    STRING_AGG(CONCAT(c.UserDisplayName, ':', c.Text), ' | ' ORDER BY c.CreationDate) AS AllComments
  FROM recent_activity ra
  LEFT JOIN Comments c ON ra.PostId = c.PostId
  GROUP BY ra.PostId
),
tags_expansion AS (
  SELECT
    ra.PostId,
    ra.Title,
    ra.Tags,
    ra.CreationDate,
    ra.Score,
    ra.ViewCount,
    ra.OwnerUserId,
    ra.LastActivityDate,
    ra.CommentCount,
    ra.AnswerCount,
    ra.FavoriteCount,
    ra.Reputation,
    ra.DisplayName,
    ra.Location,
    ra.UpVotesPlaced,
    ra.DownVotesPlaced,
    ra.LastUpvoteDate,
    ra.LastDownvoteDate,
    c.CommentCountAll,
    c.AllComments,
    CASE
      WHEN testo.tag_present THEN true
      ELSE false
    END AS HasTagExpansion
  FROM recent_activity ra
  LEFT JOIN comments c ON ra.PostId = c.PostId
  CROSS JOIN LATERAL (
    SELECT
      EXISTS (
        SELECT 1
        FROM unnest(string_to_array(ra.Tags, '<>')) AS t(tag)
        WHERE t.tag <> ''
      ) AS tag_present
  ) AS testo
)
SELECT
  te.PostId,
  te.Title,
  te.Tags,
  te.CreationDate,
  te.Score,
  te.ViewCount,
  te.OwnerUserId,
  te.LastActivityDate,
  te.CommentCount,
  te.AnswerCount,
  te.FavoriteCount,
  te.Reputation,
  te.DisplayName,
  te.Location,
  te.UpVotesPlaced,
  te.DownVotesPlaced,
  te.LastUpvoteDate,
  te.LastDownvoteDate,
  te.CommentCountAll,
  te.AllComments
FROM tags_expansion te
ORDER BY te.LastActivityDate DESC, te.Score DESC
LIMIT 200;