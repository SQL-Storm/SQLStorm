WITH RankedQuestions AS (
    SELECT 
        p.Id AS QuestionId,
        p.Title,
        p.CreationDate,
        p.ViewCount,
        u.DisplayName AS OwnerDisplayName,
        COUNT(a.Id) AS AnswerCount,
        COUNT(c.Id) AS CommentCount,
        RANK() OVER (ORDER BY p.ViewCount DESC) AS ViewRank
    FROM 
        Posts p
    LEFT JOIN 
        Posts a ON a.ParentId = p.Id AND a.PostTypeId = 2
    LEFT JOIN 
        Comments c ON c.PostId = p.Id
    LEFT JOIN 
        Users u ON u.Id = p.OwnerUserId
    WHERE 
        p.PostTypeId = 1
    GROUP BY 
        p.Id, u.DisplayName
), 
HighEngagementQuestions AS (
    SELECT 
        rq.QuestionId,
        rq.Title,
        rq.CreationDate,
        rq.ViewCount,
        rq.OwnerDisplayName,
        rq.AnswerCount,
        rq.CommentCount
    FROM 
        RankedQuestions rq
    WHERE 
        rq.ViewCount > 1000 AND rq.AnswerCount > 5
), 
TopTags AS (
    SELECT 
        unnest(string_to_array(substring(p.Tags, 2, length(p.Tags) - 2), '><')) AS TagName,
        COUNT(*) AS TagCount
    FROM 
        Posts p
    WHERE 
        p.PostTypeId = 1
    GROUP BY 
        TagName
    ORDER BY 
        TagCount DESC
    LIMIT 5
)
SELECT 
    hq.Title AS QuestionTitle,
    hq.OwnerDisplayName,
    hq.ViewCount,
    hq.AnswerCount,
    hq.CommentCount,
    tt.TagName AS TopTag,
    tt.TagCount AS TopTagCount
FROM 
    HighEngagementQuestions hq
JOIN 
    TopTags tt ON hq.QuestionId IN (
        SELECT 
            p.Id 
        FROM 
            Posts p 
        WHERE 
            p.PostTypeId = 1 
            AND p.Tags LIKE '%' || tt.TagName || '%'
    )
ORDER BY 
    hq.ViewCount DESC;
