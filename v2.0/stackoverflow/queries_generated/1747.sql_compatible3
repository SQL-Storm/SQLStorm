WITH UserEngagement AS (
    SELECT
        U.Id AS UserId,
        U.DisplayName,
        U.Reputation,
        U.CreationDate,
        U.LastAccessDate,
        U.UpVotes,
        U.DownVotes,
        U.Views AS UserProfileViews,
        GREATEST(0, EXTRACT(EPOCH FROM (U.LastAccessDate - U.CreationDate)) / (3600 * 24)) AS AccountAgeDays,
        COALESCE(SUM(CASE WHEN B.Class = 1 THEN 1 ELSE 0 END), 0) AS GoldBadges,
        COALESCE(SUM(CASE WHEN B.Class = 2 THEN 1 ELSE 0 END), 0) AS SilverBadges,
        COALESCE(SUM(CASE WHEN B.Class = 3 THEN 1 ELSE 0 END), 0) AS BronzeBadges,
        COUNT(B.Id) AS TotalBadges,
        COUNT(DISTINCT CASE WHEN B.TagBased = TRUE THEN B.Name ELSE NULL END) AS UniqueTagBadges,
        CASE
            WHEN U.WebsiteUrl IS NOT NULL AND U.WebsiteUrl LIKE 'http%' AND CHAR_LENGTH(TRIM(U.WebsiteUrl)) > 20 THEN TRUE
            ELSE FALSE
        END AS HasDetailedWebsite,
        COALESCE(U.Location, 'Unknown Location') AS UserLocation,
        (U.UpVotes + U.DownVotes) AS TotalUserVotes,
        (U.UpVotes * 1.0 / NULLIF(U.DownVotes + U.UpVotes, 0)) AS UpvoteRatio,
        RANK() OVER (PARTITION BY FLOOR(U.Reputation / 100000) ORDER BY COUNT(B.Id) DESC) AS BadgeRankInReputationTier
    FROM
        Users U
    LEFT JOIN Badges B ON U.Id = B.UserId
    GROUP BY
        U.Id, U.DisplayName, U.Reputation, U.CreationDate, U.LastAccessDate, U.UpVotes, U.DownVotes, U.Views, U.WebsiteUrl, U.Location
),
PostAggregates AS (
    SELECT
        P.OwnerUserId AS UserId,
        P.Id AS PostId,
        P.PostTypeId,
        PT.Name AS PostTypeName,
        P.Score AS PostScore,
        P.ViewCount,
        P.AnswerCount,
        P.CommentCount AS BuiltInCommentCount,
        P.FavoriteCount,
        P.CreationDate AS PostCreationDate,
        P.LastActivityDate,
        P.LastEditDate,
        P.ClosedDate,
        P.AcceptedAnswerId,
        P.ParentId,
        P.Title,
        P.Tags,
        CHAR_LENGTH(P.Body) AS BodyLength,
        GREATEST(0, EXTRACT(EPOCH FROM (P.LastActivityDate - P.CreationDate)) / (3600 * 24 * 365.25)) AS PostActivityYears,
        (SELECT COUNT(DISTINCT PH.UserId)
         FROM PostHistory PH
         WHERE PH.PostId = P.Id
           AND PH.UserId IS NOT NULL
           AND PH.UserId <> P.OwnerUserId
           AND PH.PostHistoryTypeId IN (4, 5, 6, 8, 9)) AS ExternalEditorCount,
        (SELECT MAX(CASE WHEN PH.PostHistoryTypeId = 11 THEN 1 ELSE 0 END)
         FROM PostHistory PH
         WHERE PH.PostId = P.Id) AS WasReopened,
        COALESCE(SUM(CASE WHEN V.VoteTypeId = 2 THEN 1 ELSE 0 END), 0) - COALESCE(SUM(CASE WHEN V.VoteTypeId = 3 THEN 1 ELSE 0 END), 0) AS NetPostVotes,
        MAX(CASE WHEN PL.LinkTypeId = 3 AND PL.RelatedPostId = P.Id THEN 1 ELSE 0 END) AS IsDuplicateTarget,
        MAX(CASE WHEN PL.LinkTypeId = 3 AND PL.PostId = P.Id THEN 1 ELSE 0 END) AS IsDuplicateSource,
        COALESCE(SUM(C.Score), 0) AS TotalCommentScoreFromCommentsTable,
        COUNT(DISTINCT C.Id) AS ActualCommentCountFromCommentsTable
    FROM
        Posts P
    LEFT JOIN PostTypes PT ON P.PostTypeId = PT.Id
    LEFT JOIN Comments C ON P.Id = C.PostId
    LEFT JOIN Votes V ON P.Id = V.PostId
    LEFT JOIN PostLinks PL ON P.Id = PL.PostId OR P.Id = PL.RelatedPostId
    WHERE
        P.OwnerUserId IS NOT NULL
        AND P.CreationDate >= DATE '2019-01-01'
        AND P.Body IS NOT NULL
        AND P.PostTypeId IN (1, 2)
    GROUP BY
        P.OwnerUserId, P.Id, P.PostTypeId, PT.Name, P.Score, P.ViewCount, P.AnswerCount, P.CommentCount, P.FavoriteCount,
        P.CreationDate, P.LastActivityDate, P.LastEditDate, P.ClosedDate, P.AcceptedAnswerId, P.ParentId, P.Title, P.Tags, P.Body
),
UserPostContributions AS (
    SELECT
        PA.UserId,
        COUNT(DISTINCT PA.PostId) AS TotalPostsContributed,
        SUM(CASE WHEN PA.PostTypeId = 1 THEN 1 ELSE 0 END) AS TotalQuestions,
        SUM(CASE WHEN PA.PostTypeId = 2 THEN 1 ELSE 0 END) AS TotalAnswers,
        SUM(PA.PostScore) AS TotalPostScore,
        AVG(PA.PostScore) AS AvgPostScore,
        COALESCE(SUM(CASE WHEN PA.PostTypeId = 1 THEN PA.ViewCount ELSE 0 END), 0) AS TotalQuestionViews,
        COALESCE(AVG(CASE WHEN PA.PostTypeId = 1 THEN PA.ViewCount ELSE NULL END), 0) AS AvgQuestionViews,
        COALESCE(SUM(CASE WHEN PA.PostTypeId = 1 THEN PA.AnswerCount ELSE 0 END), 0) AS TotalAnswersOnQuestions,
        COALESCE(SUM(CASE WHEN PA.FavoriteCount IS NOT NULL THEN PA.FavoriteCount ELSE 0 END), 0) AS TotalFavoriteCounts,
        COALESCE(SUM(PA.NetPostVotes), 0) AS TotalNetPostVotes,
        COALESCE(SUM(PA.ActualCommentCountFromCommentsTable), 0) AS TotalEffectiveComments,
        COALESCE(SUM(PA.TotalCommentScoreFromCommentsTable), 0) AS TotalEffectiveCommentScore,
        (SUM(CASE WHEN PA.PostTypeId = 2 AND PA.PostId = QP.AcceptedAnswerId THEN 1 ELSE 0 END) * 1.0 /
         NULLIF(SUM(CASE WHEN PA.PostTypeId = 2 THEN 1 ELSE 0 END), 0)) AS AcceptedAnswerRatio,
        COALESCE(SUM(PA.ExternalEditorCount), 0) AS TotalExternalEditorCount,
        COALESCE(SUM(PA.WasReopened), 0) AS PostsReopenedCount,
        COALESCE(SUM(PA.IsDuplicateTarget), 0) AS PostsAsDuplicateTarget,
        COALESCE(SUM(PA.IsDuplicateSource), 0) AS PostsAsDuplicateSource,
        COUNT(DISTINCT T.tag) AS DistinctTagsUsed,
        SUM(CASE WHEN T.tag ILIKE '%java%' OR T.tag ILIKE '%python%' OR T.tag ILIKE '%javascript%' THEN 1 ELSE 0 END) AS MajorLanguageTagsUsed,
        MAX(PA.BodyLength) AS MaxPostBodyLength
    FROM
        PostAggregates PA
    LEFT JOIN Posts QP ON PA.ParentId = QP.Id
    LEFT JOIN LATERAL (
        SELECT tag FROM UNNEST(string_to_array(SUBSTRING(PA.Tags FROM 2 FOR CHAR_LENGTH(PA.Tags) - 2), '><')) AS tag
    ) T ON PA.Tags IS NOT NULL AND CHAR_LENGTH(PA.Tags) > 2
    GROUP BY
        PA.UserId
),
HighImpactUsers AS (
    SELECT
        UE.UserId,
        UE.DisplayName,
        UE.Reputation,
        UE.AccountAgeDays,
        UE.GoldBadges,
        UE.SilverBadges,
        UE.BronzeBadges,
        UE.TotalBadges,
        UE.HasDetailedWebsite,
        UE.UserLocation,
        UE.UpvoteRatio,
        -- replace nonexistent UE.Views reference with UE.UserProfileViews
        UE.UserProfileViews AS DummyUserViews,
        UPC.TotalPostsContributed,
        UPC.TotalQuestions,
        UPC.TotalAnswers,
        UPC.TotalPostScore,
        UPC.AvgPostScore,
        UPC.TotalQuestionViews,
        UPC.AvgQuestionViews,
        UPC.TotalAnswersOnQuestions,
        UPC.TotalFavoriteCounts,
        UPC.TotalNetPostVotes,
        UPC.TotalEffectiveComments,
        COALESCE(UPC.AcceptedAnswerRatio, 0.0) AS AcceptedAnswerRatio,
        UPC.TotalExternalEditorCount,
        UPC.PostsReopenedCount,
        UPC.PostsAsDuplicateTarget,
        UPC.PostsAsDuplicateSource,
        UPC.DistinctTagsUsed,
        UPC.MajorLanguageTagsUsed,
        UPC.MaxPostBodyLength,
        (UE.Reputation * 0.05 +
         UPC.TotalNetPostVotes * 0.4 +
         UPC.TotalFavoriteCounts * 0.2 +
         COALESCE(UPC.AcceptedAnswerRatio, 0) * 1500 +
         UPC.TotalEffectiveComments * 0.1 +
         UE.GoldBadges * 80 + UE.SilverBadges * 15 +
         UPC.TotalQuestions * 3 + UPC.TotalAnswers * 2 +
         (COALESCE(UPC.TotalQuestionViews,0) / NULLIF(UPC.TotalQuestions, 0)) * 0.005 +
         (UPC.DistinctTagsUsed * 5) + (UPC.MajorLanguageTagsUsed * 10) -
         (UPC.PostsAsDuplicateSource * 40) - (UPC.PostsAsDuplicateTarget * 20) -
         (UPC.TotalExternalEditorCount * 3) -
         (UPC.PostsReopenedCount * 10)
        ) AS InfluenceScore,
        CASE
            WHEN UE.Reputation > 100000 AND COALESCE(UPC.AcceptedAnswerRatio, 0) > 0.6 AND UPC.TotalNetPostVotes > 5000 AND UE.GoldBadges >= 5 THEN 'Legendary Contributor'
            WHEN UE.Reputation > 50000 AND COALESCE(UPC.AcceptedAnswerRatio, 0) > 0.4 AND UPC.TotalNetPostVotes > 2000 AND UE.GoldBadges >= 1 THEN 'Senior Expert'
            WHEN UE.Reputation > 10000 AND UPC.TotalPostsContributed > 100 AND UPC.AvgPostScore > 5 THEN 'Active Participant'
            ELSE 'Emerging Contributor'
        END AS UserTier,
        UE.UserProfileViews,
        UE.HasDetailedWebsite AS HIU_HasDetailedWebsite
    FROM
        UserEngagement UE
    JOIN UserPostContributions UPC ON UE.UserId = UPC.UserId
    WHERE
        UE.AccountAgeDays > 365
        AND UE.Reputation > 500
        AND UPC.TotalPostsContributed > 5
        AND (UE.UserLocation IS NOT NULL AND UE.UserLocation NOT ILIKE '%internet%' AND UE.UserLocation NOT ILIKE '%online%')
)
SELECT
    HIU.UserId,
    HIU.DisplayName,
    HIU.Reputation,
    HIU.AccountAgeDays,
    HIU.TotalPostsContributed,
    HIU.TotalQuestions,
    HIU.TotalAnswers,
    HIU.TotalNetPostVotes,
    HIU.AcceptedAnswerRatio,
    HIU.TotalBadges,
    HIU.GoldBadges,
    HIU.DistinctTagsUsed,
    HIU.MajorLanguageTagsUsed,
    HIU.InfluenceScore,
    HIU.UserTier,
    COALESCE(HIU.UserProfileViews, 0) + COALESCE(HIU.TotalQuestionViews, 0) AS CombinedTotalViews,
    CASE
        WHEN HIU.UserTier = 'Legendary Contributor' AND HIU.InfluenceScore > 50000 AND HIU.HIU_HasDetailedWebsite THEN 'Elite Verified Architect'
        WHEN HIU.UserTier = 'Senior Expert' AND HIU.InfluenceScore > 20000 AND HIU.MaxPostBodyLength > 1000 THEN 'Profound Senior Expert'
        WHEN HIU.UserTier = 'Active Participant' AND HIU.TotalExternalEditorCount = 0 THEN 'Independent Contributor'
        WHEN HIU.MaxPostBodyLength IS NULL OR HIU.MaxPostBodyLength < 200 THEN 'Concise Contributor'
        ELSE 'General Contributor'
    END AS FinalUserClassification,
    UPPER(SUBSTRING(COALESCE(TRIM(HIU.DisplayName), 'ANON') FROM 1 FOR 4)) || '_' ||
    LPAD(REPLACE(REPLACE(CAST(HIU.UserId AS TEXT), ' ', ''), ',', ''), 10, '0') || '_' ||
    SUBSTRING(MD5(HIU.DisplayName || COALESCE(HIU.UserLocation, '') || COALESCE(CAST(HIU.AccountAgeDays AS TEXT), '')), 1, 8) AS UserIdentifierHash
FROM
    HighImpactUsers HIU
WHERE
    HIU.InfluenceScore IS NOT NULL
    AND HIU.InfluenceScore > 500
    AND (HIU.TotalNetPostVotes > 200 OR (HIU.TotalQuestions > 20 AND HIU.AvgQuestionViews > 1000))
    AND NOT (HIU.PostsAsDuplicateSource > 0 AND HIU.PostsReopenedCount > 0 AND HIU.AcceptedAnswerRatio < 0.2)
ORDER BY
    HIU.InfluenceScore DESC, HIU.Reputation DESC, HIU.AccountAgeDays ASC
LIMIT 100;