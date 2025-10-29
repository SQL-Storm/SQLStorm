-- {"query": "4752.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-flash-lite", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 1256} 

WITH RankedPosts AS (
    SELECT
        p.Id AS PostId,
        p.OwnerUserId,
        p.PostTypeId,
        p.Title,
        p.Tags,
        p.CreationDate,
        p.Score,
        p.AnswerCount,
        p.CommentCount,
        p.FavoriteCount,
        p.ViewCount,
        ROW_NUMBER() OVER(PARTITION BY p.OwnerUserId ORDER BY p.Score DESC, p.CreationDate DESC) as rn_user_score,
        DENSE_RANK() OVER(ORDER BY p.Score DESC) as dr_global_score,
        LAG(p.Score, 1, 0) OVER(PARTITION BY p.OwnerUserId ORDER BY p.CreationDate) as prev_score_same_user,
        LEAD(p.Score, 1, 0) OVER(PARTITION BY p.OwnerUserId ORDER BY p.CreationDate) as next_score_same_user,
        COUNT(c.Id) OVER(PARTITION BY p.OwnerUserId) as user_comment_count_total,
        CASE WHEN p.ClosedDate IS NOT NULL THEN 1 ELSE 0 END AS is_closed
    FROM Posts p
    LEFT JOIN Comments c ON p.Id = c.PostId
    WHERE p.OwnerUserId IS NOT NULL AND p.OwnerUserId <> -1
    GROUP BY
        p.Id, p.OwnerUserId, p.PostTypeId, p.Title, p.Tags, p.CreationDate, p.Score, p.AnswerCount, p.CommentCount, p.FavoriteCount, p.ViewCount, p.ClosedDate
),
UserEngagement AS (
    SELECT
        u.Id AS UserId,
        u.DisplayName,
        u.Reputation,
        u.CreationDate AS UserCreationDate,
        COUNT(DISTINCT rp.PostId) AS TotalPosts,
        SUM(rp.Score) AS TotalScore,
        AVG(rp.Score) AS AvgScore,
        SUM(rp.AnswerCount) AS TotalAnswers,
        SUM(rp.CommentCount) AS TotalComments,
        SUM(rp.FavoriteCount) AS TotalFavorites,
        SUM(rp.ViewCount) AS TotalViews,
        COUNT(CASE WHEN rp.is_closed = 1 THEN 1 END) AS ClosedPosts,
        MAX(rp.user_comment_count_total) AS UserTotalCommentCount,
        SUM(CASE WHEN rp.PostTypeId = 1 THEN 1 ELSE 0 END) AS QuestionCount,
        SUM(CASE WHEN rp.PostTypeId = 2 THEN 1 ELSE 0 END) AS AnswerCount,
        (SELECT COUNT(*) FROM Badges b WHERE b.UserId = u.Id AND b.Class = 1) AS GoldBadges,
        (SELECT COUNT(*) FROM Badges b WHERE b.UserId = u.Id AND b.Class = 2) AS SilverBadges,
        (SELECT COUNT(*) FROM Badges b WHERE b.UserId = u.Id AND b.Class = 3) AS BronzeBadges
    FROM Users u
    LEFT JOIN RankedPosts rp ON u.Id = rp.OwnerUserId
    GROUP BY u.Id, u.DisplayName, u.Reputation, u.CreationDate
),
TopUsers AS (
    SELECT
        UserId,
        DisplayName,
        Reputation,
        UserCreationDate,
        TotalPosts,
        TotalScore,
        AvgScore,
        ClosedPosts,
        QuestionCount,
        AnswerCount,
        GoldBadges,
        SilverBadges,
        BronzeBadges,
        ROW_NUMBER() OVER(ORDER BY Reputation DESC, TotalScore DESC) as rn_user_rep
    FROM UserEngagement
    WHERE TotalPosts > 100 AND UserCreationDate < DATE('now', '-1 year')
)
SELECT
    u.DisplayName AS TopUserDisplayName,
    u.Reputation AS TopUserReputation,
    u.TotalPosts AS TopUserTotalPosts,
    u.TotalScore AS TopUserTotalScore,
    u.AvgScore AS TopUserAvgScore,
    u.ClosedPosts AS TopUserClosedPosts,
    u.QuestionCount AS TopUserQuestionCount,
    u.AnswerCount AS TopUserAnswerCount,
    u.GoldBadges AS TopUserGoldBadges,
    u.SilverBadges AS TopUserSilverBadges,
    u.BronzeBadges AS TopUserBronzeBadges,
    p.Title AS SamplePostTitle,
    p.Tags AS SamplePostTags,
    p.Score AS SamplePostScore,
    p.CommentCount AS SamplePostCommentCount,
    p.FavoriteCount AS SamplePostFavoriteCount,
    p.ViewCount AS SamplePostViewCount,
    p.prev_score_same_user AS PrevScoreSameUser,
    p.next_score_same_user AS NextScoreSameUser,
    pt.Name AS PostTypeName,
    CASE
        WHEN p.rn_user_score <= 5 THEN 'Top 5 Rated Post By User'
        WHEN p.dr_global_score <= 10 THEN 'Global Top 10 Rated Post'
        ELSE 'Other'
    END AS PostCategory
FROM TopUsers u
JOIN RankedPosts p ON u.UserId = p.OwnerUserId
JOIN PostTypes pt ON p.PostTypeId = pt.Id
WHERE p.rn_user_score <= 5 OR p.dr_global_score <= 10
ORDER BY u.Reputation DESC, p.Score DESC, p.CreationDate ASC
LIMIT 100;
