-- {"query": "7802.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "qwen3-coder", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2102, "output_tokens": 4813} 
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
        ROW_NUMBER() OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate DESC) as rn,
        LAG(p.Score) OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate) as prev_score,
        LAG(p.ViewCount) OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate) as prev_views,
        AVG(p.Score) OVER (PARTITION BY p.OwnerUserId ROWS BETWEEN 2 PRECEDING AND CURRENT ROW) as avg_score_3posts,
        CASE 
            WHEN p.Score > 100 THEN 'High'
            WHEN p.Score > 50 THEN 'Medium'
            ELSE 'Low'
        END as score_category,
        COALESCE(
            (SELECT COUNT(*) FROM Comments c WHERE c.PostId = p.Id AND c.Score > 0),
            0
        ) as positive_comments_count,
        COALESCE(
            (SELECT COUNT(*) FROM Votes v WHERE v.PostId = p.Id AND v.VoteTypeId = 2),
            0
        ) as upvotes_count,
        COALESCE(
            (SELECT COUNT(*) FROM Votes v WHERE v.PostId = p.Id AND v.VoteTypeId = 3),
            0
        ) as downvotes_count,
        CASE 
            WHEN p.Tags IS NOT NULL AND p.Tags != '' THEN 
                TRIM(REPLACE(REPLACE(REPLACE(p.Tags, '<', ''), '>', ''), ' ', ''))
            ELSE ''
        END as clean_tags,
        DATEDIFF('day', p.CreationDate, CURRENT_TIMESTAMP) as days_since_creation,
        CASE 
            WHEN EXISTS (
                SELECT 1 FROM PostLinks pl 
                WHERE pl.PostId = p.Id AND pl.LinkTypeId = 3
            ) THEN 'Duplicate'
            WHEN EXISTS (
                SELECT 1 FROM PostHistory ph 
                WHERE ph.PostId = p.Id AND ph.PostHistoryTypeId = 12
            ) THEN 'Deleted'
            WHEN EXISTS (
                SELECT 1 FROM PostHistory ph 
                WHERE ph.PostId = p.Id AND ph.PostHistoryTypeId = 11
            ) THEN 'Reopened'
            ELSE 'Active'
        END as post_status,
        (SELECT COUNT(*) FROM Badges b WHERE b.UserId = p.OwnerUserId AND b.Class = 1) as gold_badges_count,
        (SELECT COUNT(*) FROM Badges b WHERE b.UserId = p.OwnerUserId AND b.Class = 2) as silver_badges_count,
        (SELECT COUNT(*) FROM Badges b WHERE b.UserId = p.OwnerUserId AND b.Class = 3) as bronze_badges_count,
        CASE 
            WHEN p.OwnerUserId IS NULL THEN 'Community Wiki'
            ELSE 'User Owned'
        END as ownership_type,
        COALESCE(
            (SELECT COUNT(DISTINCT ph.UserId) 
             FROM PostHistory ph 
             WHERE ph.PostId = p.Id AND ph.UserId IS NOT NULL),
            0
        ) as unique_editors_count,
        COALESCE(
            (SELECT COUNT(*) 
             FROM PostHistory ph 
             WHERE ph.PostId = p.Id AND ph.PostHistoryTypeId IN (5, 6)),
            0
        ) as edit_count
    FROM Posts p
    WHERE p.PostTypeId IN (1, 2) -- Questions and Answers only
),
PostStats AS (
    SELECT 
        Id,
        PostTypeId,
        OwnerUserId,
        Score,
        ViewCount,
        CreationDate,
        Title,
        Tags,
        rn,
        prev_score,
        prev_views,
        avg_score_3posts,
        score_category,
        positive_comments_count,
        upvotes_count,
        downvotes_count,
        clean_tags,
        days_since_creation,
        post_status,
        gold_badges_count,
        silver_badges_count,
        bronze_badges_count,
        ownership_type,
        unique_editors_count,
        edit_count,
        CASE 
            WHEN (avg_score_3posts > 50 OR Score > 100) THEN 'High Engagement'
            WHEN (avg_score_3posts > 20 OR Score > 50) THEN 'Medium Engagement'
            ELSE 'Low Engagement'
        END as engagement_level,
        CASE 
            WHEN Score > 0 AND ViewCount > 1000 THEN 'Popular'
            WHEN Score > 0 AND ViewCount > 100 THEN 'Moderate'
            ELSE 'Less Popular'
        END as popularity_level,
        CASE 
            WHEN Days_Since_Creation < 30 THEN 'New'
            WHEN Days_Since_Creation BETWEEN 30 AND 180 THEN 'Medium Age'
            ELSE 'Old'
        END as age_category,
        (COALESCE(upvotes_count, 0) - COALESCE(downvotes_count, 0)) as net_votes,
        CASE 
            WHEN net_votes > 50 THEN 'Highly Upvoted'
            WHEN net_votes > 10 THEN 'Upvoted'
            WHEN net_votes < -10 THEN 'Downvoted'
            ELSE 'Neutral'
        END as voting_status,
        CASE 
            WHEN (positive_comments_count + COALESCE(upvotes_count, 0)) > 10 THEN 'Well Received'
            WHEN (positive_comments_count + COALESCE(upvotes_count, 0)) > 5 THEN 'Accepted'
            ELSE 'Needs Work'
        END as reception_status,
        CASE 
            WHEN edit_count > 5 OR unique_editors_count > 3 THEN 'Active'
            WHEN edit_count > 2 OR unique_editors_count > 1 THEN 'Moderate'
            ELSE 'Inactive'
        END as activity_level,
        CASE 
            WHEN Length(clean_tags) > 0 THEN 
                (SELECT string_agg(t.value, ', ' ORDER BY t.value)
                 FROM unnest(string_to_array(clean_tags, ',')) AS t(value)
                 WHERE t.value IS NOT NULL AND t.value != '')
            ELSE 'No Tags'
        END as formatted_tags,
        COALESCE(
            (SELECT u.DisplayName 
             FROM Users u 
             WHERE u.Id = OwnerUserId),
            'Unknown User'
        ) as creator_name,
        COALESCE(
            (SELECT CAST(Reputation AS VARCHAR(10)) 
             FROM Users u 
             WHERE u.Id = OwnerUserId),
            'N/A'
        ) as creator_reputation,
        COALESCE(
            (SELECT COUNT(*) 
             FROM Posts p2 
             WHERE p2.OwnerUserId = OwnerUserId AND p2.PostTypeId = 1),
            0
        ) as total_questions_by_user,
        COALESCE(
            (SELECT COUNT(*) 
             FROM Posts p3 
             WHERE p3.OwnerUserId = OwnerUserId AND p3.PostTypeId = 2),
            0
        ) as total_answers_by_user,
        COALESCE(
            (SELECT AVG(p4.Score) 
             FROM Posts p4 
             WHERE p4.OwnerUserId = OwnerUserId AND p4.PostTypeId = 1),
            0
        ) as avg_question_score_by_user,
        COALESCE(
            (SELECT AVG(p5.Score) 
             FROM Posts p5 
             WHERE p5.OwnerUserId = OwnerUserId AND p5.PostTypeId = 2),
            0
        ) as avg_answer_score_by_user
    FROM RankedPosts
),
QuestionMetrics AS (
    SELECT 
        ps.Id,
        ps.PostTypeId,
        ps.OwnerUserId,
        ps.Score,
        ps.ViewCount,
        ps.CreationDate,
        ps.Title,
        ps.Tags,
        ps.rn,
        ps.prev_score,
        ps.prev_views,
        ps.avg_score_3posts,
        ps.score_category,
        ps.positive_comments_count,
        ps.upvotes_count,
        ps.downvotes_count,
        ps.clean_tags,
        ps.days_since_creation,
        ps.post_status,
        ps.gold_badges_count,
        ps.silver_badges_count,
        ps.bronze_badges_count,
        ps.ownership_type,
        ps.unique_editors_count,
        ps.edit_count,
        ps.engagement_level,
        ps.popularity_level,
        ps.age_category,
        ps.net_votes,
        ps.voting_status,
        ps.reception_status,
        ps.activity_level,
        ps.formatted_tags,
        ps.creator_name,
        ps.creator_reputation,
        ps.total_questions_by_user,
        ps.total_answers_by_user,
        ps.avg_question_score_by_user,
        ps.avg_answer_score_by_user,
        CASE 
            WHEN ps.post_status = 'Active' AND ps.engagement_level = 'High Engagement' THEN 'Prime Content'
            WHEN ps.post_status <> 'Active' AND ps.score > 50 THEN 'Legacy High Value'
            WHEN ps.popularity_level = 'Popular' AND ps.score_category = 'High' THEN 'High Impact'
            ELSE 'Standard Content'
        END as content_classification,
        COALESCE(
            (SELECT COUNT(*) 
             FROM Posts p6 
             WHERE p6.ParentId = ps.Id AND p6.PostTypeId = 2),
            0
        ) as answer_count,
        COALESCE(
            (SELECT MAX(p7.Score) 
             FROM Posts p7 
             WHERE p7.ParentId = ps.Id AND p7.PostTypeId = 2),
            0
        ) as max_answer_score,
        COALESCE(
            (SELECT COUNT(*) 
             FROM Votes v2 
             WHERE v2.PostId IN (ps.Id, ps.Id) AND v2.VoteTypeId = 5),
            0
        ) as favorite_count,
        COALESCE(
            (SELECT AVG(p8.Score) 
             FROM Posts p8 
             WHERE p8.ParentId = ps.Id AND p8.PostTypeId = 2 AND p8.Score > 0),
            0
        ) as avg_answer_score,
        COALESCE(
            (SELECT MAX(p9.LastActivityDate) 
             FROM Posts p9 
             WHERE p9.ParentId = ps.Id),
            ps.CreationDate
        ) as last_activity_datetime,
        CASE 
            WHEN ps.answer_count > 5 AND ps.avg_answer_score > 10 THEN 'Well Answered'
            WHEN ps.answer_count > 2 THEN 'Has Answers'
            ELSE 'No Answers Yet'
        END as question_completion_status,
        CASE 
            WHEN ps.days_since_creation < 7 AND ps.score > 50 THEN 'Hot Trending'
            WHEN ps.days_since_creation BETWEEN 7 AND 30 AND ps.score > 30 THEN 'Recently Popular'
            ELSE 'Historical'
        END as timeliness_category
    FROM PostStats ps
    WHERE ps.PostTypeId = 1 -- Only questions
),
AnswerMetrics AS (
    SELECT 
        ps.Id,
        ps.PostTypeId,
        ps.OwnerUserId,
        ps.Score,
        ps.ViewCount,
        ps.CreationDate,
        ps.Title,
        ps.Tags,
        ps.rn,
        ps.prev_score,
        ps.prev_views,
        ps.avg_score_3posts,
        ps.score_category,
        ps.positive_comments_count,
        ps.upvotes_count,
        ps.downvotes_count,
        ps.clean_tags,
        ps.days_since_creation,
        ps.post_status,
        ps.gold_badges_count,
        ps.silver_badges_count,
        ps.bronze_badges_count,
        ps.ownership_type,
        ps.unique_editors_count,
        ps.edit_count,
        ps.engagement_level,
        ps.popularity_level,
        ps.age_category,
        ps.net_votes,
        ps.voting_status,
        ps.reception_status,
        ps.activity_level,
        ps.formatted_tags,
        ps.creator_name,
        ps.creator_reputation,
        ps.total_questions_by_user,
        ps.total_answers_by_user,
        ps.avg_question_score_by_user,
        ps.avg_answer_score_by_user,
        CASE 
            WHEN ps.OwnerUserId IS NOT NULL AND ps.OwnerUserId IN (
                SELECT Id FROM Users WHERE Reputation > 10000
            ) THEN 'Expert Level'
            WHEN ps.OwnerUserId IS NOT NULL AND ps.OwnerUserId IN (
                SELECT Id FROM Users WHERE Reputation BETWEEN 1000 AND 10000
            ) THEN 'Intermediate Level'
            ELSE 'Beginner Level'
        END as user_level,
        COALESCE(
            (SELECT psq.Title 
             FROM Posts psq 
             WHERE psq.Id = ps.ParentId),
            'Unknown Question'
        ) as answer_to_question,
        COALESCE(
            (SELECT psq.OwnerUserId 
             FROM Posts psq 
             WHERE psq.Id = ps.ParentId),
            -1
        ) as question_owner_id,
        COALESCE(
            (SELECT COUNT(*) 
             FROM Comments c2 
             WHERE c2.PostId = ps.Id AND c2.UserId IS NOT NULL),
            0
        ) as user_comments_count,
        COALESCE(
            (SELECT COUNT(*) 
             FROM Votes v3 
             WHERE v3.PostId = ps.Id AND v3.UserId IS NOT NULL),
            0
        ) as total_user_votes,
        COALESCE(
            (SELECT COUNT(*) 
             FROM Badges b2 
             WHERE b2.UserId = ps.OwnerUserId AND b2.Name IN (
                 SELECT Name FROM Badges WHERE UserId = ps.OwnerUserId
                 GROUP BY Name 
                 HAVING COUNT(*) > 1
             )),
            0
        ) as multiple_badges_count
    FROM PostStats ps
    WHERE ps.PostTypeId = 2 -- Only answers
),
CombinedMetrics AS (
    SELECT 
        'Question' as content_type,
        qm.Id,
        qm.PostTypeId,
        qm.OwnerUserId,
        qm.Score,
        qm.ViewCount,
        qm.CreationDate,
        qm.Title,
        qm.Tags,
        qm.rn,
        qm.prev_score,
        qm.prev_views,
        qm.avg_score_3posts,
        qm.score_category,
        qm.positive_comments_count,
        qm.upvotes_count,
        qm.downvotes_count,
        qm.clean_tags,
        qm.days_since_creation,
        qm.post_status,
        qm.gold_badges_count,
        qm.silver_badges_count,
        qm.bronze_badges_count,
        qm.ownership_type,
        qm.unique_editors_count,
        qm.edit_count,
        qm.engagement_level,
        qm.popularity_level,
        qm.age_category,
        qm.net_votes,
        qm.voting_status,
        qm.reception_status,
        qm.activity_level,
        qm.formatted_tags,
        qm.creator_name,
        qm.creator_reputation,
        qm.total_questions_by_user,
        qm.total_answers_by_user,
        qm.avg_question_score_by_user,
        qm.avg_answer_score_by_user,
        qm.content_classification,
        qm.answer_count,
        qm.max_answer_score,
        qm.favorite_count,
        qm.avg_answer_score,
        qm.last_activity_datetime,
        qm.question_completion_status,
        qm.timeliness_category
    FROM QuestionMetrics qm
    UNION ALL
    SELECT 
        'Answer' as content_type,
        am.Id,
        am.PostTypeId,
        am.OwnerUserId,
        am.Score,
        am.ViewCount,
        am.CreationDate,
        am.Title,
        am.Tags,
        am.rn,
        am.prev_score,
        am.prev_views,
        am.avg_score_3posts,
        am.score_category,
        am.positive_comments_count,
        am.upvotes_count,
        am.downvotes_count,
        am.clean_tags,
        am.days_since_creation,
        am.post_status,
        am.gold_badges_count,
        am.silver_badges_count,
        am.bronze_badges_count,
        am.ownership_type,
        am.unique_editors_count,
        am.edit_count,
        am.engagement_level,
        am.popularity_level,
        am.age_category,
        am.net_votes,
        am.voting_status,
        am.reception_status,
        am.activity_level,
        am.formatted_tags,
        am.creator_name,
        am.creator_reputation,
        am.total_questions_by_user,
        am.total_answers_by_user,
        am.avg_question_score_by_user,
        am.avg_answer_score_by_user,
        NULL as content_classification,
        NULL as answer_count,
        NULL as max_answer_score,
        NULL as favorite_count,
        NULL as avg_answer_score,
        NULL as last_activity_datetime,
        NULL as question_completion_status,
        NULL as timeliness_category
    FROM AnswerMetrics am
),
FinalAggregation AS (
    SELECT 
        cm.content_type,
        cm.Id,
        cm.PostTypeId,
        cm.OwnerUserId,
        cm.Score,
        cm.ViewCount,
        cm.CreationDate,
        cm.Title,
        cm.Tags,
        cm.rn,
        cm.prev_score,
        cm.prev_views,
        cm.avg_score_3posts,
        cm.score_category,
        cm.positive_comments_count,
        cm.upvotes_count,
        cm.downvotes_count,
        cm.clean_tags,
        cm.days_since_creation,
        cm.post_status,
        cm.gold_badges_count,
        cm.silver_badges_count,
        cm.bronze_badges_count,
        cm.ownership_type,
        cm.unique_editors_count,
        cm.edit_count,
        cm.engagement_level,
        cm.popularity_level,
        cm.age_category,
        cm.net_votes,
        cm.voting_status,
        cm.reception_status,
        cm.activity_level,
        cm.formatted_tags,
        cm.creator_name,
        cm.creator_reputation,
        cm.total_questions_by_user,
        cm.total_answers_by_user,
        cm.avg_question_score_by_user,
        cm.avg_answer_score_by_user,
        cm.content_classification,
        cm.answer_count,
        cm.max_answer_score,
        cm.favorite_count,
        cm.avg_answer_score,
        cm.last_activity_datetime,
        cm.question_completion_status,
        cm.timeliness_category,
        AVG(cm.Score) OVER (PARTITION BY cm.OwnerUserId) as avg_user_score,
        COUNT(*) OVER (PARTITION BY cm.OwnerUserId) as total_user_posts,
        RANK() OVER (ORDER BY cm.Score DESC) as global_rank_by_score,
        RANK() OVER (ORDER BY cm.ViewCount DESC) as global_rank_by_views,
        PERCENT_RANK() OVER (ORDER BY cm.Score) as score_percentile,
        DENSE_RANK() OVER (ORDER BY cm.CreationDate) as chronological_rank
    FROM CombinedMetrics cm
)
SELECT 
    fa.content_type,
    fa.Id,
    fa.PostTypeId,
    fa.OwnerUserId,
    fa.Score,
    fa.ViewCount,
    fa.CreationDate,
    fa.Title,
    fa.Tags,
    fa.rn,
    fa.prev_score,
    fa.prev_views,
    fa.avg_score_3posts,
    fa.score_category,
    fa.positive_comments_count,
    fa.upvotes_count,
    fa.downvotes_count,
    fa.clean_tags,
    fa.days_since_creation,
    fa.post_status,
    fa.gold_badges_count,
    fa.silver_badges_count,
    fa.bronze_badges_count,
    fa.ownership_type,
    fa.unique_editors_count,
    fa.edit_count,
    fa.engagement_level,
    fa.popularity_level,
    fa.age_category,
    fa.net_votes,
    fa.voting_status,
    fa.reception_status,
    fa.activity_level,
    fa.formatted_tags,
    fa.creator_name,
    fa.creator_reputation,
    fa.total_questions_by_user,
    fa.total_answers_by_user,
    fa.avg_question_score_by_user,
    fa.avg_answer_score_by_user,
    fa.content_classification,
    fa.answer_count,
    fa.max_answer_score,
    fa.favorite_count,
    fa.avg_answer_score,
    fa.last_activity_datetime,
    fa.question_completion_status,
    fa.timeliness_category,
    fa.avg_user_score,
    fa.total_user_posts,
    fa.global_rank_by_score,
    fa.global_rank_by_views,
    fa.score_percentile,
    fa.chronological_rank,
    CASE 
        WHEN fa.net_votes > 0 AND fa.score > 100 THEN 'High Quality Content'
        WHEN fa.net_votes <= 0 AND fa.score <= 50 THEN 'Low Quality Content'
        WHEN fa.global_rank_by_score <= 10 THEN 'Top Ranked Content'
        WHEN fa.global_rank_by_views <= 20 THEN 'Highly Viewed Content'
        ELSE 'Standard Content'
    END as quality_assessment,
    CASE 
        WHEN fa.days_since_creation <= 30 AND fa.avg_score_3posts > 50 THEN 'Recently High Performing'
        WHEN fa.days_since_creation > 30 AND fa.avg_score_3posts > 30 THEN 'Established Performer'
        WHEN fa.days_since_creation > 30 AND fa.score > 100 THEN 'Legacy High Performer'
        ELSE 'Standard Performer'
    END as performance_category,
    CASE 
        WHEN fa.engagement_level = 'High Engagement' AND 
             fa.popularity_level = 'Popular' AND 
             fa.activity_level = 'Active' THEN 'Premium Content'
        WHEN fa.engagement_level = 'Medium Engagement' OR 
             fa.popularity_level = 'Moderate' THEN 'Good Content'
        ELSE 'Standard Content'
    END as content_category,
    CASE 
        WHEN fa.total_user_posts > 100 THEN 'Active Contributor'
        WHEN fa.total_user_posts > 50 THEN 'Regular Contributor'
        WHEN fa.total_user_posts > 10 THEN 'Occasional Contributor'
        ELSE 'New Contributor'
    END as contributor_status,
    CASE 
        WHEN LENGTH(fa.formatted_tags) > 0 AND LENGTH(fa.formatted_tags) < 50 THEN 'Short Tags'
        WHEN LENGTH(fa.formatted_tags) >= 50 AND LENGTH(fa.formatted_tags) < 150 THEN 'Medium Tags'
        ELSE 'Long Tags'
    END as tag_length_category,
    COALESCE(
        (SELECT CONCAT('User ', fa.OwnerUserId, ' with ', fa.gold_badges_count, ' Gold, ', 
                       fa.silver_badges_count, ' Silver, ', fa.bronze_badges_count, ' Bronze')
         FROM DUAL),
        'No Badge Info'
    ) as user_badge_summary
FROM FinalAggregation fa
WHERE fa.Score IS NOT NULL 
  AND fa.OwnerUserId IS NOT NULL
  AND (fa.content_type = 'Question' OR fa.content_type = 'Answer')
  AND fa.days_since_creation > 0
  AND (fa.post_status = 'Active' OR fa.post_status = 'Reopened' OR fa.post_status = 'Duplicate')
ORDER BY fa.Score DESC, fa.ViewCount DESC, fa.CreationDate DESC
LIMIT 10000;