-- {"query": "52049.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "grok-code-fast", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2165, "output_tokens": 731} 
WITH UserStats AS (
    SELECT 
        u.Id,
        u.DisplayName,
        u.Reputation,
        COUNT(DISTINCT b.Id) AS GoldBadges,
        COUNT(DISTINCT p.Id) AS TotalPosts,
        SUM(p.Score) AS TotalScore,
        AVG(p.Score) AS AvgScore,
        COUNT(DISTINCT CASE WHEN p.PostTypeId = 1 THEN p.Id END) AS Questions,
        COUNT(DISTINCT CASE WHEN p.PostTypeId = 2 THEN p.Id END) AS Answers,
        SUM(p.ViewCount) AS TotalViews,
        SUM(p.AnswerCount) AS TotalAnswersOnQuestions,
        COUNT(DISTINCT v.Id) AS TotalVotesReceived,
        COUNT(DISTINCT CASE WHEN v.VoteTypeId = 2 THEN v.Id END) AS Upvotes,
        COUNT(DISTINCT CASE WHEN v.VoteTypeId = 3 THEN v.Id END) AS Downvotes
    FROM Users u
    LEFT JOIN Badges b ON u.Id = b.UserId AND b.Class = 1
    LEFT JOIN Posts p ON u.Id = p.OwnerUserId
    LEFT JOIN Votes v ON p.Id = v.PostId
    GROUP BY u.Id, u.DisplayName, u.Reputation
),
TagStats AS (
    SELECT 
        p.OwnerUserId,
        t.TagName,
        COUNT(*) AS PostsInTag,
        SUM(p.Score) AS ScoreInTag,
        AVG(p.Score) AS AvgScoreInTag,
        SUM(p.ViewCount) AS ViewsInTag
    FROM Posts p
    INNER JOIN Tags t ON POSITION('<' || t.TagName || '>' IN '<' || p.Tags || '>') > 0
    WHERE p.PostTypeId = 1
    GROUP BY p.OwnerUserId, t.TagName
),
CommentStats AS (
    SELECT 
        p.OwnerUserId,
        COUNT(c.Id) AS CommentsOnPosts,
        SUM(c.Score) AS CommentScore
    FROM Posts p
    LEFT JOIN Comments c ON p.Id = c.PostId
    GROUP BY p.OwnerUserId
),
PostHistoryStats AS (
    SELECT 
        ph.UserId,
        COUNT(*) AS Edits,
        COUNT(DISTINCT ph.PostId) AS PostsEdited
    FROM PostHistory ph
    WHERE ph.PostHistoryTypeId IN (4, 5, 6, 24)
    GROUP BY ph.UserId
)
SELECT 
    us.Id,
    us.DisplayName,
    us.Reputation,
    us.GoldBadges,
    us.TotalPosts,
    us.TotalScore,
    us.AvgScore,
    us.Questions,
    us.Answers,
    us.TotalViews,
    us.TotalAnswersOnQuestions,
    us.TotalVotesReceived,
    us.Upvotes,
    us.Downvotes,
    ts.TagName,
    ts.PostsInTag,
    ts.ScoreInTag,
    ts.AvgScoreInTag,
    ts.ViewsInTag,
    cs.CommentsOnPosts,
    cs.CommentScore,
    phs.Edits,
    phs.PostsEdited,
    RANK() OVER (ORDER BY us.GoldBadges DESC, us.Reputation DESC, us.TotalScore DESC) AS UserRank
FROM UserStats us
LEFT JOIN TagStats ts ON us.Id = ts.OwnerUserId
LEFT JOIN CommentStats cs ON us.Id = cs.OwnerUserId
LEFT JOIN PostHistoryStats phs ON us.Id = phs.UserId
ORDER BY UserRank, ts.TagName
LIMIT 1000;