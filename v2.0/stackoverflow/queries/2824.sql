-- {"query": "2824.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1762}
WITH RecentActiveUsers AS (
    SELECT
        u.Id,
        u.DisplayName,
        u.Reputation,
        u.CreationDate,
        u.Location,
        COALESCE(u.WebsiteUrl, '') AS WebsiteUrl,
        u.Views,
        u.UpVotes,
        u.DownVotes,
        BadgesSummary.BadgeCount,
        BadgesSummary.GoldBadges,
        BadgesSummary.SilverBadges,
        BadgesSummary.BronzeBadges,
        ROW_NUMBER() OVER (ORDER BY u.Reputation DESC, u.Views DESC) AS UserRank
    FROM Users u
    LEFT JOIN (
        SELECT
            b.UserId,
            COUNT(*) AS BadgeCount,
            COUNT(CASE WHEN b.Class = 1 THEN 1 END) AS GoldBadges,
            COUNT(CASE WHEN b.Class = 2 THEN 1 END) AS SilverBadges,
            COUNT(CASE WHEN b.Class = 3 THEN 1 END) AS BronzeBadges
        FROM Badges b
        GROUP BY b.UserId
    ) BadgesSummary ON BadgesSummary.UserId = u.Id
    WHERE u.LastAccessDate >= CAST('2024-10-01 12:34:56' AS timestamp) - INTERVAL '90' DAY
),
UserQuestionStats AS (
    SELECT
        p.OwnerUserId AS UserId,
        COUNT(*) FILTER (WHERE p.PostTypeId = 1) AS TotalQuestions,
        COUNT(*) FILTER (WHERE p.PostTypeId = 1 AND p.ClosedDate IS NOT NULL) AS ClosedQuestions,
        AVG(p.Score) FILTER (WHERE p.PostTypeId = 1) AS AvgQuestionScore,
        SUM(p.ViewCount) FILTER (WHERE p.PostTypeId = 1) AS TotalQuestionViews,
        SUM(p.FavoriteCount) FILTER (WHERE p.PostTypeId = 1) AS TotalFavorites
    FROM Posts p
    WHERE p.OwnerUserId IS NOT NULL
    GROUP BY p.OwnerUserId
),
UserAnswerStats AS (
    SELECT
        p.OwnerUserId AS UserId,
        COUNT(*) FILTER (WHERE p.PostTypeId = 2) AS TotalAnswers,
        AVG(p.Score) FILTER (WHERE p.PostTypeId = 2) AS AvgAnswerScore,
        COUNT(q.Id) FILTER (WHERE p.PostTypeId = 2 AND q.AcceptedAnswerId = p.Id) AS AcceptedAnswersGiven
    FROM Posts p
    LEFT JOIN Posts q ON q.AcceptedAnswerId = p.Id
    WHERE p.OwnerUserId IS NOT NULL
    GROUP BY p.OwnerUserId
),
UserLinkStats AS (
    SELECT
        pl.PostId,
        lt.Name AS LinkTypeName,
        COUNT(*) AS LinkCount
    FROM PostLinks pl
    JOIN LinkTypes lt ON lt.Id = pl.LinkTypeId
    GROUP BY pl.PostId, lt.Name
),
TopTags AS (
    SELECT
        tag AS TagName,
        COUNT(*) AS TagUsageCount
    FROM (
        SELECT
            regexp_split_to_table( substring(p.Tags FROM 2 FOR length(p.Tags) - 2), '><') AS tag
        FROM Posts p
        WHERE p.PostTypeId = 1 AND p.Tags IS NOT NULL
    ) sub
    GROUP BY tag
    ORDER BY TagUsageCount DESC
    LIMIT 10
),
UserTopTags AS (
    SELECT
        u.Id AS UserId,
        tag AS TagName,
        COUNT(*) AS QuestionsWithTag
    FROM Users u
    JOIN Posts p ON p.OwnerUserId = u.Id AND p.PostTypeId = 1 AND p.Tags IS NOT NULL
    JOIN LATERAL (
        SELECT regexp_split_to_table( substring(p.Tags FROM 2 FOR length(p.Tags) - 2), '><') AS tag
    ) t ON true
    WHERE EXISTS (SELECT 1 FROM TopTags tt WHERE tt.TagName = t.tag)
    GROUP BY u.Id, t.tag
),
UserEngagement AS (
    SELECT
        u.Id AS UserId,
        COALESCE(uqs.TotalQuestions, 0) AS TotalQuestions,
        COALESCE(uqs.ClosedQuestions, 0) AS ClosedQuestions,
        COALESCE(uqs.AvgQuestionScore, 0) AS AvgQuestionScore,
        COALESCE(uqs.TotalQuestionViews, 0) AS TotalQuestionViews,
        COALESCE(uqs.TotalFavorites, 0) AS TotalFavorites,
        COALESCE(uans.TotalAnswers, 0) AS TotalAnswers,
        COALESCE(uans.AvgAnswerScore, 0) AS AvgAnswerScore,
        COALESCE(uans.AcceptedAnswersGiven, 0) AS AcceptedAnswersGiven
    FROM RecentActiveUsers u
    LEFT JOIN UserQuestionStats uqs ON uqs.UserId = u.Id
    LEFT JOIN UserAnswerStats uans ON uans.UserId = u.Id
),
UserCommentsSummary AS (
    SELECT
        c.UserId,
        COUNT(*) AS TotalComments,
        AVG(c.Score) AS AvgCommentScore,
        COUNT(DISTINCT c.PostId) AS DistinctPostsCommented
    FROM Comments c
    WHERE c.UserId IS NOT NULL
    GROUP BY c.UserId
),
FinalUserStat AS (
    SELECT
        ua.UserRank,
        ua.Id AS UserId,
        ua.DisplayName,
        ua.Reputation,
        ua.Location,
        ua.WebsiteUrl,
        ua.Views,
        ua.UpVotes,
        ua.DownVotes,
        ua.BadgeCount,
        ua.GoldBadges,
        ua.SilverBadges,
        ua.BronzeBadges,
        ue.TotalQuestions,
        ue.ClosedQuestions,
        ue.AvgQuestionScore,
        ue.TotalQuestionViews,
        ue.TotalFavorites,
        ue.TotalAnswers,
        ue.AvgAnswerScore,
        ue.AcceptedAnswersGiven,
        COALESCE(ucs.TotalComments, 0) AS TotalComments,
        COALESCE(ucs.AvgCommentScore, 0) AS AvgCommentScore,
        COALESCE(ucs.DistinctPostsCommented, 0) AS DistinctPostsCommented,
        CASE 
            WHEN ue.TotalQuestions + ue.TotalAnswers > 0 THEN ROUND((CAST(ue.AcceptedAnswersGiven AS numeric) / NULLIF(ue.TotalAnswers,0)) * 100,2)
            ELSE 0
        END AS AcceptedAnswerPercentage
    FROM RecentActiveUsers ua
    LEFT JOIN UserEngagement ue ON ue.UserId = ua.Id
    LEFT JOIN UserCommentsSummary ucs ON ucs.UserId = ua.Id
),
RankedUsersByAcceptedPercent AS (
    SELECT
        fou.UserRank,
        fou.UserId,
        fou.DisplayName,
        fou.Reputation,
        fou.Location,
        fou.WebsiteUrl,
        fou.Views,
        fou.UpVotes,
        fou.DownVotes,
        fou.BadgeCount,
        fou.GoldBadges,
        fou.SilverBadges,
        fou.BronzeBadges,
        fou.TotalQuestions,
        fou.ClosedQuestions,
        fou.AvgQuestionScore,
        fou.TotalQuestionViews,
        fou.TotalFavorites,
        fou.TotalAnswers,
        fou.AvgAnswerScore,
        fou.AcceptedAnswersGiven,
        fou.AcceptedAnswerPercentage,
        fou.TotalComments,
        fou.AvgCommentScore,
        fou.DistinctPostsCommented,
        RANK() OVER (ORDER BY fou.AcceptedAnswerPercentage DESC, fou.Reputation DESC) AS AcceptanceRank
    FROM FinalUserStat fou
)
SELECT
    rus.UserRank,
    rus.UserId,
    rus.DisplayName,
    rus.Reputation,
    rus.Location,
    rus.WebsiteUrl,
    rus.Views,
    rus.UpVotes,
    rus.DownVotes,
    rus.BadgeCount,
    rus.GoldBadges,
    rus.SilverBadges,
    rus.BronzeBadges,
    rus.TotalQuestions,
    rus.ClosedQuestions,
    rus.AvgQuestionScore,
    rus.TotalQuestionViews,
    rus.TotalFavorites,
    rus.TotalAnswers,
    rus.AvgAnswerScore,
    rus.AcceptedAnswersGiven,
    rus.AcceptedAnswerPercentage,
    rus.TotalComments,
    rus.AvgCommentScore,
    rus.DistinctPostsCommented,
    rt.TagName AS MostUsedTopTag,
    utq.QuestionsWithTag,
    CASE
        WHEN rus.ClosedQuestions > 0 AND rus.TotalQuestions > rus.ClosedQuestions THEN 'Has active open questions'
        WHEN rus.TotalQuestions = rus.ClosedQuestions AND rus.TotalQuestions > 0 THEN 'All questions closed'
        ELSE 'No closed questions or no questions'
    END AS QuestionStatus,
    CASE 
        WHEN rus.BadgeCount > 10 AND rus.Reputation > 10000 THEN 'High influence'
        WHEN rus.BadgeCount <= 10 AND rus.Reputation < 1000 THEN 'Low influence'
        ELSE 'Moderate influence'
    END AS InfluenceCategory
FROM RankedUsersByAcceptedPercent rus
LEFT JOIN LATERAL (
    SELECT ut.TagName, ut.QuestionsWithTag
    FROM UserTopTags ut
    WHERE ut.UserId = rus.UserId
    ORDER BY ut.QuestionsWithTag DESC NULLS LAST
    LIMIT 1
) utq ON true
LEFT JOIN TopTags rt ON rt.TagName = utq.TagName
WHERE rus.UserRank <= 100
ORDER BY rus.AcceptedAnswerPercentage DESC, rus.Reputation DESC;