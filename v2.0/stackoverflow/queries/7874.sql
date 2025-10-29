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
        ROW_NUMBER() OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate DESC) AS rn,
        LAG(p.Score) OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate) AS prev_score,
        LAG(p.ViewCount) OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate) AS prev_views,
        AVG(p.Score) OVER (PARTITION BY p.OwnerUserId ROWS BETWEEN 2 PRECEDING AND CURRENT ROW) AS avg_score_3posts,
        CASE 
            WHEN p.Tags IS NOT NULL AND p.Tags <> '' THEN 
                -- split tags like '<tag1><tag2>' into array and count elements in a dialect-agnostic way
                (LENGTH(TRIM(BOTH '<' FROM TRIM(BOTH '>' FROM p.Tags)))
                 - LENGTH(REPLACE(TRIM(BOTH '<' FROM TRIM(BOTH '>' FROM p.Tags)), '><', '')) ) / NULLIF(LENGTH('><'),0) + 1
            ELSE 0 
        END AS tag_count
    FROM Posts p
    WHERE p.PostTypeId IN (1, 2)
),
UserStats AS (
    SELECT 
        u.Id AS UserId,
        u.Reputation,
        u.Views,
        u.UpVotes,
        u.DownVotes,
        COUNT(DISTINCT p.Id) AS post_count,
        SUM(p.Score) AS total_score,
        AVG(p.Score) AS avg_score,
        MAX(p.CreationDate) AS last_post_date,
        -- string aggregation using ANSI LISTAGG-style; use fallback to GROUP_CONCAT if available in target dialect
        STRING_AGG(DISTINCT p.Title, ', ') AS recent_titles
    FROM Users u
    LEFT JOIN Posts p ON u.Id = p.OwnerUserId
    WHERE p.CreationDate >= DATE '2022-01-01'
    GROUP BY u.Id, u.Reputation, u.Views, u.UpVotes, u.DownVotes
),
TagAnalysis AS (
    SELECT 
        t.TagName,
        t.Count AS tag_count,
        t.ExcerptPostId,
        t.WikiPostId,
        p.Id AS related_post_id,
        p.PostTypeId,
        p.Score,
        p.ViewCount,
        p.CreationDate,
        CASE WHEN p.Score > 10 THEN 'High' 
             WHEN p.Score > 5 THEN 'Medium' 
             ELSE 'Low' END AS score_category,
        DENSE_RANK() OVER (ORDER BY t.Count DESC) AS popularity_rank
    FROM Tags t
    INNER JOIN Posts p ON p.Tags LIKE '%' || t.TagName || '%'
    WHERE p.PostTypeId = 1 AND p.CreationDate >= DATE '2023-01-01'
),
ComplexPosts AS (
    SELECT 
        rp.Id,
        rp.PostTypeId,
        rp.OwnerUserId,
        rp.Score,
        rp.ViewCount,
        rp.CreationDate,
        rp.Title,
        rp.Tags,
        rp.AnswerCount,
        rp.CommentCount,
        rp.FavoriteCount,
        rp.rn,
        rp.prev_score,
        rp.prev_views,
        rp.avg_score_3posts,
        rp.tag_count,
        us.Reputation,
        us.post_count,
        us.total_score,
        ta.TagName,
        ta.tag_count AS related_tag_count,
        CASE 
            WHEN rp.prev_score IS NOT NULL AND rp.prev_views IS NOT NULL THEN 
                (rp.Score - rp.prev_score) + (rp.ViewCount - rp.prev_views)
            ELSE NULL 
        END AS activity_delta,
        CASE 
            WHEN rp.avg_score_3posts > 15 THEN 'Highly Active'
            WHEN rp.avg_score_3posts > 10 THEN 'Active'
            WHEN rp.avg_score_3posts > 5 THEN 'Moderate'
            ELSE 'Low'
        END AS activity_level,
        CASE WHEN rp.tag_count > 5 THEN 'Multi-tagged' ELSE 'Single-tagged' END AS tag_complexity,
        (SELECT COUNT(*) FROM Comments c WHERE c.PostId = rp.Id) AS comment_count,
        (SELECT COUNT(*) FROM Votes v WHERE v.PostId = rp.Id AND v.VoteTypeId IN (2,3)) AS vote_count,
        CASE 
            WHEN rp.Score > (SELECT AVG(Score) FROM Posts WHERE PostTypeId = 1) 
            THEN 1 ELSE 0 
        END AS above_avg_score
    FROM RankedPosts rp
    JOIN UserStats us ON rp.OwnerUserId = us.UserId
    LEFT JOIN TagAnalysis ta ON ta.related_post_id = rp.Id
    WHERE rp.rn = 1
),
FinalAnalysis AS (
    SELECT 
        cp.Id AS PostId,
        cp.OwnerUserId,
        cp.Score AS current_score,
        cp.ViewCount,
        cp.Title,
        cp.Tags,
        cp.tag_count AS TagCount,
        cp.Reputation,
        cp.post_count,
        cp.total_score,
        cp.TagName,
        cp.related_tag_count,
        cp.activity_delta,
        cp.activity_level,
        cp.tag_complexity,
        cp.comment_count,
        cp.vote_count,
        cp.above_avg_score,
        RANK() OVER (ORDER BY cp.total_score DESC) AS rank_by_total_score,
        DENSE_RANK() OVER (ORDER BY cp.Reputation DESC) AS rank_by_reputation,
        PERCENT_RANK() OVER (ORDER BY cp.Score) AS score_percentile,
        NTILE(4) OVER (ORDER BY cp.Score) AS score_quartile,
        CASE 
            WHEN cp.vote_count > 100 AND cp.comment_count > 20 THEN 'High Engagement'
            WHEN cp.vote_count > 50 OR cp.comment_count > 10 THEN 'Medium Engagement'
            ELSE 'Low Engagement'
        END AS engagement_level,
        ROW_NUMBER() OVER (PARTITION BY cp.OwnerUserId ORDER BY cp.CreationDate) AS user_post_rank,
        cp.CreationDate
    FROM ComplexPosts cp
)
SELECT 
    fa.PostId,
    fa.OwnerUserId,
    fa.current_score,
    fa.ViewCount,
    fa.Title,
    fa.Tags,
    fa.TagCount,
    fa.Reputation,
    fa.post_count,
    fa.total_score,
    fa.TagName,
    fa.related_tag_count,
    fa.activity_delta,
    fa.activity_level,
    fa.tag_complexity,
    fa.comment_count,
    fa.vote_count,
    fa.above_avg_score,
    fa.rank_by_total_score,
    fa.rank_by_reputation,
    fa.score_percentile,
    fa.score_quartile,
    fa.engagement_level,
    fa.user_post_rank,
    CASE 
        WHEN fa.above_avg_score = 1 AND fa.engagement_level = 'High Engagement' THEN 'Premium Post'
        WHEN fa.above_avg_score = 1 OR fa.engagement_level = 'High Engagement' THEN 'Notable Post'
        ELSE 'Regular Post'
    END AS post_classification,
    CASE 
        WHEN fa.TagCount > 5 AND fa.related_tag_count > 3 THEN 'Complex Topic'
        WHEN fa.TagCount > 3 THEN 'Moderate Topic'
        WHEN fa.TagCount >= 1 THEN 'Simple Topic'
        ELSE 'Unknown Topic'
    END AS topic_complexity,
    COALESCE(fa.current_score, 0) + COALESCE(fa.ViewCount, 0) + COALESCE(fa.comment_count, 0) * 2 + COALESCE(fa.vote_count, 0) * 3 AS composite_metric,
    CONCAT(fa.Title, ' - ', COALESCE(fa.TagName, '')) AS title_tag_combo,
    (SELECT COUNT(*) FROM Posts p2 WHERE p2.OwnerUserId = fa.OwnerUserId AND p2.CreationDate < fa.CreationDate) AS prior_posts_count,
    (SELECT MAX(Score) FROM Posts p3 WHERE p3.OwnerUserId = fa.OwnerUserId AND p3.CreationDate < fa.CreationDate) AS max_prior_score,
    (SELECT MIN(CreationDate) FROM Posts p4 WHERE p4.OwnerUserId = fa.OwnerUserId) AS first_post_date,
    (SELECT COUNT(*) FROM Posts p5 WHERE p5.OwnerUserId = fa.OwnerUserId AND p5.PostTypeId = 2) AS answer_count,
    (SELECT COUNT(*) FROM Posts p6 WHERE p6.OwnerUserId = fa.OwnerUserId AND p6.PostTypeId = 1) AS question_count,
    CASE WHEN EXISTS (
        SELECT 1 FROM Posts p7 WHERE p7.ParentId = fa.PostId AND p7.PostTypeId = 2 AND p7.Score > 10
    ) THEN 'Has High Scoring Answer' ELSE 'No High Scoring Answer' END AS has_high_scoring_answer,
    CASE WHEN EXISTS (
        SELECT 1 FROM Comments c2 WHERE c2.PostId = fa.PostId AND c2.UserId IS NOT NULL
    ) THEN 'Has User Comments' ELSE 'No User Comments' END AS has_user_comments,
    CASE WHEN EXISTS (
        SELECT 1 FROM Votes v2 WHERE v2.PostId = fa.PostId AND v2.VoteTypeId = 5
    ) THEN 'Has Favorites' ELSE 'No Favorites' END AS has_favorites,
    (SELECT AVG(Score) FROM Posts p8 WHERE p8.OwnerUserId = fa.OwnerUserId) AS user_avg_score,
    (SELECT AVG(ViewCount) FROM Posts p9 WHERE p9.OwnerUserId = fa.OwnerUserId) AS user_avg_views,
    (SELECT AVG(comment_count) FROM (
        SELECT COUNT(*) AS comment_count FROM Comments c3 WHERE c3.PostId IN (
            SELECT Id FROM Posts p10 WHERE p10.OwnerUserId = fa.OwnerUserId
        ) GROUP BY c3.PostId
    ) sub) AS user_avg_comments_per_post,
    (SELECT COUNT(*) FROM Posts p11 WHERE p11.OwnerUserId = fa.OwnerUserId AND p11.Score > 0) AS positive_score_posts,
    (SELECT COUNT(*) FROM Posts p12 WHERE p12.OwnerUserId = fa.OwnerUserId AND p12.Score < 0) AS negative_score_posts,
    (SELECT COUNT(*) FROM Posts p13 WHERE p13.OwnerUserId = fa.OwnerUserId AND p13.Score = 0) AS zero_score_posts
FROM FinalAnalysis fa
WHERE EXISTS (
    SELECT 1 FROM Users u2 WHERE u2.Id = fa.OwnerUserId AND u2.Reputation > 1000
)
AND EXISTS (
    SELECT 1 FROM Posts p14 WHERE p14.OwnerUserId = fa.OwnerUserId AND p14.CreationDate >= DATE '2022-01-01'
)
ORDER BY fa.total_score DESC, fa.Reputation DESC
LIMIT 1000;