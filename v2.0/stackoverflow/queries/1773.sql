-- {"query": "1773.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-flash", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 3818}
WITH RelevantTags AS (
    SELECT 'sql' AS TagName
    UNION ALL SELECT 'performance'
    UNION ALL SELECT 'database'
    UNION ALL SELECT 'optimization'
    UNION ALL SELECT 'query'
    UNION ALL SELECT 'indexing'
),
ExplodedPostTags AS (
    SELECT
        p.Id AS PostId,
        p.PostTypeId,
        p.OwnerUserId,
        p.CreationDate AS PostCreationDate,
        p.Score AS PostScore,
        p.ViewCount,
        p.AnswerCount,
        p.CommentCount,
        p.FavoriteCount,
        p.LastActivityDate,
        p.LastEditDate,
        p.ClosedDate,
        p.Title,
        p.Body,
        LOWER(TRIM(unnest(string_to_array(SUBSTRING(p.Tags, 2, LENGTH(p.Tags) - 2), '><')))) AS Tag
    FROM Posts AS p
    WHERE p.Tags IS NOT NULL
      AND (
            p.Tags LIKE '%<sql>%' OR p.Tags LIKE '%<performance>%' OR p.Tags LIKE '%<database>%' OR
            p.Tags LIKE '%<optimization>%' OR p.Tags LIKE '%<query>%' OR p.Tags LIKE '%<indexing>%'
          )
),
FilteredPostsWithTags AS (
    SELECT
        ept.PostId,
        ept.PostTypeId,
        ept.OwnerUserId,
        ept.PostCreationDate,
        ept.PostScore,
        ept.ViewCount,
        ept.AnswerCount,
        ept.CommentCount,
        ept.FavoriteCount,
        ept.LastActivityDate,
        ept.LastEditDate,
        ept.ClosedDate,
        ept.Title,
        ept.Body,
        ept.Tag
    FROM ExplodedPostTags AS ept
    INNER JOIN RelevantTags AS rt ON ept.Tag = rt.TagName
),
UserOverallActivity AS (
    SELECT
        u.Id AS UserId,
        u.DisplayName,
        u.Reputation,
        u.CreationDate AS UserCreationDate,
        u.LastAccessDate,
        u.UpVotes AS TotalUpVotes,
        u.DownVotes AS TotalDownVotes,
        u.Views AS ProfileViews,
        COALESCE(u.Location, 'Unknown') AS UserLocation,
        CASE
            WHEN u.AboutMe LIKE '%developer%' OR u.AboutMe LIKE '%engineer%' THEN 'Developer/Engineer'
            WHEN u.AboutMe LIKE '%student%' THEN 'Student'
            WHEN u.AboutMe LIKE '%manager%' OR u.AboutMe LIKE '%lead%' THEN 'Manager/Lead'
            WHEN u.AboutMe IS NULL OR TRIM(u.AboutMe) = '' THEN 'No Bio'
            ELSE 'Other Professional'
        END AS AboutMeCategory,
        (SELECT MAX(b.Date) FROM Badges AS b WHERE b.UserId = u.Id AND b.Class = 1) AS LastGoldBadgeDate,
        (SELECT COUNT(DISTINCT p.Id) FROM Posts AS p WHERE p.OwnerUserId = u.Id AND p.PostTypeId = 1) AS QuestionCount,
        (SELECT COUNT(DISTINCT p.Id) FROM Posts AS p WHERE p.OwnerUserId = u.Id AND p.PostTypeId = 2) AS AnswerCount,
        AVG(CASE WHEN p.PostTypeId = 1 THEN p.Score ELSE 0 END) AS AvgQuestionScore,
        AVG(CASE WHEN p.PostTypeId = 2 THEN p.Score ELSE 0 END) AS AvgAnswerScore,
        COUNT(DISTINCT ph.Id) AS TotalPostHistoryEvents,
        SUM(CASE WHEN ph.PostHistoryTypeId IN (4, 5, 6, 8, 9) THEN 1 ELSE 0 END) AS TotalEditOrRollbackEvents
    FROM Users AS u
    LEFT JOIN Posts AS p ON u.Id = p.OwnerUserId
    LEFT JOIN PostHistory AS ph ON u.Id = ph.UserId AND ph.PostId IS NOT NULL
    GROUP BY u.Id, u.DisplayName, u.Reputation, u.CreationDate, u.LastAccessDate, u.UpVotes, u.DownVotes, u.Views, u.Location, u.AboutMe
),
TagSpecificUserContributions AS (
    SELECT
        fpt.OwnerUserId AS UserId,
        fpt.Tag,
        COUNT(DISTINCT fpt.PostId) AS PostsInTag,
        SUM(fpt.PostScore) AS TotalTagScore,
        AVG(fpt.PostScore) AS AvgTagPostScore,
        SUM(CASE WHEN fpt.PostTypeId = 1 THEN 1 ELSE 0 END) AS QuestionsInTag,
        SUM(CASE WHEN fpt.PostTypeId = 2 THEN 1 ELSE 0 END) AS AnswersInTag,
        SUM(fpt.CommentCount) AS TotalCommentsReceived,
        SUM(fpt.FavoriteCount) AS TotalFavoritesReceived,
        MAX(fpt.LastActivityDate) AS LastActivityInTag
    FROM FilteredPostsWithTags AS fpt
    WHERE fpt.OwnerUserId IS NOT NULL
    GROUP BY fpt.OwnerUserId, fpt.Tag
    HAVING COUNT(DISTINCT fpt.PostId) > 1
),
RankedTagContributions AS (
    SELECT
        tsc.UserId,
        tsc.Tag,
        tsc.PostsInTag,
        tsc.TotalTagScore,
        tsc.AvgTagPostScore,
        RANK() OVER (PARTITION BY tsc.UserId ORDER BY tsc.TotalTagScore DESC, tsc.PostsInTag DESC) AS TagRankForUser,
        NTILE(5) OVER (ORDER BY tsc.TotalTagScore DESC, tsc.PostsInTag DESC) AS OverallTagContributionNtile
    FROM TagSpecificUserContributions AS tsc
),
TopPostsPerTagUser AS (
    SELECT
        fpt.PostId,
        fpt.PostTypeId,
        fpt.OwnerUserId AS UserId,
        fpt.Tag,
        fpt.PostScore,
        fpt.ViewCount,
        fpt.AnswerCount,
        fpt.CommentCount,
        fpt.FavoriteCount,
        fpt.LastActivityDate,
        fpt.Title,
        LEFT(fpt.Body, 200) AS ShortBody,
        fpt.PostCreationDate,
        ROW_NUMBER() OVER (PARTITION BY fpt.OwnerUserId, fpt.Tag ORDER BY fpt.PostScore DESC, fpt.ViewCount DESC) AS RankInTagUser
    FROM FilteredPostsWithTags AS fpt
    WHERE fpt.OwnerUserId IS NOT NULL
),
PostDetailAggregates AS (
    SELECT
        p.Id AS PostId,
        SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS UpvotesCount,
        SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS DownvotesCount,
        SUM(CASE WHEN v.VoteTypeId = 5 THEN 1 ELSE 0 END) AS FavoriteVotesCount,
        AVG(c.Score) AS AvgCommentScore,
        COUNT(DISTINCT c.Id) AS CommentCountActual,
        MAX(ph.CreationDate) AS LatestEditDate,
        MIN(ph.CreationDate) AS FirstEditDate,
        COUNT(DISTINCT ph.Id) AS EditHistoryCount,
        SUM(CASE WHEN ph.PostHistoryTypeId = 10 THEN 1 ELSE 0 END) AS CloseVotes,
        MAX(CASE WHEN ph.PostHistoryTypeId = 10 THEN ph.Comment ELSE NULL END) AS LastCloseReasonComment,
        MAX(CASE WHEN pl.LinkTypeId = 3 THEN 1 ELSE 0 END) AS IsDuplicateSource,
        COUNT(DISTINCT pl_dup.PostId) AS DuplicateLinksReferringHereCount,
        COALESCE(MAX(CASE WHEN p.AcceptedAnswerId IS NOT NULL THEN 1 ELSE 0 END), 0) AS HasAcceptedAnswer,
        (SELECT COUNT(b2.Id) FROM Badges AS b2 WHERE b2.UserId = p.OwnerUserId AND b2.Class = 1) AS GoldBadgesForOwner
    FROM Posts AS p
    LEFT JOIN Votes AS v ON p.Id = v.PostId
    LEFT JOIN Comments AS c ON p.Id = c.PostId
    LEFT JOIN PostHistory AS ph ON p.Id = ph.PostId
    LEFT JOIN PostLinks AS pl ON p.Id = pl.PostId AND pl.LinkTypeId = 3
    LEFT JOIN PostLinks AS pl_dup ON p.Id = pl_dup.RelatedPostId AND pl_dup.LinkTypeId = 3
    GROUP BY p.Id, p.OwnerUserId
)
SELECT
    ua.UserId,
    ua.DisplayName,
    ua.Reputation,
    ua.UserLocation,
    ua.AboutMeCategory,
    rtc.Tag AS TopContributingTag,
    rtc.TotalTagScore,
    rtc.PostsInTag,
    rtc.AvgTagPostScore,
    rtc.OverallTagContributionNtile,
    tpt.PostId AS TopPostIdInTag,
    tpt.PostTypeId AS TopPostTypeInTag,
    tpt.PostScore AS TopPostScoreInTag,
    tpt.ViewCount AS TopPostViewCount,
    tpt.Title AS TopPostTitle,
    tpt.ShortBody AS TopPostSnippet,
    ROUND(CAST(tpt.PostScore AS NUMERIC) / NULLIF(CAST(tpt.ViewCount AS NUMERIC), 0), 4) AS TopPostScorePerView,
    pda.UpvotesCount AS TopPostUpvotes,
    pda.DownvotesCount AS TopPostDownvotes,
    pda.FavoriteVotesCount AS TopPostFavorites,
    pda.AvgCommentScore AS TopPostAvgCommentScore,
    pda.CommentCountActual AS TopPostActualCommentCount,
    pda.EditHistoryCount AS TopPostEditHistoryCount,
    pda.CloseVotes AS TopPostCloseVotes,
    pda.LastCloseReasonComment AS TopPostLastCloseReason,
    pda.IsDuplicateSource AS TopPostIsDuplicateSource,
    pda.DuplicateLinksReferringHereCount AS TopPostDuplicateTargets,
    pda.GoldBadgesForOwner,
    ua.QuestionCount AS TotalQuestionsByOwner,
    ua.AnswerCount AS TotalAnswersByOwner,
    ua.TotalPostHistoryEvents AS OwnerTotalHistoryEvents,
    ua.TotalEditOrRollbackEvents AS OwnerTotalEditAndRollbackEvents,
    ROUND(CAST(EXTRACT(EPOCH FROM (ua.LastAccessDate - ua.UserCreationDate)) / 3600.0 / 24.0 AS NUMERIC), 2) AS UserTenureDays,
    ROUND(CAST(EXTRACT(EPOCH FROM (CAST('2024-10-01 12:34:56' AS TIMESTAMP) - tpt.LastActivityDate)) / 3600.0 / 24.0 AS NUMERIC), 2) AS DaysSinceTopPostActivity,
    COALESCE(ua.LastGoldBadgeDate, CAST('1900-01-01' AS TIMESTAMP)) AS LastGoldBadgeAward,
    (
        SELECT
            COALESCE(SUM(t2.Count), 0)
        FROM Tags AS t2
        WHERE t2.TagName IN (
            SELECT t3.Tag
            FROM TagSpecificUserContributions AS t3
            WHERE t3.UserId = ua.UserId
              AND t3.Tag != rtc.Tag
            ORDER BY t3.TotalTagScore DESC
            LIMIT 1
        )
    ) AS OtherTopTagGlobalQuestionCount,
    (
        SELECT AVG(u_overall.Reputation)
        FROM Users AS u_overall
        WHERE u_overall.CreationDate >= (SELECT MIN(u4.CreationDate) FROM Users u4 WHERE u4.Reputation > 1000)
    ) AS GlobalAvgExperiencedUserReputation,
    (
        SELECT AVG(p_overall.Score)
        FROM Posts AS p_overall
        WHERE p_overall.PostTypeId = 1
          AND p_overall.CreationDate >= (CAST('2024-10-01 12:34:56' AS TIMESTAMP) - INTERVAL '1 year')
    ) AS GlobalAvgRecentQuestionScore,
    (
        SELECT
            CONCAT(
                MAX(ph_sub.PostHistoryTypeId), ':',
                COALESCE(MAX(cr.Name), COALESCE(MAX(ph_sub.Comment), 'N/A'))
            )
        FROM PostHistory AS ph_sub
        LEFT JOIN CloseReasonTypes AS cr ON ph_sub.PostHistoryTypeId = 10 AND ph_sub.Comment = CAST(cr.Id AS TEXT)
        WHERE ph_sub.PostId = tpt.PostId
          AND ph_sub.UserId = ua.UserId
          AND ph_sub.PostHistoryTypeId IN (1, 2, 3, 4, 5, 6, 10, 11, 12, 13)
        GROUP BY ph_sub.PostId, ph_sub.UserId
        ORDER BY MAX(ph_sub.CreationDate) DESC
        LIMIT 1
    ) AS LatestRelevantHistoryForTopPost,
    CASE
        WHEN ua.Reputation > (SELECT AVG(Reputation) * 2.5 FROM Users) AND rtc.TotalTagScore > 1000 THEN 'Legendary Contributor'
        WHEN ua.Reputation > (SELECT AVG(Reputation) * 1.5 FROM Users) AND rtc.TotalTagScore > 250 THEN 'Highly Valued Contributor'
        WHEN ua.Reputation > (SELECT AVG(Reputation) FROM Users) THEN 'Above Average Contributor'
        ELSE 'Active Contributor'
    END AS ContributorTier,
    CASE
        WHEN tpt.PostTypeId = 1 AND tpt.AnswerCount > 0 AND pda.HasAcceptedAnswer = 1 THEN 'Question with Accepted Answer'
        WHEN tpt.PostTypeId = 1 AND tpt.AnswerCount > 0 AND pda.HasAcceptedAnswer = 0 THEN 'Question with Unaccepted Answers'
        WHEN tpt.PostTypeId = 1 AND tpt.AnswerCount = 0 AND pda.CloseVotes = 0 THEN 'Unanswered Question'
        WHEN tpt.PostTypeId = 2 AND tpt.PostScore >= 10 AND pda.FavoriteVotesCount >= 1 THEN 'Highly Rated Answer'
        WHEN tpt.PostTypeId = 2 AND tpt.PostScore > 0 THEN 'Positive Answer'
        ELSE 'Other Notable Post'
    END AS TopPostCategory,
    LAG(rtc.TotalTagScore, 1, 0) OVER (PARTITION BY rtc.UserId ORDER BY rtc.TagRankForUser) AS ScoreOfSecondTopTag,
    LEAD(rtc.TotalTagScore, 1, 0) OVER (PARTITION BY rtc.UserId ORDER BY rtc.TagRankForUser) AS ScoreOfThirdTopTag
FROM UserOverallActivity AS ua
INNER JOIN RankedTagContributions AS rtc ON ua.UserId = rtc.UserId
INNER JOIN TopPostsPerTagUser AS tpt ON ua.UserId = tpt.UserId AND rtc.Tag = tpt.Tag
LEFT JOIN PostDetailAggregates AS pda ON tpt.PostId = pda.PostId
WHERE rtc.TagRankForUser = 1
  AND tpt.RankInTagUser = 1
  AND ua.Reputation > (SELECT AVG(Reputation) FROM Users WHERE CreationDate >= (CAST('2024-10-01 12:34:56' AS TIMESTAMP) - INTERVAL '5 year'))
  AND ua.ProfileViews > 500
  AND pda.EditHistoryCount > 0
  AND tpt.PostCreationDate >= (CAST('2024-10-01 12:34:56' AS TIMESTAMP) - INTERVAL '3 year')
  AND tpt.ViewCount > 500
ORDER BY ua.Reputation DESC, rtc.TotalTagScore DESC, tpt.PostScore DESC
LIMIT 2000;