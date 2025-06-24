
WITH TagStats AS (
    SELECT 
        t.TagName,
        COUNT(DISTINCT p.Id) AS PostCount,
        SUM(p.ViewCount) AS TotalViews,
        AVG(p.Score) AS AverageScore
    FROM 
        Tags t
    LEFT JOIN 
        Posts p ON p.Tags LIKE CONCAT('%', t.TagName, '%')
    GROUP BY 
        t.TagName
),
UserStats AS (
    SELECT 
        u.DisplayName,
        SUM(CASE WHEN p.PostTypeId = 1 THEN 1 ELSE 0 END) AS QuestionCount,
        SUM(CASE WHEN p.PostTypeId = 2 THEN 1 ELSE 0 END) AS AnswerCount,
        SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS UpVotes,
        SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS DownVotes
    FROM 
        Users u
    LEFT JOIN 
        Posts p ON u.Id = p.OwnerUserId
    LEFT JOIN 
        Votes v ON p.Id = v.PostId
    GROUP BY 
        u.DisplayName
),
TopTags AS (
    SELECT 
        TagName,
        TotalViews,
        AverageScore,
        @row_number := @row_number + 1 AS Rank
    FROM 
        TagStats, (SELECT @row_number := 0) r
    ORDER BY 
        TotalViews DESC
),
TopContributors AS (
    SELECT 
        DisplayName,
        QuestionCount,
        AnswerCount,
        UpVotes,
        DownVotes,
        @contributor_rank := @contributor_rank + 1 AS ContributorRank
    FROM 
        UserStats, (SELECT @contributor_rank := 0) r
    ORDER BY 
        UpVotes DESC
)
SELECT 
    t.TagName,
    t.TotalViews,
    t.AverageScore,
    u.DisplayName AS TopContributor,
    u.QuestionCount,
    u.AnswerCount,
    u.UpVotes,
    u.DownVotes
FROM 
    TopTags t
JOIN 
    TopContributors u ON u.QuestionCount > 0 
WHERE 
    t.Rank <= 10 AND u.ContributorRank <= 5
ORDER BY 
    t.TotalViews DESC, u.UpVotes DESC;
