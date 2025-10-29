-- {"query": "1745.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-flash", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 2614} 

WITH UserOverallActivity AS (
    SELECT
        U.Id AS UserId,
        U.DisplayName,
        U.Reputation,
        U.CreationDate AS UserCreationDate,
        U.LastAccessDate,
        U.Views AS UserProfileViews,
        U.UpVotes AS UserUpVotesGiven,
        U.DownVotes AS UserDownVotesGiven,
        COUNT(DISTINCT P.Id) AS TotalPostsCreated,
        COALESCE(SUM(P.Score), 0) AS TotalPostScoreReceived,
        COUNT(DISTINCT C.Id) AS TotalCommentsCreated,
        COUNT(DISTINCT B.Id) AS TotalBadgesEarned,
        SUM(CASE WHEN P.PostTypeId = 1 THEN 1 ELSE 0 END) AS TotalQuestionsAsked,
        SUM(CASE WHEN P.PostTypeId = 2 THEN 1 ELSE 0 END) AS TotalAnswersGiven,
        SUM(CASE WHEN P.PostTypeId = 1 AND P.AnswerCount > 0 THEN P.AnswerCount ELSE 0 END) AS TotalAnswersOnUserQuestions,
        SUM(CASE WHEN P.PostTypeId = 2 AND EXISTS (SELECT 1 FROM Posts Q WHERE Q.Id = P.ParentId AND Q.AcceptedAnswerId = P.Id) THEN 1 ELSE 0 END) AS TotalAcceptedAnswers
    FROM Users AS U
    LEFT JOIN Posts AS P ON U.Id = P.OwnerUserId
    LEFT JOIN Comments AS C ON U.Id = C.UserId
    LEFT JOIN Badges AS B ON U.Id = B.UserId
    GROUP BY
        U.Id, U.DisplayName, U.Reputation, U.CreationDate, U.LastAccessDate, U.Views, U.UpVotes, U.DownVotes
),
QuestionPerformanceMetrics AS (
    SELECT
        Q.Id AS QuestionId,
        Q.OwnerUserId,
        Q.CreationDate AS QuestionCreationDate,
        Q.Score AS QuestionScore,
        Q.ViewCount,
        Q.AnswerCount,
        Q.CommentCount AS QuestionCommentCount,
        COALESCE(Q.FavoriteCount, 0) AS QuestionFavoriteCount,
        Q.ClosedDate,
        LOWER(TRIM(Q.Title)) AS LowercasedTitle,
        -- Extract the first tag from the tags string
        NULLIF(SUBSTRING(Q.Tags FROM 2 FOR POSITION('>' IN Q.Tags)-2), '') AS PrimaryTag,
        Q.Tags,
        (CAST(Q.Score AS NUMERIC) + Q.AnswerCount * 2 + Q.CommentCount * 0.5 + COALESCE(Q.FavoriteCount, 0) * 3)
            / NULLIF(CAST(Q.ViewCount AS NUMERIC) + Q.AnswerCount + Q.CommentCount + 1, 0) AS EngagementRatio,
        COUNT(DISTINCT PL.RelatedPostId) AS DuplicateLinksCount,
        RANK() OVER (PARTITION BY DATE_TRUNC('month', Q.CreationDate) ORDER BY Q.Score DESC, Q.ViewCount DESC) AS MonthlyScoreViewRank,
        AVG(Q.Score) OVER (PARTITION BY Q.OwnerUserId ORDER BY Q.CreationDate ROWS BETWEEN 5 PRECEDING AND CURRENT ROW) AS OwnerRollingAvgQuestionScore
    FROM Posts AS Q
    LEFT JOIN PostLinks AS PL ON Q.Id = PL.PostId AND PL.LinkTypeId = 3 -- Duplicates
    WHERE Q.PostTypeId = 1
    GROUP BY
        Q.Id, Q.OwnerUserId, Q.CreationDate, Q.Score, Q.ViewCount, Q.AnswerCount, Q.CommentCount, Q.FavoriteCount,
        Q.ClosedDate, Q.Title, Q.Tags
),
PostClosureDetails AS (
    SELECT
        PH.PostId AS ClosedQuestionId,
        MAX(PH.CreationDate) AS LatestClosureDate,
        STRING_AGG(DISTINCT CR.Name, ', ' ORDER BY CR.Name) AS AllCloseReasonNames,
        COUNT(DISTINCT PH.UserId) AS UniqueClosingVoterCount,
        MAX(CAST(PH.Comment AS SMALLINT)) AS PrimaryCloseReasonTypeId
    FROM PostHistory AS PH
    JOIN CloseReasonTypes AS CR ON CAST(PH.Comment AS SMALLINT) = CR.Id
    WHERE PH.PostHistoryTypeId = 10 -- Post Closed
    AND PH.Comment ~ '^[0-9]+$' -- Ensure Comment is a numeric ID
    GROUP BY PH.PostId
),
AnswerQualityMetrics AS (
    SELECT
        A.Id AS AnswerId,
        A.ParentId AS ParentQuestionId,
        A.OwnerUserId AS AnswerOwnerUserId,
        A.CreationDate AS AnswerCreationDate,
        A.Score AS AnswerScore,
        A.CommentCount AS AnswerCommentCount,
        (Q.AcceptedAnswerId = A.Id) AS IsAcceptedAnswer,
        NTILE(4) OVER (PARTITION BY A.ParentId ORDER BY A.Score DESC) AS AnswerScoreQuartile,
        (SELECT AVG(A2.Score) FROM Posts AS A2 WHERE A2.ParentId = A.ParentId AND A2.Id != A.Id AND A2.OwnerUserId IS NOT NULL) AS AvgSiblingAnswerScore, -- Correlated subquery
        EXISTS (
            SELECT 1
            FROM Badges B
            JOIN Tags T ON B.Name = T.TagName -- Simplistic join: badge name == tag name for tag-based badges
            WHERE B.UserId = A.OwnerUserId
            AND Q.Tags LIKE '%<' || T.TagName || '>%' -- Check if question tags contain the badge's tag
            AND B.TagBased = TRUE
        ) AS HasRelatedTagBadge
    FROM Posts AS A
    JOIN Posts AS Q ON A.ParentId = Q.Id
    WHERE A.PostTypeId = 2
)
-- Main query combining information: Question-centric view
SELECT
    UOA.UserId,
    UOA.DisplayName,
    UOA.Reputation,
    UOA.TotalPostsCreated,
    UOA.TotalPostScoreReceived,
    QPM.QuestionId AS PostId,
    'Question' AS PostType,
    QPM.QuestionCreationDate AS PostCreationDate,
    QPM.QuestionScore AS PostScore,
    QPM.EngagementRatio,
    QPM.LowercasedTitle AS PostTitleSnippet,
    QPM.PrimaryTag,
    QPM.MonthlyScoreViewRank,
    QPM.OwnerRollingAvgQuestionScore,
    PCD.LatestClosureDate,
    PCD.AllCloseReasonNames,
    PCD.UniqueClosingVoterCount,
    NULL::INT AS AnswerId,
    NULL::INT AS ParentQuestionId,
    NULL::INT AS AnswerScore,
    NULL::BOOLEAN AS IsAcceptedAnswer,
    NULL::INT AS RankAmongAnswers,
    NULL::NUMERIC AS AvgSiblingAnswerScore,
    NULL::BOOLEAN AS HasRelatedTagBadge,
    CASE
        WHEN UOA.Reputation > 50000 AND QPM.EngagementRatio > 0.5 AND PCD.ClosedQuestionId IS NULL THEN 'High_Impact_Open_Question'
        WHEN UOA.Reputation < 1000 AND QPM.QuestionScore < 0 AND PCD.ClosedQuestionId IS NOT NULL THEN 'Low_Quality_Closed_Question'
        ELSE 'Other_Question_Activity'
    END AS ActivityCategory,
    UOA.DisplayName || ' asked: ' || QPM.LowercasedTitle AS PostContext,
    EXTRACT(DAY FROM (UOA.LastAccessDate - UOA.CreationDate)) AS UserActivityDurationDays,
    (QPM.Tags ILIKE '%<sql>%' OR QPM.Tags ILIKE '%<database>%') AS IsSqlOrDatabaseRelated
