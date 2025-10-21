WITH UserActivitySummary AS (
    SELECT
        u.Id AS UserId,
        u.DisplayName,
        u.Reputation,
        u.CreationDate AS UserCreationDate,
        COUNT(DISTINCT p.Id) AS TotalPosts,
        SUM(CASE WHEN p.PostTypeId = 1 THEN 1 ELSE 0 END) AS TotalQuestions,
        SUM(CASE WHEN p.PostTypeId = 2 THEN 1 ELSE 0 END) AS TotalAnswers,
        SUM(CASE WHEN p.PostTypeId = 1 THEN p.ViewCount ELSE 0 END) AS TotalQuestionViews,
        AVG(CASE WHEN p.PostTypeId = 1 THEN CAST(p.ViewCount AS numeric) ELSE NULL END) AS AvgQuestionViewCount,
        SUM(p.Score) AS TotalPostScore,
        SUM(COALESCE(p.FavoriteCount, 0)) AS TotalFavoriteCount,
        COUNT(DISTINCT CASE WHEN p.AcceptedAnswerId IS NOT NULL AND p.PostTypeId = 1 THEN p.AcceptedAnswerId ELSE NULL END) AS AcceptedAnswersToOwnQuestions,
        SUM(CASE WHEN p.PostTypeId = 2 AND p_parent.AcceptedAnswerId = p.Id THEN 1 ELSE 0 END) AS AnswersAcceptedByOthers
    FROM
        Users u
    JOIN
        Posts p ON u.Id = p.OwnerUserId
    LEFT JOIN
        Posts p_parent ON p.ParentId = p_parent.Id AND p.PostTypeId = 2
    WHERE
        p.CreationDate >= (CAST('2024-10-01' AS date) - INTERVAL '5 year')
    GROUP BY
        u.Id, u.DisplayName, u.Reputation, u.CreationDate
    HAVING
        COUNT(DISTINCT p.Id) >= 50
        AND SUM(p.Score) >= 1000
),
UserBadgeStats AS (
    SELECT
        b.UserId,
        COUNT(b.Id) AS TotalBadges,
        SUM(CASE WHEN b.Class = 1 THEN 1 ELSE 0 END) AS GoldBadges,
        SUM(CASE WHEN b.Class = 2 THEN 1 ELSE 0 END) AS SilverBadges,
        SUM(CASE WHEN b.Class = 3 THEN 1 ELSE 0 END) AS BronzeBadges
    FROM
        Badges b
    GROUP BY
        b.UserId
),
PostHistoryEngagement AS (
    SELECT
        p.OwnerUserId AS UserId,
        COUNT(ph.Id) AS TotalPostEdits,
        COUNT(DISTINCT ph.PostId) AS UniquePostsEdited,
        SUM(CASE WHEN ph.PostHistoryTypeId IN (4, 5, 6) THEN 1 ELSE 0 END) AS MajorContentEdits,
        SUM(CASE WHEN ph.PostHistoryTypeId IN (10, 11, 12, 13) THEN 1 ELSE 0 END) AS LifecycleEvents
    FROM
        PostHistory ph
    JOIN
        Posts p ON ph.PostId = p.Id
    WHERE
        ph.CreationDate >= (CAST('2024-10-01' AS date) - INTERVAL '5 year')
        AND p.OwnerUserId IS NOT NULL
        AND ph.PostHistoryTypeId NOT IN (1, 2, 3, 50)
    GROUP BY
        p.OwnerUserId
),
CommentInteraction AS (
    SELECT
        p.OwnerUserId AS UserId,
        COUNT(c.Id) AS CommentsReceived,
        SUM(c.Score) AS TotalCommentScoreReceived
    FROM
        Comments c
    JOIN
        Posts p ON c.PostId = p.Id
    WHERE
        c.CreationDate >= (CAST('2024-10-01' AS date) - INTERVAL '5 year')
        AND p.OwnerUserId IS NOT NULL
    GROUP BY
        p.OwnerUserId
),
UserCommentContribution AS (
    SELECT
        c.UserId,
        COUNT(c.Id) AS CommentsMade,
        SUM(c.Score) AS TotalCommentScoreMade
    FROM
        Comments c
    WHERE
        c.CreationDate >= (CAST('2024-10-01' AS date) - INTERVAL '5 year')
        AND c.UserId IS NOT NULL
    GROUP BY
        c.UserId
),
RecentPostStats AS (
    SELECT
        p.OwnerUserId AS UserId,
        COUNT(p.Id) AS RecentPosts,
        SUM(p.Score) AS RecentPostScore,
        AVG(CASE WHEN p.PostTypeId = 1 THEN CAST(p.ViewCount AS numeric) ELSE NULL END) AS RecentAvgQuestionViewCount,
        COUNT(DISTINCT p.AcceptedAnswerId) FILTER (WHERE p.PostTypeId = 1 AND p.AcceptedAnswerId IS NOT NULL) AS RecentAcceptedAnswersToOwnQuestions,
        SUM(CASE WHEN p.PostTypeId = 2 AND p_parent.AcceptedAnswerId = p.Id THEN 1 ELSE 0 END) AS RecentAnswersAcceptedByOthers
    FROM
        Posts p
    LEFT JOIN
        Posts p_parent ON p.ParentId = p_parent.Id AND p.PostTypeId = 2
    WHERE
        p.CreationDate >= (CAST('2024-10-01' AS date) - INTERVAL '90 day')
        AND p.OwnerUserId IS NOT NULL
    GROUP BY
        p.OwnerUserId
),
UserTagImpact AS (
    SELECT
        UserId,
        STRING_AGG(TagName, ', ' ORDER BY TagRank) AS Top5Tags
    FROM (
        SELECT
            p.OwnerUserId AS UserId,
            TRIM(UNNEST(string_to_array(substring(p.Tags, 2, length(p.Tags)-2), '><'))) AS TagName,
            COUNT(p.Id) AS PostsWithTag,
            SUM(p.Score) AS TagScoreContribution,
            ROW_NUMBER() OVER (PARTITION BY p.OwnerUserId ORDER BY COUNT(p.Id) DESC, SUM(p.Score) DESC) AS TagRank
        FROM
            Posts p
        WHERE
            p.PostTypeId = 1
            AND p.Tags IS NOT NULL
            AND p.Tags <> '><'
            AND p.OwnerUserId IS NOT NULL
            AND p.CreationDate >= (CAST('2024-10-01' AS date) - INTERVAL '5 year')
        GROUP BY
            p.OwnerUserId, TRIM(UNNEST(string_to_array(substring(p.Tags, 2, length(p.Tags)-2), '><')))
    ) AS TaggedPosts
    WHERE TagRank <= 5
    GROUP BY UserId
)
SELECT
    uas.UserId,
    uas.DisplayName,
    uas.Reputation,
    uas.UserCreationDate,
    uas.TotalPosts,
    uas.TotalQuestions,
    uas.TotalAnswers,
    uas.TotalPostScore,
    uas.AvgQuestionViewCount,
    uas.TotalFavoriteCount,
    uas.AnswersAcceptedByOthers,
    COALESCE(ubs.TotalBadges, 0) AS TotalBadges,
    COALESCE(ubs.GoldBadges, 0) AS GoldBadges,
    COALESCE(phe.TotalPostEdits, 0) AS TotalPostEdits,
    COALESCE(phe.MajorContentEdits, 0) AS MajorContentEdits,
    COALESCE(ci.CommentsReceived, 0) AS CommentsReceived,
    COALESCE(ucci.CommentsMade, 0) AS CommentsMade,
    COALESCE(rs.RecentPosts, 0) AS RecentPostsLast90Days,
    COALESCE(rs.RecentPostScore, 0) AS RecentPostScoreLast90Days,
    COALESCE(rs.RecentAvgQuestionViewCount, 0.0) AS RecentAvgQuestionViewCountLast90Days,
    COALESCE(uti.Top5Tags, 'N/A') AS Top5Tags,
    RANK() OVER (ORDER BY uas.Reputation DESC, uas.TotalPostScore DESC, uas.TotalPosts DESC, COALESCE(ubs.TotalBadges, 0) DESC) AS OverallRank
FROM
    UserActivitySummary uas
LEFT JOIN
    UserBadgeStats ubs ON uas.UserId = ubs.UserId
LEFT JOIN
    PostHistoryEngagement phe ON uas.UserId = phe.UserId
LEFT JOIN
    CommentInteraction ci ON uas.UserId = ci.UserId
LEFT JOIN
    UserCommentContribution ucci ON uas.UserId = ucci.UserId
LEFT JOIN
    RecentPostStats rs ON uas.UserId = rs.UserId
LEFT JOIN
    UserTagImpact uti ON uas.UserId = uti.UserId
WHERE
    uas.Reputation > 50000
    AND uas.TotalPosts > 100
    AND (COALESCE(ubs.TotalBadges, 0) > 10 OR uas.AnswersAcceptedByOthers > 50)
ORDER BY
    OverallRank
LIMIT 100;