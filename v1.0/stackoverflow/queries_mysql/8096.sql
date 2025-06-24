
WITH UserStatistics AS (
    SELECT 
        U.Id AS UserId,
        U.DisplayName,
        COUNT(DISTINCT P.Id) AS PostCount,
        SUM(CASE WHEN P.PostTypeId = 1 THEN 1 ELSE 0 END) AS QuestionCount,
        SUM(CASE WHEN P.PostTypeId = 2 THEN 1 ELSE 0 END) AS AnswerCount,
        SUM(CASE WHEN V.VoteTypeId = 2 THEN 1 ELSE 0 END) AS Upvotes,
        SUM(CASE WHEN V.VoteTypeId = 3 THEN 1 ELSE 0 END) AS Downvotes,
        SUM(CASE WHEN B.Id IS NOT NULL THEN 1 ELSE 0 END) AS BadgeCount
    FROM 
        Users U
    LEFT JOIN 
        Posts P ON U.Id = P.OwnerUserId
    LEFT JOIN 
        Votes V ON P.Id = V.PostId
    LEFT JOIN 
        Badges B ON U.Id = B.UserId
    GROUP BY 
        U.Id, U.DisplayName
),
TopUsers AS (
    SELECT 
        UserId,
        DisplayName,
        PostCount,
        QuestionCount,
        AnswerCount,
        Upvotes,
        Downvotes,
        BadgeCount,
        @row_num_posts := @row_num_posts + 1 AS RankByPosts,
        @row_num_upvotes := @row_num_upvotes + 1 AS RankByUpvotes
    FROM 
        UserStatistics, (SELECT @row_num_posts := 0, @row_num_upvotes := 0) AS init
    ORDER BY 
        PostCount DESC, Upvotes DESC
)
SELECT 
    UserId,
    DisplayName,
    PostCount,
    QuestionCount,
    AnswerCount,
    Upvotes,
    Downvotes,
    BadgeCount,
    RankByPosts,
    RankByUpvotes
FROM 
    TopUsers
WHERE 
    RankByPosts <= 10 OR RankByUpvotes <= 10
ORDER BY 
    RankByPosts, RankByUpvotes;
