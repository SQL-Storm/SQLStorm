-- {"query": "17093.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p1", "model": "claude-4.1-opus", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2335, "output_tokens": 2114}

WITH UserActivity AS (
    SELECT 
        u.Id,
        u.DisplayName,
        u.Reputation,
        COUNT(DISTINCT p.Id) AS PostCount,
        COUNT(DISTINCT CASE WHEN p.PostTypeId = 1 THEN p.Id END) AS QuestionCount,
        COUNT(DISTINCT CASE WHEN p.PostTypeId = 2 THEN p.Id END) AS AnswerCount,
        AVG(p.Score) AS AvgPostScore,
        COALESCE(SUM(p.ViewCount), 0) AS TotalViews,
        DENSE_RANK() OVER (ORDER BY u.Reputation DESC) AS ReputationRank,
        PERCENT_RANK() OVER (ORDER BY COUNT(DISTINCT p.Id)) AS PostPercentile
    FROM Users u
    LEFT JOIN Posts p ON u.Id = p.OwnerUserId
    WHERE u.CreationDate >= CURRENT_DATE - INTERVAL '2 years'
    GROUP BY u.Id, u.DisplayName, u.Reputation
),
TopTags AS (
    SELECT 
        t.TagName,
        t.Count AS TagUsageCount,
        COUNT(DISTINCT p.OwnerUserId) AS UniqueContributors,
        AVG(CASE WHEN p.Score > 0 THEN p.Score END) AS AvgPositiveScore,
        STRING_AGG(
            DISTINCT CASE 
                WHEN p.Score >= 100 THEN u.DisplayName 
            END, ', ' ORDER BY u.DisplayName
        ) AS HighScoreContributors,
        ROW_NUMBER() OVER (ORDER BY t.Count DESC) AS TagRank
    FROM Tags t
    INNER JOIN Posts p ON p.Tags LIKE '%<' || t.TagName || '>%'
    LEFT JOIN Users u ON p.OwnerUserId = u.Id
    WHERE t.Count > 1000
    GROUP BY t.TagName, t.Count
),
EditHistory AS (
    SELECT 
        ph.PostId,
        COUNT(*) AS EditCount,
        COUNT(DISTINCT ph.UserId) AS UniqueEditors,
        MAX(ph.CreationDate) AS LastEditDate,
        FIRST_VALUE(ph.Comment) OVER (
            PARTITION BY ph.PostId 
            ORDER BY ph.CreationDate DESC
            ROWS BETWEEN UNBOUNDED PRECEDING AND UNBOUNDED FOLLOWING
        ) AS LastEditComment
    FROM PostHistory ph
    WHERE ph.PostHistoryTypeId IN (4, 5, 6)
    GROUP BY ph.PostId, ph.Comment, ph.CreationDate
),
ComplexMetrics AS (
    SELECT 
        q.Id AS QuestionId,
        q.Title,
        q.Score AS QuestionScore,
        q.OwnerUserId,
        ua.DisplayName AS QuestionAuthor,
        ua.ReputationRank,
        COALESCE(q.AnswerCount, 0) AS AnswerCount,
        COALESCE(eh.EditCount, 0) AS QuestionEditCount,
        (
            SELECT COUNT(DISTINCT v.UserId)
            FROM Votes v
            WHERE v.PostId = q.Id 
                AND v.VoteTypeId = 2
                AND v.UserId IN (
                    SELECT b.UserId 
                    FROM Badges b 
                    WHERE b.Class = 1
                )
        ) AS GoldBadgeUpvotes,
        CASE 
            WHEN q.ClosedDate IS NOT NULL THEN 'Closed'
            WHEN q.AcceptedAnswerId IS NOT NULL THEN 'Answered'
            WHEN q.AnswerCount > 0 THEN 'Open with Answers'
            ELSE 'Unanswered'
        END AS QuestionStatus,
        COALESCE(
            (
                SELECT MAX(a.Score)
                FROM Posts a
                WHERE a.ParentId = q.Id 
                    AND a.PostTypeId = 2
            ), 
            -999
        ) AS HighestAnswerScore,
        LENGTH(q.Body) - LENGTH(REPLACE(q.Body, '<code>', '')) AS CodeBlockCount,
        SUBSTRING(
            q.Tags, 
            2, 
            POSITION('>' IN q.Tags) - 2
        ) AS FirstTag,
        EXTRACT(EPOCH FROM (
            COALESCE(q.ClosedDate, CURRENT_TIMESTAMP) - q.CreationDate
        )) / 86400.0 AS DaysToCloseOrNow
    FROM Posts q
    LEFT JOIN UserActivity ua ON q.OwnerUserId = ua.Id
    LEFT JOIN EditHistory eh ON q.Id = eh.PostId
    WHERE q.PostTypeId = 1
        AND q.CreationDate >= CURRENT_DATE - INTERVAL '1 year'
        AND q.Score >= 5
)
SELECT 
    cm.QuestionId,
    cm.Title,
    cm.QuestionAuthor,
    cm.ReputationRank,
    cm.QuestionScore,
    cm.AnswerCount,
    cm.QuestionEditCount,
    cm.GoldBadgeUpvotes,
    cm.QuestionStatus,
    cm.HighestAnswerScore,
    cm.CodeBlockCount,
    cm.FirstTag,
    ROUND(cm.DaysToCloseOrNow::numeric, 2) AS DaysToCloseOrNow,
    tt.TagRank AS FirstTagRank,
    tt.TagUsageCount AS FirstTagUsage,
    tt.AvgPositiveScore AS FirstTagAvgScore,
    COALESCE(tt.HighScoreContributors, 'None') AS FirstTagTopContributors,
    CASE 
        WHEN cm.HighestAnswerScore > cm.QuestionScore * 2 
            AND cm.HighestAnswerScore > 10 
        THEN 'Answer Outshines Question'
        WHEN cm.QuestionScore > 50 
            AND cm.AnswerCount = 0 
        THEN 'Popular but Unanswered'
        WHEN cm.GoldBadgeUpvotes::float / NULLIF(cm.QuestionScore, 0) > 0.3 
        THEN 'Expert Approved'
        WHEN cm.QuestionEditCount > 5 
        THEN 'Heavily Edited'
        WHEN cm.CodeBlockCount > 10 
        THEN 'Code Heavy'
        ELSE 'Standard'
    END AS QuestionCategory,
    LAG(cm.QuestionScore, 1) OVER (
        PARTITION BY cm.FirstTag 
        ORDER BY cm.QuestionScore DESC
    ) AS PrevHigherScoreInTag,
    LEAD(cm.Title, 1) OVER (
        PARTITION BY cm.QuestionAuthor 
        ORDER BY cm.QuestionId
    ) AS AuthorsNextQuestion,
    PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY cm.QuestionScore) OVER (
        PARTITION BY cm.FirstTag
    ) AS MedianScoreForTag,
    EXISTS (
        SELECT 1 
        FROM PostLinks pl 
        WHERE pl.PostId = cm.QuestionId 
            AND pl.LinkTypeId = 3
    ) AS IsDuplicateTarget,
    (
        SELECT COUNT(*) 
        FROM Comments c 
        WHERE c.PostId = cm.QuestionId 
            AND c.Text LIKE '%thank%'
            AND c.UserId = cm.OwnerUserId
    ) AS AuthorThankComments
FROM ComplexMetrics cm
LEFT OUTER JOIN TopTags tt ON cm.FirstTag = tt.TagName
WHERE cm.QuestionScore > (
    SELECT AVG(p.Score) + STDDEV(p.Score)
    FROM Posts p 
    WHERE p.PostTypeId = 1 
        AND p.CreationDate >= CURRENT_DATE - INTERVAL '1 year'
)
    OR cm.GoldBadgeUpvotes > 5
    OR (cm.AnswerCount > 10 AND cm.HighestAnswerScore < cm.QuestionScore)
ORDER BY 
    cm.QuestionScore DESC NULLS LAST,
    cm.GoldBadgeUpvotes DESC NULLS LAST,
    cm.DaysToCloseOrNow ASC NULLS FIRST
LIMIT 100;
