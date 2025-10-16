-- {"query": "1183.sql", "dataset": "stackoverflow", "version": "v1.2", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 1.1, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1869} 

WITH RankedAnswers AS (
    SELECT 
        a.Id,
        a.ParentId AS QuestionId,
        a.OwnerUserId,
        a.Score,
        a.CreationDate,
        ROW_NUMBER() OVER (PARTITION BY a.ParentId ORDER BY a.Score DESC, a.CreationDate ASC) AS RankWithinQuestion
    FROM Posts a
    WHERE a.PostTypeId = 2 -- Answers
),
TopAnswers AS (
    SELECT ra.Id, ra.QuestionId, ra.OwnerUserId, ra.Score, ra.CreationDate
    FROM RankedAnswers ra
    WHERE ra.RankWithinQuestion <= 3
),
UserBadgeSummary AS (
    SELECT
        b.UserId,
        SUM(CASE WHEN b.Class = 1 THEN 1 ELSE 0 END) AS GoldBadges,
        SUM(CASE WHEN b.Class = 2 THEN 1 ELSE 0 END) AS SilverBadges,
        SUM(CASE WHEN b.Class = 3 THEN 1 ELSE 0 END) AS BronzeBadges,
        COUNT(*) AS TotalBadges
    FROM Badges b
    GROUP BY b.UserId
),
QuestionWithMetrics AS (
    SELECT 
        q.Id AS QuestionId,
        q.Title,
        q.CreationDate,
        q.OwnerUserId,
        q.Score AS QuestionScore,
        q.ViewCount,
        COALESCE(q.AnswerCount,0) AS AnswerCount,
        q.FavoriteCount,
        u.Reputation AS OwnerReputation,
        ub.GoldBadges,
        ub.SilverBadges,
        ub.BronzeBadges,
        ub.TotalBadges,
        -- Calculate activity span in days between first and last answer
        DATE_PART('day', 
            COALESCE(
                (SELECT MAX(CreationDate) FROM Posts a WHERE a.ParentId = q.Id AND a.PostTypeId = 2),
                q.CreationDate
            ) 
            - q.CreationDate
        ) AS ActivitySpanDays,
        -- Count comments on question
        (SELECT COUNT(*) FROM Comments c WHERE c.PostId = q.Id) AS CommentCountOnQuestion,
        -- Count distinct commenters on answers to this question
        (SELECT COUNT(DISTINCT c.UserId) FROM Comments c JOIN Posts a2 ON c.PostId = a2.Id WHERE a2.ParentId = q.Id AND a2.PostTypeId = 2 AND c.UserId IS NOT NULL) AS DistinctCommentersOnAnswers,
        -- Flags if question was closed - correlated subquery with NULL logic
        EXISTS (
            SELECT 1 FROM PostHistory ph
            WHERE ph.PostId = q.Id AND ph.PostHistoryTypeId = 10 AND ph.CreationDate > q.CreationDate
        ) AS IsClosed
    FROM Posts q
    LEFT JOIN Users u ON q.OwnerUserId = u.Id
    LEFT JOIN UserBadgeSummary ub ON q.OwnerUserId = ub.UserId
    WHERE q.PostTypeId = 1 -- Questions
),
QuestionAnswersAndComments AS (
    SELECT 
        q.QuestionId,
        COUNT(DISTINCT ta.Id) AS Top3AnswersCount,
        AVG(COALESCE(ta.Score, 0)) AS AvgTop3AnswerScore,
        MAX(ta.CreationDate) AS LatestTop3AnswerDate,
        -- Aggregate string: comma separated top answer owners (displayName fallback to 'Unknown')
        STRING_AGG(
            COALESCE(u.DisplayName, CONCAT('User#', ta.OwnerUserId::text)),
            ', ' ORDER BY ta.Score DESC NULLS LAST
        ) FILTER (WHERE ta.OwnerUserId IS NOT NULL) AS TopAnswerers,
        -- Count of answers having accepted answer id = answer id to check if one of top 3 is accepted
        SUM(CASE 
                WHEN EXISTS (
                    SELECT 1 FROM Posts q2 WHERE q2.Id = q.QuestionId AND q2.AcceptedAnswerId = ta.Id
                ) THEN 1 ELSE 0 
            END) AS AcceptedAnswersInTop3
    FROM QuestionWithMetrics q
    LEFT JOIN TopAnswers ta ON q.QuestionId = ta.QuestionId
    LEFT JOIN Users u ON ta.OwnerUserId = u.Id
    GROUP BY q.QuestionId
),
CloseReasonAggregates AS (
    SELECT 
        ph.PostId,
        STRING_AGG(DISTINCT crt.Name, '; ') AS CloseReasons
    FROM PostHistory ph
    LEFT JOIN CloseReasonTypes crt ON ph.Comment::int = crt.Id AND ph.PostHistoryTypeId = 10
    WHERE ph.PostHistoryTypeId = 10
    GROUP BY ph.PostId
),
QuestionFinal AS (
    SELECT
        q.*,
        qac.Top3AnswersCount,
        qac.AvgTop3AnswerScore,
        qac.LatestTop3AnswerDate,
        qac.TopAnswerers,
        qac.AcceptedAnswersInTop3,
        cra.CloseReasons
    FROM QuestionWithMetrics q
    LEFT JOIN QuestionAnswersAndComments qac ON q.QuestionId = qac.QuestionId
    LEFT JOIN CloseReasonAggregates cra ON q.QuestionId = cra.PostId
)
SELECT 
    qf.QuestionId,
    qf.Title,
    qf.CreationDate,
    qf.OwnerUserId,
    COALESCE(u.DisplayName, 'Unknown') AS QuestionOwnerDisplayName,
    qf.OwnerReputation,
    qf.GoldBadges,
    qf.SilverBadges,
    qf.BronzeBadges,
    qf.TotalBadges,
    qf.QuestionScore,
    qf.ViewCount,
    qf.AnswerCount,
    qf.FavoriteCount,
    qf.CommentCountOnQuestion,
    qf.DistinctCommentersOnAnswers,
    qf.IsClosed,
    qf.CloseReasons,
    qf.Top3AnswersCount,
    ROUND(qf.AvgTop3AnswerScore::numeric,2) AS AvgTop3AnswerScore,
    qf.LatestTop3AnswerDate,
    qf.TopAnswerers,
    qf.AcceptedAnswersInTop3,
    qf.ActivitySpanDays,
    -- Complex expression: engagement index based on weighted sum with NULL logic
    (
        COALESCE(qf.ViewCount, 0) * 0.1 + 
        COALESCE(qf.AnswerCount, 0) * 5 + 
        COALESCE(qf.FavoriteCount, 0) * 8 +
        COALESCE(qf.CommentCountOnQuestion, 0) * 2 +
        COALESCE(qf.DistinctCommentersOnAnswers, 0) * 3 +
        COALESCE(qf.TotalBadges, 0) / NULLIF(NULLIF(qf.OwnerReputation,0),NULL) * 100
    ) AS EngagementIndex,
    -- Window function example: rank questions by engagement descending
    RANK() OVER (ORDER BY 
        COALESCE(qf.ViewCount, 0) * 0.1 + 
        COALESCE(qf.AnswerCount, 0) * 5 + 
        COALESCE(qf.FavoriteCount, 0) * 8 +
        COALESCE(qf.CommentCountOnQuestion, 0) * 2 +
        COALESCE(qf.DistinctCommentersOnAnswers, 0) * 3 +
        COALESCE(qf.TotalBadges, 0) / NULLIF(NULLIF(qf.OwnerReputation,0),NULL) * 100 DESC
    ) AS EngagementRank,
    -- Sample string expression to detect if title contains certain keywords, case insensitive
    CASE 
        WHEN qf.Title ILIKE '%error%' THEN 'Error related'
        WHEN qf.Title ILIKE '%exception%' THEN 'Exception related'
        WHEN qf.Title ILIKE '%performance%' THEN 'Performance related'
        ELSE 'Other'
    END AS TitleCategory,
    -- Boolean expression with NULL logic to check if user created account before 2010-01-01 or unknown
    (u.CreationDate < '2010-01-01' OR u.CreationDate IS NULL) AS ExperiencedUser,
    -- Outer join detecting if accepted answer owner has badges
    COALESCE(ab.GoldBadges,0) AS AcceptedAnswerOwnerGoldBadges,
    COALESCE(ab.SilverBadges,0) AS AcceptedAnswerOwnerSilverBadges,
    COALESCE(ab.BronzeBadges,0) AS AcceptedAnswerOwnerBronzeBadges
FROM QuestionFinal qf
LEFT JOIN Users u ON qf.OwnerUserId = u.Id
LEFT JOIN Posts acceptedAnswer ON acceptedAnswer.Id = (
    SELECT AcceptedAnswerId FROM Posts WHERE Id = qf.QuestionId
)
LEFT JOIN UserBadgeSummary ab ON acceptedAnswer.OwnerUserId = ab.UserId
WHERE qf.AnswerCount > 2
ORDER BY EngagementRank, qf.QuestionId
LIMIT 100;
