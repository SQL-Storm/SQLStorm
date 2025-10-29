-- {"query": "4953.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-flash-lite", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 1829}
WITH UserPostActivity AS (
    SELECT
        p.Id AS PostId,
        p.OwnerUserId,
        p.CreationDate AS PostCreationDate,
        p.Score AS PostScore,
        p.ViewCount AS PostViewCount,
        p.AnswerCount,
        p.CommentCount,
        p.FavoriteCount,
        pt.Name AS PostTypeName,
        ph.PostHistoryTypeId,
        ph.CreationDate AS HistoryCreationDate,
        ROW_NUMBER() OVER(PARTITION BY p.Id ORDER BY ph.CreationDate DESC) AS rn_history
    FROM Posts p
    JOIN PostTypes pt ON p.PostTypeId = pt.Id
    LEFT JOIN PostHistory ph ON p.Id = ph.PostId
    WHERE p.OwnerUserId IS NOT NULL AND p.OwnerUserId > 0
),
UserReputationChange AS (
    SELECT
        u.Id AS UserId,
        u.Reputation,
        u.CreationDate AS UserCreationDate,
        SUM(CASE WHEN v.VoteTypeId IN (2, 16) THEN 1 ELSE 0 END) AS TotalUpVotesReceived,
        SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS TotalDownVotesReceived,
        COUNT(DISTINCT b.Id) AS TotalBadgesEarned,
        MAX(b.Date) AS LastBadgeDate,
        STRING_AGG(DISTINCT b.Name, ', ') AS BadgeNames
    FROM Users u
    LEFT JOIN Votes v ON u.Id = v.UserId
    LEFT JOIN Badges b ON u.Id = b.UserId
    GROUP BY u.Id, u.Reputation, u.CreationDate
),
PostEngagement AS (
    SELECT
        upa.PostId,
        upa.OwnerUserId,
        upa.PostCreationDate,
        upa.PostScore,
        upa.PostViewCount,
        upa.AnswerCount,
        upa.CommentCount,
        upa.FavoriteCount,
        upa.PostTypeName,
        upa.HistoryCreationDate,
        upa.rn_history,
        CASE WHEN upa.rn_history = 1 THEN upa.PostHistoryTypeId ELSE NULL END AS LatestHistoryTypeId,
        CASE
            WHEN upa.PostTypeName = 'Question' THEN upa.PostScore * 0.5 + COALESCE(upa.PostViewCount, 0) * 0.1 + COALESCE(upa.FavoriteCount, 0) * 0.4
            WHEN upa.PostTypeName = 'Answer' THEN upa.PostScore * 0.7 + COALESCE(upa.CommentCount, 0) * 0.3
            ELSE upa.PostScore
        END AS EngagementScore
    FROM UserPostActivity upa
),
RankedPostEngagement AS (
    SELECT
        pe.PostId,
        pe.OwnerUserId,
        pe.PostCreationDate,
        pe.PostScore,
        pe.PostViewCount,
        pe.AnswerCount,
        pe.CommentCount,
        pe.FavoriteCount,
        pe.PostTypeName,
        pe.HistoryCreationDate,
        pe.rn_history,
        pe.LatestHistoryTypeId,
        pe.EngagementScore,
        ROW_NUMBER() OVER(PARTITION BY pe.OwnerUserId ORDER BY pe.EngagementScore DESC) AS UserPostRank
    FROM PostEngagement pe
    WHERE pe.rn_history = 1
),
UserPerformanceMetrics AS (
    SELECT
        rpe.OwnerUserId,
        COUNT(DISTINCT rpe.PostId) AS TotalPosts,
        SUM(rpe.EngagementScore) AS TotalEngagementScore,
        AVG(rpe.EngagementScore) AS AverageEngagementScore,
        MAX(rpe.EngagementScore) AS MaxEngagementScore,
        SUM(CASE WHEN rpe.PostTypeName = 'Question' THEN 1 ELSE 0 END) AS QuestionCount,
        SUM(CASE WHEN rpe.PostTypeName = 'Answer' THEN 1 ELSE 0 END) AS AnswerCount,
        COUNT(CASE WHEN rpe.PostScore > 0 THEN 1 ELSE NULL END) AS PostsWithPositiveScore,
        COUNT(CASE WHEN rpe.AnswerCount > 0 THEN 1 ELSE NULL END) AS PostsWithAnswers,
        COUNT(CASE WHEN rpe.LatestHistoryTypeId IN (10, 12, 14, 19) THEN 1 ELSE NULL END) AS PostsClosedOrLockedOrProtected,
        SUM(CASE WHEN rpe.PostTypeName = 'Question' AND rpe.PostScore > 50 THEN 1 ELSE 0 END) AS HighScoringQuestions
    FROM RankedPostEngagement rpe
    WHERE rpe.UserPostRank <= 100
    GROUP BY rpe.OwnerUserId
)
SELECT
    urc.UserId,
    u.DisplayName,
    urc.Reputation,
    urc.UserCreationDate,
    COALESCE(upm.TotalPosts, 0) AS TotalPostsOwned,
    COALESCE(upm.TotalEngagementScore, 0) AS CumulativeEngagement,
    COALESCE(upm.AverageEngagementScore, 0) AS AvgEngagementPerPost,
    COALESCE(upm.MaxEngagementScore, 0) AS MaxPostEngagement,
    urc.TotalUpVotesReceived,
    urc.TotalDownVotesReceived,
    urc.TotalBadgesEarned,
    urc.BadgeNames,
    COALESCE(upm.QuestionCount, 0) AS QuestionCount,
    COALESCE(upm.AnswerCount, 0) AS AnswerCount,
    COALESCE(upm.PostsWithPositiveScore, 0) AS PostsWithPositiveScore,
    COALESCE(upm.PostsWithAnswers, 0) AS PostsWithAnswers,
    COALESCE(upm.PostsClosedOrLockedOrProtected, 0) AS PostsClosedOrLockedOrProtected,
    COALESCE(upm.HighScoringQuestions, 0) AS HighScoringQuestions,
    CASE
        WHEN urc.Reputation > 100000 THEN 'Legendary'
        WHEN urc.Reputation > 50000 THEN 'Expert'
        WHEN urc.Reputation > 10000 THEN 'Trusted'
        WHEN urc.Reputation > 2000 THEN 'Experienced'
        WHEN urc.Reputation > 500 THEN 'Insightful'
        ELSE 'Newcomer'
    END AS ReputationTier,
    COALESCE(
        (
            SELECT COUNT(pl.Id)
            FROM PostLinks pl
            JOIN Posts p_linked ON pl.PostId = p_linked.Id
            WHERE p_linked.OwnerUserId = urc.UserId AND pl.LinkTypeId = 3
        ),
        0
    ) AS OutgoingDuplicateLinks,
    COALESCE(
        (
            SELECT COUNT(DISTINCT p.Id)
            FROM Posts p
            JOIN Comments c ON p.Id = c.PostId
            WHERE p.OwnerUserId = urc.UserId
            AND c.CreationDate BETWEEN urc.UserCreationDate AND (cast('2024-10-01' as date) - INTERVAL '1 year')
            AND LOWER(c.Text) LIKE '%great question%'
        ),
        0
    ) AS ComplimentsOnQuestions,
    COALESCE(
        (
            SELECT COUNT(ph.Id)
            FROM PostHistory ph
            JOIN Posts p_hist ON ph.PostId = p_hist.Id
            WHERE p_hist.OwnerUserId = urc.UserId
            AND ph.PostHistoryTypeId IN (4, 5)
            AND ph.CreationDate > (cast('2024-10-01' as date) - INTERVAL '30 days')
        ),
        0
    ) AS RecentEdits,
    CASE WHEN u.WebsiteUrl IS NOT NULL AND u.WebsiteUrl <> '' THEN 1 ELSE 0 END AS HasWebsite,
    CASE WHEN u.Location IS NOT NULL AND u.Location <> '' THEN 1 ELSE 0 END AS HasLocation,
    CASE WHEN u.AboutMe IS NOT NULL AND LENGTH(u.AboutMe) > 50 THEN 1 ELSE 0 END AS HasDetailedAboutMe
FROM UserReputationChange urc
LEFT JOIN Users u ON urc.UserId = u.Id
LEFT JOIN UserPerformanceMetrics upm ON urc.UserId = upm.OwnerUserId
WHERE urc.Reputation > 100
ORDER BY urc.Reputation DESC, COALESCE(upm.TotalPosts, 0) DESC, urc.TotalBadgesEarned DESC
LIMIT 1000;