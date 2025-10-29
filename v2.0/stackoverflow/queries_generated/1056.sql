-- {"query": "1056.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-flash", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 2609} 

WITH UserEngagement AS (
    SELECT
        U.Id AS UserId,
        U.DisplayName,
        U.Reputation,
        U.Views AS UserProfileViews,
        U.UpVotes AS UserUpVotesGiven,
        U.DownVotes AS UserDownVotesGiven,
        COUNT(DISTINCT P.Id) AS TotalPosts,
        COUNT(DISTINCT CASE WHEN P.PostTypeId = 1 THEN P.Id END) AS TotalQuestions,
        COUNT(DISTINCT CASE WHEN P.PostTypeId = 2 THEN P.Id END) AS TotalAnswers,
        COUNT(DISTINCT C.Id) AS TotalCommentsWritten,
        COUNT(DISTINCT B.Id) AS TotalBadges,
        SUM(CASE WHEN P.Score IS NOT NULL THEN P.Score ELSE 0 END) AS TotalPostScore,
        AVG(CASE WHEN P.Score IS NOT NULL THEN P.Score ELSE NULL END) AS AvgPostScore,
        EXTRACT(EPOCH FROM (NOW() - U.LastAccessDate)) / 86400 AS DaysSinceLastAccess, -- Days since last access
        MAX(P.CreationDate) AS LastPostDate,
        MIN(P.CreationDate) AS FirstPostDate
    FROM Users AS U
    LEFT JOIN Posts AS P ON U.Id = P.OwnerUserId
    LEFT JOIN Comments AS C ON U.Id = C.UserId
    LEFT JOIN Badges AS B ON U.Id = B.UserId
    GROUP BY
        U.Id, U.DisplayName, U.Reputation, U.Views, U.UpVotes, U.DownVotes, U.LastAccessDate
    HAVING COUNT(DISTINCT P.Id) > 0 OR COUNT(DISTINCT C.Id) > 0 OR COUNT(DISTINCT B.Id) > 0
),
PostHistoricalMetrics AS (
    SELECT
        P.Id AS PostId,
        P.OwnerUserId,
        P.PostTypeId,
        P.CreationDate AS PostCreationDate,
        P.ViewCount,
        P.Score AS PostScore,
        P.FavoriteCount,
        P.CommentCount AS QuestionCommentCount,
        P.AcceptedAnswerId,
        P.LastEditDate,
        P.LastActivityDate,
        P.Title,
        P.Tags,
        P.Body, -- Include Body for string length calculations
        COUNT(DISTINCT ANS.Id) AS AnswerCount,
        SUM(CASE WHEN ANS.Score IS NOT NULL THEN ANS.Score ELSE 0 END) AS TotalAnswerScore,
        NULLIF(AVG(ANS.Score), 0) AS AvgAnswerScore, -- Using NULLIF to handle cases with no answers, preventing division by zero
        MAX(CASE WHEN PH.PostHistoryTypeId IN (10, 101, 102, 103, 104, 105) THEN 1 ELSE 0 END) AS WasClosedEver,
        MAX(CASE WHEN PH.PostHistoryTypeId = 11 THEN 1 ELSE 0 END) AS WasReopenedEver,
        COUNT(DISTINCT CASE WHEN PH.PostHistoryTypeId IN (4, 5, 6) THEN PH.RevisionGUID END) AS EditCount,
        COUNT(DISTINCT CASE WHEN PL.LinkTypeId = 3 THEN PL.RelatedPostId END) AS DuplicateLinkCount,
        SUM(CASE WHEN VO.VoteTypeId = 2 THEN 1 ELSE 0 END) AS TotalUpVotesReceived,
        SUM(CASE WHEN VO.VoteTypeId = 3 THEN 1 ELSE 0 END) AS TotalDownVotesReceived
    FROM Posts AS P
    LEFT JOIN Posts AS ANS ON P.Id = ANS.ParentId AND ANS.PostTypeId = 2
    LEFT JOIN PostHistory AS PH ON P.Id = PH.PostId
    LEFT JOIN PostLinks AS PL ON P.Id = PL.PostId
    LEFT JOIN Votes AS VO ON P.Id = VO.PostId
    WHERE P.PostTypeId = 1 -- Only questions are considered for this analysis
    GROUP BY
        P.Id, P.OwnerUserId, P.PostTypeId, P.CreationDate, P.ViewCount, P.Score, P.FavoriteCount,
        P.CommentCount, P.AcceptedAnswerId, P.LastEditDate, P.LastActivityDate, P.Title, P.Tags, P.Body
),
QuestionPrimaryTagInfo AS (
    SELECT
        PHM.PostId,
        COALESCE(
            SUBSTRING(PHM.Tags FROM POSITION('<' IN PHM.Tags) + 1 FOR POSITION('>' IN PHM.Tags) - POSITION('<' IN PHM.Tags) - 1),
            'untagged'
        ) AS PrimaryTagName
    FROM PostHistoricalMetrics AS PHM
    WHERE PHM.Tags IS NOT NULL AND LENGTH(PHM.Tags) > 2
),
AggregatedTagStats AS (
    SELECT
        QPTI.PostId,
        QPTI.PrimaryTagName,
        T.Count AS PrimaryTagQuestionCount,
        T.IsModeratorOnly AS PrimaryTagIsModeratorOnly,
        T.IsRequired AS PrimaryTagIsRequired
    FROM QuestionPrimaryTagInfo AS QPTI
    LEFT JOIN Tags AS T ON QPTI.PrimaryTagName = T.TagName
)
SELECT
    Q.PostId,
    Q.Title,
    Q.PostCreationDate,
    Q.ViewCount,
    Q.PostScore,
    Q.FavoriteCount,
    Q.QuestionCommentCount,
    Q.AnswerCount,
    Q.AvgAnswerScore,
    Q.TotalUpVotesReceived,
    Q.TotalDownVotesReceived,
    COALESCE(UE.DisplayName, 'Deleted User') AS QuestionOwnerDisplayName, -- NULL logic for OwnerUserId
    COALESCE(UE.Reputation, 0) AS QuestionOwnerReputation, -- NULL logic for OwnerUserId's reputation
    COALESCE(UE.TotalQuestions, 0) AS OwnerTotalQuestions,
    COALESCE(UE.TotalAnswers, 0) AS OwnerTotalAnswers,
    COALESCE(UE.TotalBadges, 0) AS OwnerTotalBadges,
    ATS.PrimaryTagName,
    COALESCE(ATS.PrimaryTagQuestionCount, 0) AS PrimaryTagQuestionCount,
    COALESCE(ATS.PrimaryTagIsModeratorOnly, FALSE) AS PrimaryTagIsModeratorOnly,
    COALESCE(ATS.PrimaryTagIsRequired, FALSE) AS PrimaryTagIsRequired,
    Q.EditCount,
    Q.DuplicateLinkCount,
    Q.WasClosedEver,
    Q.WasReopenedEver,
    COALESCE(Q.LastEditDate, Q.PostCreationDate) AS EffectiveLastActivity, -- Use creation date if no edits
    CASE
        WHEN Q.AcceptedAnswerId IS NOT NULL THEN 'Has Accepted Answer'
        WHEN Q.AnswerCount > 0 AND Q.AcceptedAnswerId IS NULL THEN 'Answers but no Accepted Answer'
        ELSE 'No Answers'
    END AS AcceptedAnswerStatus, -- Conditional logic
    CASE
        WHEN Q.WasClosedEver = 1 AND Q.WasReopenedEver = 1 THEN 'Contested Post'
        WHEN Q.WasClosedEver = 1 THEN 'Closed Post'
        WHEN Q.DuplicateLinkCount > 0 THEN 'Potential Duplicate'
        WHEN Q.FavoriteCount > 50 THEN 'Highly Favorited'
        ELSE 'Standard Post'
    END AS PostLifecycleStatus, -- Conditional logic based on post events
    ROUND(CAST(Q.ViewCount AS NUMERIC) / NULLIF(Q.FavoriteCount, 0), 2) AS ViewsPerFavoriteRatio, -- Calculation with NULLIF for division by zero
    (SELECT COUNT(DISTINCT C.UserId) FROM Comments AS C WHERE C.PostId = Q.PostId AND C.UserId IS NOT NULL) AS UniqueCommentersOnQuestion, -- Correlated subquery
    AVG(Q.PostScore) OVER (PARTITION BY ATS.PrimaryTagName) AS AvgPostScoreForTag, -- Window function: average post score per tag
    RANK() OVER (PARTITION BY ATS.PrimaryTagName ORDER BY Q.PostScore DESC, Q.ViewCount DESC) AS RankInTagByScoreViews, -- Window function: rank within tag
    LAG(Q.PostCreationDate, 1, Q.PostCreationDate) OVER (PARTITION BY Q.OwnerUserId ORDER BY Q.PostCreationDate) AS PrevPostByOwnerCreationDate, -- Window function: previous post by same owner
    EXTRACT(EPOCH FROM (Q.LastActivityDate - Q.PostCreationDate)) / 3600.0 AS HoursSinceCreationToLastActivity, -- Time difference calculation
    NULLIF(LENGTH(TRIM(Q.Body)), 0) AS BodyLengthChars, -- String function (LENGTH, TRIM) and NULL logic
    (SELECT
        STRING_AGG(COALESCE(U2.DisplayName, 'Community User'), ', ') -- String aggregation with NULL logic
     FROM PostHistory AS PH2
     LEFT JOIN Users AS U2 ON PH2.UserId = U2.Id
     WHERE PH2.PostId = Q.PostId AND PH2.PostHistoryTypeId IN (10, 101, 102, 103, 104, 105) -- Closed event types
     ORDER BY PH2.CreationDate
     LIMIT 3 -- Limit string length for readability
    ) AS ClosedByUsersSample, -- Correlated subquery for close event participants
    (SELECT COUNT(*)
     FROM Votes AS V
     WHERE V.PostId = Q.PostId AND V.VoteTypeId IN (4, 12) -- Offensive or Spam votes
    ) AS FlagCount, -- Correlated subquery for flag count
    (SELECT COUNT(*) FROM Comments WHERE PostId = Q.PostId AND TEXT ILIKE '%bug%') AS BugMentionCount -- Correlated subquery for specific string pattern in comments
