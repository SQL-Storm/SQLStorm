-- {"query": "57047.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "pixtral-large", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2291, "output_tokens": 973} 

WITH UserActivity AS (
    SELECT
        U.Id AS UserId,
        U.Reputation,
        U.CreationDate AS UserCreationDate,
        U.LastAccessDate,
        U.Views,
        U.UpVotes,
        U.DownVotes,
        COUNT(P.Id) AS TotalPosts,
        COUNT(DISTINCT C.Id) AS TotalComments,
        COUNT(DISTINCT V.Id) AS TotalVotes,
        COUNT(DISTINCT B.Id) AS TotalBadges
    FROM
        Users U
    LEFT JOIN
        Posts P ON U.Id = P.OwnerUserId
    LEFT JOIN
        Comments C ON U.Id = C.UserId
    LEFT JOIN
        Votes V ON U.Id = V.UserId
    LEFT JOIN
        Badges B ON U.Id = B.UserId
    GROUP BY
        U.Id, U.Reputation, U.CreationDate, U.LastAccessDate, U.Views,   U.UpVotes, U.DownVotes
),
PostActivity AS (
    SELECT
        P.Id AS PostId,
        P.PostTypeId,
        P.CreationDate AS PostCreationDate,
        P.Score,
        P.ViewCount,
        P.CommentCount,
        P.OwnerUserId,
        COUNT(V.Id) AS TotalVotes,
        COUNT(C.Id) AS TotalComments,
        COUNT(PH.Id) AS TotalPostHistoryEntries,
        COUNT(DISTINCT PL.Id) AS TotalPostLinks
    FROM
        Posts P
    LEFT JOIN
        Votes V ON P.Id = V.PostId
    LEFT JOIN
        Comments C ON P.Id = C.PostId
    LEFT JOIN
        PostHistory PH ON P.Id = PH.PostId
    LEFT JOIN
        PostLinks PL ON P.Id = PL.PostId
    GROUP BY
        P.Id, P.PostTypeId, P.CreationDate, P.Score, P.ViewCount, P.CommentCount, P.OwnerUserId
),
TagActivity AS (
    SELECT
        T.Id AS TagId,
        T.TagName,
        T.Count,
        COUNT(P.Id) AS TotalPostsWithTag,
        COUNT(DISTINCT U.Id) AS TotalUsersUsingTag
    FROM
        Tags T
    LEFT JOIN
        Posts P ON P.Tags LIKE '%<' || T.TagName || '>%'
    LEFT JOIN
        Users U ON P.OwnerUserId = U.Id
    GROUP BY
        T.Id, T.TagName, T.Count
)
SELECT
    UA.UserId,
    UA.Reputation,
    UA.UserCreationDate,
    UA.LastAccessDate,
    UA.Views,
    UA.UpVotes,
    UA.DownVotes,
    UA.TotalPosts,
    UA.TotalComments,
    UA.TotalVotes,
    UA.TotalBadges,
    PA.PostId,
    PA.PostTypeId,
    PA.PostCreationDate,
    PA.Score,
    PA.ViewCount,
    PA.CommentCount,
    PA.TotalVotes AS PostTotalVotes,
    PA.TotalComments AS PostTotalComments,
    PA.TotalPostHistoryEntries,
    PA.TotalPostLinks,
    TA.TagId,
    TA.TagName,
    TA.Count,
    TA.TotalPostsWithTag,
    TA.TotalUsersUsingTag
FROM
    UserActivity UA
JOIN
    PostActivity PA ON UA.UserId = PA.OwnerUserId
JOIN
    TagActivity TA ON PA.PostId = TA.TagId
ORDER BY
    UA.Reputation DESC,
    PA.Score DESC,
    TA.Count DESC
LIMIT 1000;
