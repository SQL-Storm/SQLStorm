WITH UserEngagement AS (
    SELECT
        u.Id AS UserId,
        u.DisplayName,
        u.Reputation,
        u.CreationDate AS UserCreationDate,
        u.LastAccessDate,
        u.WebsiteUrl,
        u.Location,
        u.Views AS UserProfileViews,
        u.UpVotes AS UserUpVotesGiven,
        u.DownVotes AS UserDownVotesGiven,
        COUNT(DISTINCT p.Id) AS TotalPostsOwned,
        SUM(CASE WHEN p.PostTypeId = 1 THEN 1 ELSE 0 END) AS TotalQuestionsOwned,
        SUM(CASE WHEN p.PostTypeId = 2 THEN 1 ELSE 0 END) AS TotalAnswersOwned,
        COUNT(DISTINCT c.Id) AS TotalCommentsMade,
        COUNT(DISTINCT v.Id) AS TotalVotesCast,
        SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS UpVotesCastByUserId,
        SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS DownVotesCastByUserId,
        MAX(COALESCE(p.LastActivityDate, c.CreationDate, v.CreationDate, u.LastAccessDate)) AS LatestActivityGlobally
    FROM
        Users u
    LEFT JOIN Posts p ON u.Id = p.OwnerUserId
    LEFT JOIN Comments c ON u.Id = c.UserId
    LEFT JOIN Votes v ON u.Id = v.UserId
    GROUP BY
        u.Id, u.DisplayName, u.Reputation, u.CreationDate, u.LastAccessDate, u.WebsiteUrl, u.Location, u.Views, u.UpVotes, u.DownVotes
),
PostDetailsAndHistory AS (
    SELECT
        p.Id AS PostId,
        p.OwnerUserId,
        p.PostTypeId,
        p.CreationDate AS PostCreationDate,
        p.Score AS PostScore,
        p.ViewCount AS PostViewCount,
        p.AnswerCount,
        p.CommentCount AS PostCommentCount,
        p.FavoriteCount,
        p.ClosedDate,
        p.LastEditDate,
        p.LastActivityDate,
        p.Title,
        p.Tags,
        CASE WHEN p.Tags IS NULL OR LENGTH(p.Tags) <= 2 THEN 0
             ELSE (
                 SELECT COUNT(*) FROM (
                     SELECT TRIM(x.tag) AS t FROM (
                         SELECT UNNEST(STRING_TO_ARRAY(SUBSTRING(p.Tags FROM 2 FOR (LENGTH(p.Tags)-2)), '><')) AS tag
                     ) AS x
                 ) sub
             )
        END AS NumberOfTags,
        SUM(CASE WHEN ph.PostHistoryTypeId IN (4, 5, 6, 7, 8, 9) THEN 1 ELSE 0 END) AS TotalEditEvents,
        SUM(CASE WHEN ph.PostHistoryTypeId = 10 THEN 1 ELSE 0 END) AS TotalCloseEvents,
        SUM(CASE WHEN ph.PostHistoryTypeId = 11 THEN 1 ELSE 0 END) AS TotalReopenEvents,
        MAX(CASE WHEN ph.UserId = p.OwnerUserId AND ph.PostHistoryTypeId IN (4,5,6) THEN 1 ELSE 0 END) = 1 AS EditedByOwnerFlag,
        (SELECT COUNT(pl.RelatedPostId) FROM PostLinks pl WHERE pl.PostId = p.Id AND pl.LinkTypeId = 1) AS LinkedPostsOutCount,
        (SELECT COUNT(pl.RelatedPostId) FROM PostLinks pl WHERE pl.PostId = p.Id AND pl.LinkTypeId = 3) AS DuplicatePostsOutCount
    FROM
        Posts p
    LEFT JOIN PostHistory ph ON p.Id = ph.PostId
    WHERE
        p.PostTypeId IN (1, 2)
        AND p.OwnerUserId IS NOT NULL
    GROUP BY
        p.Id, p.OwnerUserId, p.PostTypeId, p.CreationDate, p.Score, p.ViewCount, p.AnswerCount, p.CommentCount, p.FavoriteCount, p.ClosedDate, p.LastEditDate, p.LastActivityDate, p.Title, p.Tags
),
UserPostAggregates AS (
    SELECT
        pdh.OwnerUserId AS UserId,
        COUNT(DISTINCT pdh.PostId) AS TotalAnalyzedPosts,
        SUM(pdh.PostScore) AS TotalPostsScoreSum,
        AVG(pdh.PostScore) AS AveragePostScore,
        MAX(pdh.PostViewCount) AS MaxPostViewCount,
        SUM(pdh.AnswerCount) AS TotalAnswersOnQuestions,
        AVG(pdh.AnswerCount) AS AvgAnswersOnQuestions,
        SUM(pdh.TotalEditEvents) AS TotalPostEditEvents,
        SUM(pdh.TotalCloseEvents) AS TotalPostCloseEvents,
        SUM(pdh.TotalReopenEvents) AS TotalPostReopenEvents,
        SUM(CASE WHEN pdh.EditedByOwnerFlag THEN 1 ELSE 0 END) AS PostsEditedByOwnerCount,
        COUNT(DISTINCT t.TagName) AS UniqueTagsUsedInQuestions,
        SUM(pdh.LinkedPostsOutCount) AS TotalLinkedPostsOutgoing,
        SUM(pdh.DuplicatePostsOutCount) AS TotalDuplicatePostsOutgoing
    FROM
        PostDetailsAndHistory pdh
    LEFT JOIN (
        SELECT
            pdh_inner.PostId,
            tag AS TagName
        FROM PostDetailsAndHistory pdh_inner,
             LATERAL (
                 SELECT UNNEST(STRING_TO_ARRAY(SUBSTRING(pdh_inner.Tags FROM 2 FOR (LENGTH(pdh_inner.Tags)-2)), '><')) AS tag
             ) s
        WHERE pdh_inner.PostTypeId = 1 AND pdh_inner.Tags IS NOT NULL AND LENGTH(pdh_inner.Tags) > 2
    ) t ON pdh.PostId = t.PostId
    GROUP BY
        pdh.OwnerUserId
),
UserBadgeSummary AS (
    SELECT
        b.UserId,
        COUNT(b.Id) AS TotalBadgesEarned,
        SUM(CASE WHEN b.Class = 1 THEN 1 ELSE 0 END) AS GoldBadgesCount,
        SUM(CASE WHEN b.Class = 2 THEN 1 ELSE 0 END) AS SilverBadgesCount,
        SUM(CASE WHEN b.Class = 3 THEN 1 ELSE 0 END) AS BronzeBadgesCount,
        MAX(b.Date) AS LastBadgeAwardDate
    FROM
        Badges b
    GROUP BY
        b.UserId
),
CombinedUserData AS (
    SELECT
        ue.UserId,
        ue.DisplayName,
        ue.Reputation,
        ue.UserCreationDate,
        ue.LastAccessDate,
        ue.WebsiteUrl,
        ue.Location,
        ue.UserProfileViews,
        ue.UserUpVotesGiven,
        ue.UserDownVotesGiven,
        ue.TotalPostsOwned,
        ue.TotalQuestionsOwned,
        ue.TotalAnswersOwned,
        ue.TotalCommentsMade,
        ue.TotalVotesCast,
        ue.UpVotesCastByUserId,
        ue.DownVotesCastByUserId,
        ue.LatestActivityGlobally,
        COALESCE(upa.TotalAnalyzedPosts, 0) AS TotalAnalyzedPosts,
        COALESCE(upa.TotalPostsScoreSum, 0) AS TotalPostsScoreSum,
        COALESCE(upa.AveragePostScore, 0.0) AS AveragePostScore,
        COALESCE(upa.MaxPostViewCount, 0) AS MaxPostViewCount,
        COALESCE(upa.TotalAnswersOnQuestions, 0) AS TotalAnswersOnQuestions,
        COALESCE(upa.AvgAnswersOnQuestions, 0.0) AS AvgAnswersOnQuestions,
        COALESCE(upa.TotalPostEditEvents, 0) AS TotalPostEditEvents,
        COALESCE(upa.TotalPostCloseEvents, 0) AS TotalPostCloseEvents,
        COALESCE(upa.TotalPostReopenEvents, 0) AS TotalPostReopenEvents,
        COALESCE(upa.PostsEditedByOwnerCount, 0) AS PostsEditedByOwnerCount,
        COALESCE(upa.UniqueTagsUsedInQuestions, 0) AS UniqueTagsUsedInQuestions,
        COALESCE(upa.TotalLinkedPostsOutgoing, 0) AS TotalLinkedPostsOutgoing,
        COALESCE(upa.TotalDuplicatePostsOutgoing, 0) AS TotalDuplicatePostsOutgoing,
        COALESCE(ubs.TotalBadgesEarned, 0) AS TotalBadgesEarned,
        COALESCE(ubs.GoldBadgesCount, 0) AS GoldBadgesCount,
        COALESCE(ubs.SilverBadgesCount, 0) AS SilverBadgesCount,
        COALESCE(ubs.BronzeBadgesCount, 0) AS BronzeBadgesCount,
        ubs.LastBadgeAwardDate,
        (ue.Reputation * 0.15) + (ue.TotalPostsOwned * 0.7) + (ue.TotalCommentsMade * 0.25) +
        (COALESCE(upa.AveragePostScore, 0) * 0.9) + (COALESCE(upa.UniqueTagsUsedInQuestions, 0) * 0.4) +
        (COALESCE(ubs.GoldBadgesCount, 0) * 10) + (COALESCE(ubs.SilverBadgesCount, 0) * 4) + (COALESCE(ubs.BronzeBadgesCount, 0) * 1) +
        (EXTRACT(EPOCH FROM (TIMESTAMP '2024-10-01 12:34:56' - ue.UserCreationDate)) / 31536000.0 * 0.01)
        AS ActivityScore
    FROM
        UserEngagement ue
    LEFT JOIN UserPostAggregates upa ON ue.UserId = upa.UserId
    LEFT JOIN UserBadgeSummary ubs ON ue.UserId = ubs.UserId
),
RankedUserData AS (
    SELECT
        cud.UserId,
        cud.DisplayName,
        cud.Reputation,
        cud.UserCreationDate,
        cud.LastAccessDate,
        cud.WebsiteUrl,
        cud.Location,
        cud.UserProfileViews,
        cud.UserUpVotesGiven,
        cud.UserDownVotesGiven,
        cud.TotalPostsOwned,
        cud.TotalQuestionsOwned,
        cud.TotalAnswersOwned,
        cud.TotalCommentsMade,
        cud.TotalVotesCast,
        cud.UpVotesCastByUserId,
        cud.DownVotesCastByUserId,
        cud.LatestActivityGlobally,
        cud.TotalAnalyzedPosts,
        cud.TotalPostsScoreSum,
        cud.AveragePostScore,
        cud.MaxPostViewCount,
        cud.TotalAnswersOnQuestions,
        cud.AvgAnswersOnQuestions,
        cud.TotalPostEditEvents,
        cud.TotalPostCloseEvents,
        cud.TotalPostReopenEvents,
        cud.PostsEditedByOwnerCount,
        cud.UniqueTagsUsedInQuestions,
        cud.TotalLinkedPostsOutgoing,
        cud.TotalDuplicatePostsOutgoing,
        cud.TotalBadgesEarned,
        cud.GoldBadgesCount,
        cud.SilverBadgesCount,
        cud.BronzeBadgesCount,
        cud.LastBadgeAwardDate,
        cud.ActivityScore,
        RANK() OVER (ORDER BY cud.ActivityScore DESC, cud.Reputation DESC, cud.LatestActivityGlobally DESC) AS OverallActivityRank,
        AVG(cud.ActivityScore) OVER (PARTITION BY FLOOR(cud.Reputation / 5000) * 5000) AS AvgActivityScoreInRepTier,
        LAG(cud.ActivityScore, 1, 0.0) OVER (ORDER BY cud.ActivityScore DESC) AS PreviousRankActivityScore,
        DENSE_RANK() OVER (PARTITION BY EXTRACT(YEAR FROM cud.UserCreationDate) ORDER BY cud.GoldBadgesCount DESC, cud.SilverBadgesCount DESC, cud.BronzeBadgesCount DESC) AS BadgeRankWithinCreationYear
    FROM
        CombinedUserData cud
    WHERE
        cud.TotalPostsOwned > 0 OR cud.TotalCommentsMade > 0 OR cud.TotalVotesCast > 0 OR cud.TotalBadgesEarned > 0
)
SELECT
    rud.UserId,
    rud.DisplayName,
    rud.Reputation,
    rud.OverallActivityRank,
    rud.ActivityScore,
    rud.TotalPostsOwned,
    rud.TotalCommentsMade,
    rud.TotalBadgesEarned,
    rud.GoldBadgesCount,
    rud.SilverBadgesCount,
    rud.BronzeBadgesCount,
    rud.LatestActivityGlobally,
    rud.AvgActivityScoreInRepTier,
    rud.TotalPostCloseEvents,
    rud.TotalPostReopenEvents,
    rud.TotalLinkedPostsOutgoing,
    rud.UniqueTagsUsedInQuestions,
    rud.Location,
    rud.WebsiteUrl,
    rud.PreviousRankActivityScore,
    rud.BadgeRankWithinCreationYear,
    COALESCE(
        CASE
            WHEN rud.WebsiteUrl IS NOT NULL AND LENGTH(rud.WebsiteUrl) > 8 AND rud.WebsiteUrl LIKE 'http%'
                THEN 'Web: ' || UPPER(SUBSTRING(rud.WebsiteUrl FROM POSITION('//' IN rud.WebsiteUrl) + 2 FOR 5)) || '...'
            WHEN rud.Location IS NOT NULL AND LENGTH(rud.Location) > 5
                THEN 'Loc: ' || INITCAP(SUBSTRING(rud.Location FROM 1 FOR 8)) || '...'
            ELSE 'No Public Contact Info'
        END,
        'Info Not Available'
    ) AS FormattedContactInfo
