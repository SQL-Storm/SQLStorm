
WITH TagCounts AS (
    SELECT 
        VALUE AS Tag,
        COUNT(*) AS PostCount
    FROM 
        Posts
    CROSS APPLY STRING_SPLIT(SUBSTRING(Tags, 2, LEN(Tags) - 2), '><')
    WHERE 
        PostTypeId = 1 
    GROUP BY 
        VALUE
),
UserActivity AS (
    SELECT 
        u.Id AS UserId,
        u.DisplayName,
        COUNT(DISTINCT p.Id) AS QuestionsAsked,
        SUM(ISNULL(p.ViewCount, 0)) AS TotalViews,
        SUM(ISNULL(p.Score, 0)) AS TotalScore
    FROM 
        Users u
    LEFT JOIN 
        Posts p ON u.Id = p.OwnerUserId
    WHERE 
        p.PostTypeId = 1 
    GROUP BY 
        u.Id, u.DisplayName
),
TopTags AS (
    SELECT 
        Tag,
        PostCount,
        ROW_NUMBER() OVER (ORDER BY PostCount DESC) AS Rank
    FROM 
        TagCounts
),
ActiveUsers AS (
    SELECT 
        UserId,
        DisplayName,
        QuestionsAsked,
        TotalViews,
        TotalScore,
        ROW_NUMBER() OVER (ORDER BY QuestionsAsked DESC) AS UserRank
    FROM 
        UserActivity
)

SELECT 
    ut.UserId,
    ut.DisplayName,
    tt.Tag,
    tt.PostCount,
    ut.QuestionsAsked,
    ut.TotalViews,
    ut.TotalScore
FROM 
    ActiveUsers ut
JOIN 
    (SELECT 
        tt.Tag,
        tt.PostCount,
        tt.Rank
     FROM 
        TopTags tt
     WHERE 
        tt.Rank <= 5) AS tt ON ut.UserRank <= 10 
ORDER BY 
    tt.PostCount DESC, ut.TotalViews DESC, ut.TotalScore DESC;
