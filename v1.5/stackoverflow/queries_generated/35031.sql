-- {"query": "35031.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "gpt-4.1", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 1986, "output_tokens": 727} 
WITH UserActivity AS (
    SELECT
        u.Id AS UserId,
        u.DisplayName,
        COUNT(DISTINCT p.Id) AS TotalPosts,
        COUNT(DISTINCT c.Id) AS TotalComments,
        COUNT(DISTINCT b.Id) AS TotalBadges,
        SUM(p.Score) AS PostScore,
        SUM(p.ViewCount) AS TotalViews,
        SUM(u.UpVotes) AS TotalUpVotes,
        SUM(u.DownVotes) AS TotalDownVotes
    FROM Users u
    LEFT JOIN Posts p ON p.OwnerUserId = u.Id
    LEFT JOIN Comments c ON c.UserId = u.Id
    LEFT JOIN Badges b ON b.UserId = u.Id
    GROUP BY u.Id, u.DisplayName
),
TopActiveUsers AS (
    SELECT
        UserId,
        DisplayName,
        TotalPosts,
        TotalComments,
        TotalBadges,
        PostScore,
        TotalViews,
        TotalUpVotes,
        TotalDownVotes,
        RANK() OVER (ORDER BY (COALESCE(TotalPosts,0) + COALESCE(TotalComments,0) + COALESCE(TotalBadges,0)) DESC) AS ActivityRank
    FROM UserActivity
    WHERE TotalPosts > 10 AND TotalComments > 20
    LIMIT 100
),
TagPopularity AS (
    SELECT
        unnest(string_to_array(substring(LOWER(p.Tags), 2, length(p.Tags)-2), '><')) AS TagName,
        COUNT(DISTINCT p.Id) AS QuestionsWithTag
    FROM Posts p
    WHERE p.PostTypeId = 1
    GROUP BY TagName
    ORDER BY COUNT(DISTINCT p.Id) DESC
    LIMIT 50
),
HotQuestions AS (
    SELECT
        p.Id,
        p.Title,
        p.Score,
        p.ViewCount,
        p.CreationDate,
        p.OwnerUserId,
        COALESCE(ARRAY_AGG(unnest(string_to_array(substring(LOWER(p.Tags), 2, length(p.Tags)-2), '><'))), '{}') AS Tags
    FROM Posts p
    WHERE p.PostTypeId = 1 AND p.ViewCount > 1000 AND p.Score > 5
    GROUP BY p.Id, p.Title, p.Score, p.ViewCount, p.CreationDate, p.OwnerUserId
    ORDER BY p.ViewCount DESC
    LIMIT 100
)
SELECT
    tau.UserId,
    tau.DisplayName,
    tau.TotalPosts,
    tau.TotalComments,
    tau.TotalBadges,
    tau.PostScore,
    tau.TotalViews,
    tau.TotalUpVotes,
    tau.TotalDownVotes,
    tau.ActivityRank,
    COUNT(DISTINCT hq.Id) AS HotQuestionsCount,
    ARRAY_AGG(DISTINCT tpop.TagName) FILTER (WHERE tpop.TagName IS NOT NULL) AS PopularTagsWorkedWith
FROM TopActiveUsers tau
LEFT JOIN HotQuestions hq ON hq.OwnerUserId = tau.UserId
LEFT JOIN LATERAL (
    SELECT TagName FROM TagPopularity t
    WHERE TagName = ANY(hq.Tags)
) tpop ON TRUE
GROUP BY
    tau.UserId, tau.DisplayName, tau.TotalPosts, tau.TotalComments, tau.TotalBadges,
    tau.PostScore, tau.TotalViews, tau.TotalUpVotes, tau.TotalDownVotes, tau.ActivityRank
ORDER BY
    tau.ActivityRank ASC,
    HotQuestionsCount DESC
LIMIT 20;