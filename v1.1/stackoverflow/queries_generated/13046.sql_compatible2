WITH UserActivity AS (
    SELECT
        OwnerUserId,
        COUNT(DISTINCT CASE WHEN PostTypeId = 1 THEN Id END) AS QuestionsAsked,
        COUNT(DISTINCT CASE WHEN PostTypeId = 2 THEN Id END) AS AnswersProvided,
        SUM(Score) AS TotalScore,
        MAX(CreationDate) AS LastActivityDate
    FROM Posts
    WHERE OwnerUserId IS NOT NULL
    GROUP BY OwnerUserId
),
HighlyActiveUsers AS (
    SELECT 
        ua.OwnerUserId,
        u.DisplayName,
        ua.QuestionsAsked,
        ua.AnswersProvided,
        ua.TotalScore,
        ua.LastActivityDate,
        ROW_NUMBER() OVER (ORDER BY ua.TotalScore DESC, ua.LastActivityDate DESC) AS Rank
    FROM UserActivity ua
    JOIN Users u ON ua.OwnerUserId = u.Id
    WHERE u.Reputation > 1000 
      AND u.LastAccessDate > (CAST('2024-10-01 12:34:56' AS TIMESTAMP) - INTERVAL '1' MONTH)
),
TopQuestions AS (
    SELECT 
        p.Id,
        p.Title,
        p.OwnerUserId,
        p.Score,
        ph.Comment AS CloseReason,
        DENSE_RANK() OVER (PARTITION BY p.OwnerUserId ORDER BY p.Score DESC) AS QuestionRank
    FROM Posts p
    LEFT JOIN PostHistory ph ON p.Id = ph.PostId AND ph.PostHistoryTypeId = 10
    WHERE p.PostTypeId = 1 
      AND p.Score > 10 
      AND (p.Tags LIKE '%<sql>%' OR p.Tags LIKE '%<performance>%')
),
CommentSummary AS (
    SELECT
        PostId,
        COUNT(*) AS TotalComments,
        STRING_AGG(CASE WHEN Score > 0 THEN Text ELSE NULL END, ' || ') AS PositiveComments
    FROM Comments
    GROUP BY PostId
)
SELECT
    hau.DisplayName,
    hau.QuestionsAsked,
    hau.AnswersProvided,
    hau.TotalScore,
    tq.Title AS TopQuestionTitle,
    tq.Score AS TopQuestionScore,
    crt.Name AS CloseReasonTypeName,
    cs.TotalComments,
    cs.PositiveComments,
    b.Name AS LatestBadgeEarned
FROM HighlyActiveUsers hau
LEFT JOIN TopQuestions tq ON hau.OwnerUserId = tq.OwnerUserId AND tq.QuestionRank = 1
LEFT JOIN CommentSummary cs ON tq.Id = cs.PostId
LEFT JOIN Badges b ON hau.OwnerUserId = b.UserId 
    AND b.Date = (
        SELECT MAX(b2.Date) 
        FROM Badges b2
        WHERE b2.UserId = hau.OwnerUserId
    )
LEFT JOIN CloseReasonTypes crt ON
    -- convert CloseReason to integer safely: try to cast numeric-looking text, else NULL
    (CASE 
        WHEN tq.CloseReason ~ '^[0-9]+$' THEN CAST(tq.CloseReason AS INTEGER)
        ELSE NULL
     END) = crt.Id
WHERE hau.Rank <= 10
GROUP BY
    hau.DisplayName,
    hau.QuestionsAsked,
    hau.AnswersProvided,
    hau.TotalScore,
    hau.OwnerUserId,
    hau.LastActivityDate,
    tq.Title,
    tq.Score,
    tq.Id,
    tq.OwnerUserId,
    tq.QuestionRank,
    crt.Name,
    cs.TotalComments,
    cs.PositiveComments,
    b.Name,
    hau.Rank
ORDER BY hau.TotalScore DESC, hau.QuestionsAsked DESC;