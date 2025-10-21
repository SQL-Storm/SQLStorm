-- {"query": "41043.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "nova-lite", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2057, "output_tokens": 304} 

SELECT 
    U.DisplayName AS UserName,
    P.Title AS PostTitle,
    P.CreationDate AS PostCreationDate,
    P.Score AS PostScore,
    P.ViewCount AS PostViewCount,
    COUNT(V.Id) AS TotalVotesCount,
    SUM(CASE WHEN V.VoteTypeId = 2 THEN 1 ELSE 0 END) AS UpVoteCount,
    SUM(CASE WHEN V.VoteTypeId = 3 THEN 1 ELSE 0 END) AS DownVoteCount,
    AVG(CASE WHEN V.VoteTypeId = 2 THEN 1 ELSE 0 END) AS AvgUpVotes,
    AVG(CASE WHEN V.VoteTypeId = 3 THEN 1 ELSE 0 END) AS AvgDownVotes
FROM 
    Users U
JOIN 
    Posts P ON U.Id = P.OwnerUserId
LEFT JOIN 
    Votes V ON P.Id = V.PostId
WHERE 
    P.PostTypeId = 1
    AND P.CreationDate BETWEEN '2022-01-01' AND '2022-12-31'
GROUP BY 
    U.DisplayName, P.Title, P.CreationDate, P.Score, P.ViewCount
ORDER BY 
    P.Score DESC, P.ViewCount DESC, TotalVotesCount DESC
LIMIT 10;
