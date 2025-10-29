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
    WHERE p.PostTypeId = 1 -- Questions
      AND p.CreationDate >= NOW() - INTERVAL '30 days'
  ),
  top_tags AS (
    SELECT
      t.TagName,
      AVG(p.Score) AS avg_score,
      MAX(p.ViewCount) AS max_views,
      COUNT(*) AS q_count
    FROM unnest(string_to_array(replace(replace(p.Tags, '><', ','), '<', ''), ',')) AS t(TagName)
    JOIN recent_questions p ON p.Id = p.PostId
    GROUP BY t.TagName
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
      ROW_NUMBER() OVER (PARTITION BY q.OwnerUserId ORDER BY q.ViewCount DESC, q.Score DESC) AS rn
    FROM recent_questions q
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
      NULL AS RelatedTag,
      NULL AS RelatedPostId,
      NULL AS ErrMsg
    FROM expensive_operations fr
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
      NULL AS OwnerDisplayName,
      NULL AS Reputation,
      NULL AS last_active,
      rr.CommentCount,
      rr.AnswerCount,
      rr.FavoriteCount,
      tt.TagName AS RelatedTag,
      NULL AS RelatedPostId,
      NULL AS ErrMsg
    FROM expensive_operations rr
    JOIN top_tags tt ON rr.TagName = tt.TagName
      AND rr.rn = 1
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