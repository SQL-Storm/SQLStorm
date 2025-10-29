-- {"query": "7616.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "qwen3-coder", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2102, "output_tokens": 1430} 
WITH RankedUsers AS (
    SELECT 
        u.Id,
        u.Reputation,
        u.CreationDate,
        u.DisplayName,
        u.Views,
        u.UpVotes,
        u.DownVotes,
        ROW_NUMBER() OVER (ORDER BY u.Reputation DESC) as rn,
        COUNT(*) OVER () as total_users
    FROM Users u
    WHERE u.Reputation > 1000
),
QuestionStats AS (
    SELECT 
        p.OwnerUserId,
        COUNT(*) as question_count,
        AVG(p.Score) as avg_score,
        MAX(p.ViewCount) as max_views,
        STRING_AGG(p.Title, ' | ' ORDER BY p.CreationDate) as titles
    FROM Posts p
    WHERE p.PostTypeId = 1 AND p.CreationDate >= '2020-01-01'
    GROUP BY p.OwnerUserId
),
AnswerStats AS (
    SELECT 
        p.OwnerUserId,
        COUNT(*) as answer_count,
        SUM(p.Score) as total_score,
        AVG(p.Score) as avg_score
    FROM Posts p
    WHERE p.PostTypeId = 2
    GROUP BY p.OwnerUserId
),
BadgeCounts AS (
    SELECT 
        b.UserId,
        COUNT(*) as badge_count,
        COUNT(CASE WHEN b.Class = 1 THEN 1 END) as gold_badges,
        COUNT(CASE WHEN b.Class = 2 THEN 1 END) as silver_badges,
        COUNT(CASE WHEN b.Class = 3 THEN 1 END) as bronze_badges
    FROM Badges b
    GROUP BY b.UserId
),
UserActivity AS (
    SELECT 
        u.Id,
        CASE 
            WHEN u.Views IS NULL THEN 'Inactive'
            WHEN u.Views > 10000 THEN 'Super Active'
            WHEN u.Views > 5000 THEN 'Active'
            ELSE 'Regular'
        END as activity_level,
        COALESCE(uc.question_count, 0) as questions,
        COALESCE(uc.avg_score, 0) as avg_question_score,
        COALESCE(ac.answer_count, 0) as answers,
        COALESCE(ac.total_score, 0) as total_answer_score,
        COALESCE(bc.badge_count, 0) as badges,
        COALESCE(bc.gold_badges, 0) as gold_badges
    FROM Users u
    LEFT JOIN QuestionStats uc ON u.Id = uc.OwnerUserId
    LEFT JOIN AnswerStats ac ON u.Id = ac.OwnerUserId
    LEFT JOIN BadgeCounts bc ON u.Id = bc.UserId
    WHERE u.Id IN (
        SELECT DISTINCT OwnerUserId 
        FROM Posts 
        WHERE PostTypeId = 1 
        AND CreationDate >= '2020-01-01'
        AND OwnerUserId IS NOT NULL
    )
),
ComplexUserAnalysis AS (
    SELECT 
        ua.Id,
        ua.activity_level,
        ua.questions,
        ua.avg_question_score,
        ua.answers,
        ua.total_answer_score,
        ua.badges,
        ua.gold_badges,
        (SELECT COUNT(*) 
         FROM Posts p 
         WHERE p.OwnerUserId = ua.Id 
         AND p.PostTypeId = 1 
         AND p.CreationDate >= '2020-01-01') as recent_questions,
        (SELECT COUNT(*) 
         FROM Comments c 
         WHERE c.UserId = ua.Id 
         AND c.CreationDate >= '2020-01-01') as recent_comments,
        CASE 
            WHEN ua.questions > 0 AND ua.answers > 0 
            THEN CAST(ua.answers AS FLOAT) / CAST(ua.questions AS FLOAT)
            ELSE 0 
        END as qa_ratio,
        ROW_NUMBER() OVER (PARTITION BY ua.activity_level ORDER BY ua.total_answer_score DESC) as score_rank_by_activity,
        DENSE_RANK() OVER (ORDER BY ua.badges DESC, ua.questions DESC) as overall_rank
    FROM UserActivity ua
    WHERE NOT EXISTS (
        SELECT 1 
        FROM Posts p 
        WHERE p.OwnerUserId = ua.Id 
        AND p.PostTypeId = 1 
        AND p.ClosedDate IS NOT NULL
    )
)
SELECT 
    cu.Id,
    cu.activity_level,
    cu.questions,
    cu.avg_question_score,
    cu.answers,
    cu.total_answer_score,
    cu.badges,
    cu.gold_badges,
    cu.recent_questions,
    cu.recent_comments,
    cu.qa_ratio,
    cu.score_rank_by_activity,
    cu.overall_rank,
    CASE 
        WHEN cu.questions > 100 THEN 'Elite'
        WHEN cu.questions > 50 THEN 'Veteran'
        WHEN cu.questions > 10 THEN 'Contributor'
        ELSE 'Member'
    END as contribution_level,
    ROUND(cu.badges * 100.0 / NULLIF(cu.questions, 0), 2) as badge_efficiency_ratio,
    CASE 
        WHEN cu.questions > 0 THEN 
            LTRIM(RTRIM(STRING_AGG(
                CASE WHEN cu.answers > 0 THEN 'QA' ELSE 'Q' END || 
                '(' || CAST(CAST(cu.questions AS FLOAT) / NULLIF(cu.answers, 0) AS INTEGER) || ')', 
                ', ' 
            ORDER BY cu.questions DESC))) 
        ELSE 'No activity'
    END as contribution_pattern,
    (SELECT u.DisplayName 
     FROM Users u 
     WHERE u.Id = cu.Id 
     AND u.Reputation > (SELECT AVG(Reputation) FROM Users WHERE Id = cu.Id)) as named_display,
    CASE 
        WHEN cu.answers > 0 AND cu.questions > 0 THEN 
            ROUND((cu.total_answer_score * 100.0) / NULLIF(cu.questions, 0), 2)
        ELSE 0 
    END as avg_answer_score_per_question,
    ABS(CAST(cu.questions AS FLOAT) - CAST(cu.answers AS FLOAT)) as question_answer_difference
FROM ComplexUserAnalysis cu
WHERE cu.overall_rank <= 100
GROUP BY 
    cu.Id, cu.activity_level, cu.questions, cu.avg_question_score, 
    cu.answers, cu.total_answer_score, cu.badges, cu.gold_badges, 
    cu.recent_questions, cu.recent_comments, cu.qa_ratio, 
    cu.score_rank_by_activity, cu.overall_rank
HAVING 
    cu.questions > 0 
    AND (cu.answers > 0 OR cu.total_answer_score > 0)
    AND cu.badges > 0
    AND (cu.recent_questions > 0 OR cu.recent_comments > 0)
ORDER BY 
    cu.overall_rank ASC,
    cu.questions DESC,
    cu.total_answer_score DESC,
    cu.badges DESC
LIMIT 500;