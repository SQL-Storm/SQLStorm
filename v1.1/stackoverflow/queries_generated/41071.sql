-- {"query": "41071.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "nova-lite", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2057, "output_tokens": 388} 

SELECT 
    U.DisplayName AS UserName,
    COUNT(P.Id) AS TotalPosts,
    SUM(P.Score) AS TotalScore,
    AVG(P.ViewCount) AS AvgViews,
    MAX(P.CreationDate) AS LatestPostDate,
    COUNT(DISTINCT P.Tags) AS UniqueTagsUsed,
    COUNT(DISTINCT V.PostId) AS TotalVotes,
    SUM(V.BountyAmount) AS TotalBountyAmount,
    COUNT(DISTINCT B.Id) AS TotalBadges,
    COUNT(DISTINCT C.Id) AS TotalComments,
    COUNT(DISTINCT PH.PostId) AS TotalPostEdits,
    COUNT(DISTINCT PL.PostId) AS TotalLinkedPosts,
    GROUP_CONCAT(DISTINCT T.TagName) AS TagsUsed
FROM 
    Users U
LEFT JOIN 
    Posts P ON U.Id = P.OwnerUserId
LEFT JOIN 
    Votes V ON P.Id = V.PostId
LEFT JOIN 
    Badges B ON U.Id = B.UserId
LEFT JOIN 
    Comments C ON P.Id = C.PostId
LEFT JOIN 
    PostHistory PH ON P.Id = PH.PostId
LEFT JOIN 
    PostLinks PL ON P.Id = PL.PostId
LEFT JOIN 
    Tags T ON P.Id = T.Id
WHERE 
    U.Reputation > 1000
GROUP BY 
    U.DisplayName
ORDER BY 
    TotalPosts DESC, 
    TotalScore DESC, 
    TotalVotes DESC, 
    TotalBountyAmount DESC, 
    TotalBadges DESC, 
    TotalComments DESC, 
    TotalPostEdits DESC, 
    TotalLinkedPosts DESC
LIMIT 10;
