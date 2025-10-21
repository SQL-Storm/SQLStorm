-- {"query": "41052.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "nova-lite", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2057, "output_tokens": 374} 
SELECT 
    U.DisplayName AS UserDisplayName,
    P.Id AS PostId,
    P.Title AS PostTitle,
    PT.Name AS PostTypeName,
    COUNT(V.Id) AS TotalVotes,
    SUM(CASE WHEN V.VoteTypeId = 2 THEN 1 ELSE 0 END) AS UpVotes,
    SUM(CASE WHEN V.VoteTypeId = 3 THEN 1 ELSE 0 END) AS DownVotes,
    AVG(P.Score) AS AverageScore,
    MAX(P.ViewCount) AS MaxViews,
    MIN(P.CreationDate) AS EarliestPost,
    MAX(P.LastEditDate) AS LatestEdit,
    AVG(U.Reputation) AS AvgUserReputation,
    AVG(U.UpVotes) AS AvgUserUpVotes,
    AVG(U.DownVotes) AS AvgUserDownVotes
FROM 
    Users U
JOIN 
    Posts P ON U.Id = P.OwnerUserId
JOIN 
    PostTypes PT ON P.PostTypeId = PT.Id
LEFT JOIN 
    Votes V ON P.Id = V.PostId
WHERE 
    P.PostTypeId = 1 AND P.CreationDate > '2020-01-01'
GROUP BY 
    U.DisplayName, P.Id, P.Title, PT.Name
HAVING 
    COUNT(V.Id) > 10
ORDER BY 
    AVG(P.Score) DESC, 
    MAX(P.ViewCount) DESC, 
    AvgUserReputation DESC, 
    AvgUserUpVotes DESC, 
    AvgUserDownVotes ASC
LIMIT 10;