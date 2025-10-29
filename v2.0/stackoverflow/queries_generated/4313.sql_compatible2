WITH RankedPostEdits AS (
    SELECT
        ph.PostId,
        ph.UserId,
        ph.CreationDate AS EditDate,
        ph.PostHistoryTypeId,
        ROW_NUMBER() OVER(PARTITION BY ph.PostId, ph.UserId ORDER BY ph.CreationDate DESC) AS rn
    FROM PostHistory ph
    WHERE ph.PostHistoryTypeId IN (4, 5, 6)
),
UserEditActivity AS (
    SELECT
        rpe.PostId,
        rpe.UserId,
        rpe.EditDate,
        p.PostTypeId,
        p.Score,
        p.AnswerCount,
        p.CommentCount,
        u.Reputation,
        u.UpVotes AS UserUpVotes,
        u.DownVotes AS UserDownVotes,
        CASE WHEN p.OwnerUserId = rpe.UserId THEN 1 ELSE 0 END AS IsOwner
    FROM RankedPostEdits rpe
    JOIN Posts p ON rpe.PostId = p.Id
    JOIN Users u ON rpe.UserId = u.Id
    WHERE rpe.rn = 1
),
PostEditCounts AS (
    SELECT
        PostId,
        COUNT(DISTINCT UserId) AS DistinctEditors,
        COUNT(CASE WHEN IsOwner = 1 THEN 1 END) AS OwnerEdits,
        SUM(CASE WHEN IsOwner = 0 THEN 1 ELSE 0 END) AS NonOwnerEdits
    FROM UserEditActivity
    GROUP BY PostId
),
QuestionPerformance AS (
    SELECT
        p.Id AS QuestionId,
        p.Title,
        p.CreationDate AS QuestionCreationDate,
        p.Score AS QuestionScore,
        p.ViewCount AS QuestionViewCount,
        p.AnswerCount AS QuestionAnswerCount,
        p.FavoriteCount AS QuestionFavoriteCount,
        u.DisplayName AS OwnerDisplayName,
        u.Reputation AS OwnerReputation,
        COALESCE(pec.DistinctEditors, 0) AS TotalDistinctEditors,
        COALESCE(pec.OwnerEdits, 0) AS OwnerEdits,
        COALESCE(pec.NonOwnerEdits, 0) AS NonOwnerEdits,
        (p.Score * 1.0 / NULLIF(p.ViewCount, 0)) AS ScorePerView,
        CAST(EXTRACT(EPOCH FROM (p.LastActivityDate - p.CreationDate)) / 86400 AS INTEGER) AS DaysSinceLastActivity,
        CASE WHEN p.ClosedDate IS NOT NULL THEN 1 ELSE 0 END AS IsClosed
    FROM Posts p
    JOIN Users u ON p.OwnerUserId = u.Id
    LEFT JOIN PostEditCounts pec ON p.Id = pec.PostId
    WHERE p.PostTypeId = 1
),
AnswerMetrics AS (
    SELECT
        parent.Id AS ParentId,
        COUNT(*) AS TotalAnswers,
        SUM(CASE WHEN parent.AcceptedAnswerId = child.Id THEN 1 ELSE 0 END) AS IsAccepted,
        AVG(child.Score) AS AvgAnswerScore,
        MAX(child.Score) AS MaxAnswerScore,
        CAST(EXTRACT(EPOCH FROM (MAX(child.CreationDate) - MIN(child.CreationDate))) / 86400 AS INTEGER) AS AnswerLagDays
    FROM Posts child
    JOIN Posts parent ON child.ParentId = parent.Id
    WHERE child.PostTypeId = 2
    GROUP BY parent.Id
)
SELECT
    qp.QuestionId,
    qp.Title,
    qp.QuestionCreationDate,
    qp.QuestionScore,
    qp.QuestionViewCount,
    qp.QuestionFavoriteCount,
    qp.OwnerDisplayName,
    qp.OwnerReputation,
    qp.TotalDistinctEditors,
    qp.OwnerEdits,
    qp.NonOwnerEdits,
    qp.ScorePerView,
    qp.DaysSinceLastActivity,
    qp.IsClosed,
    COALESCE(am.TotalAnswers, 0) AS TotalAnswers,
    COALESCE(am.IsAccepted, 0) AS IsAcceptedAnswer,
    COALESCE(am.AvgAnswerScore, 0.0) AS AvgAnswerScore,
    COALESCE(am.MaxAnswerScore, 0) AS MaxAnswerScore,
    COALESCE(am.AnswerLagDays, 0) AS AnswerLagDays,
    (
        SELECT COUNT(c.Id)
        FROM Comments c
        WHERE c.PostId = qp.QuestionId
          AND c.CreationDate BETWEEN qp.QuestionCreationDate AND (qp.QuestionCreationDate + INTERVAL '24' HOUR)
    ) AS CommentsInFirst24Hours,
    CASE
        WHEN qp.QuestionScore > 1000 AND qp.QuestionViewCount > 100000 THEN 'High Engagement'
        WHEN qp.QuestionScore < 0 AND qp.IsClosed = 1 THEN 'Low Engagement & Closed'
        WHEN qp.TotalDistinctEditors > 5 THEN 'Community Driven'
        ELSE 'Standard'
    END AS QuestionEngagementCategory,
    CASE
        WHEN am.TotalAnswers IS NULL THEN 'No Answers'
        WHEN am.TotalAnswers > 0 AND am.IsAccepted = 1 THEN 'Answered and Accepted'
        WHEN am.TotalAnswers > 0 AND am.IsAccepted = 0 THEN 'Answered, Not Accepted'
    END AS AnswerStatus
FROM QuestionPerformance qp
LEFT JOIN AnswerMetrics am ON qp.QuestionId = am.ParentId
WHERE qp.QuestionScore > -5
ORDER BY qp.QuestionScore DESC, qp.QuestionViewCount DESC
LIMIT 100;