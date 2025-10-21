-- {"query": "48025.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "gemini-2.5-flash-lite", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2074, "output_tokens": 901} 
WITH RankedPosts AS (
    SELECT
        p.Id AS PostId,
        p.Title,
        p.Score,
        p.ViewCount,
        p.AnswerCount,
        p.CommentCount,
        p.FavoriteCount,
        ROW_NUMBER() OVER (ORDER BY p.Score DESC, p.ViewCount DESC, p.AnswerCount DESC) as rn_score,
        ROW_NUMBER() OVER (ORDER BY p.ViewCount DESC, p.Score DESC, p.AnswerCount DESC) as rn_views,
        ROW_NUMBER() OVER (ORDER BY p.AnswerCount DESC, p.Score DESC, p.ViewCount DESC) as rn_answers,
        ROW_NUMBER() OVER (ORDER BY p.CommentCount DESC, p.Score DESC, p.ViewCount DESC) as rn_comments,
        ROW_NUMBER() OVER (ORDER BY p.FavoriteCount DESC, p.Score DESC, p.ViewCount DESC) as rn_favorites
    FROM Posts p
    WHERE p.PostTypeId = 1 -- Questions only
),
TagEngagement AS (
    SELECT
        SUBSTRING(Tags, 2, LENGTH(Tags) - 2) AS TagName,
        COUNT(p.Id) AS PostCount,
        SUM(p.Score) AS TotalScore,
        SUM(p.ViewCount) AS TotalViews,
        AVG(p.Score) AS AverageScore,
        AVG(p.ViewCount) AS AverageViews
    FROM Posts p
    WHERE p.PostTypeId = 1 AND p.Tags IS NOT NULL AND p.Tags <> ''
    GROUP BY TagName
),
UserActivity AS (
    SELECT
        u.Id AS UserId,
        u.DisplayName,
        u.Reputation,
        COUNT(DISTINCT p.Id) AS QuestionCount,
        SUM(CASE WHEN p.AcceptedAnswerId IS NOT NULL THEN 1 ELSE 0 END) AS AcceptedAnswerCount,
        COUNT(c.Id) AS CommentCount,
        COUNT(b.Id) AS BadgeCount
    FROM Users u
    LEFT JOIN Posts p ON u.Id = p.OwnerUserId AND p.PostTypeId = 1
    LEFT JOIN Comments c ON u.Id = c.UserId
    LEFT JOIN Badges b ON u.Id = b.UserId
    GROUP BY u.Id, u.DisplayName, u.Reputation
)
SELECT
    rp.PostId,
    rp.Title,
    rp.Score,
    rp.ViewCount,
    rp.AnswerCount,
    rp.CommentCount,
    rp.FavoriteCount,
    rp.rn_score,
    rp.rn_views,
    rp.rn_answers,
    rp.rn_comments,
    rp.rn_favorites,
    te.TagName,
    te.PostCount AS TagPostCount,
    te.TotalScore AS TagTotalScore,
    te.TotalViews AS TagTotalViews,
    te.AverageScore AS TagAverageScore,
    te.AverageViews AS TagAverageViews,
    ua.UserId,
    ua.DisplayName AS UserDisplayName,
    ua.Reputation AS UserReputation,
    ua.QuestionCount AS UserQuestionCount,
    ua.AcceptedAnswerCount AS UserAcceptedAnswerCount,
    ua.CommentCount AS UserCommentCount,
    ua.BadgeCount AS UserBadgeCount
FROM RankedPosts rp
LEFT JOIN (
    SELECT
        Id,
        TAG
    FROM Posts
    CROSS JOIN UNNEST(string_to_array(substring(Tags, 2, length(Tags)-2), '><')) AS TAG
    WHERE PostTypeId = 1
) AS TaggedPosts ON rp.PostId = TaggedPosts.Id
LEFT JOIN TagEngagement te ON TaggedPosts.TAG = te.TagName
LEFT JOIN UserActivity ua ON rp.OwnerUserId = ua.UserId
WHERE rp.rn_score <= 100 -- Top 100 by score
ORDER BY rp.rn_score, te.TagName, ua.Reputation DESC;