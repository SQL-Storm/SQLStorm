-- {"query": "57043.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "pixtral-large", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2291, "output_tokens": 1018} 
WITH UserActivity AS (
    SELECT
        u.Id AS UserId,
        u.Reputation,
        u.CreationDate AS UserCreationDate,
        COUNT(p.Id) AS TotalPosts,
        COALESCE(SUM(CASE WHEN p.PostTypeId = 1 THEN 1 ELSE 0 END), 0) AS TotalQuestions,
        COALESCE(SUM(CASE WHEN p.PostTypeId = 2 THEN 1 ELSE 0 END), 0) AS TotalAnswers,
        COALESCE(SUM(p.Score), 0) AS TotalPostScore,
         CASE
            WHEN EXTRACT(YEAR FROM AGE(cast('2024-10-01 12:34:56' as timestamp), u.CreationDate)) >= 5 THEN 'Veteran'
            WHEN EXTRACT(YEAR FROM AGE(cast('2024-10-01 12:34:56' as timestamp), u.CreationDate)) >= 2 THEN 'Experienced'
            ELSE 'New'
        END AS UserLevel
    FROM
        Users u
    LEFT JOIN
        Posts p ON u.Id = p.OwnerUserId
    GROUP BY
        u.Id, u.Reputation, u.CreationDate
), HighActivityUsers AS (
    SELECT
        UserId,
        Reputation,
        UserCreationDate,
        TotalPosts,
        TotalQuestions,
        TotalAnswers,
        TotalPostScore,
        UserLevel
    FROM
        UserActivity
    WHERE
        TotalPosts > 100
), MostActiveTags AS (
    SELECT
        t.TagName,
        t.Count,
        t.WikiPostId,
        EXTRACT(YEAR FROM p.CreationDate) AS Year,
        COUNT(p.Id) AS PostCount,
        SUM(p.Score) AS TotalScore
    FROM
        Tags t
    JOIN
        Posts p ON t.WikiPostId = p.Id
    GROUP BY
        t.TagName, t.Count, t.WikiPostId, EXTRACT(YEAR FROM p.CreationDate)
    ORDER BY
        PostCount DESC, TotalScore DESC
    LIMIT 50
), TagActivity AS (
    SELECT
        t.TagName,
        COUNT(p.Id) AS TotalPosts,
        COUNT(DISTINCT p.OwnerUserId) AS UniqueAuthors,
        SUM(p.Score) AS TotalScore,
        SUM(p.ViewCount) AS TotalViews,
         (COUNT(DISTINCT CASE WHEN v.VoteTypeId = 2 THEN v.PostId ELSE NULL END) * 1.0 / NULLIF(COUNT(p.Id), 0)) * 100 AS UpvotePercentage,
        (COUNT(DISTINCT CASE WHEN v.VoteTypeId = 3 THEN v.PostId ELSE NULL END) * 1.0 / NULLIF(COUNT(p.Id), 0)) * 100 AS DownvotePercentage
    FROM
        Tags t
    JOIN
        Posts p ON p.Tags LIKE CONCAT('%<', t.TagName, '>%')
    LEFT JOIN
        Votes v ON p.Id = v.PostId
    GROUP BY
        t.TagName
)
SELECT
    ha.UserId,
    ha.Reputation,
    ha.UserCreationDate,
    ha.TotalPosts,
    ha.TotalQuestions,
    ha.TotalAnswers,
    ha.TotalPostScore,
    ha.UserLevel,
    mat.TagName,
    mat.Count,
    mat.Year,
    mat.PostCount,
    mat.TotalScore,
    ta.TotalPosts AS TagTotalPosts,
    ta.UniqueAuthors,
    ta.TotalScore AS TagTotalScore,
    ta.TotalViews,
    ta.UpvotePercentage,
    ta.DownvotePercentage
FROM
    HighActivityUsers ha
CROSS JOIN
    MostActiveTags mat
LEFT JOIN
    TagActivity ta ON mat.TagName = ta.TagName
ORDER BY
    ha.TotalPosts DESC, mat.PostCount DESC, ta.TotalScore DESC;