FROM UserOverallActivity AS UOA
JOIN QuestionPerformanceMetrics AS QPM ON UOA.UserId = QPM.OwnerUserId
LEFT JOIN PostClosureDetails AS PCD ON QPM.QuestionId = PCD.ClosedQuestionId
WHERE UOA.Reputation >= 1000
    AND QPM.QuestionCreationDate >= '2020-01-01'
    AND NOT EXISTS (
        SELECT 1 FROM Comments AS C WHERE C.PostId = QPM.QuestionId AND C.Text ILIKE '%spam%' AND C.CreationDate < QPM.QuestionCreationDate
    )
    AND (
        COALESCE(QPM.QuestionScore, 0) > 0
        OR QPM.ViewCount > 500
    )

UNION ALL

-- Answer-centric view
SELECT
    UOA.UserId,
    UOA.DisplayName,
    UOA.Reputation,
    UOA.TotalPostsCreated,
    UOA.TotalPostScoreReceived,
    AQM.AnswerId AS PostId,
    'Answer' AS PostType,
    AQM.AnswerCreationDate AS PostCreationDate,
    AQM.AnswerScore AS PostScore,
    NULL::NUMERIC AS EngagementRatio,
    LEFT(A.Body, 100) AS PostTitleSnippet, -- Snippet of answer body
    NULLIF(SUBSTRING(Q.Tags FROM 2 FOR POSITION('>' IN Q.Tags)-2), '') AS PrimaryTag, -- Get parent question's primary tag
    NULL::INT AS MonthlyScoreViewRank,
    NULL::NUMERIC AS OwnerRollingAvgQuestionScore,
    NULL::TIMESTAMP AS LatestClosureDate,
    NULL::TEXT AS AllCloseReasonNames,
    NULL::BIGINT AS UniqueClosingVoterCount,
    AQM.AnswerId,
    AQM.ParentQuestionId,
    AQM.AnswerScore,
    AQM.IsAcceptedAnswer,
    AQM.RankAmongAnswers,
    AQM.AvgSiblingAnswerScore,
    AQM.HasRelatedTagBadge,
    CASE
        WHEN AQM.IsAcceptedAnswer AND AQM.AnswerScore > 50 AND AQM.HasRelatedTagBadge THEN 'Elite_Accepted_Answer'
        WHEN AQM.IsAcceptedAnswer AND AQM.AvgSiblingAnswerScore IS NOT NULL AND AQM.AnswerScore < AQM.AvgSiblingAnswerScore THEN 'Accepted_But_Below_Avg'
        WHEN AQM.AnswerScore < -2 AND UOA.TotalBadgesEarned < 5 THEN 'Low_Quality_Answer_By_New_User'
        ELSE 'Other_Answer_Activity'
    END AS ActivityCategory,
    UOA.DisplayName || ' answered: ' || LEFT(A.Body, 50) AS PostContext,
    EXTRACT(DAY FROM (UOA.LastAccessDate - UOA.CreationDate)) AS UserActivityDurationDays,
    (Q.Tags ILIKE '%<sql>%' OR Q.Tags ILIKE '%<database>%') AS IsSqlOrDatabaseRelated
FROM UserOverallActivity AS UOA
JOIN AnswerQualityMetrics AS AQM ON UOA.UserId = AQM.AnswerOwnerUserId
JOIN Posts AS A ON AQM.AnswerId = A.Id
JOIN Posts AS Q ON AQM.ParentQuestionId = Q.Id
WHERE UOA.Reputation >= 1000
    AND AQM.AnswerCreationDate >= '2020-01-01'
    AND UOA.TotalAnswersGiven > 0
    AND (
        COALESCE(AQM.AnswerScore, 0) > 0
        OR AQM.IsAcceptedAnswer
    )
ORDER BY
    Reputation DESC,
    PostCreationDate DESC,
    PostScore DESC
LIMIT 5000;
