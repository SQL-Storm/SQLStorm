-- {"query": "4506.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-flash-lite", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 1959}
WITH RankedAnswers AS (
    SELECT
        ROW_NUMBER() OVER (PARTITION BY p.ParentId ORDER BY p.Score DESC, p.CreationDate ASC) AS rn,
        p.Id AS AnswerId,
        p.ParentId AS QuestionId,
        p.OwnerUserId AS AnswererUserId,
        p.Score AS AnswerScore,
        p.CreationDate AS AnswerCreationDate,
        u.Reputation AS AnswererReputation,
        u.DisplayName AS AnswererDisplayName,
        CASE
            WHEN p.OwnerUserId = q.OwnerUserId THEN 1
            ELSE 0
        END AS IsOwnerAnswer,
        ROW_NUMBER() OVER (PARTITION BY p.ParentId ORDER BY p.CreationDate ASC) AS answer_order
    FROM Posts p
    JOIN Posts q ON p.ParentId = q.Id
    LEFT JOIN Users u ON p.OwnerUserId = u.Id
    WHERE p.PostTypeId = 2
      AND q.PostTypeId = 1
),
QuestionStats AS (
    SELECT
        q.Id AS QuestionId,
        q.Title AS QuestionTitle,
        q.CreationDate AS QuestionCreationDate,
        q.OwnerUserId AS QuestionOwnerUserId,
        q.AnswerCount,
        q.FavoriteCount,
        q.ViewCount AS QuestionViewCount,
        q.Score AS QuestionScore,
        CASE WHEN q.ClosedDate IS NOT NULL THEN 1 ELSE 0 END AS IsClosed,
        q.ClosedDate,
        q.Tags,
        COUNT(DISTINCT c.Id) AS CommentCountOnQuestion,
        MAX(q.LastActivityDate) AS LastQuestionActivity
    FROM Posts q
    LEFT JOIN Comments c ON q.Id = c.PostId AND c.UserId IS NOT NULL
    WHERE q.PostTypeId = 1
    GROUP BY
        q.Id,
        q.Title,
        q.CreationDate,
        q.OwnerUserId,
        q.AnswerCount,
        q.FavoriteCount,
        q.ViewCount,
        q.Score,
        q.ClosedDate,
        q.Tags,
        q.LastActivityDate
),
UserAnswerAnalysis AS (
    SELECT
        ra.QuestionId,
        ra.AnswererUserId,
        COUNT(ra.AnswerId) AS TotalAnswersByUserForThisQuestion,
        SUM(ra.AnswerScore) AS TotalScoreOfAnswersByThisUserForThisQuestion,
        MAX(ra.AnswerCreationDate) AS LastAnswerDateByThisUserForThisQuestion,
        SUM(CASE WHEN ra.IsOwnerAnswer = 1 THEN 1 ELSE 0 END) AS OwnerAnswerCount
    FROM RankedAnswers ra
    GROUP BY ra.QuestionId, ra.AnswererUserId
),
AnswerRankDetails AS (
    SELECT
        ra.QuestionId,
        ra.AnswerId,
        ra.AnswererUserId,
        ra.AnswerScore,
        ra.AnswerCreationDate,
        ra.AnswererReputation,
        ra.AnswererDisplayName,
        ra.rn AS AnswerRank,
        ra.IsOwnerAnswer,
        uaa.TotalAnswersByUserForThisQuestion,
        uaa.TotalScoreOfAnswersByThisUserForThisQuestion,
        uaa.LastAnswerDateByThisUserForThisQuestion,
        uaa.OwnerAnswerCount,
        LAG(ra.AnswerScore, 1, 0) OVER (PARTITION BY ra.QuestionId ORDER BY ra.rn) AS PreviousAnswerScore,
        LEAD(ra.AnswerScore, 1, 0) OVER (PARTITION BY ra.QuestionId ORDER BY ra.rn) AS NextAnswerScore,
        CASE WHEN ra.rn = 1 THEN 1 ELSE 0 END AS IsBestAnswerByRank,
        CASE WHEN q.QuestionId IS NOT NULL AND EXISTS (
            SELECT 1 FROM Posts pq WHERE pq.Id = q.QuestionId AND pq.AcceptedAnswerId = ra.AnswerId
        ) THEN 1 ELSE 0 END AS IsAcceptedAnswer
    FROM RankedAnswers ra
    JOIN QuestionStats q ON ra.QuestionId = q.QuestionId
    LEFT JOIN UserAnswerAnalysis uaa ON ra.QuestionId = uaa.QuestionId AND ra.AnswererUserId = uaa.AnswererUserId
)
SELECT
    qs.QuestionId,
    qs.QuestionTitle,
    qs.QuestionCreationDate,
    qs.QuestionOwnerUserId,
    u_q.DisplayName AS QuestionOwnerDisplayName,
    qs.AnswerCount AS TotalAnswers,
    qs.FavoriteCount,
    qs.QuestionViewCount,
    qs.QuestionScore AS QuestionScore,
    qs.IsClosed,
    qs.ClosedDate,
    qs.Tags,
    qs.CommentCountOnQuestion,
    qs.LastQuestionActivity,
    COUNT(DISTINCT ard.AnswerId) AS ProcessedAnswerCount,
    SUM(ard.AnswerScore) AS TotalAnswerScoreSum,
    AVG(ard.AnswerScore) AS AverageAnswerScore,
    MAX(ard.AnswerScore) AS MaxAnswerScore,
    MIN(ard.AnswerScore) AS MinAnswerScore,
    SUM(ard.IsAcceptedAnswer) AS AcceptedAnswerCount,
    SUM(ard.IsBestAnswerByRank) AS BestRankedAnswerCount,
    SUM(CASE WHEN ard.AnswerRank <= 5 THEN 1 ELSE 0 END) AS Top5AnswersCount,
    SUM(ard.AnswererReputation) AS TotalAnswererReputation,
    AVG(ard.AnswererReputation) AS AverageAnswererReputation,
    SUM(ard.IsOwnerAnswer) AS OwnerAnsweredCount,
    SUM(ard.TotalScoreOfAnswersByThisUserForThisQuestion) AS TotalScoreFromTopAnswerers,
    COUNT(DISTINCT ard.AnswererUserId) AS DistinctAnswerersCount,
    MAX(ard.AnswerCreationDate) AS LastAnswerDate,
    MIN(ard.AnswerCreationDate) AS FirstAnswerDate,
    (SELECT COUNT(*) FROM PostLinks pl WHERE pl.PostId = qs.QuestionId AND pl.LinkTypeId = 3) AS DuplicateLinkCount,
    COALESCE(
        (
            SELECT AVG(CAST(ph.Text AS NUMERIC))
            FROM PostHistory ph
            WHERE ph.PostId = qs.QuestionId
              AND ph.PostHistoryTypeId = 10
              AND ph.Text IS NOT NULL
              AND (
                  CASE
                      WHEN ph.Text ~ '^\d+$' THEN CAST(ph.Text AS INTEGER)
                      ELSE NULL
                  END
              ) IN (101, 102, 103, 104, 105)
        ),
        0
    ) AS AverageCloseVoteDuration,
    CASE
        WHEN qs.Tags LIKE '%<sql>%' THEN 1
        ELSE 0
    END AS HasSqlTag,
    CASE
        WHEN qs.QuestionTitle IS NULL OR qs.QuestionTitle = '' THEN 1
        ELSE 0
    END AS HasMissingTitle,
    CASE
        WHEN qs.QuestionViewCount > 100000 THEN 'HighView'
        WHEN qs.QuestionViewCount > 10000 THEN 'MediumView'
        ELSE 'LowView'
    END AS ViewCategory,
    LAG(qs.QuestionScore, 1, 0) OVER (ORDER BY qs.QuestionCreationDate) AS PreviousQuestionScore,
    LEAD(qs.QuestionScore, 1, 0) OVER (ORDER BY qs.QuestionCreationDate) AS NextQuestionScore,
    qs.QuestionScore - LAG(qs.QuestionScore, 1, 0) OVER (ORDER BY qs.QuestionCreationDate) AS ScoreDifferenceWithPrevious,
    DENSE_RANK() OVER (ORDER BY qs.QuestionScore DESC) AS ScoreRank,
    ROW_NUMBER() OVER (PARTITION BY u_q.Id ORDER BY qs.QuestionCreationDate DESC) AS UserQuestionSequence
FROM QuestionStats qs
LEFT JOIN Users u_q ON qs.QuestionOwnerUserId = u_q.Id
LEFT JOIN AnswerRankDetails ard ON qs.QuestionId = ard.QuestionId
WHERE qs.QuestionOwnerUserId IS NOT NULL
  AND qs.QuestionCreationDate >= DATE '2023-01-01'
  AND qs.QuestionViewCount > 100
GROUP BY
    qs.QuestionId,
    qs.QuestionTitle,
    qs.QuestionCreationDate,
    qs.QuestionOwnerUserId,
    u_q.DisplayName,
    qs.AnswerCount,
    qs.FavoriteCount,
    qs.QuestionViewCount,
    qs.QuestionScore,
    qs.IsClosed,
    qs.ClosedDate,
    qs.Tags,
    qs.CommentCountOnQuestion,
    qs.LastQuestionActivity,
    u_q.Id
HAVING COUNT(DISTINCT ard.AnswerId) > 0
ORDER BY qs.QuestionCreationDate DESC
LIMIT 1000;