-- {"query": "27088.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "pixtral-large", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2337, "output_tokens": 1406} 

WITH ActiveUsers AS (
    SELECT
        U.Id AS UserId,
        U.Reputation,
        U.CreationDate,
        U.DisplayName,
        U.LastAccessDate,
        U.Views,
        U.UpVotes,
        U.DownVotes,
        COUNT(P.Id) AS TotalPosts,
        MAX(P.LastActivityDate) AS LastPostActivity
    FROM
        Users U
    LEFT JOIN
        Posts P ON U.Id = P.OwnerUserId
    WHERE
        U.LastAccessDate > NOW() - INTERVAL '30 days'
    GROUP BY
        U.Id,
        U.Reputation,
        U.CreationDate,
        U.DisplayName,
        U.LastAccessDate,
        U.Views,
        U.UpVotes,
        U.DownVotes
),
HighReputationUsers AS (
    SELECT
        UserId,
        Reputation,
        DisplayName,
        ROW_NUMBER() OVER (ORDER BY Reputation DESC) AS ReputationRank
    FROM
        ActiveUsers
    WHERE
        Reputation > 1000
),
PopularPosts AS (
    SELECT
        P.Id AS PostId,
        P.PostTypeId,
        P.Title,
        P.ViewCount,
        P.Score,
        P.AnswerCount,
        P.CreationDate AS PostCreationDate,
        U.DisplayName AS OwnerDisplayName,
        COALESCE(A.Id, 0) AS AcceptedAnswerId,
        COALESCE(A.Body, '') AS AcceptedAnswerBody,
        COALESCE(A.Score, 0) AS AcceptedAnswerScore
    FROM
        Posts P
    LEFT JOIN
        Users U ON P.OwnerUserId = U.Id
    LEFT JOIN
        Posts A ON P.AcceptedAnswerId = A.Id
    WHERE
        P.PostTypeId = 1
        AND P.CreationDate > NOW() - INTERVAL '1 year'
        AND P.ViewCount > 1000
    ORDER BY
        P.ViewCount DESC
),
TopCommentedPosts AS (
    SELECT
        PostId,
        COUNT(C.Id) AS CommentCount
    FROM
        Comments C
    GROUP BY
        PostId
    HAVING
        COUNT(C.Id) > 10
),
TagStats AS (
    SELECT
        T.TagName,
        COUNT(PT.Id) AS PostCount,
        MAX(PT.CreationDate) AS LastPostDate,
        SUM(PT.Score) AS TotalScore
    FROM
        Tags T
    JOIN
        Posts PT ON T.Id = PT.Id
    WHERE
        PT.Tags LIKE CONCAT('%<', T.TagName, '>%')
    GROUP BY
        T.TagName
),
BadgeHolders AS (
    SELECT
        B.UserId,
        COUNT(B.Id) AS BadgeCount,
        MAX(B.Class) AS HighestBadgeClass
    FROM
        Badges B
    GROUP BY
        B.UserId
),
PostActivityMetrics AS (
    SELECT
        P.Id AS PostId,
        P.Title,
        COUNT(V.Id) AS VoteCount,
        SUM(CASE WHEN V.VoteTypeId = 2 THEN 1 ELSE 0 END) AS UpVotes,
        SUM(CASE WHEN V.VoteTypeId = 3 THEN 1 ELSE 0 END) AS DownVotes,
        COUNT(C.Id) AS CommentCount,
        COUNT(PH.Id) AS EditCount,
        MAX(PH.CreationDate) AS LastEditDate
    FROM
        Posts P
    LEFT JOIN
        Votes V ON P.Id = V.PostId
    LEFT JOIN
        Comments C ON P.Id = C.PostId
    LEFT JOIN
        PostHistory PH ON P.Id = PH.PostId
    WHERE
        P.PostTypeId = 1
    GROUP BY
        P.Id,
        P.Title
)
SELECT
    A.UserId,
    A.DisplayName,
    A.Reputation,
    A.ReputationRank,
    PP.PostId,
    PP.Title AS PostTitle,
    PP.ViewCount,
    PP.Score,
    PP.AnswerCount,
    PP.AcceptedAnswerBody,
    TCP.CommentCount AS PostCommentCount,
    PA.VoteCount,
    PA.UpVotes,
    PA.DownVotes,
    PA.EditCount,
    PA.LastEditDate,
    PA.Score,
    TVotes.Votes AS DownvotePercentage,
    U.EmailHash,
    U.AccountId
FROM
    HighReputationUsers A
JOIN
    PopularPosts PP ON A.UserId = PP.OwnerUserId
LEFT JOIN
    TopCommentedPosts TCP ON PP.PostId = TCP.PostId
LEFT JOIN
    PostActivityMetrics PA ON PP.PostId = PA.PostId
LEFT JOIN
(SELECT PostId, COUNT(VoteTypeId) as Votes
        FROM
                 (SELECT *, LAG(PostId) OVER (PARTITION BY PostId ORDER BY CreationDate DESC) AS prev
                  FROM Votes) windowsub
        WHERE VoteTypeId = 3 AND (PostId <> prev OR prev IS NULL)
        GROUP BY PostId
    ) AS TVotes ON TVotes.PostId=PP.PostId
LEFT JOIN Users u on u.Id=A.UsersId
ORDER BY
    PP.PostId DESC
LIMIT 100;
