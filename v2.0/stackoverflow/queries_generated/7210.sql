-- {"query": "7210.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "qwen3-coder", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2102, "output_tokens": 3212} 
WITH RankedPosts AS (
    SELECT 
        p.Id,
        p.PostTypeId,
        p.OwnerUserId,
        p.Score,
        p.ViewCount,
        p.CreationDate,
        p.Title,
        p.Tags,
        p.AnswerCount,
        p.CommentCount,
        p.FavoriteCount,
        ROW_NUMBER() OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate DESC) as rn,
        LAG(p.Score) OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate) as prev_score,
        AVG(p.Score) OVER (PARTITION BY p.OwnerUserId ROWS BETWEEN 1 PRECEDING AND 1 FOLLOWING) as avg_score_3day,
        NTILE(4) OVER (ORDER BY p.Score DESC) as quartile,
        CASE 
            WHEN p.Tags IS NOT NULL AND p.Tags != '' THEN 
                (SELECT COUNT(*) FROM unnest(string_to_array(trim(p.Tags, '<>'), '><')) as tag)
            ELSE 0 
        END as tag_count
    FROM Posts p
    WHERE p.PostTypeId IN (1, 2)
),
UserStats AS (
    SELECT 
        u.Id as UserId,
        u.DisplayName,
        u.Reputation,
        u.Views,
        u.UpVotes,
        u.DownVotes,
        COALESCE(SUM(p.Score), 0) as total_score,
        COALESCE(COUNT(DISTINCT p.Id), 0) as post_count,
        COALESCE(COUNT(DISTINCT c.Id), 0) as comment_count,
        MAX(p.CreationDate) as latest_post_date,
        STRING_AGG(DISTINCT p.Title, ', ' ORDER BY p.CreationDate DESC) as recent_titles,
        COUNT(DISTINCT b.Id) as badge_count,
        CASE 
            WHEN u.Reputation > 10000 THEN 'Elite'
            WHEN u.Reputation > 5000 THEN 'Veteran'
            WHEN u.Reputation > 1000 THEN 'Regular'
            ELSE 'Newbie'
        END as reputation_level
    FROM Users u
    LEFT JOIN Posts p ON u.Id = p.OwnerUserId
    LEFT JOIN Comments c ON u.Id = c.UserId
    LEFT JOIN Badges b ON u.Id = b.UserId
    GROUP BY u.Id, u.DisplayName, u.Reputation, u.Views, u.UpVotes, u.DownVotes
),
TopQuestions AS (
    SELECT 
        p.Id,
        p.Title,
        p.Score,
        p.ViewCount,
        p.AnswerCount,
        p.CommentCount,
        p.CreationDate,
        u.DisplayName as owner_name,
        p.Tags,
        STRING_AGG(DISTINCT c.Text, ' | ' ORDER BY c.CreationDate) as comments,
        COALESCE(SUM(v.BountyAmount), 0) as total_bounty,
        CASE 
            WHEN p.ClosedDate IS NOT NULL THEN 'Closed'
            WHEN p.CommunityOwnedDate IS NOT NULL THEN 'Community Owned'
            WHEN p.AcceptedAnswerId IS NOT NULL THEN 'Answered'
            ELSE 'Open'
        END as status,
        DATEDIFF(day, p.CreationDate, COALESCE(p.ClosedDate, NOW())) as days_open,
        ROW_NUMBER() OVER (ORDER BY p.Score DESC, p.ViewCount DESC) as popularity_rank
    FROM Posts p
    JOIN Users u ON p.OwnerUserId = u.Id
    LEFT JOIN Comments c ON p.Id = c.PostId
    LEFT JOIN Votes v ON p.Id = v.PostId AND v.VoteTypeId = 8
    WHERE p.PostTypeId = 1
    GROUP BY p.Id, p.Title, p.Score, p.ViewCount, p.AnswerCount, p.CommentCount, p.CreationDate, u.DisplayName, p.Tags, p.ClosedDate, p.CommunityOwnedDate, p.AcceptedAnswerId
),
TagAnalysis AS (
    SELECT 
        t.TagName,
        t.Count,
        t.ExcerptPostId,
        t.WikiPostId,
        COALESCE(p.Title, 'No Title') as excerpt_title,
        COALESCE(p.Body, 'No Body') as excerpt_body,
        CASE 
            WHEN t.Count > 1000 THEN 'Popular'
            WHEN t.Count > 500 THEN 'Moderately Popular'
            WHEN t.Count > 100 THEN 'Common'
            ELSE 'Rare'
        END as tag_category
    FROM Tags t
    LEFT JOIN Posts p ON t.ExcerptPostId = p.Id
),
PostActivity AS (
    SELECT 
        ph.PostId,
        ph.PostHistoryTypeId,
        ph.UserId,
        ph.CreationDate,
        ph.Comment,
        ph.Text,
        u.DisplayName as editor_name,
        CASE 
            WHEN ph.PostHistoryTypeId IN (10, 11, 12, 13) THEN 'Status Change'
            WHEN ph.PostHistoryTypeId IN (1, 2, 3, 4, 5, 6) THEN 'Content Edit'
            WHEN ph.PostHistoryTypeId IN (14, 15, 19, 20) THEN 'Moderation Action'
            ELSE 'Other'
        END as activity_type,
        DENSE_RANK() OVER (PARTITION BY ph.PostId ORDER BY ph.CreationDate DESC) as activity_sequence
    FROM PostHistory ph
    LEFT JOIN Users u ON ph.UserId = u.Id
    WHERE ph.CreationDate >= DATEADD(month, -6, NOW())
)
SELECT 
    '=== BENCHMARK REPORT ===' as report_title,
    COUNT(*) as total_posts,
    (SELECT COUNT(*) FROM Posts WHERE PostTypeId = 1) as question_count,
    (SELECT COUNT(*) FROM Posts WHERE PostTypeId = 2) as answer_count,
    (SELECT COUNT(*) FROM Users) as user_count,
    (SELECT COUNT(*) FROM Badges) as badge_count,
    (SELECT COUNT(*) FROM Comments) as comment_count,
    (
        SELECT COUNT(*) 
        FROM Posts p 
        JOIN (
            SELECT OwnerUserId, COUNT(*) as post_count 
            FROM Posts 
            WHERE PostTypeId = 1 
            GROUP BY OwnerUserId 
            HAVING COUNT(*) > 50
        ) high_posters ON p.OwnerUserId = high_posters.OwnerUserId
    ) as high_volume_users,
    (
        SELECT COUNT(*) 
        FROM Posts p 
        WHERE p.Score > 1000 
        AND p.PostTypeId = 1
    ) as highly_voted_questions,
    (
        SELECT AVG(ViewCount) 
        FROM Posts 
        WHERE PostTypeId = 1
    ) as avg_question_views,
    (
        SELECT AVG(Score) 
        FROM Posts 
        WHERE PostTypeId = 2
    ) as avg_answer_score,
    (
        SELECT COUNT(*) 
        FROM (
            SELECT PostId 
            FROM Comments 
            GROUP BY PostId 
            HAVING COUNT(*) > 10
        ) as prolific_comments
    ) as highly_commented_posts,
    (
        SELECT COUNT(DISTINCT ParentId) 
        FROM Posts 
        WHERE PostTypeId = 2 
        AND ParentId IS NOT NULL
    ) as unique_answered_questions,
    (
        SELECT COUNT(DISTINCT p.Id) 
        FROM Posts p 
        JOIN Posts parent ON p.ParentId = parent.Id 
        JOIN Users u ON parent.OwnerUserId = u.Id 
        WHERE p.PostTypeId = 2 
        AND u.Reputation > 1000
    ) as high_reputation_answers,
    (
        SELECT COUNT(*) 
        FROM (
            SELECT p.Id, COUNT(*) as comment_count
            FROM Posts p
            JOIN Comments c ON p.Id = c.PostId
            WHERE p.PostTypeId = 1
            GROUP BY p.Id
            HAVING COUNT(*) BETWEEN 5 AND 20
        ) as medium_commented
    ) as medium_commented_questions,
    (
        SELECT COUNT(*) 
        FROM Posts p 
        WHERE p.Tags IS NOT NULL 
        AND p.Tags != ''
        AND p.PostTypeId = 1
    ) as tagged_questions,
    (
        SELECT AVG(tag_count) 
        FROM RankedPosts 
        WHERE PostTypeId = 1
    ) as avg_tags_per_question,
    (
        SELECT COUNT(*) 
        FROM (
            SELECT OwnerUserId, AVG(Score) as avg_score
            FROM Posts 
            WHERE PostTypeId = 1 
            GROUP BY OwnerUserId
            HAVING AVG(Score) > 50
        ) as high_scorers
    ) as high_scoring_question_authors,
    (
        SELECT COUNT(*) 
        FROM (
            SELECT p.Id, SUM(p.Score) as total_score
            FROM Posts p
            JOIN Votes v ON p.Id = v.PostId
            WHERE v.VoteTypeId IN (2, 3)
            GROUP BY p.Id
            HAVING SUM(p.Score) > 100
        ) as high_scored_posts
    ) as high_scoring_posts,
    (
        SELECT COUNT(*) 
        FROM Posts p 
        WHERE p.CreationDate >= DATEADD(day, -30, NOW())
        AND p.PostTypeId = 1
    ) as recent_questions,
    (
        SELECT COUNT(*) 
        FROM (
            SELECT PostId, COUNT(*) as edit_count
            FROM PostHistory 
            WHERE PostHistoryTypeId IN (1, 2, 3, 4, 5, 6)
            GROUP BY PostId
            HAVING COUNT(*) > 10
        ) as heavily_edited
    ) as heavily_edited_posts,
    (
        SELECT AVG(comment_count) 
        FROM TopQuestions
    ) as avg_comments_per_question,
    (
        SELECT COUNT(*) 
        FROM PostLinks 
        WHERE LinkTypeId = 3
    ) as duplicate_links,
    (
        SELECT COUNT(*) 
        FROM (
            SELECT ph.PostId, COUNT(*) as activity_count
            FROM PostActivity ph
            WHERE ph.activity_sequence <= 3
            GROUP BY ph.PostId
            HAVING COUNT(*) >= 2
        ) as active_posts
    ) as rapidly_active_posts,
    (
        SELECT COUNT(*) 
        FROM (
            SELECT TagName
            FROM Tags
            WHERE Count > 100
            GROUP BY TagName
            HAVING COUNT(*) > 1
        ) as popular_tags
    ) as multi_use_popular_tags,
    (
        SELECT SUM(total_score) 
        FROM UserStats
    ) as total_user_score,
    (
        SELECT AVG(post_count) 
        FROM UserStats
    ) as average_posts_per_user,
    (
        SELECT MAX(total_score) 
        FROM UserStats
    ) as max_user_score,
    (
        SELECT COUNT(*) 
        FROM (
            SELECT UserId, COUNT(*) as badge_count
            FROM Badges
            GROUP BY UserId
            HAVING COUNT(*) > 50
        ) as badge_hoarders
    ) as badge_hoarders,
    (
        SELECT COUNT(*) 
        FROM (
            SELECT PostId
            FROM PostHistory
            WHERE PostHistoryTypeId = 10
            GROUP BY PostId
            HAVING COUNT(*) >= 1
        ) as closed_posts
    ) as closed_posts_count,
    (
        SELECT COUNT(*) 
        FROM (
            SELECT PostId, COUNT(DISTINCT Comment) as close_reason_count
            FROM PostHistory
            WHERE PostHistoryTypeId = 10
            GROUP BY PostId
            HAVING COUNT(DISTINCT Comment) >= 2
        ) as disputed_closures
    ) as disputed_closures_count,
    (
        SELECT COUNT(*) 
        FROM (
            SELECT PostId, COUNT(DISTINCT Text) as edit_count
            FROM PostHistory
            WHERE PostHistoryTypeId IN (1, 2, 3, 4, 5, 6)
            GROUP BY PostId
            HAVING COUNT(DISTINCT Text) > 5
        ) as multiple_edits
    ) as multiple_edits_count,
    (
        SELECT COUNT(*) 
        FROM (
            SELECT u.Id
            FROM Users u
            JOIN Posts p ON u.Id = p.OwnerUserId
            WHERE p.PostTypeId = 1
            GROUP BY u.Id
            HAVING COUNT(p.Id) >= 100
        ) as prolific_questioners
    ) as prolific_questioners_count,
    (
        SELECT COUNT(*) 
        FROM (
            SELECT u.Id
            FROM Users u
            JOIN Posts p ON u.Id = p.OwnerUserId
            WHERE p.PostTypeId = 2
            GROUP BY u.Id
            HAVING COUNT(p.Id) >= 1000
        ) as prolific_answerers
    ) as prolific_answerers_count,
    (
        SELECT MIN(reputation) 
        FROM UserStats
    ) as min_reputation,
    (
        SELECT MAX(reputation) 
        FROM UserStats
    ) as max_reputation,
    (
        SELECT AVG(Reputation) 
        FROM Users
    ) as avg_reputation,
    (
        SELECT COUNT(*) 
        FROM (
            SELECT p.Id, COUNT(c.Id) as comment_count
            FROM Posts p
            JOIN Comments c ON p.Id = c.PostId
            WHERE p.PostTypeId = 1
            GROUP BY p.Id
            HAVING COUNT(c.Id) BETWEEN 0 AND 2
        ) as sparsely_commented
    ) as sparsely_commented_questions,
    (
        SELECT COUNT(*) 
        FROM (
            SELECT u.Id
            FROM Users u
            WHERE u.Reputation BETWEEN 100 AND 999
        ) as regular_users
    ) as regular_users_count,
    (
        SELECT COUNT(*) 
        FROM (
            SELECT u.Id
            FROM Users u
            WHERE u.Reputation BETWEEN 1000 AND 9999
        ) as veteran_users
    ) as veteran_users_count,
    (
        SELECT COUNT(*) 
        FROM (
            SELECT u.Id
            FROM Users u
            WHERE u.Reputation >= 10000
        ) as elite_users
    ) as elite_users_count,
    (
        SELECT COUNT(*) 
        FROM (
            SELECT p.Id
            FROM Posts p
            WHERE p.Tags IS NULL OR p.Tags = ''
        ) as untagged_questions
    ) as untagged_questions_count;

-- This query is designed for performance benchmarking with:
-- 1. Multiple CTEs with complex logic
-- 2. Window functions (ROW_NUMBER, LAG, AVG, NTILE, DENSE_RANK)
-- 3. Correlated subqueries
-- 4. Outer joins (LEFT JOINs)
-- 5. Set operators and aggregations
-- 6. Complex predicates and expressions
-- 7. String operations (STRING_AGG, substring, trim, unnest)
-- 8. NULL handling (COALESCE, IS NULL checks)
-- 9. Multiple table references
-- 10. Date arithmetic (DATEDIFF, DATEADD)
-- 11. Conditional logic (CASE statements)
-- 12. Subquery correlations
-- 13. Grouping and having clauses
-- 14. Combinations of different SQL constructs
-- 15. Complex joins with multiple conditions