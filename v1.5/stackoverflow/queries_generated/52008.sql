-- {"query": "52008.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "grok-code-fast", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2165, "output_tokens": 701} 
WITH UserStats AS (
    SELECT 
        u.Id,
        u.DisplayName,
        COALESCE(SUM(p.Score), 0) AS TotalPostScore,
        COUNT(DISTINCT p.Id) AS PostCount,
        COALESCE(COUNT(c.Id), 0) AS CommentCount,
        COALESCE(COUNT(v.Id), 0) AS UpvoteCountReceived,
        COALESCE(COUNT(b.Id), 0) AS BadgeCount,
        AVG(p.Score) AS AvgPostScore,
        ROW_NUMBER() OVER (ORDER BY COALESCE(SUM(p.Score), 0) + COALESCE(COUNT(c.Id), 0) * 0.1 + COALESCE(COUNT(v.Id), 0) * 0.5 + COALESCE(COUNT(b.Id), 0) * 10 DESC) AS Rank
    FROM Users u
    LEFT JOIN Posts p ON u.Id = p.OwnerUserId AND p.PostTypeId IN (1, 2) AND p.CreationDate >= '2008-01-01'
    LEFT JOIN Comments c ON u.Id = c.UserId
    LEFT JOIN Votes v ON p.Id = v.PostId AND v.VoteTypeId = 2
    LEFT JOIN Badges b ON u.Id = b.UserId
    GROUP BY u.Id, u.DisplayName
    HAVING COUNT(DISTINCT p.Id) > 0 OR COALESCE(COUNT(c.Id), 0) > 0
),
TagPostStats AS (
    SELECT 
        p.Id AS PostId,
        unnest(string_to_array(substring(p.Tags, 2, length(p.Tags)-2), '><')) AS TagName,
        p.Score,
        p.ViewCount,
        p.AnswerCount
    FROM Posts p
    WHERE p.PostTypeId = 1 AND p.Tags IS NOT NULL
),
UserTagContribution AS (
    SELECT 
        u.Id,
        t.TagName,
        COUNT(tp.PostId) AS QuestionCount,
        SUM(tp.Score) AS TotalScore,
        AVG(tp.Score) AS AvgScore,
        SUM(tp.ViewCount) AS TotalViews
    FROM UserStats u
    JOIN Posts p ON u.Id = p.OwnerUserId AND p.PostTypeId = 1
    JOIN TagPostStats tp ON p.Id = tp.PostId
    JOIN Tags t ON tp.TagName = t.TagName
    GROUP BY u.Id, t.TagName
),
FinalRanking AS (
    SELECT 
        us.Id,
        us.DisplayName,
        us.TotalPostScore,
        us.PostCount,
        us.CommentCount,
        us.UpvoteCountReceived,
        us.BadgeCount,
        us.AvgPostScore,
        us.Rank,
        ARRAY_AGG(CONCAT(utc.TagName, ': ', utc.TotalScore)) AS TopTagsContributions,
        (us.TotalPostScore + us.CommentCount * 0.1 + us.UpvoteCountReceived * 0.5 + us.BadgeCount * 10) AS CompositeScore
    FROM UserStats us
    LEFT JOIN UserTagContribution utc ON us.Id = utc.Id
    GROUP BY us.Id, us.DisplayName, us.TotalPostScore, us.PostCount, us.CommentCount, us.UpvoteCountReceived, us.BadgeCount, us.AvgPostScore, us.Rank
)
SELECT * FROM FinalRanking WHERE Rank <= 100 ORDER BY CompositeScore DESC;