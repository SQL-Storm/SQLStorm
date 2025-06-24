WITH TagStats AS (
    SELECT 
        t.TagName,
        COUNT(DISTINCT p.Id) AS PostCount,
        SUM(CASE WHEN p.PostTypeId = 1 THEN 1 ELSE 0 END) AS QuestionCount,
        SUM(CASE WHEN p.PostTypeId = 2 THEN 1 ELSE 0 END) AS AnswerCount,
        SUM(p.ViewCount) AS TotalViews,
        AVG(u.Reputation) AS AvgUserReputation
    FROM 
        Tags t
    JOIN 
        Posts p ON p.Tags LIKE '%' || t.TagName || '%'
    JOIN 
        Users u ON p.OwnerUserId = u.Id
    GROUP BY 
        t.TagName
),
TopTags AS (
    SELECT 
        TagName,
        PostCount,
        QuestionCount,
        AnswerCount,
        TotalViews,
        AvgUserReputation,
        RANK() OVER (ORDER BY TotalViews DESC) AS ViewRank
    FROM 
        TagStats
)
SELECT 
    t.TagName,
    t.PostCount,
    t.QuestionCount,
    t.AnswerCount,
    t.TotalViews,
    t.AvgUserReputation
FROM 
    TopTags t
WHERE 
    t.ViewRank <= 10
ORDER BY 
    t.ViewRank;

-- Retrieve detailed post history for the top tags
SELECT 
    p.Title,
    p.CreationDate,
    ph.PostHistoryTypeId,
    ph.CreationDate AS HistoryDate,
    ph.UserDisplayName,
    ph.Comment,
    ph.Text
FROM 
    Posts p
JOIN 
    PostHistory ph ON p.Id = ph.PostId
JOIN 
    TopTags tt ON p.Tags LIKE '%' || tt.TagName || '%'
WHERE 
    tt.ViewRank <= 10
ORDER BY 
    p.Title, ph.CreationDate DESC;
