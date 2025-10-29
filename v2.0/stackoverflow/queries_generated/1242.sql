-- {"query": "1242.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-flash", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 3089} 
WITH UserEngagement AS (
    SELECT
        U.Id AS UserId,
        U.DisplayName,
        U.Reputation,
        U.CreationDate,
        U.LastAccessDate,
        U.Views AS UserViews,
        U.UpVotes AS UserUpVotes,
        U.DownVotes AS UserDownVotes,
        COUNT(DISTINCT P.Id) AS TotalPostsCount,
        SUM(CASE WHEN P.PostTypeId = 1 THEN 1 ELSE 0 END) AS QuestionCount,
        SUM(CASE WHEN P.PostTypeId = 2 THEN 1 ELSE 0 END) AS AnswerCount,
        AVG(CASE WHEN P.PostTypeId = 1 THEN P.Score ELSE NULL END) AS AvgQuestionScore,
        MAX(CASE WHEN P.PostTypeId = 2 THEN P.Score ELSE NULL END) AS MaxAnswerScore,
        SUM(P.ViewCount) AS TotalPostViewCount,
        SUM(P.CommentCount) AS TotalPostCommentCount,
        SUM(P.FavoriteCount) AS TotalFavoriteCount,
        COUNT(DISTINCT C.Id) AS TotalCommentsMadeByUser,
        MAX(P.LastActivityDate) AS LastPostActivity,
        MIN(P.CreationDate) AS FirstPostCreation,
        COUNT(DISTINCT PH.PostId) FILTER (WHERE PH.PostHistoryTypeId IN (4,5,6) AND PH.UserId = U.Id) AS SelfEditedPostsCount, -- Posts owned by U and edited by U
        COUNT(DISTINCT PH_all.PostId) FILTER (WHERE PH_all.PostHistoryTypeId IN (10, 11) AND P.Id = PH_all.PostId) AS PostClosedReopenedEvents -- Closed or Reopened posts owned by U
    FROM
        Users U
    LEFT JOIN
        Posts P ON U.Id = P.OwnerUserId
    LEFT JOIN
        Comments C ON U.Id = C.UserId
    LEFT JOIN
        PostHistory PH ON U.Id = PH.UserId AND P.Id = PH.PostId -- Specific history actions by this user on their own posts
    LEFT JOIN
        PostHistory PH_all ON P.Id = PH_all.PostId -- All history actions on this user's posts
    GROUP BY
        U.Id, U.DisplayName, U.Reputation, U.CreationDate, U.LastAccessDate, U.Views, U.UpVotes, U.DownVotes
),
QuestionTagDiversity AS (
    SELECT
        P.OwnerUserId AS UserId,
        COUNT(DISTINCT TRIM(unnest(string_to_array(SUBSTRING(P.Tags FROM 2 FOR LENGTH(P.Tags)-2), '><')))) AS DistinctQuestionTags,
        AVG(LENGTH(TRIM(unnest(string_to_array(SUBSTRING(P.Tags FROM 2 FOR LENGTH(P.Tags)-2), '><'))))) AS AvgTagLength,
        COUNT(DISTINCT T.Id) FILTER (WHERE T.IsModeratorOnly = TRUE) AS ModeratorOnlyTagCount
    FROM
        Posts P
    LEFT JOIN
        Tags T ON T.TagName = TRIM(unnest(string_to_array(SUBSTRING(P.Tags FROM 2 FOR LENGTH(P.Tags)-2), '><')))
    WHERE
        P.PostTypeId = 1 AND P.Tags IS NOT NULL AND LENGTH(P.Tags) > 2 AND P.OwnerUserId IS NOT NULL
    GROUP BY
        P.OwnerUserId
),
ComplexPostHistoryAnalysis AS (
    SELECT
        P.Id AS PostId,
        P.OwnerUserId AS PostOwnerUserId,
        P.CreationDate AS PostCreationDate,
        P.LastEditDate,
        P.LastActivityDate,
        SUM(CASE WHEN PH.PostHistoryTypeId IN (4,5,6) THEN 1 ELSE 0 END) AS EditCount,
        MAX(CASE WHEN PH.PostHistoryTypeId = 10 THEN PH.CreationDate ELSE NULL END) AS LastClosedDate,
        MAX(CASE WHEN PH.PostHistoryTypeId = 11 THEN PH.CreationDate ELSE NULL END) AS LastReopenedDate,
        MAX(CASE WHEN PH.PostHistoryTypeId = 35 THEN 1 ELSE 0 END) AS WasMigratedAway,
        MIN(PH.CreationDate) FILTER (WHERE PH.PostHistoryTypeId = 2) AS InitialBodyDate,
        MAX(PH.CreationDate) FILTER (WHERE PH.PostHistoryTypeId = 8) AS LastBodyRollbackDate,
        LAG(PH.CreationDate, 1, PH.CreationDate) OVER (PARTITION BY P.Id, PH.PostHistoryTypeId ORDER BY PH.CreationDate) AS PreviousHistoryEventDate
    FROM
        Posts P
    JOIN
        PostHistory PH ON P.Id = PH.PostId
    WHERE
        P.OwnerUserId IS NOT NULL
        AND P.PostTypeId IN (1, 2)
    GROUP BY
        P.Id, P.OwnerUserId, P.CreationDate, P.LastEditDate, P.LastActivityDate
),
ControversialAnswersSummary AS (
    SELECT
        P.OwnerUserId AS UserId,
        P.Id AS AnswerId,
        P.Score AS AnswerScore,
        P.CreationDate AS AnswerCreationDate,
        P.ParentId AS QuestionId,
        SUM(CASE WHEN V.VoteTypeId = 2 THEN 1 ELSE 0 END) AS Upvotes,
        SUM(CASE WHEN V.VoteTypeId = 3 THEN 1 ELSE 0 END) AS Downvotes,
        COUNT(DISTINCT C.Id) AS CommentCountOnAnswer,
        ROW_NUMBER() OVER (PARTITION BY P.OwnerUserId ORDER BY P.Score DESC, COUNT(DISTINCT C.Id) DESC) AS Rnk_UserAnswer
    FROM
        Posts P
    LEFT JOIN
        Votes V ON P.Id = V.PostId
    LEFT JOIN
        Comments C ON P.Id = C.PostId
    WHERE
        P.PostTypeId = 2 AND P.OwnerUserId IS NOT NULL
    GROUP BY
        P.OwnerUserId, P.Id, P.Score, P.CreationDate, P.ParentId
    HAVING
        SUM(CASE WHEN V.VoteTypeId = 2 THEN 1 ELSE 0 END) >= 5 -- at least 5 upvotes
        AND SUM(CASE WHEN V.VoteTypeId = 3 THEN 1 ELSE 0 END) >= 3 -- at least 3 downvotes
        AND (SUM(CASE WHEN V.VoteTypeId = 3 THEN 1 ELSE 0 END) * 1.0 / NULLIF(SUM(CASE WHEN V.VoteTypeId = 2 THEN 1 ELSE 0 END), 0)) > 0.4 -- downvote ratio > 40%
),
RecentHighActivityUsers AS (
    SELECT
        ue.UserId,
        ue.DisplayName,
        ue.Reputation,
        ue.LastAccessDate,
        EXTRACT(EPOCH FROM (CURRENT_TIMESTAMP - ue.LastAccessDate)) / 86400.0 AS DaysSinceLastAccess,
        NTILE(10) OVER (ORDER BY ue.Reputation DESC) AS ReputationDecile,
        RANK() OVER (ORDER BY ue.TotalPostsCount DESC, ue.TotalCommentsMadeByUser DESC) AS OverallActivityRank,
        AVG(ue.AvgQuestionScore) OVER (PARTITION BY NTILE(10) OVER (ORDER BY ue.Reputation DESC)) AS AvgQuestionScoreInDecile
    FROM
        UserEngagement ue
    WHERE
        ue.LastAccessDate >= CURRENT_TIMESTAMP - INTERVAL '6 months'
        AND ue.TotalPostsCount > 10
        AND ue.QuestionCount > 0
),
UsersWithComplexPostInteraction AS (
    SELECT DISTINCT
        cpha.PostOwnerUserId AS UserId,
        COUNT(DISTINCT cpha.PostId) AS ComplexInteractionPostCount,
        AVG(EXTRACT(EPOCH FROM (cpha.LastReopenedDate - cpha.LastClosedDate)) / 86400.0) AS AvgReopenDays
    FROM
        ComplexPostHistoryAnalysis cpha
    WHERE
        cpha.EditCount > 1 -- At least two edits
        AND cpha.LastClosedDate IS NOT NULL -- Was closed at some point
        AND cpha.LastReopenedDate IS NOT NULL -- Was reopened at some point
        AND (cpha.LastReopenedDate - cpha.LastClosedDate) < INTERVAL '30 days' -- Reopened within 30 days of closing
        AND cpha.WasMigratedAway = 0 -- Not migrated away
    GROUP BY
        cpha.PostOwnerUserId
    HAVING
        COUNT(DISTINCT cpha.PostId) >= 2 -- At least two such posts
),
TopControversialAnswersPerUser AS (
    SELECT
        UserId,
        AnswerId AS TopControversialAnswerId,
        AnswerScore AS TopControversialAnswerScore,
        QuestionId AS QuestionOfControversialAnswer,
        Upvotes AS TopControversialUpvotes,
        Downvotes AS TopControversialDownvotes
    FROM
        ControversialAnswersSummary
    WHERE
        Rnk_UserAnswer = 1
)
SELECT
    RHA.UserId,
    RHA.DisplayName,
    RHA.Reputation,
    RHA.ReputationDecile,
    RHA.DaysSinceLastAccess,
    RHA.OverallActivityRank,
    RHA.AvgQuestionScoreInDecile,
    UE.TotalPostsCount,
    UE.QuestionCount,
    UE.AnswerCount,
    UE.AvgQuestionScore,
    UE.MaxAnswerScore,
    UE.TotalPostViewCount,
    UE.TotalCommentsMadeByUser,
    TD.DistinctQuestionTags,
    TD.AvgTagLength,
    TD.ModeratorOnlyTagCount,
    CASE
        WHEN RHA.DaysSinceLastAccess < 7 AND UE.TotalCommentsMadeByUser > 50 THEN 'Highly Engaged Recent User'
        WHEN RHA.DaysSinceLastAccess < 30 AND UE.QuestionCount > 5 AND UE.AvgQuestionScore > 10 THEN 'Active Questioner with Good Content'
        WHEN UE.SelfEditedPostsCount > 5 AND UCI.ComplexInteractionPostCount IS NOT NULL THEN 'Self-Reflecting and Complex Contributor'
        ELSE 'Moderately Engaged User'
    END AS UserEngagementCategory,
    COALESCE(UCI.UserId IS NOT NULL, FALSE) AS HasComplexPostHistory, -- NULL logic, boolean check
    TCA.TopControversialAnswerId,
    TCA.TopControversialAnswerScore,
    TCA.TopControversialUpvotes,
    TCA.TopControversialDownvotes,
    (UE.UserUpVotes * 1.0 / NULLIF(UE.UserDownVotes, 0)) AS UserUpToDownVoteRatio, -- NULLIF for division by zero
    AGE(CURRENT_TIMESTAMP, UE.CreationDate) AS AccountAge, -- Date calculation
    LOWER(TRIM(SUBSTRING(U.Location FROM POSITION(',' IN U.Location) + 1))) AS RegionSuffix, -- String manipulation
    REPLACE(U.DisplayName, ' ', '-') AS DisplayNameSlug,
    (SELECT COUNT(B.Id) FROM Badges B WHERE B.UserId = RHA.UserId AND B.Date >= RHA.LastAccessDate - INTERVAL '3 months') AS RecentBadgesAwardedCount, -- Correlated subquery
    (SELECT AVG(P_inner.Score) FROM Posts P_inner WHERE P_inner.OwnerUserId = RHA.UserId AND P_inner.PostTypeId = 1 AND P_inner.CreationDate > CURRENT_TIMESTAMP - INTERVAL '1 year' AND P_inner.ViewCount > (SELECT AVG(ViewCount) FROM Posts WHERE PostTypeId = 1)) AS AvgRecentHighViewQuestionScore -- Another correlated subquery
