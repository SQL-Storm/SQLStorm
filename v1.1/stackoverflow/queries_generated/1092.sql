-- {"query": "1092.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-4o-mini", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 639} 

WITH UserActivity AS (
    SELECT 
        U.Id AS UserId, 
        U.DisplayName, 
        U.Reputation, 
        COUNT(DISTINCT P.Id) AS TotalPosts, 
        COUNT(DISTINCT C.Id) AS TotalComments, 
        SUM(CASE WHEN V.VoteTypeId = 2 THEN 1 ELSE 0 END) AS TotalUpVotes,
        SUM(CASE WHEN V.VoteTypeId = 3 THEN 1 ELSE 0 END) AS TotalDownVotes
    FROM 
        Users U
    LEFT JOIN 
        Posts P ON U.Id = P.OwnerUserId AND P.CreationDate >= CURRENT_DATE - INTERVAL '1 year'
    LEFT JOIN 
        Comments C ON U.Id = C.UserId AND C.CreationDate >= CURRENT_DATE - INTERVAL '1 year'
    LEFT JOIN 
        Votes V ON U.Id = V.UserId AND V.CreationDate >= CURRENT_DATE - INTERVAL '1 year'
    GROUP BY 
        U.Id
), RankedUsers AS (
    SELECT 
        UA.*, 
        RANK() OVER (ORDER BY UA.TotalPosts DESC, UA.TotalUpVotes DESC, UA.Reputation DESC) AS Rank
    FROM 
        UserActivity UA
)
SELECT 
    RU.DisplayName, 
    RU.Reputation, 
    RU.TotalPosts, 
    RU.TotalComments, 
    RU.TotalUpVotes, 
    RU.TotalDownVotes
FROM 
    RankedUsers RU
WHERE 
    RU.Rank <= 10
ORDER BY 
    RU.Rank;

SELECT 
    P.Title, 
    STRING_AGG(DISTINCT T.TagName, ', ') AS Tags
FROM 
    Posts P
JOIN 
    LATERAL (
        SELECT 
            UNNEST(STRING_TO_ARRAY(P.Tags, '><')) AS TagName
    ) T ON TRUE
WHERE 
    P.CreationDate >= CURRENT_DATE - INTERVAL '30 days'
GROUP BY 
    P.Id;

SELECT 
    U.DisplayName, 
    COUNT(P.Id) AS QuestionsAsked, 
    COUNT(C.Id) AS CommentsMade,
    COALESCE(MAX(B.Class), 0) AS HighestBadgeLevel
FROM 
    Users U
LEFT JOIN 
    Posts P ON U.Id = P.OwnerUserId AND P.PostTypeId = 1
LEFT JOIN 
    Comments C ON U.Id = C.UserId
LEFT JOIN 
    Badges B ON U.Id = B.UserId
GROUP BY 
    U.Id
HAVING 
    COUNT(P.Id) > 0
ORDER BY 
    HighestBadgeLevel DESC, QuestionsAsked DESC;

SELECT 
    PH.UserDisplayName, 
    PH.CreationDate, 
    PH.Comment, 
    P.Title
FROM 
    PostHistory PH 
JOIN 
    Posts P ON PH.PostId = P.Id
WHERE 
    PH.PostHistoryTypeId = 10 
    AND PH.CreationDate >= CURRENT_DATE - INTERVAL '3 months'
ORDER BY 
    PH.CreationDate DESC
LIMIT 5;
