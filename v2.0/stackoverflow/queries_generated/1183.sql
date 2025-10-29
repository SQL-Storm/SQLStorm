-- {"query": "1183.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-flash", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 2446} 

WITH UserEngagement AS (
    SELECT
        u.Id AS UserId,
        u.DisplayName,
        u.Reputation,
        u.CreationDate AS UserCreationDate,
        u.LastAccessDate,
        u.UpVotes,
        u.DownVotes,
        u.Views AS UserProfileViews,
        b.GoldBadges,
        b.SilverBadges,
        b.BronzeBadges,
        b.TotalBadges,
        AGE(u.LastAccessDate, u.CreationDate) AS AccountAgeInterval,
        EXTRACT(EPOCH FROM (u.LastAccessDate - u.CreationDate)) / 86400.0 AS AccountAgeDays, -- in days, as decimal
        (u.UpVotes - u.DownVotes) AS NetVotesGiven,
        CASE
            WHEN u.Reputation >= 100000 THEN 'Legendary'
            WHEN u.Reputation >= 25000 THEN 'Guru'
            WHEN u.Reputation >= 5000 THEN 'Expert'
            WHEN u.Reputation >= 1000 THEN 'Advanced'
            ELSE 'Novice'
        END AS ReputationTier,
        NTILE(5) OVER (ORDER BY u.Reputation DESC, u.LastAccessDate DESC) AS ReputationQuintileRank
    FROM
        Users u
    LEFT JOIN (
        SELECT
            UserId,
            SUM(CASE WHEN Class = 1 THEN 1 ELSE 0 END) AS GoldBadges,
            SUM(CASE WHEN Class = 2 THEN 1 ELSE 0 END) AS SilverBadges,
            SUM(CASE WHEN Class = 3 THEN 1 ELSE 0 END) AS BronzeBadges,
            COUNT(Id) AS TotalBadges
        FROM
            Badges
        GROUP BY
            UserId
    ) b ON u.Id = b.UserId
    WHERE
        u.Reputation > 500
        AND u.LastAccessDate >= NOW() - INTERVAL '1 year'
        AND (u.DisplayName IS NOT NULL OR u.AboutMe IS NOT NULL)
        AND u.AccountId IS NOT NULL
),
PostContentAnalysis AS (
    SELECT
        p.Id AS PostId,
        p.PostTypeId,
        p.OwnerUserId,
        COALESCE(p.OwnerDisplayName, 'Community') AS PostOwnerDisplayName,
        p.CreationDate AS PostCreationDate,
        p.Score AS PostScore,
        p.ViewCount,
        p.CommentCount,
        p.FavoriteCount,
        p.Title,
        p.Tags,
        p.ParentId,
        p.AcceptedAnswerId,
        ph_close.CreationDate AS ClosedDate,
        ph_reopen.CreationDate AS ReopenedDate,
        ARRAY_LENGTH(STRING_TO_ARRAY(SUBSTRING(p.Tags, 2, LENGTH(p.Tags) - 2), '><'), 1) AS NumberOfTags,
        LENGTH(p.Body) AS BodyLength,
        (SELECT AVG(c_sub.Score) FROM Comments c_sub WHERE c_sub.PostId = p.Id AND c_sub.CreationDate BETWEEN p.CreationDate AND p.CreationDate + INTERVAL '30 days') AS AvgInitialCommentScore,
        (SELECT COUNT(DISTINCT ph_edit.UserId) FROM PostHistory ph_edit WHERE ph_edit.PostId = p.Id AND ph_edit.PostHistoryTypeId IN (5, 6, 8, 9) AND ph_edit.UserId IS NOT NULL) AS DistinctEditorsCount,
        ROW_NUMBER() OVER (PARTITION BY p.OwnerUserId ORDER BY p.Score DESC, p.ViewCount DESC) AS UserPostRank,
        LAG(p.CreationDate, 1, p.CreationDate) OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate) AS PreviousPostDate,
        CASE
            WHEN p.Body ILIKE '%performance%' OR p.Title ILIKE '%benchmark%' OR p.Tags ILIKE '%<performance>%' THEN TRUE
            ELSE FALSE
        END AS ContainsPerformanceKeyword
    FROM
        Posts p
    LEFT JOIN PostHistory ph_close ON p.Id = ph_close.PostId AND ph_close.PostHistoryTypeId = 10 -- Post Closed
    LEFT JOIN PostHistory ph_reopen ON p.Id = ph_reopen.PostId AND ph_reopen.PostHistoryTypeId = 11 -- Post Reopened
    WHERE
        p.PostTypeId IN (1, 2) -- Questions or Answers
        AND p.CreationDate BETWEEN NOW() - INTERVAL '3 years' AND NOW() - INTERVAL '1 month'
        AND p.Score >= 5
        AND p.ViewCount >= 100
        AND p.OwnerUserId IS NOT NULL -- Exclude community-owned posts if OwnerUserId is null
),
PostInteractionMetrics AS (
    SELECT
        pca.PostId,
        pca.PostTypeId,
        pca.OwnerUserId,
        pca.PostCreationDate,
        pca.PostScore,
        pca.ViewCount,
        pca.CommentCount,
        pca.FavoriteCount,
        pca.Title,
        pca.Tags,
        pca.NumberOfTags,
        pca.BodyLength,
        pca.AvgInitialCommentScore,
        pca.DistinctEditorsCount,
        pca.UserPostRank,
        pca.PreviousPostDate,
        pca.ContainsPerformanceKeyword,
        CAST(COALESCE(pca.FavoriteCount, 0) AS DECIMAL) / NULLIF(pca.ViewCount, 0) AS FavoriteToViewRatio,
        CASE
            WHEN pca.PostTypeId = 1 AND pca.AcceptedAnswerId IS NOT NULL THEN TRUE
            WHEN pca.PostTypeId = 2 AND p_parent.AcceptedAnswerId = pca.PostId THEN TRUE
            ELSE FALSE
        END AS IsAcceptedSolution,
        COALESCE(
            (SELECT SUM(v.BountyAmount) FROM Votes v WHERE v.PostId = pca.PostId AND v.VoteTypeId = 8),
            0
        ) AS TotalBountyOffered,
        (SELECT COUNT(pl_dup.RelatedPostId) FROM PostLinks pl_dup WHERE pl_dup.PostId = pca.PostId AND pl_dup.LinkTypeId = 3) AS DuplicateCount,
        DENSE_RANK() OVER (PARTITION BY pca.OwnerUserId ORDER BY pca.PostScore DESC, pca.PostCreationDate DESC) AS RankOfPostByScoreForUser
    FROM
        PostContentAnalysis pca
    LEFT JOIN Posts p_parent ON pca.PostTypeId = 2 AND pca.ParentId = p_parent.Id -- To check if an answer is accepted for its parent question
    WHERE
        (pca.PostTypeId = 1 AND pca.Title IS NOT NULL AND pca.NumberOfTags >= 1) -- Questions must have a title and at least one tag
        OR (pca.PostTypeId = 2 AND pca.BodyLength > 50 AND pca.ParentId IS NOT NULL) -- Answers must have a non-trivial body and a parent
)
SELECT
    ue.UserId,
    ue.DisplayName,
    ue.Reputation,
    ue.ReputationTier,
    ue.ReputationQuintileRank,
    ue.GoldBadges,
    ue.SilverBadges,
    ue.BronzeBadges,
    ue.TotalBadges,
    ue.NetVotesGiven,
    pim.PostId,
    pim.PostTypeId,
    pim.PostOwnerDisplayName,
    pim.PostCreationDate,
    pim.PostScore,
    pim.ViewCount,
    pim.CommentCount,
    pim.FavoriteCount,
    pim.Title,
    pim.Tags,
    pim.NumberOfTags,
    pim.BodyLength,
    pim.AvgInitialCommentScore,
    pim.DistinctEditorsCount,
    pim.UserPostRank,
    pim.PreviousPostDate,
    pim.ContainsPerformanceKeyword,
    pim.FavoriteToViewRatio,
    pim.IsAcceptedSolution,
    pim.TotalBountyOffered,
    pim.DuplicateCount,
    pim.RankOfPostByScoreForUser,
    MAX(ph_last_edit.CreationDate) OVER (PARTITION BY pim.PostId) AS LatestEditDate,
    COALESCE(
        (SELECT COUNT(DISTINCT c.UserId) FROM Comments c WHERE c.PostId = pim.PostId AND c.UserId != ue.UserId AND c.CreationDate BETWEEN pim.PostCreationDate AND pim.PostCreationDate + INTERVAL '60 days'),
        0
    ) AS OtherCommentersCountIn60Days,
    CASE
        WHEN pim.PostScore > 50 AND COALESCE(pim.FavoriteToViewRatio, 0) > 0.01 AND pim.DistinctEditorsCount > 1 THEN 'HighlyEngagingAndCollaborative'
        WHEN pim.PostScore > 20 AND pim.CommentCount > 5 THEN 'Engaging'
        ELSE 'Standard'
    END AS PostEngagementCategory,
    ph_revert.CreationDate AS LastRevertDate,
    (SELECT COUNT(DISTINCT pl_link.RelatedPostId) FROM PostLinks pl_link WHERE pl_link.PostId = pim.PostId AND pl_link.LinkTypeId = 1) AS LinkedPostsCount