FROM
    RecentHighActivityUsers RHA
JOIN
    UserEngagement UE ON RHA.UserId = UE.UserId
LEFT JOIN
    QuestionTagDiversity TD ON RHA.UserId = TD.UserId
LEFT JOIN
    UsersWithComplexPostInteraction UCI ON RHA.UserId = UCI.UserId -- Outer join for NULL logic
LEFT JOIN
    TopControversialAnswersPerUser TCA ON RHA.UserId = TCA.UserId -- Outer join for NULL logic
LEFT JOIN
    Users U ON RHA.UserId = U.Id -- To get Location and AboutMe for final string ops and filtering
WHERE
    RHA.ReputationDecile <= 3 -- Top 30% by reputation
    AND UE.TotalPostsCount > 20
    AND (TD.DistinctQuestionTags IS NULL OR TD.DistinctQuestionTags > 5) -- Users with diverse tags or no questions posted
    AND (
        (UE.AvgQuestionScore IS NOT NULL AND UE.AvgQuestionScore > 15)
        OR (UE.MaxAnswerScore IS NOT NULL AND UE.MaxAnswerScore > 20)
    )
    AND (
        (UCI.UserId IS NOT NULL AND TCA.TopControversialAnswerId IS NOT NULL AND UE.SelfEditedPostsCount > 0) -- Users with complex history, controversial answers, AND self-edited posts
        OR (RHA.DaysSinceLastAccess < 14 AND UE.TotalCommentsMadeByUser > 100 AND UE.QuestionCount >= 3) -- Or very recently active, highly communicative, and has asked at least 3 questions
    )
    AND (U.AboutMe IS NOT NULL AND (U.AboutMe ILIKE '%sql%' OR U.AboutMe ILIKE '%database%')) -- String search using ILIKE
ORDER BY
    RHA.Reputation DESC, RHA.DaysSinceLastAccess ASC, UE.TotalPostsCount DESC;