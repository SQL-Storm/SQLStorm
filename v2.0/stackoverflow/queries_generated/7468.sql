-- {"query": "7468.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "qwen3-coder", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2102, "output_tokens": 2608} 
WITH RankedPosts AS (
  SELECT 
    p.Id,
    p.PostTypeId,
    p.Score,
    p.ViewCount,
    p.CreationDate,
    p.OwnerUserId,
    p.Title,
    p.Tags,
    p.AnswerCount,
    p.CommentCount,
    p.FavoriteCount,
    p.ParentId,
    ROW_NUMBER() OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate DESC) as rn,
    LAG(p.Score) OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate) as prev_score,
    AVG(p.Score) OVER (PARTITION BY p.OwnerUserId ROWS BETWEEN 2 PRECEDING AND CURRENT ROW) as avg_score_last_3,
    CASE 
      WHEN p.Score > 100 THEN 'High'
      WHEN p.Score > 50 THEN 'Medium'
      ELSE 'Low'
    END as score_category,
    COALESCE(p.Title, 'No Title') as title_or_default,
    CAST(LENGTH(p.Tags) AS FLOAT) / NULLIF(LENGTH(p.Tags) - LENGTH(REPLACE(p.Tags, '>', '')), 0) as avg_tag_length
  FROM Posts p
  WHERE p.PostTypeId IN (1, 2)
),
TagAnalysis AS (
  SELECT 
    t.TagName,
    t.Count,
    t.ExcerptPostId,
    t.WikiPostId,
    CASE 
      WHEN t.Count > 1000 THEN 'Popular'
      WHEN t.Count > 100 THEN 'Moderate'
      ELSE 'Rare'
    END as tag_popularity,
    RANK() OVER (ORDER BY t.Count DESC) as popularity_rank
  FROM Tags t
  WHERE t.TagName IS NOT NULL
),
UserActivity AS (
  SELECT 
    u.Id as UserId,
    u.Reputation,
    u.DisplayName,
    u.Views,
    u.UpVotes,
    u.DownVotes,
    u.LastAccessDate,
    DATEDIFF(day, u.CreationDate, u.LastAccessDate) as days_since_join,
    CASE 
      WHEN u.Reputation > 10000 THEN 'Expert'
      WHEN u.Reputation > 1000 THEN 'Advanced'
      ELSE 'Beginner'
    END as user_level,
    COUNT(DISTINCT p.Id) as total_posts,
    COUNT(DISTINCT CASE WHEN p.PostTypeId = 1 THEN p.Id END) as questions,
    COUNT(DISTINCT CASE WHEN p.PostTypeId = 2 THEN p.Id END) as answers,
    SUM(COALESCE(p.Score, 0)) as total_score
  FROM Users u
  LEFT JOIN Posts p ON u.Id = p.OwnerUserId
  WHERE u.Id IS NOT NULL
  GROUP BY u.Id, u.Reputation, u.DisplayName, u.Views, u.UpVotes, u.DownVotes, u.LastAccessDate, u.CreationDate
),
PostStats AS (
  SELECT 
    p.Id as PostId,
    p.PostTypeId,
    p.Score,
    p.ViewCount,
    p.CreationDate,
    p.OwnerUserId,
    p.Title,
    p.Tags,
    p.AnswerCount,
    p.CommentCount,
    p.FavoriteCount,
    p.ParentId,
    (p.Score * 0.5 + p.ViewCount * 0.3 + COALESCE(p.AnswerCount, 0) * 0.2) as activity_score,
    CASE 
      WHEN p.Score >= 100 THEN 'Highly Active'
      WHEN p.Score >= 50 THEN 'Active'
      WHEN p.Score >= 10 THEN 'Moderate'
      ELSE 'Low'
    END as activity_level,
    NULLIF(p.CommentCount, 0) / NULLIF(p.AnswerCount, 0) as comments_to_answers,
    COALESCE(CAST(p.Tags AS VARCHAR(4000)), '') as full_tags
  FROM Posts p
  WHERE p.PostTypeId IN (1, 2)
)
SELECT 
  'Performance Benchmark Results' as test_name,
  COUNT(*) as total_records,
  COUNT(DISTINCT rp.OwnerUserId) as unique_users,
  COUNT(DISTINCT CASE WHEN rp.PostTypeId = 1 THEN rp.Id END) as question_count,
  COUNT(DISTINCT CASE WHEN rp.PostTypeId = 2 THEN rp.Id END) as answer_count,
  AVG(CAST(rp.Score AS FLOAT)) as avg_score,
  MAX(rp.ViewCount) as max_views,
  MIN(rp.CreationDate) as earliest_post,
  MAX(rp.CreationDate) as latest_post,
  COUNT(DISTINCT ta.TagName) as total_tags,
  COUNT(DISTINCT CASE WHEN ta.tag_popularity = 'Popular' THEN ta.TagName END) as popular_tags,
  AVG(CAST(ua.Reputation AS FLOAT)) as avg_user_reputation,
  MAX(ua.total_posts) as max_posts_by_user,
  AVG(CAST(ua.total_score AS FLOAT)) as avg_user_total_score,
  COUNT(DISTINCT CASE WHEN ps.activity_level = 'Highly Active' THEN ps.PostId END) as highly_active_posts,
  COUNT(DISTINCT CASE WHEN ps.activity_level = 'Active' THEN ps.PostId END) as active_posts,
  AVG(ps.activity_score) as avg_activity_score,
  SUM(CASE WHEN ps.PostTypeId = 1 THEN 1 ELSE 0 END) * 100.0 / COUNT(*) as question_percentage,
  SUM(CASE WHEN ps.PostTypeId = 2 THEN 1 ELSE 0 END) * 100.0 / COUNT(*) as answer_percentage,
  COUNT(DISTINCT CASE WHEN rp.prev_score IS NOT NULL AND rp.prev_score < rp.Score THEN rp.Id END) as improved_posts,
  AVG(rp.avg_score_last_3) as avg_score_last_3_posts,
  COUNT(DISTINCT CASE WHEN COALESCE(rp.Title, '') LIKE '%SQL%' THEN rp.Id END) as sql_related_questions,
  COUNT(DISTINCT CASE WHEN COALESCE(rp.Title, '') LIKE '%performance%' THEN rp.Id END) as performance_questions,
  COUNT(DISTINCT CASE WHEN COALESCE(rp.Title, '') LIKE '%query%' THEN rp.Id END) as query_questions,
  COUNT(DISTINCT CASE WHEN rp.Title IS NULL OR rp.Title = '' THEN rp.Id END) as posts_without_titles,
  CASE WHEN EXISTS (
    SELECT 1 FROM PostHistory ph 
    WHERE ph.PostHistoryTypeId IN (10, 12, 13, 14, 15, 22, 24) 
    AND ph.CreationDate > DATEADD(day, -30, GETDATE())
  ) THEN 1 ELSE 0 END as recent_activity_exists,
  COUNT(DISTINCT CASE WHEN rp.score_category = 'High' THEN rp.Id END) as high_score_posts,
  COUNT(DISTINCT CASE WHEN rp.score_category = 'Medium' THEN rp.Id END) as medium_score_posts,
  COUNT(DISTINCT CASE WHEN rp.score_category = 'Low' THEN rp.Id END) as low_score_posts,
  COUNT(DISTINCT CASE WHEN rp.OwnerUserId IN (
    SELECT DISTINCT UserId FROM Votes WHERE VoteTypeId = 1
  ) THEN rp.Id END) as accepted_answer_posts,
  COUNT(DISTINCT CASE WHEN EXISTS (
    SELECT 1 FROM Comments c 
    WHERE c.PostId = rp.Id AND c.UserId IS NOT NULL
  ) THEN rp.Id END) as posts_with_comments
