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
        p.AnswerCount,
        p.CommentCount,
        p.FavoriteCount,
        p.ParentId,
        ROW_NUMBER() OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate DESC) as rn,
        LAG(p.Score) OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate) as prev_score,
        AVG(p.Score) OVER (PARTITION BY p.PostTypeId ORDER BY p.CreationDate ROWS BETWEEN 10 PRECEDING AND CURRENT ROW) as moving_avg_score,
        DENSE_RANK() OVER (ORDER BY p.Score DESC) as score_rank
    FROM Posts p
    WHERE p.PostTypeId IN (1, 2) 
      AND p.CreationDate >= DATE '2021-01-01'
),
UserActivity AS (
    SELECT 
        u.Id as UserId,
        u.DisplayName,
        u.Reputation,
        u.Views,
        u.UpVotes,
        u.DownVotes,
        u.LastAccessDate,
        COUNT(DISTINCT p.Id) as total_posts,
        COUNT(DISTINCT CASE WHEN p.PostTypeId = 1 THEN p.Id END) as questions,
        COUNT(DISTINCT CASE WHEN p.PostTypeId = 2 THEN p.Id END) as answers,
        SUM(p.Score) as total_score,
        AVG(p.Score) as avg_score,
        MAX(p.CreationDate) as last_post_date,
        STRING_AGG(DISTINCT p.Tags, '; ') as tag_experience,
        CASE WHEN MAX(p.CreationDate) >= DATE '2022-01-01' THEN 'Active' ELSE 'Inactive' END as user_status
    FROM Users u
    LEFT JOIN Posts p ON u.Id = p.OwnerUserId
    GROUP BY u.Id, u.DisplayName, u.Reputation, u.Views, u.UpVotes, u.DownVotes, u.LastAccessDate
),
PostMetrics AS (
    SELECT 
        rp.Id,
        rp.PostTypeId,
        rp.Score,
        rp.ViewCount,
        rp.CreationDate,
        rp.Title,
        rp.Tags,
        rp.OwnerUserId,
        rp.AnswerCount,
        rp.CommentCount,
        rp.FavoriteCount,
        rp.ParentId,
        rp.rn,
        rp.prev_score,
        rp.moving_avg_score,
        rp.score_rank,
        CASE WHEN rp.prev_score IS NOT NULL THEN (rp.Score - rp.prev_score) ELSE 0 END as score_change,
        CASE WHEN rp.moving_avg_score > 0 THEN (rp.Score - rp.moving_avg_score) / rp.moving_avg_score ELSE 0 END as percentile_score,
        CASE WHEN rp.Score > 100 AND rp.AnswerCount > 0 THEN 1 ELSE 0 END as high_value_post,
        CASE 
            WHEN rp.Tags IS NOT NULL AND rp.Tags LIKE '%<%' THEN array_length(string_to_array(substring(rp.Tags FROM 2 FOR char_length(rp.Tags)-2), '><'), 1)
            ELSE 0 
        END as tag_count,
        CASE 
            WHEN rp.PostTypeId = 1 THEN 
                CASE 
                    WHEN rp.AnswerCount = 0 THEN 'No Answers'
                    WHEN rp.AnswerCount < 3 THEN 'Few Answers'
                    WHEN rp.AnswerCount BETWEEN 3 AND 10 THEN 'Many Answers'
                    ELSE 'Lots of Answers'
                END
            ELSE 'Not a Question'
        END as answer_status,
        (rp.Title || ' - ' || rp.Score || ' points') as title_score
    FROM RankedPosts rp
),
AggregatedData AS (
    SELECT 
        pm.Id,
        pm.PostTypeId,
        pm.Score,
        pm.ViewCount,
        pm.CreationDate,
        pm.Title,
        pm.Tags,
        pm.OwnerUserId,
        pm.AnswerCount,
        pm.CommentCount,
        pm.FavoriteCount,
        pm.ParentId,
        pm.rn,
        pm.prev_score,
        pm.moving_avg_score,
        pm.score_rank,
        pm.score_change,
        pm.percentile_score,
        pm.high_value_post,
        pm.tag_count,
        pm.answer_status,
        pm.title_score,
        ua.DisplayName as owner_name,
        ua.Reputation as owner_reputation,
        ua.total_posts,
        ua.questions,
        ua.answers,
        ua.total_score,
        ua.avg_score,
        ua.last_post_date,
        ua.tag_experience,
        ua.user_status,
        CASE 
            WHEN pm.Score >= 100 AND pm.ViewCount >= 1000 THEN 'Popular'
            WHEN pm.Score >= 50 AND pm.ViewCount >= 500 THEN 'Moderate'
            WHEN pm.Score >= 10 AND pm.ViewCount >= 100 THEN 'Low'
            ELSE 'Very Low'
        END as popularity_level,
        CAST(DATE_PART('day', CAST('2024-10-01' AS timestamp) - pm.CreationDate) AS integer) as days_since_post,
        CASE 
            WHEN pm.ViewCount > 0 THEN (pm.Score * 1.0 / pm.ViewCount)
            ELSE 0 
        END as score_per_view,
        COALESCE(SUM(pm.Score) OVER (ORDER BY pm.CreationDate), 0) as cumulative_score,
        COALESCE(AVG(pm.Score) OVER (ORDER BY pm.CreationDate), 0) as cumulative_avg_score
    FROM PostMetrics pm
    LEFT JOIN UserActivity ua ON pm.OwnerUserId = ua.UserId
),
FinalAnalysis AS (
    SELECT 
        ad.Id,
        ad.PostTypeId,
        ad.Score,
        ad.ViewCount,
        ad.CreationDate,
        ad.Title,
        ad.Tags,
        ad.OwnerUserId,
        ad.AnswerCount,
        ad.CommentCount,
        ad.FavoriteCount,
        ad.ParentId,
        ad.rn,
        ad.prev_score,
        ad.moving_avg_score,
        ad.score_rank,
        ad.score_change,
        ad.percentile_score,
        ad.high_value_post,
        ad.tag_count,
        ad.answer_status,
        ad.title_score,
        ad.owner_name,
        ad.owner_reputation,
        ad.total_posts,
        ad.questions,
        ad.answers,
        ad.total_score,
        ad.avg_score,
        ad.last_post_date,
        ad.tag_experience,
        ad.user_status,
        ad.popularity_level,
        ad.days_since_post,
        ad.score_per_view,
        ad.cumulative_score,
        ad.cumulative_avg_score,
        CASE 
            WHEN ad.answer_status = 'No Answers' AND ad.PostTypeId = 1 THEN 'Unanswered Question'
            WHEN ad.answer_status = 'Few Answers' AND ad.PostTypeId = 1 THEN 'Low Engagement Question'
            WHEN ad.answer_status = 'Many Answers' AND ad.PostTypeId = 1 THEN 'High Engagement Question'
            WHEN ad.answer_status = 'Lots of Answers' AND ad.PostTypeId = 1 THEN 'Trending Question'
            ELSE 'Regular Post'
        END as engagement_level,
        CASE 
            WHEN ad.cumulative_avg_score > 100 THEN 'High'
            WHEN ad.cumulative_avg_score > 50 THEN 'Medium'
            WHEN ad.cumulative_avg_score > 10 THEN 'Low'
            ELSE 'Very Low'
        END as cumulative_score_level,
        CASE WHEN ad.owner_reputation > 10000 AND ad.questions > 50 THEN 1 ELSE 0 END as expert_contributor
    FROM AggregatedData ad
)
SELECT 
    fa.Id,
    fa.PostTypeId,
    fa.Score,
    fa.ViewCount,
    fa.CreationDate,
    fa.Title,
    fa.Tags,
    fa.OwnerUserId,
    fa.AnswerCount,
    fa.CommentCount,
    fa.FavoriteCount,
    fa.ParentId,
    fa.rn,
    fa.prev_score,
    fa.moving_avg_score,
    fa.score_rank,
    fa.score_change,
    fa.percentile_score,
    fa.high_value_post,
    fa.tag_count,
    fa.answer_status,
    fa.title_score,
    fa.owner_name,
    fa.owner_reputation,
    fa.total_posts,
    fa.questions,
    fa.answers,
    fa.total_score,
    fa.avg_score,
    fa.last_post_date,
    fa.tag_experience,
    fa.user_status,
    fa.popularity_level,
    fa.days_since_post,
    fa.score_per_view,
    fa.cumulative_score,
    fa.cumulative_avg_score,
    fa.engagement_level,
    fa.cumulative_score_level,
    fa.expert_contributor,
    CASE 
        WHEN fa.score_change > 20 AND fa.prev_score IS NOT NULL THEN 'Major Improvement'
        WHEN fa.score_change > 0 AND fa.prev_score IS NOT NULL THEN 'Minor Improvement'
        WHEN fa.score_change < 0 AND fa.prev_score IS NOT NULL THEN 'Deterioration'
        ELSE 'Stable'
    END as performance_trend,
    CASE 
        WHEN fa.score_rank <= 10 THEN 'Top 10'
        WHEN fa.score_rank <= 50 THEN 'Top 50'
        WHEN fa.score_rank <= 100 THEN 'Top 100'
        ELSE 'Below Top 100'
    END as rank_category
FROM FinalAnalysis fa
WHERE fa.Score > 0 
  AND fa.OwnerUserId IS NOT NULL
  AND fa.CreationDate >= DATE '2020-01-01'
  AND (
    fa.engagement_level IN ('Unanswered Question', 'High Engagement Question', 'Trending Question') 
    OR fa.popularity_level IN ('Popular', 'Moderate')
    OR fa.cumulative_score_level IN ('High', 'Medium')
  )
  AND (
    fa.OwnerUserId IN (
      SELECT UserId 
      FROM Badges 
      WHERE Name IN ('Good Question', 'Great Question', 'Popular Question', 'Notable Question')
    )
    OR fa.expert_contributor = 1
  )
ORDER BY 
    fa.cumulative_score DESC,
    fa.days_since_post ASC,
    fa.score_per_view DESC
LIMIT 1000
OFFSET 0;