WITH monthly_user_activity AS (
    SELECT 
        u.Id AS user_id,
        u.DisplayName,
        DATE_TRUNC('month', p.CreationDate) AS month,
        COUNT(DISTINCT p.Id) AS posts_created,
        COUNT(DISTINCT CASE WHEN v.VoteTypeId = 2 THEN v.Id END) AS upvotes_given,
        COUNT(DISTINCT CASE WHEN v.VoteTypeId = 3 THEN v.Id END) AS downvotes_given,
        COUNT(DISTINCT CASE WHEN pt.Id = 1 AND p.Score >= 10 THEN p.Id END) AS high_score_questions,
        AVG(u.Reputation) OVER (PARTITION BY DATE_TRUNC('month', p.CreationDate)) AS avg_monthly_reputation
    FROM Users u
    INNER JOIN Posts p ON u.Id = p.OwnerUserId
    LEFT JOIN Votes v ON u.Id = v.UserId AND v.PostId = p.Id
    INNER JOIN PostTypes pt ON p.PostTypeId = pt.Id
    WHERE p.CreationDate >= CAST('2024-10-01' AS date) - INTERVAL '1 year'
      AND p.PostTypeId IN (1, 2)
    GROUP BY u.Id, u.DisplayName, DATE_TRUNC('month', p.CreationDate), u.Reputation
),
tag_popularity AS (
    SELECT 
        t.Id AS tag_id,
        t.TagName,
        COUNT(DISTINCT ps.Id) AS question_count,
        AVG(ps.Score) AS avg_question_score,
        PERCENTILE_CONT(0.9) WITHIN GROUP (ORDER BY ps.ViewCount) AS p90_views
    FROM Tags t
    INNER JOIN Posts ps ON POSITION(t.TagName IN ps.Tags) > 0 AND ps.PostTypeId = 1
    WHERE ps.CreationDate >= CAST('2024-10-01' AS date) - INTERVAL '6 months'
    GROUP BY t.Id, t.TagName
    HAVING COUNT(DISTINCT ps.Id) >= 5
),
engaged_users AS (
    SELECT mua.user_id,
           mua.DisplayName,
           mua.month,
           mua.posts_created,
           mua.upvotes_given,
           mua.downvotes_given,
           mua.high_score_questions,
           mua.avg_monthly_reputation,
           tp.TagName AS popular_tag,
           RANK() OVER (PARTITION BY mua.month ORDER BY (mua.posts_created + mua.upvotes_given) DESC) AS activity_rank
    FROM monthly_user_activity mua
    INNER JOIN Posts popular_posts ON popular_posts.OwnerUserId = mua.user_id 
        AND popular_posts.CreationDate >= mua.month 
        AND popular_posts.CreationDate < mua.month + INTERVAL '1 month'
    INNER JOIN tag_popularity tp ON POSITION(tp.TagName IN popular_posts.Tags) > 0
    WHERE mua.posts_created >= 2 OR (mua.upvotes_given + mua.downvotes_given) >= 5
)
SELECT 
    eu.DisplayName AS top_contributor,
    eu.month,
    eu.posts_created,
    eu.upvotes_given,
    eu.downvotes_given,
    eu.high_score_questions,
    eu.popular_tag,
    eu.activity_rank,
    tp.question_count AS tag_question_count,
    tp.avg_question_score,
    tp.p90_views,
    eu.avg_monthly_reputation,
    (eu.posts_created * 10 + eu.upvotes_given * 2 - eu.downvotes_given) AS engagement_score
FROM engaged_users eu
INNER JOIN tag_popularity tp ON eu.popular_tag = tp.TagName
WHERE eu.activity_rank <= 10
  AND eu.month >= CAST('2024-10-01' AS date) - INTERVAL '6 months'
ORDER BY eu.month DESC, (eu.posts_created * 10 + eu.upvotes_given * 2 - eu.downvotes_given) DESC, eu.activity_rank;