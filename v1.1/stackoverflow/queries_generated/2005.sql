-- {"query": "2005.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p1", "model": "gpt-4o", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 530} 

WITH HighReputationUsers AS (
    SELECT 
        Id, 
        DisplayName, 
        Reputation, 
        ROW_NUMBER() OVER (ORDER BY Reputation DESC) AS Rank
    FROM 
        Users
    WHERE 
        Reputation > 10000 
        AND UpVotes > DownVotes
),
MostActiveQuestions AS (
    SELECT 
        p.Id, 
        p.Title, 
        p.ViewCount, 
        COUNT(c.Id) AS TotalComments
    FROM 
        Posts p
    LEFT JOIN 
        Comments c ON p.Id = c.PostId
    WHERE 
        p.PostTypeId = 1 
        AND p.ViewCount > 1000
    GROUP BY 
        p.Id, p.Title, p.ViewCount
    HAVING 
        COUNT(c.Id) > 5
),
UserWithBadgesAndVotes AS (
    SELECT
        u.Id AS UserId, 
        u.DisplayName, 
        COUNT(DISTINCT b.Id) AS BadgeCount, 
        SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS TotalUpVotes
    FROM 
        Users u
    LEFT JOIN 
        Badges b ON u.Id = b.UserId
    LEFT JOIN 
        Votes v ON u.Id = v.UserId
    GROUP BY 
        u.Id, u.DisplayName
    HAVING 
        COUNT(DISTINCT b.Id) > 3
)
SELECT 
    U.DisplayName AS UserName,
    H.Reputation AS UserReputation,
    M.Title AS QuestionTitle,
    M.ViewCount AS QuestionViews,
    T.TagName AS PopularTag,
    U.BagdeCount AS BadgeCount,
    U.TotalUpVotes AS UpVotes
FROM 
    HighReputationUsers H
JOIN 
    MostActiveQuestions M ON H.Id = M.Id
LEFT JOIN 
    (SELECT PostId, STRING_AGG(TagName, ', ') AS TagName 
     FROM Posts 
     CROSS APPLY STRING_TO_ARRAY(SUBSTRING(Tags, 2, LENGTH(Tags) - 2), '><') AS TID 
     JOIN Tags T ON T.TagName = TID 
     GROUP BY PostId 
     HAVING COUNT(TID) > 1) AS T ON M.Id = T.PostId
JOIN 
    UserWithBadgesAndVotes U ON H.Id = U.UserId
WHERE 
    M.ViewCount > (SELECT AVG(ViewCount) FROM MostActiveQuestions)
ORDER BY 
    H.Reputation DESC, M.ViewCount DESC;
