-- {"query": "1805.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-flash", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 2801}
WITH UserEngagement AS (
    SELECT
        U.Id AS UserId,
        U.DisplayName,
        U.Reputation,
        U.Views AS UserViews,
        COUNT(DISTINCT B.Id) AS TotalBadges,
        SUM(CASE WHEN V.VoteTypeId = 2 THEN 1 ELSE 0 END) AS TotalUpVotesGiven,
        SUM(CASE WHEN V.VoteTypeId = 3 THEN 1 ELSE 0 END) AS TotalDownVotesGiven,
        EXTRACT(EPOCH FROM (U.LastAccessDate - U.CreationDate)) / 86400.0 AS AccountActiveDays,
        (SELECT COUNT(DISTINCT PH.PostId) FROM PostHistory PH WHERE PH.UserId = U.Id AND PH.PostHistoryTypeId IN (4, 5, 6)) AS PostsEditedCount,
        (SELECT AVG(C.Score) FROM Comments C WHERE C.UserId = U.Id) AS AvgCommentScoreByUser
    FROM
        Users U
    LEFT JOIN Badges B ON U.Id = B.UserId
    LEFT JOIN Votes V ON U.Id = V.UserId
    GROUP BY
        U.Id, U.DisplayName, U.Reputation, U.Views, U.LastAccessDate, U.CreationDate
),
PostAggregates AS (
    SELECT
        P.Id AS PostId,
        P.PostTypeId,
        P.OwnerUserId,
        P.CreationDate AS PostCreationDate,
        P.LastActivityDate,
        P.Score AS PostScore,
        P.ViewCount,
        P.AnswerCount,
        P.CommentCount AS DirectCommentCount,
        P.FavoriteCount,
        P.AcceptedAnswerId,
        COALESCE(P.ClosedDate, CAST('1900-01-01 00:00:00' AS timestamp)) AS ActualClosedDate,
        (CASE WHEN P.Tags IS NOT NULL AND LENGTH(P.Tags) > 2 THEN string_to_array(substring(P.Tags, 2, length(P.Tags)-2), '><') ELSE NULL END) AS TagArray,
        (SELECT MAX(C.Score) FROM Comments C WHERE C.PostId = P.Id) AS MaxRelatedCommentScore,
        SUM(CASE WHEN C.Id IS NOT NULL THEN C.Score ELSE 0 END) AS TotalCommentsScore,
        COUNT(C.Id) AS TotalComments
    FROM
        Posts P
    LEFT JOIN Comments C ON P.Id = C.PostId
    GROUP BY
        P.Id, P.PostTypeId, P.OwnerUserId, P.CreationDate, P.LastActivityDate, P.Score, P.ViewCount, P.AnswerCount, P.CommentCount, P.FavoriteCount, P.AcceptedAnswerId, P.ClosedDate, P.Tags
),
PostHistoryDetails AS (
    SELECT
        PH.PostId,
        MAX(CASE WHEN PHT.Name = 'Post Closed' THEN PH.CreationDate END) AS LastClosedDate,
        MAX(CASE WHEN PHT.Name = 'Post Reopened' THEN PH.CreationDate END) AS LastReopenedDate,
        COUNT(DISTINCT PH.UserId) AS DistinctEditors,
        MAX(CASE WHEN PH.PostHistoryTypeId = 1 THEN PH.CreationDate END) AS InitialCreationDate,
        MIN(PH.CreationDate) AS FirstHistoryEntry,
        MAX(PH.CreationDate) AS LastHistoryEntry
    FROM
        PostHistory PH
    JOIN PostHistoryTypes PHT ON PH.PostHistoryTypeId = PHT.Id
    GROUP BY
        PH.PostId
),
TagUsageStats AS (
    SELECT
        tag AS TagName,
        COUNT(DISTINCT PA.PostId) AS PostsWithTag,
        AVG(PA.PostScore) AS AvgScoreForTag,
        SUM(PA.ViewCount) AS TotalViewsForTag
    FROM
        PostAggregates PA,
        LATERAL (
            SELECT unnest(PA.TagArray) AS tag
        ) t
    WHERE PA.TagArray IS NOT NULL
    GROUP BY
        tag
)
(
    SELECT
        P.Id AS PostId,
        P.PostTypeId,
        P.Title,
        P.CreationDate AS PostCreationDate,
        P.Score AS PostScore,
        P.ViewCount,
        P.AnswerCount,
        UE.DisplayName AS OwnerDisplayName,
        UE.Reputation AS OwnerReputation,
        UE.TotalBadges AS OwnerBadgeCount,
        PA.TotalComments AS TotalCommentsOnPost,
        PA.MaxRelatedCommentScore,
        COALESCE(PA.FavoriteCount, 0) AS ActualFavoriteCount,
        PHD.LastClosedDate,
        PHD.LastReopenedDate,
        PHD.DistinctEditors,
        (PA.PostScore * 0.5 + P.ViewCount * 0.1 + PA.TotalComments * 0.2 + COALESCE(PA.FavoriteCount, 0) * 0.8) AS EngagementMetric,
        RANK() OVER (PARTITION BY P.OwnerUserId ORDER BY P.Score DESC, P.ViewCount DESC) AS RankAmongOwnerPosts,
        NTILE(5) OVER (ORDER BY P.Score DESC) AS ScoreQuintile,
        LAG(P.Score, 1, 0) OVER (PARTITION BY P.OwnerUserId ORDER BY P.CreationDate) AS PrevPostScoreByOwner,
        (
            SELECT AVG(A.Score)
            FROM Posts A
            WHERE A.ParentId = P.Id AND A.PostTypeId = 2
        ) AS AvgChildPostScore,
        CASE
            WHEN P.Title ILIKE '%performance%' OR P.Title ILIKE '%benchmark%' THEN 'Performance Topic'
            WHEN P.Body ILIKE '%database%' OR P.Body ILIKE '%sql%' THEN 'Database/SQL Topic'
            ELSE 'Other Topic'
        END AS PostTopicCategory,
        COALESCE(
            EXTRACT(EPOCH FROM (PHD.LastReopenedDate - PHD.LastClosedDate)) / 3600.0,
            0.0
        ) AS TimeBetweenCloseAndReopenHours,
        (SELECT COUNT(DISTINCT T.TagName) FROM TagUsageStats T WHERE T.TagName = ANY(PA.TagArray)) AS UniqueTagsInPost,
        CASE
            WHEN P.AcceptedAnswerId IS NOT NULL THEN 'Accepted'
            WHEN P.ClosedDate IS NOT NULL THEN 'Closed'
            ELSE 'Open'
        END AS PostStatus
    FROM
        Posts P
    JOIN
        PostAggregates PA ON P.Id = PA.PostId AND P.PostTypeId = 1
    LEFT JOIN
        UserEngagement UE ON P.OwnerUserId = UE.UserId
    LEFT JOIN
        PostHistoryDetails PHD ON P.Id = PHD.PostId
    WHERE
        P.ViewCount > 1000
        AND PA.PostScore > 5
        AND P.CreationDate BETWEEN CAST('2020-01-01' AS date) AND CAST('2023-12-31' AS date)
        AND (
            (UE.Reputation IS NOT NULL AND UE.Reputation > 5000 AND UE.AccountActiveDays > 365)
            OR
            (PHD.LastClosedDate IS NOT NULL AND PHD.LastReopenedDate IS NOT NULL AND PHD.DistinctEditors > 1)
        )
        AND P.OwnerUserId IS NOT NULL
    ORDER BY
        EngagementMetric DESC, P.CreationDate DESC
    LIMIT 700
)
UNION ALL
(
    SELECT
        P_Ans.Id AS PostId,
        P_Ans.PostTypeId,
        P_Q.Title AS Title,
        P_Ans.CreationDate AS PostCreationDate,
        P_Ans.Score AS PostScore,
        P_Q.ViewCount AS ViewCount,
        P_Q.AnswerCount AS AnswerCount,
        UE_Ans.DisplayName AS OwnerDisplayName,
        UE_Ans.Reputation AS OwnerReputation,
        UE_Ans.TotalBadges AS OwnerBadgeCount,
        PA_Ans.TotalComments AS TotalCommentsOnPost,
        PA_Ans.MaxRelatedCommentScore,
        COALESCE(PA_Ans.FavoriteCount, 0) AS ActualFavoriteCount,
        PHD_Q.LastClosedDate,
        PHD_Q.LastReopenedDate,
        PHD_Ans.DistinctEditors,
        (P_Ans.Score * 1.5 + PA_Ans.TotalComments * 0.5 + COALESCE(P_Ans.FavoriteCount, 0) * 0.7) AS EngagementMetric,
        RANK() OVER (PARTITION BY P_Ans.OwnerUserId ORDER BY P_Ans.Score DESC) AS RankAmongOwnerPosts,
        NTILE(5) OVER (ORDER BY P_Ans.Score DESC) AS ScoreQuintile,
        LAG(P_Ans.Score, 1, 0) OVER (PARTITION BY P_Ans.OwnerUserId ORDER BY P_Ans.CreationDate) AS PrevPostScoreByOwner,
        CAST(NULL AS numeric) AS AvgChildPostScore,
        CASE
            WHEN P_Q.Tags ILIKE '%<python>%' OR P_Q.Tags ILIKE '%<java>%' THEN 'Popular Language Answer'
            WHEN P_Q.Tags ILIKE '%<optimization>%' OR P_Q.Tags ILIKE '%<algorithm>%' THEN 'Algorithm/Optimization Answer'
            ELSE 'General Answer'
        END AS PostTopicCategory,
        CAST(NULL AS numeric) AS TimeBetweenCloseAndReopenHours,
        (SELECT COUNT(DISTINCT T.TagName) FROM TagUsageStats T WHERE T.TagName = ANY(PA_Q.TagArray)) AS UniqueTagsInPost,
        CASE
            WHEN P_Q.AcceptedAnswerId = P_Ans.Id THEN 'AcceptedAnswer'
            ELSE 'Answer'
        END AS PostStatus
    FROM
        Posts P_Ans
    JOIN
        PostAggregates PA_Ans ON P_Ans.Id = PA_Ans.PostId
    JOIN
        UserEngagement UE_Ans ON P_Ans.OwnerUserId = UE_Ans.UserId
    LEFT JOIN
        Posts P_Q ON P_Ans.ParentId = P_Q.Id
    LEFT JOIN
        PostAggregates PA_Q ON P_Q.Id = PA_Q.PostId
    LEFT JOIN
        PostHistoryDetails PHD_Q ON P_Q.Id = PHD_Q.PostId
    LEFT JOIN
        PostHistoryDetails PHD_Ans ON P_Ans.Id = PHD_Ans.PostId
    WHERE
        P_Ans.PostTypeId = 2
        AND P_Ans.CreationDate BETWEEN CAST('2023-01-01' AS date) AND CAST('2023-12-31' AS date)
        AND UE_Ans.Reputation > 10000
        AND UE_Ans.PostsEditedCount > 5
        AND P_Ans.Score > 20
        AND P_Q.Tags LIKE '%<%sql%>%'
    ORDER BY
        EngagementMetric DESC, P_Ans.CreationDate DESC
    LIMIT 300
)
;