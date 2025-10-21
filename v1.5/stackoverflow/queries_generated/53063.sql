-- {"query": "53063.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "grok-4", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2646, "output_tokens": 984} 

WITH RECURSIVE PostHierarchy AS (
    SELECT 
        Id, 
        ParentId, 
        PostTypeId, 
        OwnerUserId, 
        Score, 
        CreationDate, 
        1 AS Depth
    FROM Posts
    WHERE PostTypeId = 1  -- Questions
    UNION ALL
    SELECT 
        p.Id, 
        p.ParentId, 
        p.PostTypeId, 
        p.OwnerUserId, 
        p.Score, 
        p.CreationDate, 
        ph.Depth + 1
    FROM Posts p
    INNER JOIN PostHierarchy ph ON p.ParentId = ph.Id
    WHERE p.PostTypeId = 2  -- Answers
),
TagExploded AS (
    SELECT 
        p.Id AS PostId, 
        unnest(string_to_array(substring(p.Tags, 2, length(p.Tags)-2), '><')) AS TagName
    FROM Posts p
    WHERE p.PostTypeId = 1
),
UserActivity AS (
    SELECT 
        u.Id AS UserId, 
        u.Reputation, 
        COUNT(DISTINCT p.Id) AS PostCount, 
        SUM(p.Score) AS TotalScore, 
        AVG(p.Score) AS AvgScore, 
        COUNT(DISTINCT c.Id) AS CommentCount, 
        COUNT(DISTINCT v.Id) AS VoteCount, 
        COUNT(DISTINCT b.Id) AS BadgeCount,
        COUNT(DISTINCT ph.Id) AS HistoryCount,
        COUNT(DISTINCT pl.Id) AS LinkCount
    FROM Users u
    LEFT JOIN Posts p ON u.Id = p.OwnerUserId
    LEFT JOIN Comments c ON u.Id = c.UserId
    LEFT JOIN Votes v ON u.Id = v.UserId AND v.VoteTypeId IN (2, 3)  -- Upvotes and Downvotes
    LEFT JOIN Badges b ON u.Id = b.UserId AND b.Class = 1  -- Gold badges
    LEFT JOIN PostHistory ph ON u.Id = ph.UserId AND ph.PostHistoryTypeId IN (4, 5, 6)  -- Edits
    LEFT JOIN PostLinks pl ON p.Id = pl.PostId AND pl.LinkTypeId = 3  -- Duplicates
    GROUP BY u.Id, u.Reputation
    HAVING COUNT(DISTINCT p.Id) > 100
),
TopTags AS (
    SELECT 
        t.TagName, 
        COUNT(DISTINCT te.PostId) AS QuestionCount,
        SUM(CASE WHEN p.AcceptedAnswerId IS NOT NULL THEN 1 ELSE 0 END) AS AcceptedAnswers,
        AVG(p.ViewCount) AS AvgViews
    FROM Tags t
    INNER JOIN TagExploded te ON t.TagName = te.TagName
    INNER JOIN Posts p ON te.PostId = p.Id
    INNER JOIN PostHierarchy ph ON p.Id = ph.Id
    WHERE ph.Depth <= 5
    GROUP BY t.TagName
    ORDER BY QuestionCount DESC
    LIMIT 50
),
CombinedMetrics AS (
    SELECT 
        tt.TagName, 
        ua.UserId, 
        ua.Reputation, 
        ua.PostCount, 
        ua.TotalScore, 
        ua.AvgScore, 
        ua.CommentCount, 
        ua.VoteCount, 
        ua.BadgeCount, 
        ua.HistoryCount, 
        ua.LinkCount, 
        tt.QuestionCount, 
        tt.AcceptedAnswers, 
        tt.AvgViews,
        ROW_NUMBER() OVER (PARTITION BY tt.TagName ORDER BY ua.TotalScore DESC) AS Rank
    FROM TopTags tt
    CROSS JOIN UserActivity ua
    INNER JOIN Posts p ON ua.UserId = p.OwnerUserId
    INNER JOIN TagExploded te ON p.Id = te.PostId AND te.TagName = tt.TagName
    WHERE p.CreationDate >= '2020-01-01' AND p.Score > 0
    GROUP BY tt.TagName, ua.UserId, ua.Reputation, ua.PostCount, ua.TotalScore, ua.AvgScore, ua.CommentCount, ua.VoteCount, ua.BadgeCount, ua.HistoryCount, ua.LinkCount, tt.QuestionCount, tt.AcceptedAnswers, tt.AvgViews
)
SELECT 
    TagName, 
    UserId, 
    Reputation, 
    PostCount, 
    TotalScore, 
    AvgScore, 
    CommentCount, 
    VoteCount, 
    BadgeCount, 
    HistoryCount, 
    LinkCount, 
    QuestionCount, 
    AcceptedAnswers, 
    AvgViews
FROM CombinedMetrics
WHERE Rank <= 3
ORDER BY QuestionCount DESC, Rank ASC;
