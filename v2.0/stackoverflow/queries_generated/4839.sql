-- {"query": "4839.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-flash-lite", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 1645} 

WITH UserPostCounts AS (
    SELECT
        OwnerUserId,
        COUNT(CASE WHEN PostTypeId = 1 THEN 1 END) AS QuestionCount,
        COUNT(CASE WHEN PostTypeId = 2 THEN 1 END) AS AnswerCount,
        COUNT(DISTINCT Tags) AS DistinctTagCount
    FROM Posts
    WHERE OwnerUserId IS NOT NULL
    GROUP BY OwnerUserId
),
UserEngagement AS (
    SELECT
        u.Id AS UserId,
        u.DisplayName,
        COALESCE(upc.QuestionCount, 0) AS TotalQuestions,
        COALESCE(upc.AnswerCount, 0) AS TotalAnswers,
        COALESCE(upc.DistinctTagCount, 0) AS DistinctTagsUsed,
        (SELECT COUNT(*) FROM Comments c WHERE c.UserId = u.Id) AS TotalComments,
        (SELECT COUNT(*) FROM Votes v WHERE v.UserId = u.Id AND v.VoteTypeId = 2) AS TotalUpVotesGiven,
        (SELECT COUNT(*) FROM Votes v WHERE v.UserId = u.Id AND v.VoteTypeId = 3) AS TotalDownVotesGiven,
        (SELECT COUNT(*) FROM Badges b WHERE b.UserId = u.Id AND b.Class = 1) AS GoldBadges,
        (SELECT COUNT(*) FROM Badges b WHERE b.UserId = u.Id AND b.Class = 2) AS SilverBadges,
        (SELECT COUNT(*) FROM Badges b WHERE b.UserId = u.Id AND b.Class = 3) AS BronzeBadges,
        CASE
            WHEN u.Reputation > 100000 THEN 'Legendary'
            WHEN u.Reputation > 50000 THEN 'Expert'
            WHEN u.Reputation > 10000 THEN 'Trusted'
            WHEN u.Reputation > 2000 THEN 'Experienced'
            WHEN u.Reputation > 500 THEN 'Member'
            ELSE 'New User'
        END AS ReputationLevel
    FROM Users u
    LEFT JOIN UserPostCounts upc ON u.Id = upc.OwnerUserId
    WHERE u.Id > 0
),
PostSentiment AS (
    SELECT
        p.Id AS PostId,
        p.OwnerUserId,
        p.Score,
        p.CommentCount,
        (SELECT AVG(CAST(c.Score AS DECIMAL(10, 2))) FROM Comments c WHERE c.PostId = p.Id) AS AvgCommentScore,
        CASE
            WHEN p.ClosedDate IS NOT NULL THEN 1
            ELSE 0
        END AS IsClosed,
        CASE
            WHEN p.CommunityOwnedDate IS NOT NULL THEN 1
            ELSE 0
        END AS IsCommunityOwned,
        ROW_NUMBER() OVER(PARTITION BY p.OwnerUserId ORDER BY p.CreationDate DESC) AS RowNum
    FROM Posts p
    WHERE p.PostTypeId IN (1, 2) AND p.OwnerUserId IS NOT NULL
),
LatestUserActivity AS (
    SELECT
        UserId,
        DisplayName,
        TotalQuestions,
        TotalAnswers,
        DistinctTagsUsed,
        TotalComments,
        TotalUpVotesGiven,
        TotalDownVotesGiven,
        GoldBadges,
        SilverBadges,
        BronzeBadges,
        ReputationLevel,
        (SELECT Score FROM PostSentiment ps WHERE ps.OwnerUserId = ue.UserId AND ps.RowNum = 1) AS LatestPostScore,
        (SELECT CommentCount FROM PostSentiment ps WHERE ps.OwnerUserId = ue.UserId AND ps.RowNum = 1) AS LatestPostCommentCount,
        (SELECT AvgCommentScore FROM PostSentiment ps WHERE ps.OwnerUserId = ue.UserId AND ps.RowNum = 1) AS LatestPostAvgCommentScore,
        (SELECT IsClosed FROM PostSentiment ps WHERE ps.OwnerUserId = ue.UserId AND ps.RowNum = 1) AS LatestPostIsClosed,
        (SELECT IsCommunityOwned FROM PostSentiment ps WHERE ps.OwnerUserId = ue.UserId AND ps.RowNum = 1) AS LatestPostIsCommunityOwned
    FROM UserEngagement ue
)
SELECT
    lua.UserId,
    lua.DisplayName,
    lua.ReputationLevel,
    lua.TotalQuestions,
    lua.TotalAnswers,
    lua.DistinctTagsUsed,
    lua.TotalComments,
    lua.TotalUpVotesGiven,
    lua.TotalDownVotesGiven,
    lua.GoldBadges,
    lua.SilverBadges,
    lua.BronzeBadges,
    lua.LatestPostScore,
    lua.LatestPostCommentCount,
    lua.LatestPostAvgCommentScore,
    CASE WHEN lua.LatestPostIsClosed = 1 THEN 'Yes' ELSE 'No' END AS LatestPostIsClosed,
    CASE WHEN lua.LatestPostIsCommunityOwned = 1 THEN 'Yes' ELSE 'No' END AS LatestPostIsCommunityOwned,
    (SELECT Name FROM PostTypes WHERE Id = (SELECT PostTypeId FROM Posts WHERE Id = (SELECT PostId FROM PostHistory ph WHERE ph.UserId = lua.UserId AND ph.PostHistoryTypeId = 5 ORDER BY ph.CreationDate DESC LIMIT 1))) AS LastEditedPostType,
    COALESCE(
        (SELECT 'High Engagement'
         FROM UserEngagement ue_inner
         WHERE ue_inner.UserId = lua.UserId
           AND ue_inner.TotalQuestions > 100
           AND ue_inner.TotalAnswers > 200
           AND ue_inner.TotalComments > 500
        ),
        COALESCE(
            (SELECT 'Moderate Engagement'
             FROM UserEngagement ue_inner
             WHERE ue_inner.UserId = lua.UserId
               AND ue_inner.TotalQuestions > 20
               AND ue_inner.TotalAnswers > 40
               AND ue_inner.TotalComments > 100
            ),
            'Low Engagement'
        )
    ) AS UserEngagementLevel
