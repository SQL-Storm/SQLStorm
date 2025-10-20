-- {"query": "51067.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "grok-4-fast-non-reasoning", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2129, "output_tokens": 1209} 

WITH question_stats AS (
    SELECT 
        p.Id AS question_id,
        p.CreationDate AS q_creation,
        p.Score AS q_score,
        p.ViewCount AS q_views,
        p.AnswerCount AS q_answers,
        p.CommentCount AS q_comments,
        p.FavoriteCount AS q_favorites,
        u.Reputation AS owner_rep,
        u.UpVotes AS owner_upvotes,
        u.DownVotes AS owner_downvotes,
        u.Views AS owner_views,
        COUNT(DISTINCT a.Id) AS actual_answers,
        AVG(a.Score) AS avg_answer_score,
        MAX(a.Score) AS max_answer_score,
        SUM(CASE WHEN v_up.VoteTypeId = 2 THEN 1 ELSE 0 END) AS total_upvotes,
        SUM(CASE WHEN v_down.VoteTypeId = 3 THEN 1 ELSE 0 END) AS total_downvotes,
        COUNT(DISTINCT c.Id) AS total_comments,
        COUNT(DISTINCT ph.Id) AS edit_count,
        AVG(u2.Reputation) AS avg_commenter_rep,
        b_gold.Count AS gold_badges,
        b_silver.Count AS silver_badges,
        b_bronze.Count AS bronze_badges
    FROM Posts p
    LEFT JOIN Users u ON p.OwnerUserId = u.Id
    LEFT JOIN Posts a ON p.Id = a.ParentId AND a.PostTypeId = 2 AND a.DeletionDate IS NULL
    LEFT JOIN Votes v_up ON a.Id = v_up.PostId AND v_up.VoteTypeId = 2
    LEFT JOIN Votes v_down ON a.Id = v_down.PostId AND v_down.VoteTypeId = 3
    LEFT JOIN Comments c ON p.Id = c.PostId
    LEFT JOIN Users u2 ON c.UserId = u2.Id
    LEFT JOIN PostHistory ph ON p.Id = ph.PostId AND ph.PostHistoryTypeId IN (4,5,6)
    LEFT JOIN (
        SELECT UserId, COUNT(*) AS Count 
        FROM Badges WHERE Class = 1 GROUP BY UserId
    ) b_gold ON u.Id = b_gold.UserId
    LEFT JOIN (
        SELECT UserId, COUNT(*) AS Count 
        FROM Badges WHERE Class = 2 GROUP BY UserId
    ) b_silver ON u.Id = b_silver.UserId
    LEFT JOIN (
        SELECT UserId, COUNT(*) AS Count 
        FROM Badges WHERE Class = 3 GROUP BY UserId
    ) b_bronze ON u.Id = b_bronze.UserId
    WHERE p.PostTypeId = 1 
        AND p.DeletionDate IS NULL
        AND p.CreationDate >= '2020-01-01'
        AND p.CreationDate < '2023-12-31'
        AND p.ViewCount > 100
        AND p.AnswerCount > 0
    GROUP BY p.Id, p.CreationDate, p.Score, p.ViewCount, p.AnswerCount, 
             p.CommentCount, p.FavoriteCount, u.Reputation, u.UpVotes, 
             u.DownVotes, u.Views
),
high_performers AS (
    SELECT 
        qs.*,
        ROW_NUMBER() OVER (ORDER BY (q_score * LOG(q_views + 1) + q_favorites * 10 + owner_rep / 1000.0) DESC) AS performance_rank,
        NTILE(4) OVER (ORDER BY q_creation) AS creation_quartile,
        CASE 
            WHEN q_answers >= 10 AND max_answer_score >= 50 THEN 'High Engagement'
            WHEN q_views > 10000 AND q_score > 20 THEN 'Viral'
            WHEN owner_rep > 10000 AND gold_badges > 5 THEN 'Expert Author'
            ELSE 'Standard'
        END AS engagement_category
    FROM question_stats qs
),
linked_activity AS (
    SELECT 
        pl.PostId,
        COUNT(DISTINCT pl.RelatedPostId) AS link_count,
        AVG(pl.CreationDate::date - hp.CreationDate::date) AS avg_link_delay_days
    FROM PostLinks pl
    JOIN high_performers hp ON pl.PostId = hp.question_id
    WHERE pl.LinkTypeId IN (1, 3)
    GROUP BY pl.PostId
)
SELECT 
    hp.question_id,
    hp.q_creation,
    hp.q_score,
    hp.q_views,
    hp.q_answers,
    hp.actual_answers,
    hp.avg_answer_score,
    hp.max_answer_score,
    hp.total_upvotes,
    hp.total_downvotes,
    hp.q_comments,
    hp.total_comments,
    hp.q_favorites,
    hp.owner_rep,
    hp.owner_upvotes,
    hp.owner_downvotes,
    hp.owner_views,
    hp.edit_count,
    hp.gold_badges,
    hp.silver_badges,
    hp.bronze_badges,
    hp.performance_rank,
    hp.engagement_category,
    hp.creation_quartile,
    COALESCE(la.link_count, 0) AS link_count,
    ROUND(COALESCE(la.avg_link_delay_days, 0)::numeric, 2) AS avg_link_delay_days,
    (hp.total_upvotes - hp.total_downvotes) AS net_votes,
    hp.q_score * hp.q_views / 1000.0 AS engagement_score,
    CASE 
        WHEN hp.performance_rank <= 100 THEN 'Top 100'
        WHEN hp.performance_rank <= 1000 THEN 'Top 1000'
        ELSE 'Other'
    END AS rank_tier
FROM high_performers hp
LEFT JOIN linked_activity la ON hp.question_id = la.PostId
WHERE hp.performance_rank <= 5000
ORDER BY hp.performance_rank ASC
LIMIT 1000;
