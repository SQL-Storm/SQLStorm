-- {"query": "52017.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "grok-code-fast", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2165, "output_tokens": 784} 

WITH UserPostStats AS (
    SELECT
        u.Id AS UserId,
        u.DisplayName,
        u.Reputation,
        u.Location,
        COUNT(DISTINCT p.Id) AS TotalPosts,
        SUM(CASE WHEN pt.Name = 'Question' THEN p.ViewCount ELSE 0 END) AS TotalViewsOnQuestions,
        SUM(CASE WHEN pt.Name = 'Answer' THEN v.Score ELSE 0 END) AS TotalUpvotesOnAnswers,
        AVG(CASE WHEN pt.Name = 'Question' THEN p.Score ELSE NULL END) AS AvgQuestionScore,
        COUNT(DISTINCT CASE WHEN ph.PostHistoryTypeId IN (1, 2, 3, 4, 5, 6) THEN p.Id END) AS EditedPosts,
        STRING_AGG(DISTINCT t.TagName, ', ') AS AssociatedTags
    FROM Users u
    LEFT JOIN Posts p ON u.Id = p.OwnerUserId
    LEFT JOIN PostTypes pt ON p.PostTypeId = pt.Id
    LEFT JOIN Votes v ON p.Id = v.PostId AND v.VoteTypeId = 2 AND pt.Name = 'Answer'
    LEFT JOIN PostHistory ph ON p.Id = ph.PostId
    LEFT JOIN UNNEST(string_to_array(substring(p.Tags, 2, length(p.Tags)-2), '><')) AS t(TagName) ON p.PostTypeId = 1
    WHERE u.CreationDate >= '2008-01-01'::timestamp
      AND p.CreationDate >= '2008-01-01'::timestamp
    GROUP BY u.Id, u.DisplayName, u.Reputation, u.Location
),
BadgeStats AS (
    SELECT
        b.UserId,
        COUNT(CASE WHEN b.Class = 1 THEN 1 END) AS GoldBadges,
        COUNT(CASE WHEN b.Class = 2 THEN 1 END) AS SilverBadges,
        COUNT(CASE WHEN b.Class = 3 THEN 1 END) AS BronzeBadges,
        COUNT(CASE WHEN b.Date >= CURRENT_DATE - INTERVAL '1 year' THEN 1 END) AS RecentBadges
    FROM Badges b
    GROUP BY b.UserId
),
CommentStats AS (
    SELECT
        c.UserId,
        COUNT(*) AS TotalComments,
        SUM(c.Score) AS TotalCommentScore
    FROM Comments c
    WHERE c.CreationDate >= '2008-01-01'::timestamp
    GROUP BY c.UserId
),
TopUsers AS (
    SELECT
        ups.UserId,
        ups.DisplayName,
        ups.Reputation,
        ups.Location,
        ups.TotalPosts,
        ups.TotalViewsOnQuestions,
        ups.TotalUpvotesOnAnswers,
        ups.AvgQuestionScore,
        ups.EditedPosts,
        ups.AssociatedTags,
        bs.GoldBadges,
        bs.SilverBadges,
        bs.BronzeBadges,
        bs.RecentBadges,
        cs.TotalComments,
        cs.TotalCommentScore,
        ROW_NUMBER() OVER (ORDER BY (ups.TotalUpvotesOnAnswers + ups.TotalViewsOnQuestions * 0.01 + ups.AvgQuestionScore * 100 + bs.GoldBadges * 1000 + bs.SilverBadges * 100 + bs.BronzeBadges * 10 + cs.TotalCommentScore) DESC) AS Rank
    FROM UserPostStats ups
    LEFT JOIN BadgeStats bs ON ups.UserId = bs.UserId
    LEFT JOIN CommentStats cs ON ups.UserId = cs.UserId
    WHERE ups.TotalPosts > 10
      AND ups.TotalViewsOnQuestions > 10000
      AND ups.TotalUpvotesOnAnswers > 100
)
SELECT *
FROM TopUsers
WHERE Rank <= 10
ORDER BY Rank;
