-- {"query": "17028.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p1", "model": "claude-4.1-opus", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2335, "output_tokens": 2545}

WITH UserMetrics AS (
    SELECT 
        u.Id,
        u.DisplayName,
        u.Reputation,
        COALESCE(u.Location, 'Unknown') AS Location,
        DENSE_RANK() OVER (PARTITION BY COALESCE(u.Location, 'Unknown') ORDER BY u.Reputation DESC) AS location_rep_rank,
        COUNT(DISTINCT p.Id) AS post_count,
        COUNT(DISTINCT CASE WHEN p.PostTypeId = 1 THEN p.Id END) AS question_count,
        COUNT(DISTINCT CASE WHEN p.PostTypeId = 2 THEN p.Id END) AS answer_count,
        AVG(CASE WHEN p.Score IS NOT NULL THEN p.Score ELSE 0 END) AS avg_post_score,
        STRING_AGG(DISTINCT b.Name, ', ' ORDER BY b.Class, b.Name) FILTER (WHERE b.Class = 1) AS gold_badges,
        COUNT(DISTINCT b.Id) FILTER (WHERE b.Class = 1) AS gold_badge_count,
        PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY p.Score) FILTER (WHERE p.Score IS NOT NULL) AS median_post_score
    FROM Users u
    LEFT JOIN Posts p ON u.Id = p.OwnerUserId
    LEFT JOIN Badges b ON u.Id = b.UserId
    WHERE u.CreationDate >= CURRENT_DATE - INTERVAL '2 years'
        AND (u.Reputation > 1000 OR EXISTS (
            SELECT 1 FROM Badges b2 
            WHERE b2.UserId = u.Id AND b2.Class IN (1, 2)
        ))
    GROUP BY u.Id, u.DisplayName, u.Reputation, u.Location
),
QuestionAnalysis AS (
    SELECT 
        q.Id AS QuestionId,
        q.Title,
        q.OwnerUserId,
        q.Score AS QuestionScore,
        q.ViewCount,
        q.AnswerCount,
        q.Tags,
        CASE 
            WHEN q.AcceptedAnswerId IS NOT NULL THEN 'Accepted'
            WHEN q.ClosedDate IS NOT NULL THEN 'Closed'
            WHEN q.AnswerCount > 0 THEN 'Answered'
            ELSE 'Unanswered'
        END AS Status,
        COALESCE(a.Score, 0) AS AcceptedAnswerScore,
        COALESCE(a.OwnerUserId, -1) AS AcceptedAnswerUserId,
        ROW_NUMBER() OVER (PARTITION BY q.OwnerUserId ORDER BY q.Score DESC NULLS LAST) AS user_question_rank,
        FIRST_VALUE(q.Title) OVER (
            PARTITION BY SUBSTRING(LOWER(COALESCE(q.Tags, '')), 1, 
                CASE WHEN POSITION('>' IN COALESCE(q.Tags, '')) > 0 
                THEN POSITION('>' IN COALESCE(q.Tags, '')) - 1 
                ELSE 0 END)
            ORDER BY q.ViewCount DESC NULLS LAST
            ROWS BETWEEN UNBOUNDED PRECEDING AND UNBOUNDED FOLLOWING
        ) AS most_viewed_similar_tag_question
    FROM Posts q
    LEFT JOIN Posts a ON q.AcceptedAnswerId = a.Id
    WHERE q.PostTypeId = 1
        AND q.CreationDate >= CURRENT_DATE - INTERVAL '1 year'
),
TagPerformance AS (
    SELECT 
        t.TagName,
        t.Count AS TagUsageCount,
        COUNT(DISTINCT pl.PostId) AS LinkedPostCount,
        AVG(CAST(ph.PostHistoryTypeId IN (10, 12) AS INT)) AS problem_rate,
        (
            SELECT COUNT(DISTINCT v.UserId)
            FROM Votes v
            INNER JOIN Posts p2 ON v.PostId = p2.Id
            WHERE v.VoteTypeId = 2
                AND p2.Tags LIKE '%<' || t.TagName || '>%'
        ) AS unique_upvoters
    FROM Tags t
    LEFT JOIN Posts p ON p.Tags LIKE '%<' || t.TagName || '>%'
    LEFT JOIN PostLinks pl ON pl.PostId = p.Id OR pl.RelatedPostId = p.Id
    LEFT JOIN PostHistory ph ON ph.PostId = p.Id
    WHERE t.Count >= 100
    GROUP BY t.Id, t.TagName, t.Count
),
ComplexUserActivity AS (
    SELECT 
        um.*,
        qa.QuestionId,
        qa.Title,
        qa.QuestionScore,
        qa.Status,
        tp.TagName,
        tp.TagUsageCount,
        tp.problem_rate,
        CASE 
            WHEN um.gold_badge_count > 5 AND um.avg_post_score > 10 THEN 'Elite'
            WHEN um.question_count > um.answer_count * 2 THEN 'Asker'
            WHEN um.answer_count > um.question_count * 2 THEN 'Answerer'
            WHEN um.post_count > 50 THEN 'Active'
            ELSE 'Regular'
        END AS UserType,
        LAG(qa.QuestionScore, 1, 0) OVER (PARTITION BY um.Id ORDER BY qa.QuestionId) AS prev_question_score,
        LEAD(qa.QuestionScore, 1, 0) OVER (PARTITION BY um.Id ORDER BY qa.QuestionId) AS next_question_score
    FROM UserMetrics um
    LEFT JOIN QuestionAnalysis qa ON um.Id = qa.OwnerUserId AND qa.user_question_rank <= 3
    LEFT JOIN LATERAL (
        SELECT tp2.*, p3.Id
        FROM Posts p3
        CROSS JOIN LATERAL (
            SELECT t2.TagName, tp3.*
            FROM TagPerformance tp3
            INNER JOIN Tags t2 ON tp3.TagName = t2.TagName
            WHERE p3.Tags LIKE '%<' || t2.TagName || '>%'
            ORDER BY tp3.TagUsageCount DESC
            LIMIT 1
        ) tp2
        WHERE p3.Id = qa.QuestionId
    ) tp ON TRUE
),
RecursiveBadgeChain AS (
    SELECT 
        UserId,
        Name AS BadgeName,
        Date AS BadgeDate,
        Class,
        1 AS Level,
        ARRAY[Name] AS badge_path
    FROM Badges
    WHERE TagBased = '0'
        AND Class = 3
    
    UNION ALL
    
    SELECT 
        b.UserId,
        b.Name,
        b.Date,
        b.Class,
        rbc.Level + 1,
        rbc.badge_path || b.Name
    FROM Badges b
    INNER JOIN RecursiveBadgeChain rbc ON b.UserId = rbc.UserId
        AND b.Date > rbc.BadgeDate
        AND b.Class < rbc.Class
    WHERE rbc.Level < 3
        AND NOT (b.Name = ANY(rbc.badge_path))
)
SELECT 
    cua.DisplayName,
    cua.Location,
    cua.Reputation,
    cua.UserType,
    cua.location_rep_rank,
    COALESCE(cua.Title, 'No Questions') AS TopQuestion,
    COALESCE(cua.QuestionScore, 0) AS TopQuestionScore,
    cua.Status AS QuestionStatus,
    COALESCE(cua.gold_badges, 'None') AS GoldBadges,
    cua.gold_badge_count,
    ROUND(cua.avg_post_score::numeric, 2) AS AvgPostScore,
    cua.median_post_score,
    COALESCE(cua.TagName, 'N/A') AS PrimaryTag,
    COALESCE(cua.TagUsageCount, 0) AS TagPopularity,
    ROUND(COALESCE(cua.problem_rate, 0)::numeric, 4) AS TagProblemRate,
    CASE 
        WHEN cua.prev_question_score IS NULL THEN 'First Question'
        WHEN cua.QuestionScore > cua.prev_question_score THEN 'Improving'
        WHEN cua.QuestionScore < cua.prev_question_score THEN 'Declining'
        ELSE 'Stable'
    END AS ScoreTrend,
    COALESCE(rbc.badge_count, 0) AS BadgeProgressionChains,
    SUBSTRING(
        REGEXP_REPLACE(
            UPPER(COALESCE(cua.DisplayName, 'Anonymous')), 
            '[^A-Z]', '', 'g'
        ), 
        1, 3
    ) || '-' || LPAD(cua.Id::text, 6, '0') AS UserCode
FROM ComplexUserActivity cua
LEFT JOIN LATERAL (
    SELECT COUNT(*) AS badge_count
    FROM RecursiveBadgeChain rbc2
    WHERE rbc2.UserId = cua.Id AND rbc2.Level = 3
) rbc ON TRUE
WHERE cua.location_rep_rank <= 10
    AND (cua.QuestionScore IS NULL OR cua.QuestionScore >= 0 OR cua.gold_badge_count > 0)
    AND NOT EXISTS (
        SELECT 1
        FROM Votes v
        WHERE v.UserId = cua.Id
            AND v.VoteTypeId IN (4, 12)
            AND v.CreationDate >= CURRENT_DATE - INTERVAL '6 months'
    )
ORDER BY 
    cua.location_rep_rank,
    cua.Reputation DESC,
    cua.gold_badge_count DESC NULLS LAST,
    cua.QuestionScore DESC NULLS LAST
LIMIT 100;
