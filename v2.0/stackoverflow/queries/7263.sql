-- {"query": "7263.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "qwen3-coder", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2102, "output_tokens": 1509}
WITH RankedPosts AS (
  SELECT 
    p.Id,
    p.PostTypeId,
    p.Score,
    p.ViewCount,
    p.CreationDate,
    p.Title,
    p.Tags,
    p.OwnerUserId,
    p.AcceptedAnswerId,
    p.AnswerCount,
    p.CommentCount,
    p.FavoriteCount,
    ROW_NUMBER() OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate DESC) as rn,
    LAG(p.Score) OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate) as prev_score,
    NTILE(10) OVER (ORDER BY p.Score DESC) as score_quartile,
    CASE 
      WHEN p.Tags IS NOT NULL AND p.Tags <> '' THEN 
        COALESCE(array_length(string_to_array(trim(both '<>' FROM p.Tags), '><'), 1), 0)
      ELSE 0 
    END as tag_count,
    COALESCE(p.ViewCount, 0) + COALESCE(p.AnswerCount, 0) + COALESCE(p.CommentCount, 0) as activity_score
  FROM Posts p
  WHERE p.PostTypeId IN (1, 2) 
    AND p.CreationDate >= DATE '2020-01-01'
),
UserStats AS (
  SELECT 
    u.Id as UserId,
    u.Reputation,
    u.Views,
    u.UpVotes,
    u.DownVotes,
    u.AccountId,
    COUNT(DISTINCT p.Id) as post_count,
    AVG(p.Score) as avg_score,
    MAX(p.CreationDate) as last_post_date,
    SUM(p.Score) as total_score
  FROM Users u
  LEFT JOIN Posts p ON u.Id = p.OwnerUserId
  WHERE u.CreationDate >= DATE '2015-01-01'
  GROUP BY u.Id, u.Reputation, u.Views, u.UpVotes, u.DownVotes, u.AccountId
),
QuestionStats AS (
  SELECT 
    q.Id as QuestionId,
    q.Title,
    q.Score,
    q.ViewCount,
    q.AnswerCount,
    q.CommentCount,
    q.CreationDate,
    q.OwnerUserId,
    MAX(a.Score) as max_answer_score,
    AVG(a.Score) as avg_answer_score,
    COUNT(a.Id) as answer_count,
    COALESCE(q.AcceptedAnswerId, 0) as accepted_answer_id,
    CASE 
      WHEN q.AcceptedAnswerId IS NOT NULL 
        THEN CASE WHEN (SELECT a2.Score FROM Posts a2 WHERE a2.Id = q.AcceptedAnswerId) > 0 THEN 1 ELSE 0 END
        ELSE 0 
    END as has_positive_accepted_answer,
    EXTRACT(EPOCH FROM (q.CreationDate - LAG(q.CreationDate) OVER (ORDER BY q.CreationDate))) as time_since_last_question
  FROM Posts q
  LEFT JOIN Posts a ON q.Id = a.ParentId
  WHERE q.PostTypeId = 1
    AND q.CreationDate >= DATE '2020-01-01'
  GROUP BY q.Id, q.Title, q.Score, q.ViewCount, q.AnswerCount, q.CommentCount, q.CreationDate, q.OwnerUserId, q.AcceptedAnswerId
),
TagSummary AS (
  SELECT 
    t.TagName,
    t.Count,
    t.IsRequired,
    t.IsModeratorOnly,
    CASE 
      WHEN COALESCE(t.IsRequired, FALSE) = TRUE THEN 'Required'
      WHEN COALESCE(t.IsModeratorOnly, FALSE) = TRUE THEN 'Moderator Only'
      ELSE 'General'
    END as tag_type,
    ROW_NUMBER() OVER (ORDER BY t.Count DESC) as popularity_rank
  FROM Tags t
  WHERE t.Count > 100
)
SELECT 
  COUNT(*) as total_questions,
  COUNT(DISTINCT rs.OwnerUserId) as unique_owners,
  AVG(rs.Score) as avg_question_score,
  AVG(rs.ViewCount) as avg_view_count,
  AVG(rs.AnswerCount) as avg_answer_count,
  AVG(rs.CommentCount) as avg_comment_count,
  AVG(rs.FavoriteCount) as avg_favorite_count,
  STRING_AGG(
    CASE 
      WHEN rs.tag_count >= 3 THEN rs.Title
      ELSE NULL 
    END, 
    ', '
  ) as high_tag_questions,
  SUM(CASE WHEN rs.Score > 10 THEN 1 ELSE 0 END) as high_score_questions,
  SUM(CASE WHEN rs.ViewCount > 1000 THEN 1 ELSE 0 END) as popular_questions,
  MAX(rs.CreationDate) as latest_question_date,
  MIN(rs.CreationDate) as earliest_question_date,
  AVG(u.Reputation) as avg_user_reputation,
  AVG(u.post_count) as avg_posts_per_user,
  AVG(qs.avg_answer_score) as avg_answer_score,
  AVG(qs.time_since_last_question) as avg_time_between_questions,
  STRING_AGG(DISTINCT ts.TagName, ', ') as popular_tags,
  COUNT(DISTINCT CASE WHEN rs.Score > 20 OR rs.ViewCount > 500 THEN rs.OwnerUserId END) as elite_contributors,
  AVG(CASE WHEN rs.prev_score IS NOT NULL THEN rs.Score - rs.prev_score ELSE 0 END) as avg_score_improvement,
  COUNT(CASE WHEN rs.score_quartile = 1 THEN 1 END) as top_score_quartile,
  COUNT(CASE WHEN rs.score_quartile = 4 THEN 1 END) as bottom_score_quartile,
  STRING_AGG(
    CASE 
      WHEN qs.has_positive_accepted_answer = 1 THEN CAST(qs.QuestionId AS VARCHAR) 
      ELSE NULL 
    END, 
    ', '
  ) as questions_with_positive_accepted_answers,
  COUNT(DISTINCT CASE WHEN rs.rn = 1 THEN rs.OwnerUserId END) as active_users_last_post,
  AVG(rs.activity_score) as average_activity_score,
  COUNT(CASE WHEN rs.tag_count >= 5 THEN 1 END) as high_tag_count_questions,
  COUNT(CASE WHEN rs.tag_count BETWEEN 2 AND 4 THEN 1 END) as medium_tag_count_questions,
  COUNT(CASE WHEN rs.tag_count = 1 THEN 1 END) as low_tag_count_questions
FROM RankedPosts rs
LEFT JOIN UserStats u ON rs.OwnerUserId = u.UserId
LEFT JOIN QuestionStats qs ON rs.Id = qs.QuestionId
LEFT JOIN TagSummary ts ON ts.popularity_rank <= 20
WHERE rs.PostTypeId = 1 
  AND rs.CreationDate >= DATE '2020-01-01'
  AND EXISTS (
    SELECT 1 FROM Posts p2 
    WHERE p2.OwnerUserId = rs.OwnerUserId 
      AND p2.CreationDate >= DATE '2020-01-01'
      AND p2.PostTypeId = 1
  )
  AND (
    rs.Score > 0 
    OR rs.ViewCount > 100 
    OR rs.AnswerCount > 1
  )
  AND (rs.Tags IS NULL OR rs.Tags = '' OR rs.tag_count > 0)
GROUP BY rs.PostTypeId, rs.CreationDate, rs.OwnerUserId, rs.Score, rs.ViewCount, rs.AnswerCount, rs.CommentCount, rs.FavoriteCount, rs.Title, rs.tag_count, rs.prev_score, rs.score_quartile, rs.rn, rs.activity_score
HAVING COUNT(*) > 0
ORDER BY rs.CreationDate DESC
LIMIT 100;