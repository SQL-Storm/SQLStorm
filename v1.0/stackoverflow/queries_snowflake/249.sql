
WITH PopularQuestions AS (
    SELECT 
        p.Id AS PostId,
        p.Title,
        p.CreationDate,
        p.Score,
        p.AnswerCount,
        DENSE_RANK() OVER (ORDER BY p.Score DESC) AS RankByScore
    FROM 
        Posts p
    WHERE 
        p.PostTypeId = 1 
        AND p.AcceptedAnswerId IS NOT NULL
        AND p.CreationDate >= CAST(DATEADD(year, -1, '2024-10-01 12:34:56') AS TIMESTAMP)
),
QuestionTags AS (
    SELECT 
        p.Id AS PostId,
        LISTAGG(t.TagName, ', ') AS Tags
    FROM 
        Posts p,
        LATERAL FLATTEN(INPUT => SPLIT(SUBSTR(p.Tags, 2, LENGTH(p.Tags) - 2), '><')) t
    WHERE 
        p.PostTypeId = 1
    GROUP BY 
        p.Id
),
UserReputation AS (
    SELECT 
        u.Id AS UserId,
        u.Reputation,
        ROW_NUMBER() OVER (ORDER BY u.Reputation DESC) AS ReputationRank
    FROM 
        Users u
    WHERE 
        u.Reputation > 0
)
SELECT 
    q.PostId,
    q.Title,
    q.Score,
    qt.Tags,
    u.DisplayName AS TopUser,
    u.Reputation
FROM 
    PopularQuestions q
LEFT JOIN 
    QuestionTags qt ON q.PostId = qt.PostId
LEFT JOIN 
    Users u ON u.Id = (SELECT UserId FROM Votes v WHERE v.PostId = q.PostId AND v.VoteTypeId = 2 ORDER BY v.CreationDate DESC LIMIT 1)
WHERE 
    q.RankByScore <= 10
ORDER BY 
    q.Score DESC, q.CreationDate DESC;
