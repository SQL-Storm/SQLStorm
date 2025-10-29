-- {"query": "4945.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-flash-lite", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 1149}
WITH QuestionDetails AS (
    SELECT
        p.Id AS PostId,
        p.Title,
        p.OwnerUserId,
        u.DisplayName AS OwnerDisplayName,
        p.CreationDate AS PostCreationDate,
        p.Score,
        p.AnswerCount,
        p.FavoriteCount,
        p.ViewCount,
        p.ClosedDate,
        p.CommunityOwnedDate,
        (SELECT COUNT(*) FROM Comments c WHERE c.PostId = p.Id) AS CommentCountForPost,
        CASE WHEN p.ClosedDate IS NOT NULL THEN 1 ELSE 0 END AS IsClosedFlag,
        LAG(p.Score, 1, 0) OVER (ORDER BY p.CreationDate) AS PreviousDayScore,
        ROW_NUMBER() OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate DESC) AS RowNumByUser,
        AVG(p.Score) OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate ROWS BETWEEN 2 PRECEDING AND CURRENT ROW) AS AvgScoreLast3PostsByUser
    FROM Posts p
    JOIN Users u ON p.OwnerUserId = u.Id
    WHERE p.PostTypeId = 1 AND p.OwnerUserId IS NOT NULL
),
AnswerStats AS (
    SELECT
        a.ParentId AS QuestionId,
        COUNT(a.Id) AS TotalAnswers,
        SUM(a.Score) AS TotalAnswerScore,
        AVG(a.Score) AS AvgAnswerScore,
        MAX(a.CreationDate) AS LatestAnswerDate
    FROM Posts a
    JOIN QuestionDetails q ON a.ParentId = q.PostId
    WHERE a.PostTypeId = 2
    GROUP BY a.ParentId
),
AcceptedAnswerCounts AS (
    SELECT
        q.PostId AS QuestionId,
        COUNT(a.Id) FILTER (WHERE a.Id = qrow.AcceptedAnswerId) AS AcceptedAnswerCount
    FROM QuestionDetails q
    JOIN Posts qrow ON q.PostId = qrow.Id
    LEFT JOIN Posts a ON a.ParentId = q.PostId AND a.PostTypeId = 2
    GROUP BY q.PostId, qrow.AcceptedAnswerId
),
UserPostCounts AS (
    SELECT
        OwnerUserId,
        COUNT(Id) AS TotalPostsByOwner,
        COUNT(CASE WHEN PostTypeId = 1 THEN 1 END) AS QuestionCountByOwner,
        COUNT(CASE WHEN PostTypeId = 2 THEN 1 END) AS AnswerCountByOwner
    FROM Posts
    WHERE OwnerUserId IS NOT NULL
    GROUP BY OwnerUserId
),
RecentPostHistory AS (
    SELECT
        ph.PostId,
        MAX(ph.CreationDate) AS LastHistoryDate
    FROM PostHistory ph
    WHERE ph.PostHistoryTypeId IN (4, 5, 6, 10, 11, 12, 13, 14, 15, 19, 20, 35, 36)
    GROUP BY ph.PostId
)
SELECT
    qd.PostId,
    qd.Title,
    qd.OwnerUserId,
    qd.OwnerDisplayName,
    qd.PostCreationDate,
    qd.Score,
    qd.AnswerCount AS QuestionAnswerCount,
    COALESCE(asv.TotalAnswers, 0) AS TotalAnswersForQuestion,
    COALESCE(asv.TotalAnswerScore, 0) AS TotalAnswerScoreForQuestion,
    COALESCE(asv.AvgAnswerScore, 0.0) AS AvgAnswerScoreForQuestion,
    CASE WHEN COALESCE(aac.AcceptedAnswerCount, 0) > 0 THEN 'Yes' ELSE 'No' END AS HasAcceptedAnswer,
    qd.FavoriteCount,
    qd.ViewCount,
    qd.IsClosedFlag,
    qd.ClosedDate,
    qd.CommunityOwnedDate,
    qd.CommentCountForPost,
    upc.TotalPostsByOwner,
    upc.QuestionCountByOwner,
    upc.AnswerCountByOwner,
    COALESCE(rph.LastHistoryDate, qd.PostCreationDate) AS LastRelevantHistoryOrCreationDate,
    qd.PreviousDayScore,
    qd.AvgScoreLast3PostsByUser,
    COALESCE(u.Reputation, 0) AS OwnerReputation,
    (COALESCE(u.Location, 'N/A') || ' | ' || COALESCE(u.WebsiteUrl, 'No Website')) AS UserLocationAndWebsite
FROM QuestionDetails qd
LEFT JOIN AnswerStats asv ON qd.PostId = asv.QuestionId
LEFT JOIN AcceptedAnswerCounts aac ON qd.PostId = aac.QuestionId
LEFT JOIN UserPostCounts upc ON qd.OwnerUserId = upc.OwnerUserId
LEFT JOIN RecentPostHistory rph ON qd.PostId = rph.PostId
LEFT JOIN Users u ON qd.OwnerUserId = u.Id
WHERE qd.RowNumByUser <= 10
  AND qd.PostCreationDate > (CAST('2024-10-01' AS date) - INTERVAL '1 year')
  AND qd.Score > COALESCE(qd.PreviousDayScore, 0) * 1.1
  AND (qd.FavoriteCount IS NULL OR qd.FavoriteCount > 5)
GROUP BY
    qd.PostId,
    qd.Title,
    qd.OwnerUserId,
    qd.OwnerDisplayName,
    qd.PostCreationDate,
    qd.Score,
    qd.AnswerCount,
    asv.TotalAnswers,
    asv.TotalAnswerScore,
    asv.AvgAnswerScore,
    aac.AcceptedAnswerCount,
    qd.FavoriteCount,
    qd.ViewCount,
    qd.IsClosedFlag,
    qd.ClosedDate,
    qd.CommunityOwnedDate,
    qd.CommentCountForPost,
    upc.TotalPostsByOwner,
    upc.QuestionCountByOwner,
    upc.AnswerCountByOwner,
    rph.LastHistoryDate,
    qd.PreviousDayScore,
    qd.AvgScoreLast3PostsByUser,
    u.Reputation,
    u.Location,
    u.WebsiteUrl,
    COALESCE(u.Reputation, 0),
    COALESCE(u.Location, 'N/A'),
    COALESCE(u.WebsiteUrl, 'No Website')
ORDER BY qd.Score DESC, qd.FavoriteCount DESC
LIMIT 100;