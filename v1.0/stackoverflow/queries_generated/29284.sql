WITH TagCounts AS (
    SELECT 
        Tags,
        COUNT(*) AS PostCount
    FROM 
        Posts
    WHERE 
        PostTypeId = 1  -- Only considering questions
    GROUP BY 
        Tags
),
TopTags AS (
    SELECT 
        SUBSTRING(Tags, 3, LEN(Tags) - 4) AS FormattedTags,
        PostCount
    FROM 
        TagCounts
    WHERE 
        PostCount > 10 -- considering tags used in more than 10 questions
),
UserActivity AS (
    SELECT 
        U.Id AS UserId,
        U.DisplayName,
        COUNT(DISTINCT P.Id) AS QuestionCount,
        SUM(CASE WHEN V.VoteTypeId = 2 THEN 1 ELSE 0 END) AS UpVotes,
        SUM(CASE WHEN V.VoteTypeId = 3 THEN 1 ELSE 0 END) AS DownVotes
    FROM 
        Users U
    JOIN 
        Posts P ON U.Id = P.OwnerUserId
    LEFT JOIN 
        Votes V ON P.Id = V.PostId 
    WHERE 
        P.PostTypeId = 1 -- Only questions
    GROUP BY 
        U.Id, U.DisplayName
),
TopUsers AS (
    SELECT 
        UserId, 
        DisplayName, 
        QuestionCount, 
        UpVotes - DownVotes AS VoteBalance
    FROM 
        UserActivity
    WHERE 
        QuestionCount > 5 -- Users with more than 5 questions
    ORDER BY 
        VoteBalance DESC
    LIMIT 10 -- Top 10 users
)
SELECT 
    TU.DisplayName,
    T.FormattedTags,
    T.PostCount,
    TU.QuestionCount,
    TU.VoteBalance
FROM 
    TopUsers TU
CROSS JOIN 
    TopTags T
ORDER BY 
    TU.VoteBalance DESC, T.PostCount DESC;