FROM
    UserEngagement ue
INNER JOIN
    PostInteractionMetrics pim ON ue.UserId = pim.OwnerUserId
LEFT JOIN PostHistory ph_last_edit ON pim.PostId = ph_last_edit.PostId AND ph_last_edit.PostHistoryTypeId IN (4, 5, 6) -- Edit Title, Edit Body, Edit Tags
LEFT JOIN PostHistory ph_revert ON pim.PostId = ph_revert.PostId AND ph_revert.PostHistoryTypeId IN (7, 8, 9) -- Rollback Title, Rollback Body, Rollback Tags
WHERE
    ue.ReputationTier != 'Novice'
    AND pim.RankOfPostByScoreForUser <= 5 -- Only top 5 posts by score for each user
    AND (pim.ContainsPerformanceKeyword = TRUE OR (pim.PostTypeId = 1 AND pim.NumberOfTags >= 3 AND pim.FavoriteCount IS NOT NULL))
    AND pim.DuplicateCount = 0 -- Exclude duplicated questions
    AND (ph_revert.CreationDate IS NULL OR ph_revert.CreationDate < pim.PostCreationDate + INTERVAL '1 hour') -- Check if revert happened very quickly
    AND (pim.IsAcceptedSolution = TRUE OR pim.PostTypeId = 1 AND pim.CommentCount > 0)
ORDER BY
    ue.Reputation DESC,
    pim.PostScore DESC,
    pim.PostCreationDate DESC
LIMIT 1000;
