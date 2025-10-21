-- {"query": "48047.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "gemini-2.5-flash-lite", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2074, "output_tokens": 832} 
WITH RankedPosts AS (
    SELECT
        p.Id,
        p.OwnerUserId,
        p.CreationDate,
        p.Score,
        p.ViewCount,
        p.AnswerCount,
        p.CommentCount,
        ROW_NUMBER() OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate DESC) as rn
    FROM Posts p
    WHERE p.PostTypeId = 1 AND p.OwnerUserId IS NOT NULL
),
UserPostStats AS (
    SELECT
        rp.OwnerUserId,
        COUNT(rp.Id) AS TotalPosts,
        SUM(rp.Score) AS TotalScore,
        SUM(rp.ViewCount) AS TotalViews,
        AVG(rp.Score) AS AvgScore,
        AVG(rp.ViewCount) AS AvgViews,
        MAX(rp.Score) AS MaxScore,
        MAX(rp.ViewCount) AS MaxViews,
        SUM(rp.AnswerCount) AS TotalAnswers,
        AVG(rp.AnswerCount) AS AvgAnswers,
        SUM(rp.CommentCount) AS TotalComments,
        AVG(rp.CommentCount) AS AvgComments,
        (SELECT COUNT(*) FROM Posts WHERE OwnerUserId = rp.OwnerUserId AND PostTypeId = 2) AS TotalAnswersPosted
    FROM RankedPosts rp
    WHERE rp.rn <= 100 -- Consider the 100 most recent posts per user
    GROUP BY rp.OwnerUserId
)
SELECT
    u.DisplayName,
    u.Reputation,
    u.CreationDate AS UserCreationDate,
    u.Views AS UserViews,
    ups.TotalPosts,
    ups.TotalScore,
    ups.TotalViews,
    ups.AvgScore,
    ups.AvgViews,
    ups.MaxScore,
    ups.MaxViews,
    ups.TotalAnswers,
    ups.AvgAnswers,
    ups.TotalComments,
    ups.AvgComments,
    ups.TotalAnswersPosted,
    (SELECT COUNT(*) FROM Badges b WHERE b.UserId = u.Id AND b.Class = 1) AS GoldBadges,
    (SELECT COUNT(*) FROM Badges b WHERE b.UserId = u.Id AND b.Class = 2) AS SilverBadges,
    (SELECT COUNT(*) FROM Badges b WHERE b.UserId = u.Id AND b.Class = 3) AS BronzeBadges,
    (SELECT COUNT(*) FROM Comments c WHERE c.UserId = u.Id) AS TotalCommentsMade,
    (SELECT COUNT(*) FROM Votes v WHERE v.UserId = u.Id AND v.VoteTypeId = 2) AS TotalUpvotesGiven,
    (SELECT COUNT(*) FROM Votes v WHERE v.UserId = u.Id AND v.VoteTypeId = 3) AS TotalDownvotesGiven,
    (SELECT COUNT(*) FROM Posts p WHERE p.OwnerUserId = u.Id AND p.ClosedDate IS NOT NULL) AS TotalClosedPosts,
    (SELECT COUNT(*) FROM Posts p WHERE p.OwnerUserId = u.Id AND p.CommunityOwnedDate IS NOT NULL) AS TotalCommunityOwnedPosts,
    COALESCE(
        (
            SELECT SUM(p.Score)
            FROM Posts p
            WHERE p.OwnerUserId = u.Id
            AND p.Id IN (
                SELECT ph.PostId
                FROM PostHistory ph
                WHERE ph.PostHistoryTypeId = 24 -- Suggested Edit Applied
                AND ph.UserId = u.Id
            )
        ),
        0
    ) AS ScoreFromAppliedEdits
FROM Users u
JOIN UserPostStats ups ON u.Id = ups.OwnerUserId
ORDER BY u.Reputation DESC, ups.TotalScore DESC
LIMIT 1000;