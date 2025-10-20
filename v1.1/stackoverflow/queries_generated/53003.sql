-- {"query": "53003.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "grok-4", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2646, "output_tokens": 676} 

WITH TopTags AS (
    SELECT 
        t.Id AS TagId,
        t.TagName,
        COUNT(DISTINCT p.Id) AS QuestionCount,
        ROW_NUMBER() OVER (ORDER BY COUNT(DISTINCT p.Id) DESC) AS Rank
    FROM 
        Tags t
    JOIN 
        Posts p ON p.Tags LIKE '%' || t.TagName || '%'
    WHERE 
        p.PostTypeId = 1
        AND p.CreationDate >= '2020-01-01'
    GROUP BY 
        t.Id, t.TagName
    HAVING 
        COUNT(DISTINCT p.Id) > 1000
),
TagAnswers AS (
    SELECT 
        tt.TagId,
        a.OwnerUserId,
        COUNT(a.Id) AS AnswerCount,
        SUM(v.BountyAmount) AS TotalBounty,
        AVG(a.Score) AS AvgScore,
        ROW_NUMBER() OVER (PARTITION BY tt.TagId ORDER BY COUNT(a.Id) DESC, SUM(v.BountyAmount) DESC) AS UserRank
    FROM 
        TopTags tt
    JOIN 
        Posts q ON q.Tags LIKE '%' || (SELECT TagName FROM Tags WHERE Id = tt.TagId) || '%'
    JOIN 
        Posts a ON a.ParentId = q.Id AND a.PostTypeId = 2
    LEFT JOIN 
        Votes v ON v.PostId = a.Id AND v.VoteTypeId IN (2, 8, 9)
    WHERE 
        q.PostTypeId = 1
        AND a.CreationDate >= '2020-01-01'
    GROUP BY 
        tt.TagId, a.OwnerUserId
    HAVING 
        COUNT(a.Id) > 50
),
TopUsersPerTag AS (
    SELECT 
        ta.TagId,
        u.Id AS UserId,
        u.DisplayName,
        u.Reputation,
        ta.AnswerCount,
        ta.TotalBounty,
        ta.AvgScore,
        (SELECT COUNT(b.Id) FROM Badges b WHERE b.UserId = u.Id AND b.Class = 1) AS GoldBadges,
        (SELECT COUNT(c.Id) FROM Comments c WHERE c.UserId = u.Id AND c.PostId IN (SELECT Id FROM Posts WHERE PostTypeId = 2 AND OwnerUserId = u.Id)) AS CommentCount
    FROM 
        TagAnswers ta
    JOIN 
        Users u ON u.Id = ta.OwnerUserId
    WHERE 
        ta.UserRank = 1
)
SELECT 
    tt.TagName,
    tt.QuestionCount,
    tup.UserId,
    tup.DisplayName,
    tup.Reputation,
    tup.AnswerCount,
    tup.TotalBounty,
    tup.AvgScore,
    tup.GoldBadges,
    tup.CommentCount,
    (SELECT COUNT(ph.Id) FROM PostHistory ph WHERE ph.PostId IN (SELECT Id FROM Posts WHERE OwnerUserId = tup.UserId AND PostTypeId = 2) AND ph.PostHistoryTypeId IN (4,5,6)) AS EditCount
FROM 
    TopTags tt
JOIN 
    TopUsersPerTag tup ON tup.TagId = tt.TagId
WHERE 
    tt.Rank <= 10
ORDER BY 
    tt.QuestionCount DESC;
