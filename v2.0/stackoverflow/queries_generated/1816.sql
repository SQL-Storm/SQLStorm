-- {"query": "1816.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-flash", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 2749} 

WITH UserEngagement AS (
    SELECT
        U.Id AS UserId,
        U.DisplayName,
        U.Reputation,
        U.CreationDate AS UserCreationDate,
        JULIANDAY('now') - JULIANDAY(U.CreationDate) AS UserTenureDays,
        COUNT(DISTINCT P.Id) AS TotalPostsCreated,
        COUNT(DISTINCT CASE WHEN P.PostTypeId = 1 THEN P.Id END) AS TotalQuestionsAsked,
        COUNT(DISTINCT CASE WHEN P.PostTypeId = 2 THEN P.Id END) AS TotalAnswersProvided,
        COUNT(DISTINCT C.Id) AS TotalCommentsMade,
        COUNT(DISTINCT B.Id) AS TotalBadgesEarned,
        SUM(COALESCE(PV_Up.VoteCount, 0)) AS TotalUpvotesReceived,
        SUM(COALESCE(PV_Down.VoteCount, 0)) AS TotalDownvotesReceived,
        CAST(U.UpVotes AS REAL) / NULLIF(U.DownVotes, 0) AS UpDownVoteRatio,
        MAX(CASE WHEN P.PostTypeId = 1 THEN P.ViewCount ELSE 0 END) AS MaxQuestionViewCount,
        SUM(CASE WHEN P.PostTypeId = 1 THEN P.ViewCount ELSE 0 END) AS TotalQuestionViewCount
    FROM
        Users AS U
    LEFT JOIN
        Posts AS P ON U.Id = P.OwnerUserId
    LEFT JOIN
        Comments AS C ON U.Id = C.UserId
    LEFT JOIN
        Badges AS B ON U.Id = B.UserId
    LEFT JOIN (
        SELECT PostId, COUNT(*) AS VoteCount FROM Votes WHERE VoteTypeId = 2 GROUP BY PostId
    ) AS PV_Up ON P.Id = PV_Up.PostId
    LEFT JOIN (
        SELECT PostId, COUNT(*) AS VoteCount FROM Votes WHERE VoteTypeId = 3 GROUP BY PostId
    ) AS PV_Down ON P.Id = PV_Down.PostId
    GROUP BY
        U.Id, U.DisplayName, U.Reputation, U.CreationDate, U.UpVotes, U.DownVotes
),
PostHistoricalAnalysis AS (
    SELECT
        P.Id AS PostId,
        P.PostTypeId,
        P.OwnerUserId,
        P.CreationDate AS PostCreationDate,
        P.LastEditDate,
        P.LastActivityDate,
        P.Score,
        P.ViewCount,
        P.AnswerCount,
        P.CommentCount,
        P.FavoriteCount,
        P.Tags,
        JULIANDAY('now') - JULIANDAY(P.CreationDate) AS PostAgeDays,
        (JULIANDAY(COALESCE(P.LastEditDate, P.CreationDate)) - JULIANDAY(P.CreationDate)) * 24 * 60 * 60 AS TimeToFirstEditSeconds,
        COUNT(DISTINCT PH_Edit.UserId) AS UniqueEditors,
        SUM(CASE WHEN PH_Close.PostHistoryTypeId = 10 THEN 1 ELSE 0 END) AS CloseEvents,
        SUM(CASE WHEN PH_Reopen.PostHistoryTypeId = 11 THEN 1 ELSE 0 END) AS ReopenEvents,
        (
            SELECT MAX(CAST(ph_inner.Comment AS INTEGER))
            FROM PostHistory AS ph_inner
            WHERE ph_inner.PostId = P.Id
              AND ph_inner.PostHistoryTypeId = 10 -- Post Closed event
              AND ph_inner.Comment IS NOT NULL
              AND LENGTH(ph_inner.Comment) < 5 -- Heuristic to filter out potential JSON and keep simple IDs
        ) AS MainCloseReasonId, -- Correlated subquery to get the primary close reason if present in the comment field
        ROW_NUMBER() OVER (PARTITION BY P.PostTypeId ORDER BY P.Score DESC, P.ViewCount DESC) AS PostTypeScoreRank
    FROM
        Posts AS P
    LEFT JOIN
        PostHistory AS PH_Edit ON P.Id = PH_Edit.PostId AND PH_Edit.PostHistoryTypeId IN (4, 5, 6) -- Edit Title, Body, Tags
    LEFT JOIN
        PostHistory AS PH_Close ON P.Id = PH_Close.PostId AND PH_Close.PostHistoryTypeId = 10 -- Post Closed
    LEFT JOIN
        PostHistory AS PH_Reopen ON P.Id = PH_Reopen.PostId AND PH_Reopen.PostHistoryTypeId = 11 -- Post Reopened
    GROUP BY
        P.Id, P.PostTypeId, P.OwnerUserId, P.CreationDate, P.LastEditDate, P.LastActivityDate, P.Score, P.ViewCount, P.AnswerCount, P.CommentCount, P.FavoriteCount, P.Tags
),
CommentSentimentAnalysis AS (
    SELECT
        C.PostId,
        AVG(C.Score) AS AverageCommentScore,
        COUNT(C.Id) AS TotalCommentsForPost,
        SUM(CASE WHEN C.Text LIKE '%thank%' OR C.Text LIKE '%appreciate%' OR C.Text LIKE '%good answer%' THEN 1 ELSE 0 END) AS PositiveCommentCount,
        SUM(CASE WHEN C.Text LIKE '%problem%' OR C.Text LIKE '%bug%' OR C.Text LIKE '%error%' OR C.Text LIKE '%wrong%' THEN 1 ELSE 0 END) AS NegativeCommentCount,
        AVG(LENGTH(C.Text)) AS AverageCommentLength
    FROM
        Comments AS C
    GROUP BY
        C.PostId
),
PostTaggingInfo AS (
    SELECT
        P.Id AS PostId,
        P.OwnerUserId,
        MAX(CASE WHEN P.Tags LIKE '%<sql>%' THEN 1 ELSE 0 END) AS HasSqlTag,
        MAX(CASE WHEN P.Tags LIKE '%<database>%' THEN 1 ELSE 0 END) AS HasDatabaseTag,
        MAX(CASE WHEN P.Tags LIKE '%<performance>%' THEN 1 ELSE 0 END) AS HasPerformanceTag,
        MAX(CASE WHEN P.Tags LIKE '%<javascript>%' THEN 1 ELSE 0 END) AS HasJavascriptTag,
        MAX(CASE WHEN P.Tags LIKE '%<python>%' THEN 1 ELSE 0 END) AS HasPythonTag
    FROM
        Posts AS P
    WHERE P.Tags IS NOT NULL
    GROUP BY
        P.Id, P.OwnerUserId
),
ConsecutiveCloseReopen AS (
    SELECT
        PH.PostId,
        PH.CreationDate AS CloseDate,
        LEAD(PH.CreationDate, 1) OVER (PARTITION BY PH.PostId ORDER BY PH.CreationDate) AS NextEventDate,
        LEAD(PH.PostHistoryTypeId, 1) OVER (PARTITION BY PH.PostId ORDER BY PH.CreationDate) AS NextEventTypeId,
        JULIANDAY(LEAD(PH.CreationDate, 1) OVER (PARTITION BY PH.PostId ORDER BY PH.CreationDate)) - JULIANDAY(PH.CreationDate) AS TimeToReopenDays
    FROM
        PostHistory AS PH
    WHERE
        PH.PostHistoryTypeId = 10 -- Post Closed
)
SELECT
    UE.DisplayName AS UserDisplayName,
    UE.Reputation,
    UE.TotalPostsCreated,
    PHA.PostId,
    PT.Name AS PostTypeName,
    PHA.PostCreationDate,
    PHA.Score AS PostScore,
    PHA.ViewCount AS PostViewCount,
    PHA.AnswerCount,
    PHA.CommentCount AS OriginalCommentCount, -- From Posts table
    PHA.FavoriteCount,
    PHA.PostAgeDays,
    PHA.UniqueEditors,
    PHA.CloseEvents,
    PHA.ReopenEvents,
    CR.Name AS MainCloseReason, -- Outer Join
    PTI.HasSqlTag,
    PTI.HasDatabaseTag,
    CSA.AverageCommentScore,
    CSA.TotalCommentsForPost, -- From CommentSentimentAnalysis CTE
    CSA.PositiveCommentCount,
    CSA.NegativeCommentCount,
    CCR.TimeToReopenDays,
    PHA.PostTypeScoreRank,
    COALESCE(UE.TotalAnswersProvided, 0) * 1.0 / NULLIF(UE.TotalQuestionsAsked, 0) AS AnswerRatioForUser,
    -- Complex calculation for a 'quality score'
    (PHA.Score * 0.5 + COALESCE(PHA.FavoriteCount, 0) * 1.5 + COALESCE(CSA.AverageCommentScore, 0) * 0.2
        + CASE WHEN PTI.HasSqlTag = 1 AND PTI.HasPerformanceTag = 1 THEN 10 ELSE 0 END
        - CASE WHEN PHA.CloseEvents > 0 THEN PHA.CloseEvents * 5 ELSE 0 END
        + CASE WHEN PHA.ReopenEvents > 0 THEN PHA.ReopenEvents * 3 ELSE 0 END
        + (COALESCE(PHA.ViewCount, 0) * 1.0 / NULLIF(PHA.PostAgeDays, 0)) * 0.01 -- View velocity, handles PostAgeDays being 0/NULL
    ) AS PostQualityScore,
    UPPER(SUBSTR(UE.DisplayName, 1, 3)) || '-' || COALESCE(LENGTH(PHA.Tags), 0) || '-' || COALESCE(CAST(PHA.MainCloseReasonId AS TEXT), 'N/A') AS PostIdentifierHash, -- String manipulation and NULL logic
    (SELECT COUNT(DISTINCT V.UserId) FROM Votes AS V WHERE V.PostId = PHA.PostId AND V.VoteTypeId = 5) AS NumberOfFavoriters -- Correlated subquery
