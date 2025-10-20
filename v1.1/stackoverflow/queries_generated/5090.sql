-- {"query": "5090.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p1", "model": "gpt-4.1", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1074} 
WITH question_stats AS (
    SELECT
        p.Id AS QuestionId,
        p.OwnerUserId,
        p.CreationDate,
        p.Title,
        p.Score AS QuestionScore,
        p.ViewCount,
        p.Tags,
        COALESCE(p.AnswerCount, 0) AS AnswerCount,
        COUNT(DISTINCT a.Id) AS ActualAnswerCount,
        MAX(a.Score) AS MaxAnswerScore,
        SUM(CASE WHEN a.Score >= 5 THEN 1 ELSE 0 END) AS AnswerWithHighScore,
        COUNT(DISTINCT v.Id) AS VoteCount,
        COUNT(DISTINCT c.Id) AS CommentCount,
        DENSE_RANK() OVER(ORDER BY p.Score DESC, p.ViewCount DESC) AS DenseRankByPopularity
    FROM
        Posts p
        LEFT JOIN Posts a ON a.ParentId = p.Id AND a.PostTypeId = 2
        LEFT JOIN Votes v ON v.PostId = p.Id
        LEFT JOIN Comments c ON c.PostId = p.Id
    WHERE
        p.PostTypeId = 1
        AND p.CreationDate >= CURRENT_DATE - INTERVAL '1 year'
        AND COALESCE(p.Title, '') <> ''
        AND (p.ViewCount > 1000 OR p.Score > 10)
    GROUP BY
        p.Id, p.OwnerUserId, p.CreationDate, p.Title, p.Score, p.ViewCount, p.Tags, p.AnswerCount
),

user_activity AS (
    SELECT
        u.Id AS UserId,
        u.DisplayName,
        COUNT(DISTINCT p.Id) AS QuestionsAsked,
        COUNT(DISTINCT a.Id) AS AnswersGiven,
        MAX(b.Date) AS LastBadgeDate,
        SUM(CASE WHEN b.Class = 1 THEN 1 ELSE 0 END) AS GoldBadges,
        SUM(CASE WHEN b.Class = 2 THEN 1 ELSE 0 END) AS SilverBadges,
        SUM(CASE WHEN b.Class = 3 THEN 1 ELSE 0 END) AS BronzeBadges,
        u.Reputation,
        RANK() OVER(ORDER BY u.Reputation DESC) AS ReputationRank
    FROM Users u
        LEFT JOIN Posts p ON p.OwnerUserId = u.Id AND p.PostTypeId = 1
        LEFT JOIN Posts a ON a.OwnerUserId = u.Id AND a.PostTypeId = 2
        LEFT JOIN Badges b ON b.UserId = u.Id
    GROUP BY u.Id, u.DisplayName, u.Reputation
),

tags_exploded AS (
    SELECT
        qs.QuestionId,
        unnest(string_to_array(substring(qs.Tags, 2, length(qs.Tags)-2), '><')) AS Tag
    FROM question_stats qs
),

question_close_reasons AS (
    SELECT
        ph.PostId AS QuestionId,
        crt.Name AS CloseReason,
        MIN(ph.CreationDate) AS ClosedAt
    FROM PostHistory ph
        JOIN CloseReasonTypes crt ON CAST(ph.Comment AS integer) = crt.Id
    WHERE
        ph.PostHistoryTypeId = 10
    GROUP BY ph.PostId, crt.Name
),

top_tags AS (
    SELECT
        t.Tag,
        COUNT(*) AS UsageCount,
        ROW_NUMBER() OVER(ORDER BY COUNT(*) DESC) AS TagRank
    FROM tags_exploded t
    GROUP BY t.Tag
    HAVING COUNT(*) > 10
)

SELECT
    qs.QuestionId,
    qs.Title,
    qs.QuestionScore,
    qs.ViewCount,
    qs.AnswerCount,
    qs.ActualAnswerCount,
    qs.MaxAnswerScore,
    COALESCE(qc.CloseReason, 'Open') AS CloseReason,
    CASE 
        WHEN qc.ClosedAt IS NULL THEN 'Active'
        ELSE 'Closed'
    END AS QuestionStatus,
    ROUND(100.0 * NULLIF(qs.AnswerWithHighScore,0) / NULLIF(qs.ActualAnswerCount,0),2) AS PctHighScoreAnswers,
    ua.DisplayName AS OwnerName,
    ua.Reputation,
    ua.ReputationRank,
    ua.GoldBadges,
    ua.SilverBadges,
    ua.BronzeBadges,
    (qs.VoteCount + qs.CommentCount) AS ActivityIndex,
    (
        SELECT
            string_agg(tt.Tag, ', ')
        FROM tags_exploded te
            JOIN top_tags tt ON te.Tag = tt.Tag
        WHERE te.QuestionId = qs.QuestionId
    ) AS PopularTags,
    qs.DenseRankByPopularity
FROM
    question_stats qs
    LEFT JOIN user_activity ua ON ua.UserId = qs.OwnerUserId
    LEFT JOIN question_close_reasons qc ON qc.QuestionId = qs.QuestionId
WHERE
    qs.DenseRankByPopularity <= 50
    AND (
        SELECT COUNT(DISTINCT te.Tag)
        FROM tags_exploded te
        WHERE te.QuestionId = qs.QuestionId AND te.Tag IN (SELECT Tag FROM top_tags WHERE TagRank <= 20)
    ) >= 1
ORDER BY
    qs.DenseRankByPopularity
LIMIT 25;