-- {"query": "30015.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "gpt-3.5-turbo", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 1962, "output_tokens": 97} 
SELECT u.Id as User_Id, u.DisplayName as User_Name, p.Id as Post_Id, p.Title as Post_Title, p.CreationDate as Post_Creation_Date,
COUNT(v.Id) as Total_Votes
FROM Users u
JOIN Posts p ON u.Id = p.OwnerUserId
LEFT JOIN Votes v ON p.Id = v.PostId
GROUP BY u.Id, u.DisplayName, p.Id, p.Title, p.CreationDate
ORDER BY Total_Votes DESC;