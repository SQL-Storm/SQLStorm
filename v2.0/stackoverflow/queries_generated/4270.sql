-- {"query": "4270.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-flash-lite", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 1392} 
WITH RankedPostEdits AS (
    SELECT
        ph.PostId,
        ph.UserId,
        u.DisplayName AS EditorDisplayName,
        ph.CreationDate AS EditDate,
        ph.PostHistoryTypeId,
        ph.Comment,
        ROW_NUMBER() OVER(PARTITION BY ph.PostId, ph.UserId ORDER BY ph.CreationDate DESC) as rn
    FROM PostHistory ph
    JOIN Users u ON ph.UserId = u.Id
    WHERE ph.PostHistoryTypeId IN (4, 5, 6) -- Edit Title, Edit Body, Edit Tags
),
PostEditSummary AS (
    SELECT
        rpe.PostId,
        COUNT(DISTINCT rpe.UserId) AS DistinctEditors,
        MAX(rpe.EditDate) AS LastEditDate,
        STRING_AGG(rpe.EditorDisplayName || ' edited on ' || DATE(rpe.EditDate), '; ') WITHIN GROUP (ORDER BY rpe.EditDate DESC) AS EditHistorySummary
    FROM RankedPostEdits rpe
    WHERE rpe.rn <= 5 -- Consider top 5 edits per user per post
    GROUP BY rpe.PostId
),
QuestionAnswerMetrics AS (
    SELECT
        q.Id AS QuestionId,
        q.Title AS QuestionTitle,
        q.OwnerUserId AS QuestionOwnerId,
        u_q.DisplayName AS QuestionOwnerDisplayName,
        q.CreationDate AS QuestionCreationDate,
        q.AnswerCount,
        q.FavoriteCount,
        q.ViewCount AS QuestionViewCount,
        q.Score AS QuestionScore,
        q.ClosedDate AS QuestionClosedDate,
        pes.DistinctEditors AS QuestionDistinctEditors,
        pes.LastEditDate AS QuestionLastEditDate,
        pes.EditHistorySummary AS QuestionEditSummary,
        COUNT(a.Id) AS AnswerCountActual,
        AVG(a.Score) AS AvgAnswerScore,
        MAX(a.CreationDate) AS LastAnswerDate
    FROM Posts q
    LEFT JOIN Users u_q ON q.OwnerUserId = u_q.Id
    LEFT JOIN Posts a ON q.Id = a.ParentId AND a.PostTypeId = 2 -- Type 2 is Answer
    LEFT JOIN PostEditSummary pes ON q.Id = pes.PostId
    WHERE q.PostTypeId = 1 -- Type 1 is Question
    GROUP BY
        q.Id,
        q.Title,
        q.OwnerUserId,
        u_q.DisplayName,
        q.CreationDate,
        q.AnswerCount,
        q.FavoriteCount,
        q.ViewCount,
        q.Score,
        q.ClosedDate,
        pes.DistinctEditors,
        pes.LastEditDate,
        pes.EditHistorySummary
),
UserActivity AS (
    SELECT
        u.Id AS UserId,
        u.DisplayName,
        u.Reputation,
        u.CreationDate AS UserCreationDate,
        COUNT(p.Id) AS PostsCreated,
        SUM(CASE WHEN p.PostTypeId = 1 THEN 1 ELSE 0 END) AS QuestionsAsked,
        SUM(CASE WHEN p.PostTypeId = 2 THEN 1 ELSE 0 END) AS AnswersGiven,
        COUNT(DISTINCT b.Id) AS BadgesEarned,
        MAX(p.CreationDate) AS LastPostDate
    FROM Users u
    LEFT JOIN Posts p ON u.Id = p.OwnerUserId
    LEFT JOIN Badges b ON u.Id = b.UserId
    GROUP BY u.Id, u.DisplayName, u.Reputation, u.CreationDate
),
TagPopularity AS (
    SELECT
        t.TagName,
        t.Count AS TagPostCount,
        (SELECT COUNT(*) FROM Posts p_tag WHERE p_tag.Tags LIKE '%' || t.TagName || '%' AND p_tag.PostTypeId = 1) AS QuestionsWithTag
    FROM Tags t
    ORDER BY t.Count DESC
    LIMIT 10
)
SELECT
    qam.QuestionId,
    qam.QuestionTitle,
    qam.QuestionOwnerDisplayName,
    qam.QuestionCreationDate,
    qam.AnswerCount,
    qam.FavoriteCount,
    qam.QuestionViewCount,
    qam.QuestionScore,
    CASE
        WHEN qam.QuestionClosedDate IS NOT NULL THEN 'Closed'
        ELSE 'Open'
    END AS QuestionStatus,
    COALESCE(qam.QuestionOwnerDisplayName, 'Community') AS EffectiveOwner,
    (qam.QuestionScore * 100.0 / NULLIF(qam.QuestionViewCount, 0)) AS ScoreToViewRatio,
    qam.QuestionDistinctEditors,
    qam.QuestionLastEditDate,
    SUBSTRING(qam.QuestionEditSummary FROM 1 FOR 100) AS TruncatedEditSummary,
    ua.DisplayName AS TopQuestionOwner,
    ua.Reputation AS TopQuestionOwnerReputation,
    ua.BadgesEarned AS TopQuestionOwnerBadges,
    tp.TagName AS MostPopularTag,
    tp.QuestionsWithTag AS QuestionsInPopularTag,
    -- Correlated subquery to find the user who provided the highest scoring answer
    (
        SELECT
            u_ans.DisplayName
        FROM Posts ans
        JOIN Users u_ans ON ans.OwnerUserId = u_ans.Id
        WHERE ans.ParentId = qam.QuestionId
        ORDER BY ans.Score DESC
        LIMIT 1
    ) AS BestAnswerer,
    -- Window function to rank questions by score within a specific tag
    RANK() OVER (ORDER BY qam.QuestionScore DESC) AS GlobalRankByScore
FROM QuestionAnswerMetrics qam
JOIN UserActivity ua ON qam.QuestionOwnerId = ua.UserId
LEFT JOIN TagPopularity tp ON qam.QuestionTitle LIKE '%' || tp.TagName || '%' -- Approximation for tag relevance in title
WHERE qam.QuestionScore > 0
  AND qam.QuestionCreationDate >= '2023-01-01'
ORDER BY qam.QuestionScore DESC, qam.QuestionViewCount DESC
LIMIT 100;