-- {"query": "2067.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p1", "model": "gpt-4o", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 406} 
WITH RankedAnswers AS (
    SELECT 
        p.Id AS PostId,
        p.Title,
        p.OwnerUserId,
        p.CreationDate,
        ROW_NUMBER() OVER (PARTITION BY p.ParentId ORDER BY p.Score DESC, p.CreationDate ASC) AS AnswerRank
    FROM 
        Posts p
    WHERE 
        p.PostTypeId = 2
),
HighRepUsers AS (
    SELECT 
        u.Id AS UserId,
        u.DisplayName,
        u.Reputation
    FROM 
        Users u
    WHERE 
        u.Reputation > (SELECT AVG(Reputation) FROM Users)
),
TopQuestions AS (
    SELECT
        p.Id AS PostId,
        p.Title,
        COALESCE(p.AnswerCount, 0) AS TotalAnswers,
        p.CreationDate,
        COALESCE(p.ClosedDate, p.LastActivityDate) AS LastActivity  
    FROM 
        Posts p
    WHERE 
        p.PostTypeId = 1 AND
        p.Score > 10
),
FinalSelection AS (
    SELECT
        tq.PostId,
        tq.Title,
        hru.DisplayName AS UserDisplayName,
        ra.AnswerRank,
        tq.TotalAnswers
    FROM
        TopQuestions tq
    LEFT JOIN
        HighRepUsers hru ON tq.PostId = hru.UserId
    LEFT JOIN
        RankedAnswers ra ON tq.PostId = ra.PostId
    WHERE
        ra.AnswerRank = 1 OR hru.UserId IS NOT NULL
)
SELECT
    fs.PostId,
    fs.Title,
    fs.UserDisplayName,
    CASE 
        WHEN fs.TotalAnswers > 5 THEN 'Popular'
        ELSE 'Less Populated'
    END AS AnswerPopStatus
FROM
    FinalSelection fs
WHERE
    fs.UserDisplayName IS NOT NULL OR fs.AnswerRank = 1
ORDER BY
    fs.AnswerRank;