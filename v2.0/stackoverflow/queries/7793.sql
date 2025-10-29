-- {"query": "7793.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "qwen3-coder", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2102, "output_tokens": 2012}
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
        COUNT(*) OVER (PARTITION BY p.OwnerUserId) as user_post_count,
        AVG(p.Score) OVER (PARTITION BY p.OwnerUserId) as avg_user_score,
        LAG(p.Score, 1) OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate) as prev_score
    FROM Posts p
    WHERE p.PostTypeId IN (1, 2) AND p.CreationDate >= '2020-01-01'
),
UserStats AS (
    SELECT 
        u.Id as UserId,
        u.Reputation,
        u.DisplayName,
        u.Views,
        u.UpVotes,
        u.DownVotes,
        COUNT(DISTINCT r.Id) FILTER (WHERE r.PostTypeId = 1) as user_question_count,
        SUM(CASE WHEN r.PostTypeId = 2 THEN 1 ELSE 0 END) as user_answer_count,
        AVG(CAST(r.Score AS DOUBLE PRECISION)) as avg_user_post_score
    FROM Users u
    LEFT JOIN RankedPosts r ON u.Id = r.OwnerUserId
    GROUP BY u.Id, u.Reputation, u.DisplayName, u.Views, u.UpVotes, u.DownVotes
),
QuestionTagStats AS (
    SELECT 
        p.Id,
        p.Title,
        p.Score,
        p.ViewCount,
        p.AnswerCount,
        p.CommentCount,
        p.FavoriteCount,
        p.Tags,
        -- normalize tags into array (works in multiple dialects that support split functions; keep Postgres functions here)
        STRING_TO_ARRAY(REPLACE(REPLACE(p.Tags, '<', ''), '>', ''), ' ') as tag_array,
        CASE 
            WHEN p.Tags IS NOT NULL AND p.Tags != '' THEN 
                (SELECT STRING_AGG(tag, ', ') 
                 FROM UNNEST(STRING_TO_ARRAY(REPLACE(REPLACE(p.Tags, '<', ''), '>', ''), ' ')) as tag
                 WHERE tag IN ('sql', 'python', 'javascript', 'java', 'c++')
                )
            ELSE NULL 
        END as tech_tags,
        (SELECT COUNT(*) 
         FROM Posts r 
         WHERE r.ParentId = p.Id 
           AND r.PostTypeId = 2 
           AND r.Score > 0
        ) as positive_answer_count,
        (SELECT MAX(ph.CreationDate) 
         FROM PostHistory ph 
         WHERE ph.PostId = p.Id 
           AND ph.PostHistoryTypeId IN (1, 4, 2, 5, 3, 6)
        ) as last_edit_date
    FROM Posts p
    WHERE p.PostTypeId = 1
),
ComplexCalculations AS (
    SELECT 
        qs.Id,
        qs.Title,
        qs.Score,
        qs.ViewCount,
        qs.AnswerCount,
        qs.CommentCount,
        qs.FavoriteCount,
        qs.tech_tags,
        qs.positive_answer_count,
        qs.last_edit_date,
        CASE 
            WHEN qs.Score > 0 THEN 'High'
            WHEN qs.Score BETWEEN -10 AND 0 THEN 'Medium'
            ELSE 'Low'
        END as score_category,
        CASE 
            WHEN qs.ViewCount > 1000 THEN 'Popular'
            WHEN qs.ViewCount BETWEEN 100 AND 1000 THEN 'Moderate'
            ELSE 'Low'
        END as popularity_level,
        (qs.ViewCount - qs.AnswerCount) as view_answer_difference,
        COALESCE((qs.Score * 100.0 / NULLIF(qs.ViewCount, 0)), 0) as score_to_view_ratio,
        DENSE_RANK() OVER (ORDER BY qs.ViewCount DESC) as view_rank,
        RANK() OVER (ORDER BY qs.Score DESC) as score_rank,
        NTILE(4) OVER (ORDER BY qs.AnswerCount) as answer_quartile
    FROM QuestionTagStats qs
),
FinalAnalysis AS (
    SELECT 
        ca.Id,
        ca.Title,
        ca.Score,
        ca.ViewCount,
        ca.AnswerCount,
        ca.CommentCount,
        ca.FavoriteCount,
        ca.tech_tags,
        ca.positive_answer_count,
        ca.last_edit_date,
        ca.score_category,
        ca.popularity_level,
        ca.view_answer_difference,
        ca.score_to_view_ratio,
        ca.view_rank,
        ca.score_rank,
        ca.answer_quartile,
        us.UserId,
        us.DisplayName,
        us.Reputation,
        us.user_question_count,
        us.user_answer_count,
        us.avg_user_post_score,
        CASE 
            WHEN ca.Score > (SELECT AVG(Score) FROM Posts WHERE PostTypeId = 1) 
                 AND ca.ViewCount > (SELECT AVG(ViewCount) FROM Posts WHERE PostTypeId = 1)
            THEN 'Above Average'
            ELSE 'Below Average'
        END as performance_category,
        CASE 
            WHEN ca.Score >= 100 AND ca.AnswerCount >= 5 AND ca.ViewCount >= 1000
            THEN 'High Quality'
            ELSE 'Standard'
        END as quality_level,
        NULLIF(
            ROUND(
                (COALESCE(ca.ViewCount, 0) + 
                 COALESCE(ca.AnswerCount, 0) * 5 + 
                 COALESCE(ca.CommentCount, 0) * 2 +
                 COALESCE(ca.Score, 0) * 3 +
                 COALESCE(ca.FavoriteCount, 0) * 10) / 
                NULLIF((COALESCE(ca.AnswerCount, 0) + 1), 0), 2
            ), 0
        ) as weighted_score
    FROM ComplexCalculations ca
    INNER JOIN UserStats us ON EXISTS (
        SELECT 1 FROM Posts p WHERE p.OwnerUserId = us.UserId AND p.PostTypeId = 1 AND p.Id = ca.Id
    )
    WHERE ca.ViewCount IS NOT NULL AND ca.Score IS NOT NULL
    AND EXISTS (
        SELECT 1 
        FROM PostHistory ph 
        WHERE ph.PostId = ca.Id 
          AND ph.CreationDate >= ca.last_edit_date - INTERVAL '1 year'
    )
),
CTE_ComplexJoin AS (
    SELECT 
        fa.*,
        (SELECT STRING_AGG(b.Name, ', ') 
         FROM Badges b 
         WHERE b.UserId = fa.UserId 
           AND b.Date >= '2020-01-01'
        ) as recent_badges,
        (SELECT COUNT(*) 
         FROM Votes v 
         WHERE v.PostId = fa.Id 
           AND v.VoteTypeId = 2
        ) as upvote_count,
        (SELECT COUNT(*) 
         FROM Comments c 
         WHERE c.PostId = fa.Id
        ) as comment_count,
        (SELECT COUNT(*) 
         FROM PostLinks pl 
         WHERE pl.PostId = fa.Id
        ) as link_count,
        (SELECT STRING_AGG(ph.Comment, '; ') 
         FROM PostHistory ph 
         WHERE ph.PostId = fa.Id 
           AND ph.PostHistoryTypeId IN (10, 11, 12, 13)
        ) as history_comments
    FROM FinalAnalysis fa
)
SELECT 
    cte.Id,
    cte.Title,
    cte.Score,
    cte.ViewCount,
    cte.AnswerCount,
    cte.CommentCount,
    cte.FavoriteCount,
    cte.tech_tags,
    cte.positive_answer_count,
    cte.last_edit_date,
    cte.score_category,
    cte.popularity_level,
    cte.view_answer_difference,
    cte.score_to_view_ratio,
    cte.view_rank,
    cte.score_rank,
    cte.answer_quartile,
    cte.UserId,
    cte.DisplayName,
    cte.Reputation,
    cte.user_question_count,
    cte.user_answer_count,
    cte.avg_user_post_score,
    cte.performance_category,
    cte.quality_level,
    cte.weighted_score,
    cte.recent_badges,
    cte.upvote_count,
    cte.comment_count,
    cte.link_count,
    cte.history_comments,
    CASE 
        WHEN cte.weighted_score > (SELECT AVG(weighted_score) FROM CTE_ComplexJoin) 
        THEN (SELECT COUNT(*) FROM CTE_ComplexJoin WHERE weighted_score > cte.weighted_score)
        ELSE (SELECT COUNT(*) FROM CTE_ComplexJoin WHERE weighted_score <= cte.weighted_score)
    END as ranking_position,
    ROW_NUMBER() OVER (ORDER BY cte.weighted_score DESC) as row_num,
    ROUND(
        (SELECT AVG(weighted_score) FROM CTE_ComplexJoin) - 
        (SELECT AVG(weighted_score) FROM CTE_ComplexJoin WHERE weighted_score <= cte.weighted_score)
    , 2) as percentile_rank
FROM CTE_ComplexJoin cte
WHERE cte.ViewCount >= 100
  AND cte.Score >= -50
  AND cte.last_edit_date IS NOT NULL
  AND cte.tech_tags IS NOT NULL
  AND LENGTH(cte.tech_tags) >= 5
  AND (cte.recent_badges IS NOT NULL AND cte.recent_badges != '')
ORDER BY cte.weighted_score DESC
LIMIT 2000;