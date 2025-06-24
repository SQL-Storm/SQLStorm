WITH UserActivity AS (
    SELECT 
        U.Id AS UserId,
        U.DisplayName,
        COUNT(DISTINCT P.Id) AS PostCount,
        SUM(CASE WHEN P.PostTypeId = 1 THEN 1 ELSE 0 END) AS QuestionCount,
        SUM(CASE WHEN P.PostTypeId = 2 THEN 1 ELSE 0 END) AS AnswerCount,
        COUNT(DISTINCT C.Id) AS CommentCount,
        SUM(V.BountyAmount) AS TotalBounty,
        SUM(B.Class) AS TotalBadges
    FROM 
        Users U
    LEFT JOIN 
        Posts P ON U.Id = P.OwnerUserId
    LEFT JOIN 
        Comments C ON P.Id = C.PostId
    LEFT JOIN 
        Votes V ON P.Id = V.PostId AND V.VoteTypeId IN (2, 3) -- Only Upvotes and Downvotes
    LEFT JOIN 
        Badges B ON U.Id = B.UserId
    WHERE 
        U.Reputation > 100 -- Users with reputation above 100
    GROUP BY 
        U.Id
),
RankedUsers AS (
    SELECT 
        UserId,
        DisplayName,
        PostCount,
        QuestionCount,
        AnswerCount,
        CommentCount,
        TotalBounty,
        TotalBadges,
        ROW_NUMBER() OVER (ORDER BY PostCount DESC, QuestionCount DESC, AnswerCount DESC, TotalBounty DESC) AS Rank
    FROM 
        UserActivity
)
SELECT 
    R.UserId,
    R.DisplayName,
    R.PostCount,
    R.QuestionCount,
    R.AnswerCount,
    R.CommentCount,
    R.TotalBounty,
    R.TotalBadges,
    R.Rank
FROM 
    RankedUsers R
WHERE 
    R.Rank <= 10 -- Top 10 users
ORDER BY 
    R.Rank;
