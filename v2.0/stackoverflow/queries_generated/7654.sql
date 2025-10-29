-- {"query": "7654.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "qwen3-coder", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2102, "output_tokens": 1675} 
WITH RankedPosts AS (
    SELECT 
        p.Id,
        p.PostTypeId,
        p.Score,
        p.ViewCount,
        p.Title,
        p.Body,
        p.OwnerUserId,
        p.CreationDate,
        p.Tags,
        ROW_NUMBER() OVER (PARTITION BY p.OwnerUserId ORDER BY p.Score DESC) as rn,
        LAG(p.Score) OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate) as prev_score,
        AVG(p.Score) OVER (PARTITION BY p.PostTypeId) as avg_score_by_type,
        CASE 
            WHEN p.Score > (SELECT AVG(Score) FROM Posts WHERE PostTypeId = p.PostTypeId) 
            THEN 'Above Average'
            ELSE 'Below Average'
        END as score_category,
        COALESCE(p.Tags, '') as tags_with_default
    FROM Posts p
    WHERE p.PostTypeId IN (1, 2) -- Questions and Answers
),
UserStats AS (
    SELECT 
        u.Id,
        u.Reputation,
        u.DisplayName,
        u.Views,
        u.UpVotes,
        u.DownVotes,
        COUNT(DISTINCT p.Id) as total_posts,
        SUM(CASE WHEN p.PostTypeId = 1 THEN 1 ELSE 0 END) as question_count,
        SUM(CASE WHEN p.PostTypeId = 2 THEN 1 ELSE 0 END) as answer_count,
        AVG(p.Score) as avg_score,
        MAX(p.CreationDate) as last_post_date,
        STRING_AGG(DISTINCT p.Tags, '; ') as all_tags
    FROM Users u
    LEFT JOIN Posts p ON u.Id = p.OwnerUserId
    WHERE u.Reputation > 1000
    GROUP BY u.Id, u.Reputation, u.DisplayName, u.Views, u.UpVotes, u.DownVotes
),
TagAnalysis AS (
    SELECT 
        t.TagName,
        t.Count,
        t.ExcerptPostId,
        t.WikiPostId,
        CASE 
            WHEN t.Count > (SELECT AVG(Count) FROM Tags) THEN 'High Popularity'
            ELSE 'Normal Popularity'
        END as popularity_level,
        RANK() OVER (ORDER BY t.Count DESC) as popularity_rank
    FROM Tags t
    WHERE t.Count > 10
),
ComplexPostAnalysis AS (
    SELECT 
        rp.Id,
        rp.Title,
        rp.Score,
        rp.ViewCount,
        rp.Tags,
        rp.score_category,
        rp.avg_score_by_type,
        CASE 
            WHEN rp.prev_score IS NOT NULL 
            AND rp.prev_score <> 0 
            THEN ROUND((rp.Score - rp.prev_score) * 100.0 / rp.prev_score, 2)
            ELSE 0
        END as score_change_percent,
        COALESCE(
            (SELECT COUNT(*) FROM Comments c WHERE c.PostId = rp.Id),
            0
        ) as comment_count,
        COALESCE(
            (SELECT COUNT(*) FROM Votes v WHERE v.PostId = rp.Id AND v.VoteTypeId = 2),
            0
        ) as upvotes,
        COALESCE(
            (SELECT COUNT(*) FROM Votes v WHERE v.PostId = rp.Id AND v.VoteTypeId = 3),
            0
        ) as downvotes,
        CASE 
            WHEN rp.Tags IS NOT NULL 
            AND LENGTH(rp.Tags) > 0 
            THEN ARRAY_LENGTH(string_to_array(rp.Tags, '><'), 1) - 1
            ELSE 0
        END as tag_count,
        'Post_' || rp.Id || '_Analysis' as analysis_label
    FROM RankedPosts rp
    WHERE rp.rn = 1 -- Only top scoring post per user
    AND rp.Score > 50
)
SELECT 
    ups.Id as user_id,
    ups.DisplayName,
    ups.Reputation,
    ups.total_posts,
    ups.question_count,
    ups.answer_count,
    ups.avg_score,
    ups.last_post_date,
    ups.all_tags,
    CASE 
        WHEN ups.total_posts > 100 THEN 'Veteran'
        WHEN ups.total_posts > 50 THEN 'Experienced'
        WHEN ups.total_posts > 10 THEN 'Active'
        ELSE 'New'
    END as user_status,
    (SELECT COUNT(*) 
     FROM Badges b 
     WHERE b.UserId = ups.Id 
     AND b.Class = 1) as gold_badge_count,
    (SELECT COUNT(*) 
     FROM Badges b 
     WHERE b.UserId = ups.Id 
     AND b.Class = 2) as silver_badge_count,
    (SELECT COUNT(*) 
     FROM Badges b 
     WHERE b.UserId = ups.Id 
     AND b.Class = 3) as bronze_badge_count,
    (SELECT STRING_AGG(b.Name, ', ') 
     FROM Badges b 
     WHERE b.UserId = ups.Id 
     AND b.Class = 1) as gold_badges,
    (SELECT STRING_AGG(b.Name, ', ') 
     FROM Badges b 
     WHERE b.UserId = ups.Id 
     AND b.Class = 2) as silver_badges,
    -- Combine complex analysis from multiple CTEs
    ARRAY(
        SELECT DISTINCT analysis_label 
        FROM ComplexPostAnalysis cpa 
        WHERE cpa.Id IN (
            SELECT p.Id 
            FROM Posts p 
            WHERE p.OwnerUserId = ups.Id 
            AND p.PostTypeId = 1
        )
    ) as analysis_labels,
    -- Outer join with tag analysis
    (SELECT STRING_AGG(ta.TagName, ', ') 
     FROM TagAnalysis ta 
     WHERE ta.popularity_rank <= 5
    ) as popular_tags_5,
    -- Complex filtering with correlated subqueries
    (SELECT COUNT(*) 
     FROM Posts p1 
     WHERE p1.OwnerUserId = ups.Id 
     AND p1.Score > (
         SELECT AVG(Score) 
         FROM Posts p2 
         WHERE p2.OwnerUserId = ups.Id
     )
    ) as score_above_avg,
    -- Set operators
    (SELECT COUNT(*) FROM Posts p1 WHERE p1.OwnerUserId = ups.Id) 
    - (SELECT COUNT(*) FROM Posts p2 WHERE p2.OwnerUserId = ups.Id AND p2.Score > 100) as posts_below_100,
    -- String operations and concatenations
    CONCAT(
        'User ID: ', ups.Id, 
        ' | Reputation: ', ups.Reputation,
        ' | Posts: ', ups.total_posts,
        ' | Questions: ', ups.question_count,
        ' | Answers: ', ups.answer_count
    ) as user_summary_text,
    -- NULL handling and CASE expressions
    CASE 
        WHEN ups.all_tags IS NULL THEN 'No Tags Present'
        WHEN ups.all_tags = '' THEN 'Empty Tags'
        ELSE 'Has Tags'
    END as tag_status,
    -- Window function on a joined result
    ROW_NUMBER() OVER (ORDER BY ups.Reputation DESC) as reputation_rank,
    -- Nested subqueries and complex predicates
    (SELECT MAX(c.Score) 
     FROM Comments c 
     WHERE c.UserId = ups.Id 
     AND c.Score IN (
         SELECT Score 
         FROM Comments 
         WHERE PostId IN (
             SELECT Id 
             FROM Posts 
             WHERE OwnerUserId = ups.Id
         )
     )
    ) as max_comment_score
FROM UserStats ups
WHERE ups.total_posts > 0
-- Outer join with complex analysis
LEFT JOIN ComplexPostAnalysis cpa ON cpa.Id IN (
    SELECT Id 
    FROM Posts p 
    WHERE p.OwnerUserId = ups.Id 
    AND p.PostTypeId = 1
)
-- Set operations: INTERSECT and UNION
WHERE ups.Id IN (
    SELECT UserId 
    FROM Badges 
    WHERE Class = 1
    INTERSECT
    SELECT OwnerUserId 
    FROM Posts 
    WHERE PostTypeId = 1
    UNION
    SELECT UserId 
    FROM Comments
)
ORDER BY ups.Reputation DESC
LIMIT 1000;