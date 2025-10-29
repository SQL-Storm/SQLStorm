-- {"query": "7674.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "qwen3-coder", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2102, "output_tokens": 2195} 
WITH RankedPosts AS (
    SELECT 
        p.Id,
        p.PostTypeId,
        p.ParentId,
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
        COUNT(*) OVER (PARTITION BY p.OwnerUserId) as user_post_count,
        AVG(p.Score) OVER (PARTITION BY p.OwnerUserId) as user_avg_score,
        NTILE(4) OVER (ORDER BY p.Score DESC) as score_quartile
    FROM Posts p
    WHERE p.PostTypeId IN (1, 2)
),
UserStats AS (
    SELECT 
        u.Id as UserId,
        u.Reputation,
        u.DisplayName,
        u.Views,
        u.UpVotes,
        u.DownVotes,
        u.AccountId,
        COUNT(DISTINCT p.Id) as total_posts,
        COUNT(DISTINCT CASE WHEN p.PostTypeId = 1 THEN p.Id END) as questions,
        COUNT(DISTINCT CASE WHEN p.PostTypeId = 2 THEN p.Id END) as answers,
        AVG(p.Score) as avg_score,
        MAX(p.CreationDate) as last_post_date,
        STRING_AGG(DISTINCT p.Tags, '; ') as all_tags,
        CASE WHEN COUNT(DISTINCT p.Id) > 100 THEN 'Highly Active' 
             WHEN COUNT(DISTINCT p.Id) > 50 THEN 'Active' 
             ELSE 'Regular' END as activity_level
    FROM Users u
    LEFT JOIN Posts p ON u.Id = p.OwnerUserId
    GROUP BY u.Id, u.Reputation, u.DisplayName, u.Views, u.UpVotes, u.DownVotes, u.AccountId
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
        p.Tags,
        u.DisplayName as owner_name,
        CASE WHEN p.AcceptedAnswerId IS NOT NULL THEN 1 ELSE 0 END as has_accepted_answer,
        COALESCE(p.FavoriteCount, 0) as favorite_count,
        NULLIF(p.FavoriteCount, 0) as non_zero_favorites
    FROM Posts p
    JOIN Users u ON p.OwnerUserId = u.Id
    WHERE p.PostTypeId = 1
      AND p.Score > (SELECT AVG(Score) FROM Posts WHERE PostTypeId = 1)
      AND p.CreationDate > '2020-01-01'
),
ComplexAnalysis AS (
    SELECT 
        q.Id,
        q.Title,
        q.Score,
        q.ViewCount,
        q.AnswerCount,
        q.CommentCount,
        q.CreationDate,
        q.Tags,
        q.owner_name,
        q.has_accepted_answer,
        q.favorite_count,
        q.non_zero_favorites,
        RANK() OVER (ORDER BY q.Score DESC) as score_rank,
        DENSE_RANK() OVER (ORDER BY q.ViewCount DESC) as view_rank,
        PERCENT_RANK() OVER (ORDER BY q.Score) as score_percentile,
        COALESCE(
            (SELECT COUNT(*) 
             FROM Comments c 
             WHERE c.PostId = q.Id 
               AND c.CreationDate > q.CreationDate), 0) as comment_count_since_post,
        CASE 
            WHEN q.AnswerCount > 0 AND q.AnswerCount >= (
                SELECT AVG(AnswerCount) 
                FROM Posts 
                WHERE PostTypeId = 1
            ) THEN 'Above Average Answers' 
            WHEN q.AnswerCount > 0 THEN 'Below Average Answers'
            ELSE 'No Answers'
        END as answer_quality,
        (q.Score * COALESCE(q.ViewCount, 1)) as score_view_product,
        CASE 
            WHEN q.Tags IS NOT NULL AND LENGTH(q.Tags) > 50 THEN 'Long Tags' 
            ELSE 'Short Tags' 
        END as tag_length_descriptor
    FROM TopQuestions q
),
FinalAnalysis AS (
    SELECT 
        ca.Id,
        ca.Title,
        ca.Score,
        ca.ViewCount,
        ca.AnswerCount,
        ca.CommentCount,
        ca.CreationDate,
        ca.Tags,
        ca.owner_name,
        ca.has_accepted_answer,
        ca.favorite_count,
        ca.non_zero_favorites,
        ca.score_rank,
        ca.view_rank,
        ca.score_percentile,
        ca.comment_count_since_post,
        ca.answer_quality,
        ca.score_view_product,
        ca.tag_length_descriptor,
        CASE 
            WHEN ca.Score > 100 AND ca.ViewCount > 1000 THEN 'Popular High Score'
            WHEN ca.Score > 50 AND ca.ViewCount > 500 THEN 'Popular Medium Score'
            WHEN ca.Score <= 50 AND ca.ViewCount <= 500 THEN 'Low Engagement'
            ELSE 'Moderate Engagement'
        END as engagement_category,
        DATEDIFF(day, ca.CreationDate, CURRENT_TIMESTAMP) as days_since_post,
        CASE 
            WHEN ca.score_percentile >= 0.9 THEN 'Top 10%'
            WHEN ca.score_percentile >= 0.75 THEN 'Top 25%'
            WHEN ca.score_percentile >= 0.5 THEN 'Top 50%'
            ELSE 'Below Median'
        END as percentile_category,
        ROW_NUMBER() OVER (ORDER BY ca.Score DESC, ca.ViewCount DESC) as popularity_rank,
        NULLIF(LEN(ca.Title) - LEN(REPLACE(UPPER(ca.Title), 'QUESTION', '')), 0) as contains_question_in_title,
        (
            SELECT COUNT(*) 
            FROM Votes v 
            WHERE v.PostId = ca.Id 
              AND v.VoteTypeId IN (2, 3)  -- UpMod/DownMod
        ) as up_down_vote_count,
        (
            SELECT COUNT(*) 
            FROM PostHistory ph 
            WHERE ph.PostId = ca.Id 
              AND ph.PostHistoryTypeId IN (4, 5, 6)  -- Edit Title/Body/Tags
        ) as edit_count,
        (
            SELECT AVG(v.BountyAmount) 
            FROM Votes v 
            WHERE v.PostId = ca.Id 
              AND v.VoteTypeId = 8  -- BountyStart
        ) as avg_bounty_amount,
        (
            SELECT MAX(v.CreationDate) 
            FROM Votes v 
            WHERE v.PostId = ca.Id 
              AND v.VoteTypeId IN (8, 9)  -- BountyStart/BountyClose
        ) as last_bounty_date,
        EXISTS (
            SELECT 1 
            FROM PostLinks pl 
            WHERE pl.PostId = ca.Id 
              AND pl.LinkTypeId = 3  -- Duplicate
        ) as has_duplicate_links,
        CASE 
            WHEN EXISTS (
                SELECT 1 
                FROM PostHistory ph 
                WHERE ph.PostId = ca.Id 
                  AND ph.PostHistoryTypeId IN (10, 11)  -- Post Closed/Reopened
            ) THEN 'Has Closure History'
            ELSE 'No Closure History'
        END as closure_status
    FROM ComplexAnalysis ca
)
SELECT 
    fa.Id,
    fa.Title,
    fa.Score,
    fa.ViewCount,
    fa.AnswerCount,
    fa.CommentCount,
    fa.CreationDate,
    fa.Tags,
    fa.owner_name,
    fa.has_accepted_answer,
    fa.favorite_count,
    fa.non_zero_favorites,
    fa.score_rank,
    fa.view_rank,
    fa.score_percentile,
    fa.comment_count_since_post,
    fa.answer_quality,
    fa.score_view_product,
    fa.tag_length_descriptor,
    fa.engagement_category,
    fa.days_since_post,
    fa.percentile_category,
    fa.popularity_rank,
    fa.contains_question_in_title,
    fa.up_down_vote_count,
    fa.edit_count,
    fa.avg_bounty_amount,
    fa.last_bounty_date,
    fa.has_duplicate_links,
    fa.closure_status,
    CASE 
        WHEN fa.score_percentile > 0.95 THEN 'Elite Post'
        WHEN fa.score_percentile > 0.9 THEN 'High Performing'
        WHEN fa.score_percentile > 0.75 THEN 'Moderate Performing'
        WHEN fa.score_percentile > 0.5 THEN 'Below Average'
        ELSE 'Low Performing'
    END as performance_category,
    CASE 
        WHEN fa.score_rank <= 10 THEN 'Top 10'
        WHEN fa.score_rank <= 50 THEN 'Top 50'
        WHEN fa.score_rank <= 100 THEN 'Top 100'
        ELSE 'Beyond Top 100'
    END as ranking_category,
    CASE 
        WHEN fa.days_since_post <= 30 THEN 'Recently Posted'
        WHEN fa.days_since_post <= 90 THEN 'Recently Updated'
        ELSE 'Older Post'
    END as recency_category,
    COALESCE(
        (
            SELECT COUNT(*) 
            FROM Badges b 
            WHERE b.UserId = (
                SELECT OwnerUserId 
                FROM Posts 
                WHERE Id = fa.Id
            ) 
              AND b.Date > fa.CreationDate
        ), 0
    ) as badges_earned_since_post,
    (
        SELECT STRING_AGG(DISTINCT CONCAT(b.Name, ' (', b.Class, ')'), '; ')
        FROM Badges b
        WHERE b.UserId = (
            SELECT OwnerUserId 
            FROM Posts 
            WHERE Id = fa.Id
        )
          AND b.Date > fa.CreationDate
    ) as recent_badge_list,
    fa.Id as post_id,
    COALESCE(fa.answer_count * fa.view_count, 0) as interaction_intensity,
    COALESCE(fa.comment_count + fa.favorite_count, 0) as additional_engagement
FROM FinalAnalysis fa
WHERE fa.score_rank <= 100
  AND (
    fa.Tags IS NOT NULL 
    OR fa.Title IS NOT NULL
    OR fa.owner_name IS NOT NULL
  )
  AND fa.days_since_post <= 365
ORDER BY fa.score DESC, fa.ViewCount DESC, fa.CreationDate DESC
LIMIT 500;