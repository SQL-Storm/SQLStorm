-- {"query": "54033.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "gpt-oss-20b", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2048, "output_tokens": 2480} 
WITH  
-- all questions with vote counts  
Questions AS (  
    SELECT  
        p.Id,  
        p.Title,  
        p.CreationDate,  
        p.ViewCount,  
        u.DisplayName AS OwnerName,  
        COUNT(v.Id) AS TotalVotes,  
        SUM(CASE WHEN vt.Name='UpMod' THEN 1 ELSE 0 END) AS UpVotes,  
        SUM(CASE WHEN vt.Name='DownMod' THEN 1 ELSE 0 END) AS DownVotes  
    FROM Posts p  
    LEFT JOIN Votes v ON v.PostId = p.Id  
    LEFT JOIN VoteTypes vt ON vt.Id = v.VoteTypeId  
    LEFT JOIN Users u ON u.Id = p.OwnerUserId  
    WHERE p.PostTypeId = 1  
    GROUP BY p.Id, p.Title, p.CreationDate, p.ViewCount, u.DisplayName  
),  
-- split tags for each question  
TagByQuestions AS (  
    SELECT q.Id AS QuestionId, t.value AS TagName  
    FROM Questions q  
    CROSS APPLY STRING_SPLIT(REPLACE(q.Tags, '<>', '>'), '>') AS t  
),  
-- duplicate relationships  
Duplicates AS (  
    SELECT pl.PostId, COUNT(*) AS DuplicateCount  
    FROM PostLinks pl  
    WHERE pl.LinkTypeId = 3  
    GROUP BY pl.PostId  
),  
-- badge counts per user  
Badges AS (  
    SELECT b.UserId,  
           SUM(CASE WHEN b.Class = 1 THEN 1 ELSE 0 END) AS Gold,  
           SUM(CASE WHEN b.Class = 2 THEN 1 ELSE 0 END) AS Silver,  
           SUM(CASE WHEN b.Class = 3 THEN 1 ELSE 0 END) AS Bronze  
    FROM Badges b  
    GROUP BY b.UserId  
)  
SELECT  
    q.Id,  
    q.Title,  
    q.CreationDate,  
    q.OwnerName,  
    q.ViewCount,  
    q.TotalVotes,  
    q.UpVotes,  
    q.DownVotes,  
    COALESCE(d.DuplicateCount,0) AS DuplicateLinks,  
    COALESCE(b.Gold,0) AS GoldBadges,  
    COALESCE(b.Silver,0) AS SilverBadges,  
    COALESCE(b.Bronze,0) AS BronzeBadges,  
    STRING_AGG(DISTINCT t.TagName, ', ') WITHIN GROUP (ORDER BY t.TagName) AS Tags  
FROM Questions q  
LEFT JOIN Duplicates d ON d.PostId = q.Id  
LEFT JOIN Badges b ON b.UserId = (SELECT OwnerUserId FROM Posts WHERE Id = q.Id)  
LEFT JOIN TagByQuestions t ON t.QuestionId = q.Id  
GROUP BY  
    q.Id,  
    q.Title,  
    q.CreationDate,  
    q.OwnerName,  
    q.ViewCount,  
    q.TotalVotes,  
    q.UpVotes,  
    q.DownVotes,  
    d.DuplicateCount,  
    b.Gold, b.Silver, b.Bronze  
ORDER BY q.ViewCount DESC  
OFFSET 0 ROWS FETCH NEXT 100 ROWS ONLY;