FROM LatestUserActivity lua
WHERE lua.TotalQuestions + lua.TotalAnswers > 50
UNION
SELECT
    lua.UserId,
    lua.DisplayName,
    lua.ReputationLevel,
    lua.TotalQuestions,
    lua.TotalAnswers,
    lua.DistinctTagsUsed,
    lua.TotalComments,
    lua.TotalUpVotesGiven,
    lua.TotalDownVotesGiven,
    lua.GoldBadges,
    lua.SilverBadges,
    lua.BronzeBadges,
    lua.LatestPostScore,
    lua.LatestPostCommentCount,
    lua.LatestPostAvgCommentScore,
    CASE WHEN lua.LatestPostIsClosed = 1 THEN 'Yes' ELSE 'No' END AS LatestPostIsClosed,
    CASE WHEN lua.LatestPostIsCommunityOwned = 1 THEN 'Yes' ELSE 'No' END AS LatestPostIsCommunityOwned,
    (SELECT Name FROM PostTypes WHERE Id = (SELECT PostTypeId FROM Posts WHERE Id = (SELECT PostId FROM PostHistory ph WHERE ph.UserId = lua.UserId AND ph.PostHistoryTypeId = 5 ORDER BY ph.CreationDate DESC LIMIT 1))) AS LastEditedPostType,
    'Superstar' AS UserEngagementLevel
FROM LatestUserActivity lua
WHERE lua.GoldBadges > 5 AND lua.TotalQuestions > 500
ORDER BY UserId;
