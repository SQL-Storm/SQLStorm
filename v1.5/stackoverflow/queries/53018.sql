-- {"query": "53018.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "grok-4", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2646, "output_tokens": 778} 
WITH RECURSIVE UserActivity AS (
    SELECT 
        u.Id AS UserId,
        u.DisplayName,
        u.Reputation,
        COUNT(DISTINCT p.Id) FILTER (WHERE p.PostTypeId = 1) AS QuestionCount,
        COUNT(DISTINCT p.Id) FILTER (WHERE p.PostTypeId = 2) AS AnswerCount,
        SUM(p.Score) AS TotalScore,
        SUM(p.ViewCount) AS TotalViews,
        COUNT(DISTINCT b.Id) AS BadgeCount,
        COUNT(DISTINCT v.Id) FILTER (WHERE v.VoteTypeId = 2) AS UpvoteCount
    FROM Users u
    LEFT JOIN Posts p ON u.Id = p.OwnerUserId
    LEFT JOIN Badges b ON u.Id = b.UserId
    LEFT JOIN Votes v ON p.Id = v.PostId
    WHERE u.CreationDate >= '2010-01-01' AND u.Reputation > 1000
    GROUP BY u.Id, u.DisplayName, u.Reputation
    HAVING COUNT(DISTINCT p.Id) > 50
),
TagUnnest AS (
    SELECT 
        p.Id AS PostId,
        p.PostTypeId,
        p.OwnerUserId,
        p.Score,
        p.ViewCount,
        p.CreationDate,
        unnest(string_to_array(substring(p.Tags, 2, length(p.Tags) - 2), '><')) AS TagName
    FROM Posts p
    WHERE p.Tags IS NOT NULL AND p.CreationDate >= cast('2024-10-01' as date) - INTERVAL '5 years'
),
TagStats AS (
    SELECT 
        tu.TagName,
        COUNT(DISTINCT tu.PostId) FILTER (WHERE tu.PostTypeId = 1) AS QuestionCount,
        AVG(tu.Score) FILTER (WHERE tu.PostTypeId = 2) AS AvgAnswerScore,
        SUM(tu.ViewCount) FILTER (WHERE tu.PostTypeId = 1) AS TotalQuestionViews,
        COUNT(DISTINCT tu.OwnerUserId) AS UniqueContributors,
        MAX(ua.DisplayName) AS TopContributor,
        ROW_NUMBER() OVER (ORDER BY COUNT(DISTINCT tu.PostId) FILTER (WHERE tu.PostTypeId = 1) DESC) AS Rank
    FROM TagUnnest tu
    JOIN UserActivity ua ON tu.OwnerUserId = ua.UserId
    LEFT JOIN Comments c ON tu.PostId = c.PostId
    LEFT JOIN PostHistory ph ON tu.PostId = ph.PostId AND ph.PostHistoryTypeId IN (4,5,6)
    LEFT JOIN PostLinks pl ON tu.PostId = pl.PostId OR tu.PostId = pl.RelatedPostId
    LEFT JOIN Tags t ON tu.TagName = t.TagName
    WHERE c.Score > 0 OR ph.Id IS NOT NULL OR pl.Id IS NOT NULL OR t.Count > 100
    GROUP BY tu.TagName
    HAVING COUNT(DISTINCT tu.PostId) > 1000 AND AVG(tu.Score) > 5
)
SELECT 
    ts.TagName,
    ts.QuestionCount,
    ts.AvgAnswerScore,
    ts.TotalQuestionViews,
    ts.UniqueContributors,
    ts.TopContributor,
    (SELECT COUNT(*) FROM PostHistory ph WHERE ph.PostId IN (SELECT PostId FROM TagUnnest WHERE TagName = ts.TagName)) AS EditCount,
    (SELECT SUM(BountyAmount) FROM Votes v JOIN TagUnnest tu ON v.PostId = tu.PostId WHERE tu.TagName = ts.TagName AND v.VoteTypeId IN (8,9)) AS TotalBounties
FROM TagStats ts
WHERE ts.Rank <= 50
ORDER BY ts.QuestionCount DESC, ts.AvgAnswerScore DESC;