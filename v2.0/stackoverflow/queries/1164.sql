-- {"query": "1164.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-flash", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 3466}
WITH UserEngagement AS (
    SELECT
        U.Id AS UserId,
        COALESCE(U.DisplayName, 'Anonymous User') AS DisplayName,
        U.Reputation,
        U.UpVotes,
        U.DownVotes,
        U.Views AS UserProfileViews,
        U.CreationDate AS UserCreationDate,
        U.LastAccessDate,
        COUNT(DISTINCT P.Id) AS TotalPostsOwned,
        COUNT(DISTINCT CASE WHEN P.PostTypeId = 1 THEN P.Id END) AS TotalQuestionsAsked,
        COUNT(DISTINCT CASE WHEN P.PostTypeId = 2 THEN P.Id END) AS TotalAnswersGiven,
        SUM(COALESCE(P.Score, 0)) AS TotalPostsScore,
        AVG(COALESCE(P.Score, 0)) AS AvgPostScore,
        (CAST(U.UpVotes AS NUMERIC) - U.DownVotes) AS NetVotesReceived,
        COALESCE(ROUND(CAST(U.UpVotes AS NUMERIC) / NULLIF(U.UpVotes + U.DownVotes, 0), 4), 0) AS VoteSuccessRatio,
        EXTRACT(EPOCH FROM (CAST('2024-10-01 12:34:56' AS timestamp) - U.CreationDate)) / 86400 AS DaysSinceUserCreation,
        DENSE_RANK() OVER (ORDER BY U.Reputation DESC, U.UpVotes DESC) AS ReputationRank,
        NTILE(10) OVER (ORDER BY U.UpVotes + U.DownVotes DESC, U.Reputation DESC) AS TopVoterPercentile
    FROM
        Users U
    LEFT JOIN
        Posts P ON U.Id = P.OwnerUserId
    GROUP BY
        U.Id, U.DisplayName, U.Reputation, U.UpVotes, U.DownVotes, U.Views, U.CreationDate, U.LastAccessDate
),
PostComplexActivity AS (
    SELECT
        P.Id AS PostId,
        P.PostTypeId,
        COALESCE(P.Title, 'No Title Provided') AS PostTitle,
        P.CreationDate AS PostCreationDate,
        P.LastEditDate,
        P.LastActivityDate,
        P.Score AS PostScore,
        P.ViewCount,
        P.AnswerCount,
        P.CommentCount,
        P.FavoriteCount,
        P.ClosedDate,
        P.CommunityOwnedDate,
        P.OwnerUserId,
        P.AcceptedAnswerId,
        P.ParentId,
        P.Tags,
        P.LastEditorUserId,
        COUNT(DISTINCT PH.Id) AS TotalPostHistoryEvents,
        COUNT(DISTINCT CASE WHEN PH.PostHistoryTypeId IN (4, 5, 6, 8, 9, 24) THEN PH.Id END) AS EditCount,
        COUNT(DISTINCT CASE WHEN PH.PostHistoryTypeId IN (10, 12, 14) THEN PH.Id END) AS CloseDeleteLockEvents,
        COUNT(DISTINCT CASE WHEN PH.PostHistoryTypeId IN (11, 13, 15) THEN PH.Id END) AS ReopenUndeleteUnlockEvents,
        COUNT(DISTINCT PL.Id) AS TotalPostLinkEntries,
        SUM(CASE WHEN V.VoteTypeId = 2 THEN 1 ELSE 0 END) AS TotalUpvotesReceived,
        SUM(CASE WHEN V.VoteTypeId = 3 THEN 1 ELSE 0 END) AS TotalDownvotesReceived,
        SUM(CASE WHEN V.VoteTypeId = 5 THEN 1 ELSE 0 END) AS TotalFavoritesReceived,
        MAX(CASE WHEN PH.PostHistoryTypeId = 10 THEN PH.Comment END) AS LastCloseReasonId,
        (
            (COUNT(DISTINCT PH.Id) * 0.75) +
            (COUNT(DISTINCT CASE WHEN PH.PostHistoryTypeId IN (4, 5, 6, 8, 9, 24) THEN PH.Id END) * 1.5) +
            (COUNT(DISTINCT CASE WHEN PH.PostHistoryTypeId IN (10, 12, 14, 11, 13, 15) THEN PH.Id END) * 2.5) +
            (COUNT(DISTINCT PL.Id) * 1.0) +
            (COUNT(DISTINCT C.Id) * 0.5) +
            COALESCE(P.FavoriteCount, 0) * 2.0 +
            COALESCE(P.AnswerCount, 0) * 3.0
        ) AS PostEngagementScore,
        (CASE WHEN P.Tags LIKE '%<bug>%' OR P.Tags LIKE '%<error>%' OR P.Tags LIKE '%<design>%' OR P.Tags LIKE '%<performance>%' THEN 1 ELSE 0 END) AS HasFocusTag,
        (SELECT U2.Reputation FROM Users U2 WHERE U2.Id = P.LastEditorUserId) AS LastEditorReputation,
        (SELECT CASE WHEN P_Main.Body ILIKE '%exception%' THEN TRUE ELSE FALSE END FROM Posts P_Main WHERE P_Main.Id = P.Id) AS ContainsExceptionKeyword
    FROM
        Posts P
    LEFT JOIN
        PostHistory PH ON P.Id = PH.PostId
    LEFT JOIN
        PostLinks PL ON P.Id = PL.PostId OR P.Id = PL.RelatedPostId
    LEFT JOIN
        Votes V ON P.Id = V.PostId
    LEFT JOIN
        Comments C ON P.Id = C.PostId
    GROUP BY
        P.Id, P.PostTypeId, P.Title, P.CreationDate, P.LastEditDate, P.LastActivityDate, P.Score, P.ViewCount,
        P.AnswerCount, P.CommentCount, P.FavoriteCount, P.ClosedDate, P.CommunityOwnedDate, P.OwnerUserId,
        P.AcceptedAnswerId, P.ParentId, P.Tags, P.LastEditorUserId
),
HighEngagementPosts AS (
    SELECT
        PCA.*,
        CR.Name AS CloseReasonTypeName,
        EXTRACT(EPOCH FROM (CAST('2024-10-01 12:34:56' AS timestamp) - PCA.PostCreationDate)) / 86400 AS PostAgeDays,
        RANK() OVER (PARTITION BY PCA.PostTypeId ORDER BY PCA.PostEngagementScore DESC, PCA.ViewCount DESC) AS PostTypeEngagementRank,
        NTILE(4) OVER (ORDER BY PCA.PostEngagementScore DESC) AS EngagementQuartile,
        LENGTH(P_Main.Body) AS PostBodyLength,
        EXISTS (SELECT 1 FROM Badges B WHERE B.UserId = PCA.OwnerUserId AND B.Class = 1) AS OwnerHasGoldBadge
    FROM
        PostComplexActivity PCA
    LEFT JOIN
        CloseReasonTypes CR ON PCA.LastCloseReasonId IS NOT NULL AND CR.Id = CAST(PCA.LastCloseReasonId AS SMALLINT)
    LEFT JOIN
        Posts P_Main ON PCA.PostId = P_Main.Id
    WHERE
        PCA.PostEngagementScore > 20
        AND PCA.ViewCount > 1000
        AND PCA.PostScore >= 10
        AND PCA.PostTypeId IN (1, 2)
),
RelevantInteractions AS (
    SELECT
        UE.UserId,
        UE.DisplayName,
        UE.Reputation,
        UE.TotalQuestionsAsked,
        UE.TotalAnswersGiven,
        UE.NetVotesReceived,
        UE.VoteSuccessRatio,
        HEP.PostId,
        HEP.PostTitle,
        HEP.PostCreationDate,
        HEP.PostScore,
        HEP.ViewCount,
        HEP.PostEngagementScore,
        HEP.CloseReasonTypeName,
        HEP.PostAgeDays,
        HEP.EngagementQuartile,
        HEP.PostTypeEngagementRank,
        HEP.OwnerHasGoldBadge,
        HEP.ContainsExceptionKeyword,
        HEP.LastEditorReputation,
        LAG(HEP.PostEngagementScore, 1, 0) OVER (PARTITION BY UE.UserId ORDER BY HEP.PostCreationDate) AS PreviousPostEngagementScore,
        (SELECT AVG(COALESCE(C.Score, 0)) FROM Comments C WHERE C.PostId = HEP.PostId AND C.UserId IS NOT NULL) AS AvgCommentScoreByUsers,
        -- Extract second tag safely using standard functions rewritten without PostgreSQL specific FROM syntax in POSITION
        COALESCE(
            CASE
                WHEN HEP.Tags IS NULL THEN NULL
                WHEN POSITION('<' IN HEP.Tags) = 0 THEN NULL
                ELSE
                    CASE
                        WHEN POSITION('>' IN HEP.Tags) = 0 THEN NULL
                        ELSE
                            -- find the substring starting after the first '>' and then extract next tag between '<' and '>'
                            (
                                CASE
                                    WHEN POSITION('<' IN SUBSTRING(HEP.Tags FROM POSITION('>' IN HEP.Tags) + 1)) = 0 THEN NULL
                                    ELSE
                                        SUBSTRING(
                                            SUBSTRING(HEP.Tags FROM POSITION('>' IN HEP.Tags) + 1)
                                            FROM POSITION('<' IN SUBSTRING(HEP.Tags FROM POSITION('>' IN HEP.Tags) + 1)) + 1
                                            FOR (POSITION('>' IN SUBSTRING(HEP.Tags FROM POSITION('>' IN HEP.Tags) + 1)) - POSITION('<' IN SUBSTRING(HEP.Tags FROM POSITION('>' IN HEP.Tags) + 1)) - 1)
                                        )
                                END
                            )
                    END
            END,
            'No Second Tag'
        ) AS SecondTagIfPresent,
        HEP.Tags
    FROM
        UserEngagement UE
    INNER JOIN
        HighEngagementPosts HEP ON UE.UserId = HEP.OwnerUserId
    WHERE
        UE.ReputationRank <= 500
        AND UE.NetVotesReceived > 100
        AND HEP.EngagementQuartile <= 2
)
SELECT
    RI.DisplayName,
    RI.Reputation,
    RI.TotalQuestionsAsked,
    RI.TotalAnswersGiven,
    RI.PostTitle,
    RI.PostScore AS CurrentPostScore,
    RI.ViewCount AS CurrentPostViews,
    RI.PostEngagementScore,
    RI.CloseReasonTypeName,
    RI.PostAgeDays,
    RI.OwnerHasGoldBadge,
    RI.ContainsExceptionKeyword,
    RI.LastEditorReputation,
    RI.PreviousPostEngagementScore,
    RI.AvgCommentScoreByUsers,
    RI.SecondTagIfPresent,
    CASE
        WHEN RI.PostScore > (SELECT AVG(PostScore) FROM HighEngagementPosts WHERE OwnerUserId = RI.UserId) * 1.5 THEN 'ExceptionalPostScore'
        WHEN RI.PostScore < (SELECT AVG(PostScore) FROM HighEngagementPosts WHERE OwnerUserId = RI.UserId) * 0.5 THEN 'BelowAvgPostScore'
        ELSE 'AvgRelativePostScore'
    END AS PostScoreRelativeCategory,
    COALESCE(PL.PostId, PL.RelatedPostId) AS PotentialRelatedPostId,
    COALESCE(LT.Name, 'No Link Type') AS LinkTypeName,
    RelatedHEP.PostTitle AS RelatedPostTitle,
    RelatedHEP.PostEngagementScore AS RelatedPostEngagementScore,
    STRING_AGG(DISTINCT B.Name, '; ') FILTER (WHERE B.Class = 1) AS UserGoldBadges,
    STRING_AGG(DISTINCT B.Name, '; ') FILTER (WHERE B.Class = 2) AS UserSilverBadges,
    CASE
        WHEN RI.Tags LIKE '%<sql>%' OR RI.Tags LIKE '%<database>%' THEN 'SQL/DB Related'
        WHEN RI.Tags IS NULL OR LENGTH(TRIM(RI.Tags)) < 3 THEN 'Untagged/No Tags'
        ELSE 'Other Tags'
    END AS TagCategory,
    RI.UserId
