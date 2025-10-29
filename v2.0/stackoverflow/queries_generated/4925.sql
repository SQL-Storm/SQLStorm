-- {"query": "4925.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-flash-lite", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 1623} 

WITH RankedPosts AS (
    SELECT
        p.Id AS PostId,
        p.PostTypeId,
        p.OwnerUserId,
        p.CreationDate AS PostCreationDate,
        p.Score AS PostScore,
        p.AnswerCount,
        p.CommentCount,
        p.FavoriteCount,
        p.ClosedDate,
        pt.Name AS PostTypeName,
        ROW_NUMBER() OVER (PARTITION BY p.PostTypeId ORDER BY p.CreationDate DESC) AS rn_desc,
        ROW_NUMBER() OVER (PARTITION BY p.PostTypeId ORDER BY p.Score DESC) AS rn_score_desc,
        LAG(p.Score, 1, 0) OVER (ORDER BY p.CreationDate) AS PreviousScore,
        LEAD(p.Score, 1, 0) OVER (ORDER BY p.CreationDate) AS NextScore,
        AVG(CAST(p.ViewCount AS BIGINT)) OVER (PARTITION BY p.PostTypeId ORDER BY p.CreationDate RANGE BETWEEN INTERVAL '30 day' PRECEDING AND CURRENT ROW) AS Avg30DayViewCount
    FROM Posts p
    JOIN PostTypes pt ON p.PostTypeId = pt.Id
    WHERE p.OwnerUserId IS NOT NULL
),
UserPostStats AS (
    SELECT
        u.Id AS UserId,
        u.DisplayName,
        COUNT(CASE WHEN p.PostTypeId = 1 THEN p.Id END) AS QuestionCount,
        COUNT(CASE WHEN p.PostTypeId = 2 THEN p.Id END) AS AnswerCount,
        SUM(CASE WHEN p.PostTypeId = 1 THEN p.Score ELSE 0 END) AS TotalQuestionScore,
        SUM(CASE WHEN p.PostTypeId = 2 THEN p.Score ELSE 0 END) AS TotalAnswerScore,
        AVG(CAST(p.Reputation AS BIGINT)) OVER () AS GlobalAvgReputation
    FROM Users u
    LEFT JOIN Posts p ON u.Id = p.OwnerUserId
    GROUP BY u.Id, u.DisplayName
),
RecentEdits AS (
    SELECT
        ph.PostId,
        ph.UserId AS EditorUserId,
        u.DisplayName AS EditorDisplayName,
        ph.CreationDate AS EditDate,
        COUNT(ph.Id) AS EditCountForPost,
        ROW_NUMBER() OVER (PARTITION BY ph.PostId ORDER BY ph.CreationDate DESC) AS rn_edit
    FROM PostHistory ph
    JOIN Users u ON ph.UserId = u.Id
    WHERE ph.PostHistoryTypeId IN (4, 5, 6, 7, 8, 9) -- Edit/Rollback Title, Body, Tags
    GROUP BY ph.PostId, ph.UserId, u.DisplayName, ph.CreationDate
)
SELECT
    rp_q.PostId AS QuestionId,
    rp_q.Title AS QuestionTitle,
    rp_q.PostTypeName AS QuestionType,
    rp_q.PostScore AS QuestionScore,
    rp_q.AnswerCount AS NumberOfAnswers,
    rp_q.CommentCount AS NumberOfComments,
    rp_q.FavoriteCount AS NumberOfFavorites,
    rp_q.ClosedDate AS QuestionClosedDate,
    CASE
        WHEN rp_q.ClosedDate IS NOT NULL THEN 'Closed'
        WHEN rp_q.AnswerCount > 10 AND rp_q.CommentCount > 50 THEN 'Popular'
        WHEN rp_q.Score > 100 THEN 'Highly Rated'
        ELSE 'Standard'
    END AS QuestionStatus,
    CASE
        WHEN rp_q.PreviousScore < rp_q.PostScore AND rp_q.NextScore > rp_q.PostScore THEN 'Score Fluctuated'
        WHEN rp_q.PostScore = 0 THEN 'Zero Score'
        WHEN rp_q.PostScore > 0 THEN 'Positive Score'
        ELSE 'Non-Positive Score'
    END AS ScoreTrend,
    ups.DisplayName AS OwnerDisplayName,
    ups.QuestionCount AS UserTotalQuestions,
    ups.AnswerCount AS UserTotalAnswers,
    ups.TotalQuestionScore AS UserTotalQuestionScore,
    ups.TotalAnswerScore AS UserTotalAnswerScore,
    re.EditorDisplayName AS LastEditorDisplayName,
    re.EditDate AS LastEditDate,
    re.EditCountForPost AS EditsOnQuestion,
    (rp_q.PostScore * 1.0 / NULLIF(rp_q.ViewCount, 0)) AS ScoreToViewRatio,
    rp_q.Avg30DayViewCount AS Average30DayViews,
    rp_q.PostCreationDate,
    rp_q.NextScore,
    'Q-' || CAST(rp_q.PostId AS VARCHAR) || '-' || COALESCE(rp_q.PostTypeName, 'Unknown') AS CompositeKey,
    COALESCE(rp_q.AnswerCount, 0) + COALESCE(rp_q.CommentCount, 0) AS EngagementMetrics
FROM RankedPosts rp_q
LEFT JOIN UserPostStats ups ON rp_q.OwnerUserId = ups.UserId
LEFT JOIN RecentEdits re ON rp_q.PostId = re.PostId AND re.rn_edit = 1
LEFT JOIN Posts p_answers ON rp_q.PostId = p_answers.ParentId AND p_answers.PostTypeId = 2
WHERE rp_q.PostTypeId = 1 -- Questions
  AND rp_q.rn_desc <= 1000 -- Top 1000 most recent questions
  AND rp_q.PostScore > ups.GlobalAvgReputation / 10 -- Filter for questions with relatively higher scores compared to global average reputation
  AND EXISTS (
      SELECT 1
      FROM PostLinks pl
      WHERE pl.PostId = rp_q.PostId AND pl.LinkTypeId = 3 -- Check for duplicate links
  )
  OR rp_q.PostId IN (SELECT PostId FROM Comments WHERE UserId IS NULL AND LEN(Text) > 100) -- Questions with comments from anonymous users that are long
GROUP BY
    rp_q.PostId,
    rp_q.Title,
    rp_q.PostTypeName,
    rp_q.PostScore,
    rp_q.AnswerCount,
    rp_q.CommentCount,
    rp_q.FavoriteCount,
    rp_q.ClosedDate,
    rp_q.PostCreationDate,
    rp_q.PreviousScore,
    rp_q.NextScore,
    rp_q.ViewCount,
    rp_q.Avg30DayViewCount,
    ups.DisplayName,
    ups.QuestionCount,
    ups.AnswerCount,
    ups.TotalQuestionScore,
    ups.TotalAnswerScore,
    re.EditorDisplayName,
    re.EditDate,
    re.EditCountForPost,
    ups.GlobalAvgReputation
HAVING SUM(CASE WHEN p_answers.PostTypeId = 2 THEN 1 ELSE 0 END) > 0 -- Ensure the question has at least one answer
ORDER BY rp_q.PostCreationDate DESC
LIMIT 500;
