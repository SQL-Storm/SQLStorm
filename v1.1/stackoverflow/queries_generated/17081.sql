-- {"query": "17081.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "claude-4.1-opus", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 191470, "output_tokens": 189091} 

WITH user_expertise AS (
    SELECT 
        u.Id,
        u.DisplayName,
        u.Reputation,
        COUNT(DISTINCT CASE WHEN p.Score >= 10 THEN t.value END) as expert_tags,
        PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY p.Score) FILTER (WHERE p.Score > 0) as median_score,
        STRING_AGG(DISTINCT t.value, ', ' ORDER BY t.value) FILTER (WHERE p.Score >= 20) as top_tags
    FROM Users u
    INNER JOIN Posts p ON u.Id = p.OwnerUserId
    CROSS JOIN LATERAL string_to_array(substring(p.Tags, 2, length(p.Tags)-2), '><') AS t(value)
    WHERE p.PostTypeId = 1 
        AND p.CreationDate >= CURRENT_DATE - INTERVAL '2 years'
        AND u.Reputation > 1000
    GROUP BY u.Id, u.DisplayName, u.Reputation
),
question_quality AS (
    SELECT 
        q.Id as QuestionId,
        q.OwnerUserId,
        q.Score,
        q.ViewCount,
        q.AnswerCount,
        COALESCE(q.FavoriteCount, 0) as FavoriteCount,
        COUNT(DISTINCT a.OwnerUserId) FILTER (WHERE a.Score > 5) as high_score_answerers,
        MAX(a.Score) as best_answer_score,
        BOOL_OR(a.Id = q.AcceptedAnswerId AND a.Score > 10) as has_quality_accepted,
        AVG(CASE WHEN a.CreationDate IS NOT NULL 
            THEN EXTRACT(EPOCH FROM (a.CreationDate - q.CreationDate))/3600 
            END) as avg_time_to_answer_hours,
        ROW_NUMBER() OVER (PARTITION BY q.OwnerUserId ORDER BY q.Score DESC) as user_question_rank,
        DENSE_RANK() OVER (ORDER BY q.ViewCount DESC NULLS LAST) as view_rank
    FROM Posts q
    LEFT OUTER JOIN Posts a ON q.Id = a.ParentId AND a.PostTypeId = 2
    WHERE q.PostTypeId = 1
        AND q.ClosedDate IS NULL
        AND q.Score >= 0
    GROUP BY q.Id, q.OwnerUserId, q.Score, q.ViewCount, q.AnswerCount, q.FavoriteCount
),
user_activity_patterns AS (
    SELECT 
        UserId,
        COUNT(*) as total_actions,
        COUNT(*) FILTER (WHERE PostHistoryTypeId IN (2, 5)) as edits,
        COUNT(*) FILTER (WHERE PostHistoryTypeId = 10) as close_votes,
        COUNT(*) FILTER (WHERE PostHistoryTypeId = 11) as reopen_votes,
        CASE 
            WHEN COUNT(*) > 100 THEN 'Power User'
            WHEN COUNT(*) BETWEEN 50 AND 100 THEN 'Active'
            WHEN COUNT(*) BETWEEN 10 AND 49 THEN 'Regular'
            ELSE 'Casual'
        END as activity_level,
        ARRAY_AGG(DISTINCT PostHistoryTypeId ORDER BY PostHistoryTypeId) as action_types
    FROM PostHistory
    WHERE UserId IS NOT NULL
        AND CreationDate >= CURRENT_DATE - INTERVAL '1 year'
    GROUP BY UserId
),
recursive_comment_chains AS (
    WITH RECURSIVE comment_tree AS (
        SELECT 
            c1.Id,
            c1.PostId,
            c1.UserId,
            c1.Score,
            c1.Text,
            1 as depth,
            ARRAY[c1.Id] as path,
            c1.CreationDate as root_date,
            c1.Id as root_id
        FROM Comments c1
        WHERE NOT EXISTS (
            SELECT 1 FROM Comments c2 
            WHERE c2.PostId = c1.PostId 
                AND c2.CreationDate < c1.CreationDate
                AND POSITION('@' || COALESCE(
                    (SELECT DisplayName FROM Users WHERE Id = c1.UserId), 
                    c1.UserDisplayName
                ) IN c2.Text) > 0
        )
        
        UNION ALL
        
        SELECT 
            c.Id,
            c.PostId,
            c.UserId,
            c.Score,
            c.Text,
            ct.depth + 1,
            ct.path || c.Id,
            ct.root_date,
            ct.root_id
        FROM Comments c
        INNER JOIN comment_tree ct ON c.PostId = ct.PostId
        WHERE c.CreationDate > ct.root_date
            AND c.Id != ALL(ct.path)
            AND ct.depth < 5
            AND (POSITION('@' IN c.Text) > 0 OR c.Score > 5)
    )
    SELECT PostId, MAX(depth) as max_chain_length, COUNT(DISTINCT root_id) as chain_count
    FROM comment_tree
    GROUP BY PostId
)
SELECT 
    ue.DisplayName,
    ue.Reputation,
    COALESCE(ue.expert_tags, 0) as expertise_breadth,
    COALESCE(ue.median_score, 0)::numeric(10,2) as median_post_score,
    SUBSTRING(COALESCE(ue.top_tags, 'No tags'), 1, 100) as top_expertise_areas,
    COUNT(DISTINCT qq.QuestionId) as quality_questions,
    COALESCE(AVG(qq.Score) FILTER (WHERE qq.user_question_rank <= 10), 0)::numeric(10,2) as top10_avg_score,
    COALESCE(AVG(qq.ViewCount / NULLIF(qq.AnswerCount, 0)) FILTER (WHERE qq.view_rank <= 100), 0)::numeric(10,2) as elite_view_answer_ratio,
    COALESCE(MAX(qq.best_answer_score), 0) as max_answer_received,
    COALESCE(uap.activity_level, 'Inactive') as activity_classification,
    COALESCE(uap.edits, 0) + COALESCE(uap.close_votes, 0) * 2 as moderation_score,
    COUNT(DISTINCT b.Name) FILTER (WHERE b.Class = 1) as gold_badges,
    STRING_AGG(DISTINCT b.Name, ', ' ORDER BY b.Name) FILTER (WHERE b.Class = 1 AND b.Date >= CURRENT_DATE - INTERVAL '6 months') as recent_gold_badges,
    COALESCE(AVG(rcc.max_chain_length), 0)::numeric(10,2) as avg_discussion_depth,
    CASE 
        WHEN ue.Reputation > 50000 AND COUNT(DISTINCT b.Name) FILTER (WHERE b.Class = 1) > 5 THEN 'Elite'
        WHEN ue.Reputation > 10000 OR COALESCE(ue.expert_tags, 0) > 10 THEN 'Expert'
        WHEN ue.Reputation > 5000 OR COALESCE(AVG(qq.Score), 0) > 5 THEN 'Advanced'
        WHEN ue.Reputation > 1000 THEN 'Intermediate'
        ELSE 'Beginner'
    END as user_tier,
    COALESCE((
        SELECT COUNT(DISTINCT v.PostId)
        FROM Votes v
        INNER JOIN Posts p ON v.PostId = p.Id
        WHERE v.UserId = ue.Id 
            AND v.VoteTypeId = 2
            AND p.OwnerUserId != ue.Id
            AND p.Score < 0
    ), 0) as underdog_supporter_count,
    GREATEST(
        0,
        COALESCE(ue.Reputation, 0) * 0.1 + 
        COALESCE(ue.expert_tags, 0) * 100 +
        COALESCE(AVG(qq.Score), 0) * 50 +
        COUNT(DISTINCT b.Name) FILTER (WHERE b.Class = 1) * 500 -
        COALESCE(AVG(qq.avg_time_to_answer_hours), 100) * 0.5
    )::numeric(10,2) as composite_influence_score
FROM user_expertise ue
LEFT OUTER JOIN question_quality qq ON ue.Id = qq.OwnerUserId
LEFT OUTER JOIN user_activity_patterns uap ON ue.Id = uap.UserId
LEFT OUTER JOIN Badges b ON ue.Id = b.UserId
LEFT OUTER JOIN recursive_comment_chains rcc ON qq.QuestionId = rcc.PostId
WHERE ue.DisplayName IS NOT NULL
    AND LENGTH(ue.DisplayName) > 0
GROUP BY ue.Id, ue.DisplayName, ue.Reputation, ue.expert_tags, ue.median_score, ue.top_tags, uap.activity_level, uap.edits, uap.close_votes
HAVING COUNT(DISTINCT qq.QuestionId) > 0 
    OR COUNT(DISTINCT b.Id) > 0
ORDER BY composite_influence_score DESC NULLS LAST, ue.Reputation DESC
LIMIT 100;
