-- {"query": "15099.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "claude-3.5-haiku", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 233500, "output_tokens": 69018} 
WITH UserTagActivity AS (
    SELECT 
        u.Id AS UserId,
        u.DisplayName,
        t.TagName,
        COUNT(DISTINCT p.Id) AS PostCount,
        AVG(p.Score) AS AvgPostScore,
        DENSE_RANK() OVER (PARTITION BY t.TagName ORDER BY COUNT(DISTINCT p.Id) DESC) AS TagActivityRank,
        ROW_NUMBER() OVER (PARTITION BY u.Id ORDER BY COUNT(DISTINCT p.Id) DESC) AS UserTagPreference
    FROM 
        Users u
    JOIN 
        Posts p ON u.Id = p.OwnerUserId
    JOIN 
        (SELECT Id, TagName FROM Tags) t ON ARRAY[t.TagName] <@ string_to_array(substring(p.Tags, 2, length(p.Tags)-2), '><')
    WHERE 
        p.PostTypeId = 1 
        AND u.Reputation > 100
        AND p.CreationDate > TIMESTAMP '2010-01-01'
    GROUP BY 
        u.Id, u.DisplayName, t.TagName
),
TopContributors AS (
    SELECT 
        UserId,
        DisplayName,
        SUM(PostCount) AS TotalPosts,
        COUNT(DISTINCT TagName) AS UniqueTagsContributed,
        PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY AvgPostScore) AS MedianTagScore
    FROM 
        UserTagActivity
    WHERE 
        TagActivityRank <= 3
    GROUP BY 
        UserId, DisplayName
    HAVING 
        SUM(PostCount) > 10
)
SELECT 
    tc.UserId,
    tc.DisplayName,
    tc.TotalPosts,
    tc.UniqueTagsContributed,
    tc.MedianTagScore,
    (SELECT COUNT(*) FROM Votes v WHERE v.UserId = tc.UserId AND v.VoteTypeId = 2) AS UpvotesGiven,
    COALESCE(
        (SELECT AVG(EXTRACT(EPOCH FROM (ph.CreationDate - p.CreationDate))/86400) 
         FROM PostHistory ph 
         JOIN Posts p ON ph.PostId = p.Id 
         WHERE p.OwnerUserId = tc.UserId 
         AND ph.PostHistoryTypeId = 5), 
        0
    ) AS AvgDaysBetweenEdits,
    CASE 
        WHEN tc.TotalPosts > 50 THEN 'Super Contributor'
        WHEN tc.TotalPosts > 20 THEN 'Active Contributor'
        ELSE 'Emerging Contributor'
    END AS ContributorTier
FROM 
    TopContributors tc
LEFT JOIN 
    Badges b ON tc.UserId = b.UserId AND b.Class = 1
WHERE 
    tc.UniqueTagsContributed > 3
    AND (b.Id IS NOT NULL OR tc.TotalPosts > 30)
ORDER BY 
    tc.TotalPosts DESC, tc.MedianTagScore DESC
LIMIT 100;