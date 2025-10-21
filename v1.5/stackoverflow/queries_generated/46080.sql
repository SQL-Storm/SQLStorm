-- {"query": "46080.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "claude-4.5-sonnet", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2294, "output_tokens": 2044}

WITH TopUsersByReputation AS (
    SELECT 
        u.Id,
        u.DisplayName,
        u.Reputation,
        u.CreationDate,
        DENSE_RANK() OVER (ORDER BY u.Reputation DESC) as rep_rank
    FROM Users u
    WHERE u.Reputation > 10000
),
QuestionMetrics AS (
    SELECT 
        p.Id as QuestionId,
        p.OwnerUserId,
        p.Score as QuestionScore,
        p.ViewCount,
        p.AnswerCount,
        p.CommentCount,
        p.CreationDate,
        p.AcceptedAnswerId,
        EXTRACT(YEAR FROM p.CreationDate) as CreationYear,
        EXTRACT(MONTH FROM p.CreationDate) as CreationMonth,
        string_to_array(substring(p.Tags, 2, length(p.Tags)-2), '><') as tag_array
    FROM Posts p
    WHERE p.PostTypeId = 1 
        AND p.Score > 5
        AND p.CreationDate >= CURRENT_DATE - INTERVAL '3 years'
),
AnswerMetrics AS (
    SELECT 
        a.Id as AnswerId,
        a.ParentId as QuestionId,
        a.OwnerUserId as AnswererUserId,
        a.Score as AnswerScore,
        a.CreationDate as AnswerDate,
        CASE WHEN qm.AcceptedAnswerId = a.Id THEN 1 ELSE 0 END as IsAccepted,
        ROW_NUMBER() OVER (PARTITION BY a.ParentId ORDER BY a.Score DESC, a.CreationDate ASC) as answer_rank
    FROM Posts a
    INNER JOIN QuestionMetrics qm ON a.ParentId = qm.QuestionId
    WHERE a.PostTypeId = 2 
        AND a.OwnerUserId IS NOT NULL
),
UserEngagementScores AS (
    SELECT 
        tu.Id as UserId,
        tu.DisplayName,
        tu.Reputation,
        COUNT(DISTINCT qm.QuestionId) as QuestionsAsked,
        COUNT(DISTINCT am.AnswerId) as AnswersGiven,
        AVG(qm.QuestionScore) as AvgQuestionScore,
        AVG(am.AnswerScore) as AvgAnswerScore,
        SUM(CASE WHEN am.IsAccepted = 1 THEN 1 ELSE 0 END) as AcceptedAnswers,
        SUM(CASE WHEN am.answer_rank = 1 THEN 1 ELSE 0 END) as TopRankedAnswers,
        COUNT(DISTINCT b.Id) as BadgeCount,
        COUNT(DISTINCT v.Id) as VotesCast
    FROM TopUsersByReputation tu
    LEFT JOIN QuestionMetrics qm ON tu.Id = qm.OwnerUserId
    LEFT JOIN AnswerMetrics am ON tu.Id = am.AnswererUserId
    LEFT JOIN Badges b ON tu.Id = b.UserId AND b.Date >= CURRENT_DATE - INTERVAL '3 years'
    LEFT JOIN Votes v ON tu.Id = v.UserId AND v.VoteTypeId IN (2, 3) AND v.CreationDate >= CURRENT_DATE - INTERVAL '3 years'
    WHERE tu.rep_rank <= 1000
    GROUP BY tu.Id, tu.DisplayName, tu.Reputation
),
TagPopularity AS (
    SELECT 
        unnest(qm.tag_array) as tag_name,
        COUNT(DISTINCT qm.QuestionId) as question_count,
        AVG(qm.QuestionScore) as avg_score,
        AVG(qm.ViewCount) as avg_views,
        AVG(qm.AnswerCount) as avg_answers,
        PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY qm.QuestionScore) as median_score
    FROM QuestionMetrics qm
    GROUP BY unnest(qm.tag_array)
    HAVING COUNT(DISTINCT qm.QuestionId) >= 50
),
QuestionAnswerNetwork AS (
    SELECT 
        qm.QuestionId,
        qm.OwnerUserId as QuestionerId,
        am.AnswererUserId,
        qm.CreationYear,
        qm.CreationMonth,
        tp.tag_name,
        tp.avg_score as tag_avg_score,
        qm.QuestionScore,
        am.AnswerScore,
        am.IsAccepted,
        qm.ViewCount,
        CASE 
            WHEN am.AnswerDate <= qm.CreationDate + INTERVAL '1 hour' THEN 'within_1hr'
            WHEN am.AnswerDate <= qm.CreationDate + INTERVAL '6 hours' THEN 'within_6hr'
            WHEN am.AnswerDate <= qm.CreationDate + INTERVAL '24 hours' THEN 'within_24hr'
            ELSE 'after_24hr'
        END as response_time_bucket
    FROM QuestionMetrics qm
    INNER JOIN AnswerMetrics am ON qm.QuestionId = am.QuestionId
    CROSS JOIN LATERAL unnest(qm.tag_array) as tp(tag_name)
    WHERE qm.OwnerUserId IS NOT NULL 
        AND am.AnswererUserId IS NOT NULL
)
SELECT 
    ues.DisplayName,
    ues.Reputation,
    ues.QuestionsAsked,
    ues.AnswersGiven,
    ROUND(COALESCE(ues.AvgQuestionScore, 0)::numeric, 2) as AvgQuestionScore,
    ROUND(COALESCE(ues.AvgAnswerScore, 0)::numeric, 2) as AvgAnswerScore,
    ues.AcceptedAnswers,
    ues.TopRankedAnswers,
    ues.BadgeCount,
    ues.VotesCast,
    COUNT(DISTINCT qan.tag_name) as UniqueTagsEngaged,
    STRING_AGG(DISTINCT qan.tag_name, ', ' ORDER BY qan.tag_name) FILTER (WHERE qan_ranks.tag_rank <= 5) as Top5Tags,
    AVG(CASE WHEN qan.response_time_bucket = 'within_1hr' THEN 1 ELSE 0 END) as FastResponseRate,
    ROUND(AVG(qan.tag_avg_score)::numeric, 2) as AvgTagPopularity,
    PERCENTILE_CONT(0.9) WITHIN GROUP (ORDER BY qan.AnswerScore) as Top10PctAnswerScore
FROM UserEngagementScores ues
LEFT JOIN QuestionAnswerNetwork qan ON ues.UserId = qan.AnswererUserId
LEFT JOIN LATERAL (
    SELECT tag_name, ROW_NUMBER() OVER (ORDER BY COUNT(*) DESC) as tag_rank
    FROM QuestionAnswerNetwork qan2
    WHERE qan2.AnswererUserId = ues.UserId
    GROUP BY tag_name
) qan_ranks ON qan.tag_name = qan_ranks.tag_name
WHERE (ues.QuestionsAsked + ues.AnswersGiven) >= 10
GROUP BY 
    ues.UserId,
    ues.DisplayName,
    ues.Reputation,
    ues.QuestionsAsked,
    ues.AnswersGiven,
    ues.AvgQuestionScore,
    ues.AvgAnswerScore,
    ues.AcceptedAnswers,
    ues.TopRankedAnswers,
    ues.BadgeCount,
    ues.VotesCast
HAVING COUNT(DISTINCT qan.tag_name) >= 3
ORDER BY 
    ues.Reputation DESC,
    ues.AcceptedAnswers DESC,
    ues.AnswersGiven DESC
LIMIT 100;
