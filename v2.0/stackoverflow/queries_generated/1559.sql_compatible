WITH UserActivitySummary AS (
    SELECT
        u.Id AS UserId,
        u.DisplayName,
        u.Reputation,
        u.CreationDate AS UserCreationDate,
        u.LastAccessDate,
        u.Location,
        u.Views AS UserProfileViews,
        u.UpVotes AS UserUpVotes,
        u.DownVotes AS UserDownVotes,
        COUNT(DISTINCT p.Id) AS TotalPostsOwned,
        COUNT(DISTINCT CASE WHEN p.PostTypeId = 1 THEN p.Id END) AS TotalQuestionsOwned,
        COUNT(DISTINCT CASE WHEN p.PostTypeId = 2 THEN p.Id END) AS TotalAnswersOwned,
        AVG(CASE WHEN p.Score IS NOT NULL THEN p.Score ELSE 0 END) AS AvgPostScoreOwned,
        MAX(p.LastActivityDate) AS LastPostActivityDate,
        COUNT(DISTINCT b.Id) AS TotalBadges,
        SUM(CASE WHEN b.Class = 1 THEN 1 ELSE 0 END) AS GoldBadges,
        SUM(CASE WHEN b.TagBased = TRUE THEN 1 ELSE 0 END) AS TagBasedBadges,
        FLOOR(EXTRACT(EPOCH FROM (u.LastAccessDate - u.CreationDate)) / 86400) AS DaysSinceCreation
    FROM Users AS u
    LEFT JOIN Posts AS p ON u.Id = p.OwnerUserId
    LEFT JOIN Badges AS b ON u.Id = b.UserId
    WHERE
        u.Reputation >= 10000
        AND u.CreationDate BETWEEN TIMESTAMP '2015-01-01' AND TIMESTAMP '2020-01-01'
        AND u.Location IS NOT NULL
        AND LOWER(u.Location) NOT LIKE '%internet%'
        AND u.DisplayName IS NOT NULL
    GROUP BY
        u.Id, u.DisplayName, u.Reputation, u.CreationDate, u.LastAccessDate,
        u.Location, u.Views, u.UpVotes, u.DownVotes
),
PostEngagementMetrics AS (
    SELECT
        p.Id AS PostId,
        p.OwnerUserId,
        p.PostTypeId,
        p.CreationDate AS PostCreationDate,
        p.Score AS PostScore,
        p.ViewCount,
        p.AnswerCount,
        p.CommentCount,
        p.FavoriteCount,
        p.LastEditDate,
        p.LastActivityDate,
        p.Title,
        p.Tags,
        p.AcceptedAnswerId,
        COALESCE((SELECT SUM(c.Score) FROM Comments AS c WHERE c.PostId = p.Id), 0) AS TotalCommentScore,
        COALESCE((SELECT COUNT(DISTINCT ph.Id) FROM PostHistory AS ph WHERE ph.PostId = p.Id AND ph.PostHistoryTypeId IN (4, 5, 6, 7, 8, 9)), 0) AS EditCount,
        COALESCE((SELECT COUNT(DISTINCT ph.Id) FROM PostHistory AS ph WHERE ph.PostId = p.Id AND ph.PostHistoryTypeId IN (10, 11)), 0) AS CloseReopenCount,
        COALESCE((SELECT COUNT(DISTINCT v.UserId) FROM Votes AS v WHERE v.PostId = p.Id AND v.VoteTypeId IN (2, 3)), 0) AS UniqueVoterCount,
        AGE(p.LastActivityDate, p.CreationDate) AS PostActivityDuration,
        COALESCE(p.FavoriteCount, 0) AS CoalescedFavoriteCount,
        CASE
            WHEN p.ClosedDate IS NOT NULL AND p.CommunityOwnedDate IS NOT NULL THEN 'ClosedAndCommunityWiki'
            WHEN p.ClosedDate IS NOT NULL THEN 'Closed'
            WHEN p.CommunityOwnedDate IS NOT NULL THEN 'CommunityWiki'
            ELSE 'Open'
        END AS PostStatus
    FROM Posts AS p
    WHERE p.PostTypeId IN (1, 2)
      AND p.CreationDate BETWEEN TIMESTAMP '2016-01-01' AND TIMESTAMP '2022-01-01'
      AND p.Score > 5
),
CalculatedPostScores AS (
    SELECT
        pem.PostId,
        pem.OwnerUserId,
        pem.PostTypeId,
        pem.PostCreationDate,
        pem.PostScore,
        pem.ViewCount,
        pem.AnswerCount,
        pem.CommentCount,
        pem.FavoriteCount,
        pem.LastEditDate,
        pem.LastActivityDate,
        pem.Title,
        pem.Tags,
        pem.AcceptedAnswerId,
        pem.TotalCommentScore,
        pem.EditCount,
        pem.CloseReopenCount,
        pem.UniqueVoterCount,
        pem.PostActivityDuration,
        pem.CoalescedFavoriteCount,
        pem.PostStatus,
        uas.DisplayName AS OwnerDisplayName,
        uas.Reputation AS OwnerReputation,
        (
            (pem.PostScore * 0.7) +
            (COALESCE(pem.ViewCount, 0) * 0.005) +
            (COALESCE(pem.AnswerCount, 0) * 0.1) +
            (pem.CoalescedFavoriteCount * 0.2) +
            (pem.EditCount * 5) +
            (pem.CloseReopenCount * 15) +
            (pem.TotalCommentScore * 0.05) +
            (CASE WHEN pem.AcceptedAnswerId IS NOT NULL THEN 100 ELSE 0 END) +
            (pem.UniqueVoterCount * 3) +
            (CASE WHEN pem.Tags IS NOT NULL THEN (LENGTH(pem.Tags) - LENGTH(REPLACE(pem.Tags, '><', '')) + 1) * 2 ELSE 0 END)
        ) AS PostImpactScore,
        LAG(pem.PostScore, 1, 0) OVER (PARTITION BY pem.OwnerUserId ORDER BY pem.PostCreationDate) AS PreviousPostScore,
        ROW_NUMBER() OVER (PARTITION BY pem.OwnerUserId ORDER BY
            (
                (pem.PostScore * 0.7) +
                (COALESCE(pem.ViewCount, 0) * 0.005) +
                (COALESCE(pem.AnswerCount, 0) * 0.1) +
                (pem.CoalescedFavoriteCount * 0.2) +
                (pem.EditCount * 5) +
                (pem.CloseReopenCount * 15) +
                (pem.TotalCommentScore * 0.05) +
                (CASE WHEN pem.AcceptedAnswerId IS NOT NULL THEN 100 ELSE 0 END) +
                (pem.UniqueVoterCount * 3) +
                (CASE WHEN pem.Tags IS NOT NULL THEN (LENGTH(pem.Tags) - LENGTH(REPLACE(pem.Tags, '><', '')) + 1) * 2 ELSE 0 END)
            ) DESC,
            pem.ViewCount DESC
        ) AS Rnk_PostImpactPerUser,
        NTILE(10) OVER (ORDER BY
            (
                (pem.PostScore * 0.7) +
                (COALESCE(pem.ViewCount, 0) * 0.005) +
                (COALESCE(pem.AnswerCount, 0) * 0.1) +
                (pem.CoalescedFavoriteCount * 0.2) +
                (pem.EditCount * 5) +
                (pem.CloseReopenCount * 15) +
                (pem.TotalCommentScore * 0.05) +
                (CASE WHEN pem.AcceptedAnswerId IS NOT NULL THEN 100 ELSE 0 END) +
                (pem.UniqueVoterCount * 3) +
                (CASE WHEN pem.Tags IS NOT NULL THEN (LENGTH(pem.Tags) - LENGTH(REPLACE(pem.Tags, '><', '')) + 1) * 2 ELSE 0 END)
            ) DESC
        ) AS PostImpactDecile
    FROM PostEngagementMetrics AS pem
    INNER JOIN UserActivitySummary AS uas ON pem.OwnerUserId = uas.UserId
),
UserContributionSummary AS (
    SELECT
        uas.UserId,
        uas.DisplayName,
        uas.Reputation,
        uas.UserCreationDate,
        uas.Location,
        uas.TotalBadges,
        uas.GoldBadges,
        uas.TagBasedBadges,
        uas.TotalPostsOwned,
        uas.TotalQuestionsOwned,
        uas.TotalAnswersOwned,
        SUM(cps.PostImpactScore) AS AggregateUserPostImpact,
        AVG(cps.PostImpactScore) AS AvgUserPostImpact,
        (
            uas.Reputation * 0.3 +
            uas.UserProfileViews * 0.005 +
            uas.UserUpVotes * 0.1 +
            uas.TotalBadges * 10 +
            (SUM(cps.PostImpactScore) * 0.02) +
            (uas.TotalQuestionsOwned * 25) +
            (uas.TotalAnswersOwned * 20) +
            (uas.DaysSinceCreation * 0.5)
        ) AS UserOverallContributionScore,
        RANK() OVER (ORDER BY
            (
                uas.Reputation * 0.3 + uas.UserProfileViews * 0.005 + uas.UserUpVotes * 0.1 +
                uas.TotalBadges * 10 + (SUM(cps.PostImpactScore) * 0.02) +
                (uas.TotalQuestionsOwned * 25) + (uas.TotalAnswersOwned * 20) +
                (uas.DaysSinceCreation * 0.5)
            ) DESC
        ) AS Rank_OverallUser,
        NTILE(5) OVER (ORDER BY
            (
                uas.Reputation * 0.3 + uas.UserProfileViews * 0.005 + uas.UserUpVotes * 0.1 +
                uas.TotalBadges * 10 + (SUM(cps.PostImpactScore) * 0.02) +
                (uas.TotalQuestionsOwned * 25) + (uas.TotalAnswersOwned * 20) +
                (uas.DaysSinceCreation * 0.5)
            ) DESC
        ) AS UserContributionQuintile
    FROM UserActivitySummary AS uas
    INNER JOIN CalculatedPostScores AS cps ON uas.UserId = cps.OwnerUserId
    WHERE cps.Rnk_PostImpactPerUser <= 5
    GROUP BY
        uas.UserId, uas.DisplayName, uas.Reputation, uas.UserCreationDate, uas.Location,
        uas.TotalBadges, uas.GoldBadges, uas.TagBasedBadges, uas.TotalPostsOwned,
        uas.TotalQuestionsOwned, uas.TotalAnswersOwned, uas.UserProfileViews, uas.UserUpVotes, uas.DaysSinceCreation
)
SELECT
    ucs.DisplayName AS User_DisplayName,
    ucs.Reputation AS User_Reputation,
    ucs.Location AS User_Location,
    ucs.UserCreationDate,
    ucs.TotalBadges,
    ucs.GoldBadges,
    ucs.TagBasedBadges,
    ucs.TotalQuestionsOwned,
    ucs.TotalAnswersOwned,
    ucs.UserOverallContributionScore,
    ucs.Rank_OverallUser,
    ucs.UserContributionQuintile,
    cps.Title AS Post_Title,
    cps.PostTypeId AS Post_Type,
    cps.PostCreationDate,
    cps.PostScore AS Post_Score,
    cps.ViewCount AS Post_ViewCount,
    cps.AnswerCount AS Post_AnswerCount,
    cps.CoalescedFavoriteCount AS Post_FavoriteCount,
    cps.EditCount AS Post_EditCount,
    cps.CloseReopenCount AS Post_CloseReopenCount,
    cps.UniqueVoterCount AS Post_UniqueVoterCount,
    cps.PostImpactScore,
    cps.Rnk_PostImpactPerUser,
    cps.PostImpactDecile,
    (SELECT t.TagName FROM Tags AS t WHERE t.TagName = SUBSTRING(cps.Tags FROM 2 FOR (POSITION('>' IN cps.Tags) - 2)) LIMIT 1) AS PrimaryTag,
    CASE WHEN cps.PostStatus LIKE '%Closed%' THEN TRUE ELSE FALSE END AS IsClosed,
    COALESCE(pl.LinkTypeId, 0) AS RelatedLinkType,
    COALESCE(pl.RelatedPostId, -1) AS RelatedPostId,
    (SELECT AVG(s.Score) FROM Comments AS s WHERE s.PostId = cps.PostId AND s.CreationDate BETWEEN cps.PostCreationDate AND cps.LastActivityDate) AS AvgCommentScoreForPost
FROM UserContributionSummary AS ucs
INNER JOIN CalculatedPostScores AS cps ON ucs.UserId = cps.OwnerUserId
LEFT JOIN (
    SELECT DISTINCT ON (PostId) PostId, RelatedPostId, LinkTypeId
    FROM PostLinks
    WHERE LinkTypeId IN (1, 3)
) AS pl ON cps.PostId = pl.PostId
WHERE
    cps.Rnk_PostImpactPerUser <= 3
    AND ucs.UserContributionQuintile <= 2
    AND (
        cps.Tags ILIKE '%<sql>%' OR
        cps.Tags ILIKE '%<database>%' OR
        cps.Tags ILIKE '%<performance>%' OR
        cps.Tags ILIKE '%<optimization>%'
    )
    AND ucs.DisplayName IS NOT NULL
    AND cps.Title IS NOT NULL
    AND cps.PostActivityDuration IS NOT NULL
ORDER BY
    ucs.UserOverallContributionScore DESC,
    ucs.DisplayName ASC,
    cps.PostImpactScore DESC;