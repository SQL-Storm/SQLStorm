-- {"query": "53064.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "grok-4", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2646, "output_tokens": 955} 

WITH UserActivity AS (
    SELECT 
        u.Id AS UserId,
        u.Reputation,
        COUNT(DISTINCT p.Id) AS PostCount,
        SUM(p.Score) AS TotalScore,
        SUM(p.ViewCount) AS TotalViews,
        COUNT(DISTINCT c.Id) AS CommentCount,
        COUNT(DISTINCT v.Id) AS VoteCount,
        COUNT(DISTINCT b.Id) AS BadgeCount,
        MAX(p.CreationDate) AS LastPostDate
    FROM Users u
    LEFT JOIN Posts p ON u.Id = p.OwnerUserId
    LEFT JOIN Comments c ON u.Id = c.UserId AND p.Id = c.PostId
    LEFT JOIN Votes v ON p.Id = v.PostId AND v.VoteTypeId IN (2, 3)  -- Upvotes and Downvotes
    LEFT JOIN Badges b ON u.Id = b.UserId AND b.Class = 1  -- Gold badges
    WHERE p.PostTypeId IN (1, 2)  -- Questions and Answers
    GROUP BY u.Id, u.Reputation
    HAVING COUNT(DISTINCT p.Id) > 10
),
TaggedPosts AS (
    SELECT 
        p.Id AS PostId,
        p.OwnerUserId,
        p.Score,
        p.ViewCount,
        STRING_TO_ARRAY(SUBSTRING(p.Tags, 2, LENGTH(p.Tags)-2), '><') AS TagArray
    FROM Posts p
    WHERE p.PostTypeId = 1  -- Questions
    AND p.Tags IS NOT NULL
),
ExplodedTags AS (
    SELECT 
        tp.PostId,
        tp.OwnerUserId,
        tp.Score,
        tp.ViewCount,
        unnest(tp.TagArray) AS TagName
    FROM TaggedPosts tp
),
TagStats AS (
    SELECT 
        et.TagName,
        COUNT(DISTINCT et.PostId) AS QuestionCount,
        SUM(et.Score) AS TotalTagScore,
        SUM(et.ViewCount) AS TotalTagViews,
        AVG(et.Score) AS AvgScore
    FROM ExplodedTags et
    INNER JOIN Tags t ON et.TagName = t.TagName
    WHERE t.Count > 1000
    GROUP BY et.TagName
),
UserTagActivity AS (
    SELECT 
        ua.UserId,
        et.TagName,
        COUNT(DISTINCT et.PostId) AS UserTagPostCount,
        SUM(et.Score) AS UserTagScore,
        ROW_NUMBER() OVER (PARTITION BY et.TagName ORDER BY SUM(et.Score) DESC) AS RankInTag
    FROM UserActivity ua
    INNER JOIN ExplodedTags et ON ua.UserId = et.OwnerUserId
    GROUP BY ua.UserId, et.TagName
    HAVING COUNT(DISTINCT et.PostId) >= 5
)
SELECT 
    u.DisplayName,
    ua.Reputation,
    ua.PostCount,
    ua.TotalScore,
    ua.TotalViews,
    ua.CommentCount,
    ua.VoteCount,
    ua.BadgeCount,
    ts.TagName,
    ts.QuestionCount,
    ts.TotalTagScore,
    ts.TotalTagViews,
    ts.AvgScore,
    uta.UserTagPostCount,
    uta.UserTagScore,
    uta.RankInTag,
    ph.PostHistoryTypeId,
    COUNT(DISTINCT ph.Id) AS EditCount,
    MAX(ph.CreationDate) AS LastEditDate
FROM UserActivity ua
INNER JOIN Users u ON ua.UserId = u.Id
INNER JOIN UserTagActivity uta ON ua.UserId = uta.UserId
INNER JOIN TagStats ts ON uta.TagName = ts.TagName
LEFT JOIN PostHistory ph ON ua.UserId = ph.UserId AND ph.PostHistoryTypeId IN (4, 5, 6)  -- Edits
LEFT JOIN PostLinks pl ON ph.PostId = pl.PostId AND pl.LinkTypeId = 3  -- Duplicates
WHERE uta.RankInTag <= 10
AND ua.LastPostDate >= '2020-01-01'
GROUP BY 
    u.DisplayName, ua.Reputation, ua.PostCount, ua.TotalScore, ua.TotalViews, 
    ua.CommentCount, ua.VoteCount, ua.BadgeCount, ts.TagName, ts.QuestionCount, 
    ts.TotalTagScore, ts.TotalTagViews, ts.AvgScore, uta.UserTagPostCount, 
    uta.UserTagScore, uta.RankInTag, ph.PostHistoryTypeId
ORDER BY ua.Reputation DESC, uta.RankInTag ASC
LIMIT 1000;
