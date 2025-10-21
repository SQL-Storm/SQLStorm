-- {"query": "57059.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "pixtral-large", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2291, "output_tokens": 1626} 

WITH TopTags AS (
    SELECT
        Tags.TagName,
        COUNT(P.Id) AS QuestionCount,
        SUM(P.ViewCount) AS TotalViews,
        SUM(P.Score) AS TotalScore,
        SUM(P.AnswerCount) AS TotalAnswers
    FROM
        Tags
    JOIN Posts P ON P.Tags LIKE CONCAT('%<', Tags.TagName, '>%')
    WHERE
        P.PostTypeId = 1
    GROUP BY
        Tags.TagName
    ORDER BY
        TotalViews DESC
    LIMIT 10
), MostActiveUsers AS (
    SELECT
        P.OwnerUserId AS UserId,
        COUNT(P.Id) AS PostCount,
        SUM(P.Score) AS TotalScore,
        SUM(P.ViewCount) AS TotalViews
    FROM
        Posts P
    WHERE
        P.PostTypeId IN (1, 2)
    GROUP BY
        P.OwnerUserId
    ORDER BY
        TotalScore DESC
    LIMIT 10
), UserActivity AS (
    SELECT
        U.Id AS UserId,
        COALESCE(U.DisplayName, '';, 'Unknown') as userName,
        U.Reputation,
        U.CreationDate,
        U.LastAccessDate,
        COUNT(P.Id) AS TotalPosts,
        COUNT(DISTINCT C.Id) AS TotalComments,
        SUM(V.VoteTypeId = 2) AS TotalUpvotesGiven,
        SUM(V.VoteTypeId = 3) AS TotalDownvotesGiven,
        SUM(CASE WHEN V.PostId IS NOT NULL AND V.VoteTypeId = 2 THEN 1 ELSE 0 END) AS TotalUpvotesReceived,
        SUM(CASE WHEN V.PostId IS NOT NULL AND V.VoteTypeId = 3 THEN 1 ELSE 0 END) AS TotalDownvotesReceived
    FROM
        Users U
    LEFT JOIN Posts P ON U.Id = P.OwnerUserId
    LEFT JOIN Comments C ON U.Id = C.UserId
    LEFT JOIN Votes V ON U.Id = V.UserId
    WHERE U.Reputation > 1000 AND U.LastAccessDate > NOW() - INTERVAL 30 DAY
    GROUP BY
        U.id, U.DisplayName,U.Reputation,U.CreationDate,U.LastAccessDate
    ORDER BY
        TotalPosts DESC,
        TotalComments DESC,
        TotalUpvotesGiven DESC,
        TotalUpvotesReceived DESC
),PostActivity AS(
SELECT
        P.Id AS PostId,
        P.PostTypeId,
        P.CreationDate,
        P.Score,
        P.ViewCount,
        P.Title,
        P.Tags,
        U.DisplayName AS OwnerName,
        COALESCE(A.DisplayName) AS LastEditorName,
        P.LastEditDate,
        P.LastActivityDate,
        C.CommentCount,
        SUM(V.VoteTypeId  = 2) AS UpvotesCount,
        SUM(V.VoteTypeId = 3 ) AS DownvotesCount,
        V.UserId
    FROM
        Posts P
    LEFT JOIN Users U ON P.OwnerUserId = U.Id
    LEFT JOIN (
        SELECT
            PostId,
            COUNT(Id) AS CommentCount
        FROM
            Comments
        GROUP BY
            PostId
    ) C ON P.Id = C.PostId
    LEFT JOIN Votes V ON P.Id = V.PostId
    LEFT JOIN Users A ON P.LastEditorUserId = A.Id
    WHERE
        P.PostTypeId IN (1, 2) AND
        P.CreationDate > NOW() - INTERVAL 90 DAY
    GROUP BY
        P.Id,
        P.PostTypeId,
        P.CreationDate,
        P.Score,
        P.ViewCount,
        P.Title,
        P.Tags,
        OwnerName,
        LastEditorName,
        P.LastEditDate,
        P.LastActivityDate,
        C.CommentCount
    ORDER BY
        UpvotesCount DESC,
        DownvotesCount ASC,
        ViewCount DESC,
        LastActivityDate DESC
),  RecentPostVotes as (
    Select
        V.PostId,
        COUNT(V.Id) AS VoteCount,
        SUM(V.VoteTypeId = 2) AS Upvotes,
        SUM(V.VoteTypeId = 3) AS Downvotes

    From
        Votes V
    WHERE
        V.CreationDate > NOW() - INTERVAL 7 DAY
    GROUP BY
        V.PostId
    ORDER BY
        Upvotes DESC,
        Downvotes ASC
)
SELECT
        Q.PostId,
        Q.PostTypeId,
        Q.Title,
        Q.ViewCount,
        Q.UpvotesCount,
        Q.DownvotesCount,
        Q.CommentCount,
        Q.OwnerName,
        Q.LastEditorName,
        Q.CreationDate,
        Q.LastEditDate,
        Q.LastActivityDate ,
        RPV.VoteCount,
        RPV.Upvotes as RecentUpvotes,
        RPV.Downvotes as RecentDownvotes,
        UA.UserId,
        UA.userName,
        UA.TotalPosts,
        UA.TotalComments,
        UA.TotalUpvotesGiven,
        UA.TotalDownvotesGiven,
        UA.TotalUpvotesReceived,
        UA.TotalDownvotesReceived,
        UA.LastAccessDate,
        T.TagName
    FROM
        PostActivity Q
    LEFT JOIN
        RecentPostVotes RPV ON Q.PostId = RPV.PostId
    LEFT JOIN
        UserActivity UA On Q.OwnerUserId = UA.UserId
    LEFT JOIN
		TopTags T ON Q.Tags LIKE CONCAT('%<', T.TagName, '>%')
    WHERE
        Q.LastActivityDate > NOW() - INTERVAL 30 DAY
    ORDER BY
        Q.UpvotesCount DESC,
        Q.RecentUpvotes DESC,
        Q.ViewCount DESC,
        Q.DownvotesCount ASC,
        UA.TotalPosts DESC;