FROM
    UserEngagement AS UE
INNER JOIN
    PostHistoricalAnalysis AS PHA ON UE.UserId = PHA.OwnerUserId
LEFT JOIN
    PostTypes AS PT ON PHA.PostTypeId = PT.Id
LEFT JOIN
    CloseReasonTypes AS CR ON PHA.MainCloseReasonId = CR.Id
LEFT JOIN
    CommentSentimentAnalysis AS CSA ON PHA.PostId = CSA.PostId
LEFT JOIN
    PostTaggingInfo AS PTI ON PHA.PostId = PTI.PostId
LEFT JOIN (
    SELECT PostId, MIN(TimeToReopenDays) AS TimeToReopenDays -- Get the min time if closed and reopened multiple times
    FROM ConsecutiveCloseReopen
    WHERE NextEventTypeId = 11 AND TimeToReopenDays IS NOT NULL
    GROUP BY PostId
) AS CCR ON PHA.PostId = CCR.PostId
WHERE
    UE.Reputation > 5000 -- Filter for more established users
    AND PHA.PostAgeDays > 60 -- Only posts older than 2 months
    AND (PHA.Score > 25 OR COALESCE(PHA.FavoriteCount, 0) > 5) -- Relatively popular posts
    AND (PTI.HasSqlTag = 1 OR PTI.HasDatabaseTag = 1 OR PTI.HasPerformanceTag = 1 OR PTI.HasPythonTag = 1 OR PTI.HasJavascriptTag = 1) -- Filter for specific tech tags
    AND PHA.PostTypeScoreRank <= 5000 -- Only consider a top range of posts by score within their type
    AND (PHA.UniqueEditors > 0 OR PHA.LastEditDate IS NULL) -- Edited by someone or never edited (and not by community user/self-edit only)
    AND COALESCE(CSA.TotalCommentsForPost, 0) > 5 -- Posts with a decent number of comments
    AND COALESCE(CSA.NegativeCommentCount, 0) * 1.0 / NULLIF(COALESCE(CSA.TotalCommentsForPost, 0), 0) < 0.25 -- Less than 25% negative comments
    AND PHA.OwnerUserId IS NOT NULL -- Exclude community user posts etc.
    AND UE.TotalPostsCreated > 10 -- Users who created more than 10 posts
ORDER BY
    PostQualityScore DESC, UE.Reputation DESC, PHA.PostAgeDays ASC
LIMIT 2000;
