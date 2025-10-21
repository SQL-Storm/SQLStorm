-- {"query": "52021.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "grok-code-fast", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2165, "output_tokens": 920} 
WITH user_activity AS (
    SELECT 
        u.Id AS UserId,
        u.DisplayName,
        u.Reputation,
        COUNT(DISTINCT p.Id) AS QuestionCount,
        COUNT(DISTINCT CASE WHEN p.PostTypeId = 2 THEN p.Id END) AS AnswerCount,
        SUM(p.Score) AS TotalScore,
        SUM(p.ViewCount) AS TotalViews,
        COUNT(DISTINCT c.Id) AS CommentCount,
        COUNT(DISTINCT v.Id) FILTER (WHERE v.VoteTypeId = 2) AS UpvotesReceived,
        COUNT(DISTINCT v.Id) FILTER (WHERE v.VoteTypeId = 3) AS DownvotesReceived,
        COUNT(DISTINCT b.Id) AS BadgeCount,
        AVG(p.Score) AS AvgScore,
        MAX(p.CreationDate) AS LastPostDate
    FROM Users u
    LEFT JOIN Posts p ON u.Id = p.OwnerUserId
    LEFT JOIN Comments c ON u.Id = c.UserId
    LEFT JOIN Votes v ON p.Id = v.PostId AND v.VoteTypeId IN (2, 3)
    LEFT JOIN Badges b ON u.Id = b.UserId
    GROUP BY u.Id, u.DisplayName, u.Reputation
),
tag_popularity AS (
    SELECT 
        tag,
        COUNT(*) AS UsageCount,
        SUM(p.Score) AS TotalScore,
        AVG(p.Score) AS AvgScore
    FROM (
        SELECT p.Id, p.Score, unnest(string_to_array(substring(p.Tags, 2, length(p.Tags)-2), '><')) AS tag
        FROM Posts p
        WHERE p.PostTypeId = 1 AND p.Tags IS NOT NULL
    ) sub
    JOIN Posts p ON sub.Id = p.Id
    GROUP BY tag
),
top_questions AS (
    SELECT 
        p.Id,
        p.Title,
        p.Score,
        p.ViewCount,
        p.AnswerCount,
        u.DisplayName AS OwnerName,
        ROW_NUMBER() OVER (ORDER BY p.Score DESC, p.ViewCount DESC) AS Rank
    FROM Posts p
    JOIN Users u ON p.OwnerUserId = u.Id
    WHERE p.PostTypeId = 1
    LIMIT 100
),
vote_history AS (
    SELECT 
        p.Id AS PostId,
        COUNT(CASE WHEN v.VoteTypeId = 2 THEN 1 END) AS Upvotes,
        COUNT(CASE WHEN v.VoteTypeId = 3 THEN 1 END) AS Downvotes,
        COUNT(CASE WHEN v.VoteTypeId = 8 THEN 1 END) AS Bounties,
        SUM(CASE WHEN v.VoteTypeId = 8 THEN v.BountyAmount END) AS TotalBounty
    FROM Posts p
    LEFT JOIN Votes v ON p.Id = v.PostId
    WHERE p.PostTypeId = 1
    GROUP BY p.Id
),
post_links AS (
    SELECT 
        pl.PostId,
        COUNT(*) AS LinkCount
    FROM PostLinks pl
    GROUP BY pl.PostId
)
SELECT 
    ua.UserId,
    ua.DisplayName,
    ua.Reputation,
    ua.QuestionCount,
    ua.AnswerCount,
    ua.TotalScore,
    ua.TotalViews,
    ua.CommentCount,
    ua.UpvotesReceived,
    ua.DownvotesReceived,
    ua.BadgeCount,
    ua.AvgScore,
    ua.LastPostDate,
    tq.Rank AS TopQuestionRank,
    vh.Upvotes,
    vh.Downvotes,
    vh.Bounties,
    vh.TotalBounty,
    pl.LinkCount,
    tp.UsageCount AS PopularTagUsage,
    tp.TotalScore AS PopularTagScore,
    tp.AvgScore AS PopularTagAvgScore
FROM user_activity ua
LEFT JOIN top_questions tq ON ua.UserId = (SELECT OwnerUserId FROM top_questions WHERE Rank = 1 LIMIT 1) -- Just to link somehow, actually irrelevant but for complexity
LEFT JOIN vote_history vh ON ua.UserId = (SELECT OwnerUserId FROM Posts WHERE Id = vh.PostId LIMIT 1)
LEFT JOIN post_links pl ON ua.UserId = (SELECT OwnerUserId FROM Posts WHERE Id = pl.PostId LIMIT 1)
CROSS JOIN (
    SELECT * FROM tag_popularity ORDER BY UsageCount DESC LIMIT 1
) tp
ORDER BY ua.Reputation DESC, ua.TotalScore DESC
LIMIT 50;