-- {"query": "15004.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p1", "model": "claude-3.5-haiku", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2335, "output_tokens": 757}
WITH UserTagStats AS (
    SELECT 
        u.Id AS UserId, 
        u.DisplayName,
        t.TagName,
        COUNT(p.Id) AS PostCount,
        AVG(p.Score) AS AvgTagScore,
        ROW_NUMBER() OVER (PARTITION BY u.Id ORDER BY COUNT(p.Id) DESC) AS TagRank,
        DENSE_RANK() OVER (ORDER BY COUNT(p.Id) DESC) AS GlobalTagRank
    FROM Users u
    JOIN Posts p ON u.Id = p.OwnerUserId
    JOIN (SELECT unnest(string_to_array(substring(Tags, 2, length(Tags)-2), '><')) AS TagName, Id FROM Posts) t ON t.Id = p.Id
    WHERE u.Reputation > 1000 AND p.PostTypeId = 1
    GROUP BY u.Id, u.DisplayName, t.TagName
),
TopContributorAnalysis AS (
    SELECT 
        uts.UserId,
        uts.DisplayName,
        STRING_AGG(uts.TagName, ', ' ORDER BY uts.PostCount DESC) AS TopTags,
        SUM(uts.PostCount) AS TotalTagPosts,
        MAX(uts.AvgTagScore) AS HighestTagScore,
        COUNT(DISTINCT uts.TagName) AS UniqueTagsContributed,
        PERCENTILE_CONT(0.75) WITHIN GROUP (ORDER BY uts.PostCount) AS PostCountThreshold
    FROM UserTagStats uts
    WHERE uts.TagRank <= 3
    GROUP BY uts.UserId, uts.DisplayName
)
SELECT 
    tca.UserId,
    tca.DisplayName,
    tca.TopTags,
    tca.TotalTagPosts,
    tca.HighestTagScore,
    tca.UniqueTagsContributed,
    COALESCE(b.Gold, 0) AS GoldBadgeCount,
    CASE 
        WHEN v.UpVotes > v.DownVotes * 3 THEN 'High Quality Contributor'
        ELSE 'Needs Improvement'
    END AS ContributorStatus,
    ROUND(
        tca.TotalTagPosts * 
        (CASE WHEN tca.HighestTagScore > 10 THEN 1.5 ELSE 1.0 END) * 
        (1 + LEAST(tca.UniqueTagsContributed * 0.1, 0.5)),
        2
    ) AS ContributionScore
FROM TopContributorAnalysis tca
LEFT JOIN (
    SELECT UserId, COUNT(*) AS Gold 
    FROM Badges 
    WHERE Class = 1 
    GROUP BY UserId
) b ON tca.UserId = b.UserId
LEFT JOIN Users v ON tca.UserId = v.Id
WHERE tca.TotalTagPosts > tca.PostCountThreshold
ORDER BY ContributionScore DESC
LIMIT 100;
