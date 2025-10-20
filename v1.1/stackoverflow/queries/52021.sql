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
        COUNT(DISTINCT CASE WHEN v.VoteTypeId = 2 THEN v.Id END) AS UpvotesReceived,
        COUNT(DISTINCT CASE WHEN v.VoteTypeId = 3 THEN v.Id END) AS DownvotesReceived,
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
        ROW_NUMBER() OVER (ORDER BY p.Score DESC, p.ViewCount DESC) AS Rank,
        p.OwnerUserId
    FROM Posts p
    JOIN Users u ON p.OwnerUserId = u.Id
    WHERE p.PostTypeId = 1
    ORDER BY p.Score DESC, p.ViewCount DESC
    LIMIT 100
),
vote_history AS (
    SELECT 
        p.Id AS PostId,
        p.OwnerUserId,
        SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS Upvotes,
        SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS Downvotes,
        SUM(CASE WHEN v.VoteTypeId = 8 THEN 1 ELSE 0 END) AS Bounties,
        SUM(CASE WHEN v.VoteTypeId = 8 THEN COALESCE(v.BountyAmount,0) ELSE 0 END) AS TotalBounty
    FROM Posts p
    LEFT JOIN Votes v ON p.Id = v.PostId
    WHERE p.PostTypeId = 1
    GROUP BY p.Id, p.OwnerUserId
),
post_links AS (
    SELECT 
        pl.PostId,
        p.OwnerUserId,
        COUNT(*) AS LinkCount
    FROM PostLinks pl
    JOIN Posts p ON pl.PostId = p.Id
    GROUP BY pl.PostId, p.OwnerUserId
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
LEFT JOIN top_questions tq ON ua.UserId = tq.OwnerUserId AND tq.Rank = 1
LEFT JOIN vote_history vh ON ua.UserId = vh.OwnerUserId
LEFT JOIN post_links pl ON ua.UserId = pl.OwnerUserId
CROSS JOIN (
    SELECT * FROM tag_popularity ORDER BY UsageCount DESC LIMIT 1
) tp
GROUP BY
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
    tq.Rank,
    vh.Upvotes,
    vh.Downvotes,
    vh.Bounties,
    vh.TotalBounty,
    pl.LinkCount,
    tp.UsageCount,
    tp.TotalScore,
    tp.AvgScore
ORDER BY ua.Reputation DESC, ua.TotalScore DESC
LIMIT 50;