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
        CROSS JOIN LATERAL (
            SELECT regexp_split_to_table(substring(p.Tags FROM 2 FOR (length(p.Tags)-2)), '><') AS TagName
        ) AS tags
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
        LEFT JOIN Users u ON p.OwnerUserId = u.Id
    WHERE 
        p.PostTypeId = 1
        AND p.CreationDate > (CAST('2024-10-01 12:34:56' AS timestamp) - INTERVAL '5 years')
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
        CROSS JOIN LATERAL (
            SELECT regexp_split_to_table(substring(p.Tags FROM 2 FOR (length(p.Tags)-2)), '><') AS TagName
        ) AS tags
        WHERE p.Id = qi.QuestionId AND tags.TagName = tt.TagName
    )
WHERE 
    tt.UserRank <= 3
GROUP BY 
    tt.TagName
ORDER BY 
    QuestionCount DESC, AvgQuestionVotes DESC
LIMIT 50;