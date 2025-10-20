-- {"query": "57030.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "pixtral-large", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2291, "output_tokens": 939} 
WITH UserActivity AS (
    SELECT
        U.Id AS UserId,
        U.Reputation,
        U.CreationDate AS UserCreationDate,
        U.LastAccessDate,
        COUNT(P.Id) AS TotalPosts,
        COUNT(DISTINCT CASE WHEN P.PostTypeId = 1 THEN P.Id END) AS TotalQuestions,
        COUNT(DISTINCT CASE WHEN P.PostTypeId = 2 THEN P.Id END) AS TotalAnswers,
        SUM(CASE WHEN P.PostTypeId = 1 THEN P.Score ELSE 0 END) AS QuestionScore,
        SUM(CASE WHEN P.PostTypeId = 2 THEN P.Score ELSE 0 END) AS AnswerScore,
        COUNT(DISTINCT C.Id) AS TotalComments,
        COUNT(DISTINCT V.Id) AS TotalVotes,
        SUM(CASE WHEN V.VoteTypeId = 2 THEN 1 ELSE 0 END) AS TotalUpvotes,
        SUM(CASE WHEN V.VoteTypeId = 3 THEN 1 ELSE 0 END) AS TotalDownvotes
    FROM
        Users U
    LEFT JOIN
        Posts P ON U.Id = P.OwnerUserId
    LEFT JOIN
        Comments C ON U.Id = C.UserId
    LEFT JOIN
        Votes V ON U.Id = V.UserId
    GROUP BY
        U.Id, U.Reputation, U.CreationDate, U.LastAccessDate
),
HighActivityUsers AS (
    SELECT
        UserId,
        Reputation,
        UserCreationDate,
        LastAccessDate,
        TotalPosts,
        TotalQuestions,
        TotalAnswers,
        QuestionScore,
        AnswerScore,
        TotalComments,
        TotalVotes,
        TotalUpvotes,
        TotalDownvotes,
        ROW_NUMBER() OVER (ORDER BY TotalPosts DESC, TotalVotes DESC, Reputation DESC) AS Rank
    FROM
        UserActivity
)
SELECT
    U.UserId,
    U.Reputation,
    U.UserCreationDate,
    U.LastAccessDate,
    U.TotalPosts,
    U.TotalQuestions,
    U.TotalAnswers,
    U.QuestionScore,
    U.AnswerScore,
    U.TotalComments,
    U.TotalVotes,
    U.TotalUpvotes,
    U.TotalDownvotes,
    U.Rank,
    P.Id AS LatestPostId,
    P.PostTypeId,
    P.CreationDate AS LatestPostDate,
    P.Score AS LatestPostScore,
    P.ViewCount AS LatestPostViewCount,
    P.Title AS LatestPostTitle,
    P.Tags AS LatestPostTags,
    P.AnswerCount AS LatestPostAnswerCount,
    P.CommentCount AS LatestPostCommentCount,
    P.FavoriteCount AS LatestPostFavoriteCount,
    P.ContentLicense AS LatestPostContentLicense,
(
    SELECT
        T.TagName
    FROM
        Posts P2
    JOIN
        Tags T ON P2.Tags LIKE CONCAT('%<', T.TagName, '>%')
    WHERE
        P2.Id = P.Id
    ORDER BY
        T.Count DESC
    LIMIT 1
) AS MostPopularTag
FROM
    HighActivityUsers U
LEFT JOIN
    Posts P ON U.UserId = P.OwnerUserId
WHERE
    P.CreationDate = (
        SELECT
            MAX(P2.CreationDate)
        FROM
            Posts P2
        WHERE
            P2.OwnerUserId = U.UserId
    )
ORDER BY
    U.Rank;