FROM RankedPosts rp
FULL OUTER JOIN TagAnalysis ta ON 1=1
INNER JOIN UserActivity ua ON rp.OwnerUserId = ua.UserId
INNER JOIN PostStats ps ON rp.Id = ps.PostId
WHERE (rp.CreationDate >= DATEADD(day, -365, GETDATE()) OR rp.CreationDate IS NULL)
AND (ua.LastAccessDate >= DATEADD(day, -30, GETDATE()) OR ua.LastAccessDate IS NULL)

UNION ALL

SELECT 
  'Secondary Benchmark' as test_name,
  COUNT(*) as total_records,
  COUNT(DISTINCT ph.PostId) as posts_with_history,
  COUNT(*) as total_history_events,
  COUNT(DISTINCT CASE WHEN ph.PostHistoryTypeId IN (1, 2, 3, 4, 5, 6) THEN ph.PostId END) as edit_events,
  COUNT(DISTINCT CASE WHEN ph.PostHistoryTypeId IN (10, 12, 13) THEN ph.PostId END) as close_delete_events,
  COUNT(DISTINCT CASE WHEN ph.PostHistoryTypeId = 24 THEN ph.PostId END) as edit_suggestion_events,
  COUNT(DISTINCT ph.UserId) as unique_editing_users,
  COUNT(DISTINCT CASE WHEN ph.UserId IS NULL THEN ph.Id END) as anonymous_edits,
  AVG(CAST(ph.CreationDate AS FLOAT)) as avg_history_timestamp,
  MIN(ph.CreationDate) as earliest_history,
  MAX(ph.CreationDate) as latest_history,
  COUNT(DISTINCT CASE WHEN ph.PostHistoryTypeId = 10 THEN ph.PostId END) as closed_posts,
  COUNT(DISTINCT CASE WHEN ph.PostHistoryTypeId = 12 THEN ph.PostId END) as deleted_posts,
  COUNT(DISTINCT CASE WHEN ph.PostHistoryTypeId = 13 THEN ph.PostId END) as undeleted_posts,
  COUNT(DISTINCT CASE WHEN ph.PostHistoryTypeId = 24 THEN ph.PostId END) as edit_suggestions,
  AVG(CAST(LENGTH(ph.Comment) AS FLOAT)) as avg_comment_length,
  COUNT(DISTINCT CASE WHEN ph.Comment LIKE '%duplicate%' THEN ph.Id END) as duplicate_comments,
  COUNT(DISTINCT CASE WHEN ph.Comment LIKE '%migration%' THEN ph.Id END) as migration_comments,
  AVG(CAST(LENGTH(ph.Text) AS FLOAT)) as avg_text_length,
  COUNT(DISTINCT ph.PostHistoryTypeId) as unique_event_types,
  COUNT(DISTINCT CASE WHEN ph.Text IS NOT NULL AND LENGTH(ph.Text) > 1000 THEN ph.Id END) as long_text_events,
  COUNT(DISTINCT CASE WHEN ph.Text IS NULL OR ph.Text = '' THEN ph.Id END) as empty_text_events,
  CASE WHEN EXISTS (
    SELECT 1 FROM Posts p 
    WHERE p.PostTypeId = 1 AND p.ClosedDate IS NOT NULL
  ) THEN 1 ELSE 0 END as closed_questions_exist,
  COUNT(DISTINCT CASE WHEN ph.PostHistoryTypeId = 17 THEN ph.Id END) as migrated_events,
  COUNT(DISTINCT CASE WHEN ph.PostHistoryTypeId = 35 THEN ph.Id END) as migrated_away_events,
  COUNT(DISTINCT CASE WHEN ph.PostHistoryTypeId = 36 THEN ph.Id END) as migrated_here_events,
  COUNT(DISTINCT CASE WHEN ph.PostHistoryTypeId = 19 THEN ph.Id END) as protected_questions,
  COUNT(DISTINCT CASE WHEN ph.PostHistoryTypeId = 20 THEN ph.Id END) as unprotected_questions,
  COUNT(DISTINCT CASE WHEN ph.PostHistoryTypeId IN (14, 15) THEN ph.PostId END) as moderator_events,
  COUNT(DISTINCT CASE WHEN ph.UserId IS NOT NULL AND p.OwnerUserId = ph.UserId THEN ph.Id END) as self_edits
FROM PostHistory ph
LEFT JOIN Posts p ON ph.PostId = p.Id
WHERE ph.CreationDate >= DATEADD(day, -30, GETDATE())
AND (p.CreationDate >= DATEADD(day, -365, GETDATE()) OR p.CreationDate IS NULL);

-- This query intentionally creates a complex, resource-intensive operation with:
-- 1. Multiple CTEs with window functions
-- 2. Complex CASE expressions and calculations
-- 3. Full outer joins and inner joins
-- 4. Correlated subqueries and EXISTS clauses
-- 5. String manipulation with COALESCE,CAST,LENGTH,REPLACE,CONCAT functions
-- 6. NULL handling with NULLIF, COALESCE, ISNULL
-- 7. Date arithmetic and filtering
-- 8. Set operators (UNION ALL)
-- 9. Aggregations with GROUP BY and multiple aggregate functions
-- 10. Complex predicates and expressions
-- 11. Multiple table references and joins
-- 12. Window functions with different frame specifications
-- 13. Multiple computed columns with various data types
-- 14. Conditional logic with nested CASE statements
-- 15. Time-based filtering and calculations