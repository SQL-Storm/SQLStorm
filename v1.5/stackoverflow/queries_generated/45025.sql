-- {"query": "45025.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "claude-3.5-haiku", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 57350, "output_tokens": 10063} 
WITH TopUsersTags AS (
    SELECT 
        u.Id AS UserId,
        u.DisplayName,
        t.TagName,
        COUNT(*) AS TagCount,
        DENSE_RANK() OVER (PARTITION BY t.TagName ORDER BY COUNT(*) DESC) AS UserRank
    FROM 
        Posts p
        JOIN Users u ON p.OwnerUserId = u.Id
        CROSS JOIN LATERAL string_to_array(substring(p.Tags, 2, length(p.Tags)-2), '><') AS tags(TagName)
        JOIN Tags t ON t.TagName = tags.TagName
    WHERE 
        p.PostTypeId = 1 
        AND u.Reputation > 1000
    GROUP BY 
        u.Id, u.DisplayName, t.TagName
),
QuestionInteractions AS (
    SELECT 
        p.Id AS QuestionId,
        p.Title,
        COUNT(DISTINCT v.Id) AS VoteCount,
        COUNT(DISTINCT c.Id) AS CommentCount,
        COUNT(DISTINCT pl.Id) AS LinkCount,
        AVG(u.Reputation) AS AvgUserReputation
    FROM 
        Posts p
        LEFT JOIN Votes v ON p.Id = v.PostId
        LEFT JOIN Comments c ON p.Id = c.PostId
        LEFT JOIN PostLinks pl ON p.Id = pl.PostId
    WHERE 
        p.PostTypeId = 1
        AND p.CreationDate > NOW() - INTERVAL '5 years'
    GROUP BY 
        p.Id, p.Title
)
SELECT 
    tt.TagName,
    MAX(tt.DisplayName) AS TopExpert,
    AVG(qi.VoteCount) AS AvgQuestionVotes,
    SUM(qi.CommentCount) AS TotalComments,
    MAX(qi.LinkCount) AS MaxRelatedLinks,
    COUNT(DISTINCT qi.QuestionId) AS QuestionCount
FROM 
    TopUsersTags tt
    JOIN QuestionInteractions qi ON EXISTS (
        SELECT 1 
        FROM Posts p 
        CROSS JOIN LATERAL string_to_array(substring(p.Tags, 2, length(p.Tags)-2), '><') AS tags(TagName)
        WHERE p.Id = qi.QuestionId AND tags.TagName = tt.TagName
    )
WHERE 
    tt.UserRank <= 3
GROUP BY 
    tt.TagName
ORDER BY 
    QuestionCount DESC, AvgQuestionVotes DESC
LIMIT 50;