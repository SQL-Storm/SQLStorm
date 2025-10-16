WITH UserMetrics AS (
    SELECT
        U.Id AS UserId,
        U.Reputation,
        U.CreationDate AS UserCreationDate,
        COUNT(P.Id) AS TotalPosts,
        COUNT(DISTINCT A.Id) AS TotalAnswers,
        SUM(CASE WHEN V.VoteTypeId = 2 THEN 1 ELSE 0 END) AS TotalUpVotesReceived,
        SUM(CASE WHEN V.VoteTypeId = 3 THEN 1 ELSE 0 END) AS TotalDownVotesReceived,
        COUNT(DISTINCT B.Id) AS TotalBadges,
        MAX(B.Date) AS MostRecentBadgeDate
    FROM
        Users U
    LEFT JOIN
        Posts P ON U.Id = P.OwnerUserId
    LEFT JOIN
        Posts A ON U.Id = A.OwnerUserId AND A.PostTypeId = 2
    LEFT JOIN
        Votes V ON P.Id = V.PostId
    LEFT JOIN
        Badges B ON U.Id = B.UserId
    GROUP BY
        U.Id, U.Reputation, U.CreationDate
),
PostEngagement AS (
    SELECT
        P.Id AS PostId,
        P.PostTypeId,
        P.CreationDate AS PostCreationDate,
        P.Score,
        P.ViewCount,
        COUNT(C.Id) AS TotalComments,
        COUNT(DISTINCT V.Id) AS TotalVotes,
        COUNT(DISTINCT L.RelatedPostId) AS TotalLinkedPosts,
        COUNT(DISTINCT PH.Id) AS TotalPostHistoryEntries,
        MAX(PH.CreationDate) AS MostRecentEditDate,
        CASE
            WHEN P.PostTypeId = 1 THEN 'Question'
            WHEN P.PostTypeId = 2 THEN 'Answer'
            ELSE 'Other'
        END AS PostTypeName
    FROM
        Posts P
    LEFT JOIN
        Comments C ON P.Id = C.PostId
    LEFT JOIN
        Votes V ON P.Id = V.PostId
    LEFT JOIN
        PostLinks L ON P.Id = L.PostId
    LEFT JOIN
        PostHistory PH ON P.Id = PH.PostId
    GROUP BY
        P.Id, P.PostTypeId, P.CreationDate, P.Score, P.ViewCount
),
ActiveUsers AS (
    SELECT
        UM.UserId,
        UM.Reputation,
        UM.UserCreationDate,
        UM.TotalPosts,
        UM.TotalAnswers,
        UM.TotalUpVotesReceived,
        UM.TotalDownVotesReceived,
        UM.TotalBadges,
        UM.MostRecentBadgeDate,
        P.Id AS MostRecentPostId,
        P.Score AS MostRecentPostScore,
        P.ViewCount AS MostRecentPostViewCount,
        PE.TotalComments AS MostRecentPostComments,
        PE.TotalVotes AS MostRecentPostVotes,
        PE.TotalLinkedPosts AS MostRecentPostLinkedPosts,
        PE.TotalPostHistoryEntries AS MostRecentPostHistoryEntries,
        ROW_NUMBER() OVER (PARTITION BY UM.UserId ORDER BY P.CreationDate DESC) AS rn
    FROM
        UserMetrics UM
    LEFT JOIN
        Posts P ON UM.UserId = P.OwnerUserId
    LEFT JOIN
        PostEngagement PE ON P.Id = PE.PostId
    WHERE
        P.CreationDate > (TIMESTAMP '2024-10-01 12:34:56' - INTERVAL '6 months')
)
SELECT
    AU.UserId,
    AU.Reputation,
    AU.UserCreationDate,
    AU.TotalPosts,
    AU.TotalAnswers,
    AU.TotalUpVotesReceived,
    AU.TotalDownVotesReceived,
    AU.TotalBadges,
    AU.MostRecentBadgeDate,
    AU.MostRecentPostId,
    AU.MostRecentPostScore,
    AU.MostRecentPostViewCount,
    AU.MostRecentPostComments,
    AU.MostRecentPostVotes,
    AU.MostRecentPostLinkedPosts,
    AU.MostRecentPostHistoryEntries,
    UPPER(SUBSTRING(U.DisplayName FROM 1 FOR 1) || LOWER(SUBSTRING(U.DisplayName FROM 2))) AS FormattedDisplayName,
    CASE
        WHEN AU.TotalPosts > 100 THEN 'Highly Active'
        WHEN AU.TotalPosts BETWEEN 50 AND 100 THEN 'Moderately Active'
        ELSE 'Less Active'
    END AS ActivityLevel,
    COALESCE(AU.MostRecentPostScore, 0) AS EffectivePostScore,
    LAG(AU.Reputation, 1) OVER (PARTITION BY AU.UserId ORDER BY AU.UserCreationDate) AS PreviousReputation,
    LAG(AU.TotalPosts, 1) OVER (PARTITION BY AU.UserId ORDER BY AU.UserCreationDate) AS PreviousTotalPosts,
    CASE
        WHEN AU.TotalUpVotesReceived > AU.TotalDownVotesReceived THEN 'Positive'
        WHEN AU.TotalUpVotesReceived < AU.TotalDownVotesReceived THEN 'Negative'
        ELSE 'Neutral'
    END AS VoteSentiment
FROM
    ActiveUsers AU
    JOIN Users U ON U.Id = AU.UserId
WHERE
    AU.rn = 1
ORDER BY
    AU.Reputation DESC, AU.TotalPosts DESC, AU.TotalUpVotesReceived DESC;