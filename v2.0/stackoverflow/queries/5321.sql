-- {"query": "5321.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-5-nano", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 836}
WITH
  recent_questions AS (
    SELECT
      p.Id AS PostId,
      p.Title,
      p.Tags,
      p.CreationDate,
      p.ViewCount,
      p.Score,
      p.OwnerUserId,
      p.LastActivityDate,
      p.CommentCount,
      p.AnswerCount,
      p.FavoriteCount
    FROM Posts p
    WHERE p.PostTypeId = 1
      AND p.CreationDate >= CAST('2024-10-01 12:34:56' AS TIMESTAMP) - INTERVAL '30 days'
  ),
  -- expand tags for each recent question
  question_tags AS (
    SELECT
      rq.PostId,
      TRIM(tag) AS TagName
    FROM recent_questions rq,
    LATERAL (
      SELECT UNNEST(STRING_TO_ARRAY(REPLACE(REPLACE(rq.Tags, '><', ','), '<', ''), ',')) AS tag
    ) t
  ),
  top_tags AS (
    SELECT
      qt.TagName,
      AVG(rq.Score) AS avg_score,
      MAX(rq.ViewCount) AS max_views,
      COUNT(*) AS q_count
    FROM question_tags qt
    JOIN recent_questions rq ON rq.PostId = qt.PostId
    GROUP BY qt.TagName
  ),
  correlated_user_activity AS (
    SELECT
      u.Id AS UserId,
      u.DisplayName,
      u.Reputation,
      COUNT(DISTINCT p.Id) FILTER (WHERE p.PostTypeId = 1) AS question_count,
      COUNT(DISTINCT v.PostId) AS vote_posts,
      SUM(v.BountyAmount) FILTER (WHERE v.BountyAmount IS NOT NULL) AS total_bounties,
      MAX(p.LastActivityDate) AS last_active
    FROM Users u
    LEFT JOIN Posts p ON p.OwnerUserId = u.Id
    LEFT JOIN Votes v ON v.UserId = u.Id
    WHERE u.Id IS NOT NULL
    GROUP BY u.Id, u.DisplayName, u.Reputation
  ),
  expensive_operations AS (
    SELECT
      q.PostId,
      q.Title,
      q.CreationDate,
      q.ViewCount,
      q.Score,
      q.OwnerUserId,
      q.LastActivityDate,
      q.CommentCount,
      q.AnswerCount,
      q.FavoriteCount,
      ROW_NUMBER() OVER (PARTITION BY q.OwnerUserId ORDER BY q.ViewCount DESC, q.Score DESC) AS rn,
      CAST(NULL AS TEXT) AS TagName
    FROM recent_questions q
  ),
  -- attach a representative tag per question (choose one tag if exists)
  expensive_with_tag AS (
    SELECT
      e.PostId,
      e.Title,
      e.CreationDate,
      e.ViewCount,
      e.Score,
      e.OwnerUserId,
      e.LastActivityDate,
      e.CommentCount,
      e.AnswerCount,
      e.FavoriteCount,
      e.rn,
      COALESCE(qt.TagName, e.TagName) AS TagName
    FROM expensive_operations e
    LEFT JOIN (
      SELECT PostId, TagName
      FROM (
        SELECT PostId, TagName,
               ROW_NUMBER() OVER (PARTITION BY PostId ORDER BY TagName) AS rn_tag
        FROM question_tags
      ) t
      WHERE rn_tag = 1
    ) qt ON qt.PostId = e.PostId
  ),
  final_union AS (
    SELECT
      fr.PostId,
      fr.Title,
      fr.CreationDate,
      fr.LastActivityDate,
      fr.ViewCount,
      fr.Score,
      fr.OwnerUserId,
      fu.DisplayName AS OwnerDisplayName,
      fu.Reputation,
      fu.last_active,
      fr.CommentCount,
      fr.AnswerCount,
      fr.FavoriteCount,
      CAST(NULL AS TEXT) AS RelatedTag,
      CAST(NULL AS BIGINT) AS RelatedPostId,
      CAST(NULL AS TEXT) AS ErrMsg
    FROM expensive_with_tag fr
    LEFT JOIN correlated_user_activity fu ON fu.UserId = fr.OwnerUserId
    WHERE fr.rn = 1

    UNION ALL

    SELECT
      rr.PostId,
      rr.Title,
      rr.CreationDate,
      rr.LastActivityDate,
      rr.ViewCount,
      rr.Score,
      rr.OwnerUserId,
      CAST(NULL AS TEXT) AS OwnerDisplayName,
      CAST(NULL AS INTEGER) AS Reputation,
      CAST(NULL AS TIMESTAMP) AS last_active,
      rr.CommentCount,
      rr.AnswerCount,
      rr.FavoriteCount,
      tt.TagName AS RelatedTag,
      CAST(NULL AS BIGINT) AS RelatedPostId,
      CAST(NULL AS TEXT) AS ErrMsg
    FROM expensive_with_tag rr
    JOIN top_tags tt ON rr.TagName = tt.TagName
    WHERE rr.rn = 1
  )
SELECT
  fu.PostId,
  fu.Title,
  fu.CreationDate,
  fu.LastActivityDate,
  fu.ViewCount,
  fu.Score,
  fu.OwnerUserId,
  fu.OwnerDisplayName,
  fu.Reputation,
  fu.last_active,
  fu.CommentCount,
  fu.AnswerCount,
  fu.FavoriteCount,
  fu.RelatedTag,
  fu.RelatedPostId,
  COALESCE(fu.ErrMsg, '') AS ErrMsg
FROM final_union fu
ORDER BY fu.LastActivityDate DESC, fu.Score DESC
LIMIT 100;