FROM PostHistoricalMetrics AS Q
LEFT JOIN UserEngagement AS UE ON Q.OwnerUserId = UE.UserId
LEFT JOIN AggregatedTagStats AS ATS ON Q.PostId = ATS.PostId
WHERE
    Q.ViewCount > 10000 -- Complex predicates
    AND Q.PostScore > 500
    AND Q.AnswerCount >= 5
    AND Q.QuestionCommentCount >= 3
    AND Q.PostCreationDate BETWEEN '2015-01-01' AND '2023-01-01'
    AND (
        Q.Tags ILIKE '%<sql>%' OR Q.Tags ILIKE '%<database>%' OR Q.Tags ILIKE '%<performance>%'
        OR Q.Title ILIKE '%optimization%' OR Q.Title ILIKE '%scalability%'
    ) -- String expressions with ILIKE and complex OR condition
    AND NOT EXISTS (
        SELECT 1
        FROM PostHistory AS PH_DEL
        WHERE PH_DEL.PostId = Q.PostId AND PH_DEL.PostHistoryTypeId = 12 -- Post Deleted (correlated subquery to exclude deleted posts)
    )
    AND (UE.Reputation IS NULL OR UE.Reputation > 5000) -- NULL logic combined with value condition for owner reputation
    AND COALESCE(Q.FavoriteCount, 0) > 10 -- NULL logic for FavoriteCount
    AND Q.AvgAnswerScore IS NOT NULL -- NULL logic to ensure posts with answers are considered
ORDER BY
    AvgPostScoreForTag DESC,
    Q.PostScore DESC,
    HoursSinceCreationToLastActivity ASC
LIMIT 500;