FROM
    RankedUserData rud
WHERE
    rud.OverallActivityRank <= 250
    AND rud.Reputation > 5000
    AND rud.LatestActivityGlobally >= (TIMESTAMP '2024-10-01 12:34:56' - INTERVAL '6 months')
    AND (rud.UniqueTagsUsedInQuestions > 10 OR rud.TotalPostEditEvents > 20)
    AND (rud.Location IS NOT NULL OR rud.WebsiteUrl IS NOT NULL)
    AND NOT EXISTS (
        SELECT 1 FROM Posts p_check WHERE p_check.OwnerUserId = rud.UserId AND p_check.ClosedDate IS NOT NULL AND p_check.PostTypeId = 1
        GROUP BY p_check.OwnerUserId HAVING COUNT(p_check.Id) > 5
    )

UNION ALL

SELECT
    rud.UserId,
    rud.DisplayName,
    rud.Reputation,
    rud.OverallActivityRank,
    rud.ActivityScore,
    rud.TotalPostsOwned,
    rud.TotalCommentsMade,
    rud.TotalBadgesEarned,
    rud.GoldBadgesCount,
    rud.SilverBadgesCount,
    rud.BronzeBadgesCount,
    rud.LatestActivityGlobally,
    rud.AvgActivityScoreInRepTier,
    rud.TotalPostCloseEvents,
    rud.TotalPostReopenEvents,
    rud.TotalLinkedPostsOutgoing,
    rud.UniqueTagsUsedInQuestions,
    rud.Location,
    rud.WebsiteUrl,
    rud.PreviousRankActivityScore,
    rud.BadgeRankWithinCreationYear,
    COALESCE(
        CASE
            WHEN rud.WebsiteUrl IS NOT NULL AND LENGTH(rud.WebsiteUrl) > 8 AND rud.WebsiteUrl LIKE 'http%'
                THEN 'Web: ' || UPPER(SUBSTRING(rud.WebsiteUrl FROM POSITION('//' IN rud.WebsiteUrl) + 2 FOR 5)) || '...'
            WHEN rud.Location IS NOT NULL AND LENGTH(rud.Location) > 5
                THEN 'Loc: ' || INITCAP(SUBSTRING(rud.Location FROM 1 FOR 8)) || '...'
            ELSE 'No Public Contact Info'
        END,
        'Info Not Available'
    ) AS FormattedContactInfo
