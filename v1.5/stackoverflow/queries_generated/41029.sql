-- {"query": "41029.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "nova-lite", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2057, "output_tokens": 336} 

SELECT 
    U.DisplayName AS UserName,
    P.Title, 
    PT.Name AS PostTypeName, 
    COUNT(V.Id) AS TotalVotes,
    AVG(V.BountyAmount) AS AvgBountyAmount,
    SUM(CASE WHEN V.VoteTypeId = 2 THEN 1 ELSE 0 END) AS UpVotes,
    SUM(CASE WHEN V.VoteTypeId = 3 THEN 1 ELSE 0 END) AS DownVotes,
    MAX(P.CreationDate) AS LatestPostDate,
    MAX(P.LastEditDate) AS LatestEditDate,
    COUNT(DISTINCT C.Id) AS TotalComments,
    AVG(P.Score) AS AvgScore,
    COUNT(DISTINCT PL.RelatedPostId) AS RelatedPostsCount
FROM 
    Users U
JOIN 
    Posts P ON U.Id = P.OwnerUserId
JOIN 
    PostTypes PT ON P.PostTypeId = PT.Id
LEFT JOIN 
    Votes V ON P.Id = V.PostId
LEFT JOIN 
    Comments C ON P.Id = C.PostId
LEFT JOIN 
    PostLinks PL ON P.Id = PL.PostId
WHERE 
    PT.Name IN ('Question', 'Answer')
GROUP BY 
    U.Id, P.Id, PT.Id
HAVING 
    COUNT(V.Id) > 10
ORDER BY 
    TotalVotes DESC, 
    AvgScore DESC, 
    LatestPostDate DESC, 
    UserName ASC;