FROM
    RelevantInteractions RI
LEFT JOIN
    PostLinks PL ON (RI.PostId = PL.PostId OR RI.PostId = PL.RelatedPostId)
LEFT JOIN
    HighEngagementPosts RelatedHEP ON (
        (PL.PostId = RelatedHEP.PostId AND PL.RelatedPostId = RI.PostId) OR
        (PL.RelatedPostId = RelatedHEP.PostId AND PL.PostId = RI.PostId)
    ) AND RelatedHEP.EngagementQuartile <= 1
LEFT JOIN
    LinkTypes LT ON PL.LinkTypeId = LT.Id
LEFT JOIN
    Badges B ON RI.UserId = B.UserId
WHERE
    RI.PostTypeEngagementRank <= 10
    AND (RI.CloseReasonTypeName IS NULL OR RI.CloseReasonTypeName NOT IN ('Duplicate', 'Off-topic', 'Needs details or clarity'))
    AND RI.LastEditorReputation IS NOT NULL AND RI.LastEditorReputation > RI.Reputation * 0.75
    AND RI.PreviousPostEngagementScore IS NOT NULL AND RI.PostEngagementScore > RI.PreviousPostEngagementScore * 1.1
GROUP BY
    RI.UserId, RI.DisplayName, RI.Reputation, RI.TotalQuestionsAsked, RI.TotalAnswersGiven,
    RI.PostTitle, RI.PostScore, RI.ViewCount, RI.PostEngagementScore, RI.CloseReasonTypeName,
    RI.PostAgeDays, RI.OwnerHasGoldBadge, RI.ContainsExceptionKeyword, RI.LastEditorReputation,
    RI.PreviousPostEngagementScore, RI.AvgCommentScoreByUsers, RI.SecondTagIfPresent,
    PL.PostId, PL.RelatedPostId, LT.Name, RelatedHEP.PostTitle, RelatedHEP.PostEngagementScore,
    RI.Tags, RI.PostTypeEngagementRank, RI.EngagementQuartile, RI.UserId, RI.DisplayName
ORDER BY
    RI.Reputation DESC, RI.PostEngagementScore DESC, RI.PostTitle ASC
LIMIT 1000;