FROM
    RankedUserData rud
WHERE
    rud.LastBadgeAwardDate >= (TIMESTAMP '2024-10-01 12:34:56' - INTERVAL '3 months')
    AND rud.GoldBadgesCount > 0
    AND rud.Reputation BETWEEN 1000 AND 10000
    AND rud.TotalQuestionsOwned > 0
    AND EXISTS (
        SELECT 1
        FROM Posts p_inner
        JOIN (
            SELECT
                p_inner2.Id AS PostId,
                tag AS TagName
            FROM Posts p_inner2,
                 LATERAL (
                     SELECT UNNEST(STRING_TO_ARRAY(SUBSTRING(p_inner2.Tags FROM 2 FOR (LENGTH(p_inner2.Tags)-2)), '><')) AS tag
                 ) s
            WHERE p_inner2.PostTypeId = 1 AND p_inner2.Tags IS NOT NULL AND LENGTH(p_inner2.Tags) > 2
        ) t_inner ON p_inner.Id = t_inner.PostId
        WHERE p_inner.OwnerUserId = rud.UserId
          AND (
              LOWER(t_inner.TagName) LIKE '%java%' OR
              LOWER(t_inner.TagName) LIKE '%python%' OR
              LOWER(t_inner.TagName) LIKE '%javascript%' OR
              LOWER(t_inner.TagName) LIKE '%c#%' OR
              LOWER(t_inner.TagName) LIKE '%node.js%' OR
              LOWER(t_inner.TagName) LIKE '%react%'
          )
    )
ORDER BY
    OverallActivityRank ASC, LatestActivityGlobally DESC, ActivityScore DESC
LIMIT 1000;