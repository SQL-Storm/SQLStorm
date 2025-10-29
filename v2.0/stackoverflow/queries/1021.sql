-- {"query": "1021.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-flash", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 2810}
WITH UserEngagementSummary AS (
    SELECT
        u.Id AS UserId,
        u.DisplayName AS UserDisplayName,
        u.Reputation,
        u.CreationDate AS UserCreationDate,
        u.LastAccessDate,
        u.Views AS UserProfileViews,
        u.UpVotes AS UserTotalUpVotes,
        u.DownVotes AS UserTotalDownVotes,
        COUNT(DISTINCT p.Id) AS TotalPostsOwned,
        COUNT(DISTINCT CASE WHEN p.PostTypeId = 1 THEN p.Id END) AS TotalQuestionsAsked,
        COUNT(DISTINCT CASE WHEN p.PostTypeId = 2 THEN p.Id END) AS TotalAnswersProvided,
        COUNT(DISTINCT c.Id) AS TotalCommentsMade,
        SUM(COALESCE(p.Score, 0)) AS TotalPostScore,
        SUM(COALESCE(p.ViewCount, 0)) AS TotalPostViews,
        SUM(CASE WHEN p.AcceptedAnswerId IS NOT NULL AND p.PostTypeId = 1 THEN 1 ELSE 0 END) AS AcceptedAnswersCount,
        COALESCE(CAST(u.UpVotes AS NUMERIC) / NULLIF((u.UpVotes + u.DownVotes), 0), 0) AS OverallUpvoteRatio
    FROM Users u
    LEFT JOIN Posts p ON u.Id = p.OwnerUserId
    LEFT JOIN Comments c ON u.Id = c.UserId
    GROUP BY
        u.Id, u.DisplayName, u.Reputation, u.CreationDate, u.LastAccessDate,
        u.Views, u.UpVotes, u.DownVotes
),
PostPopularityMetrics AS (
    SELECT
        p.Id AS PostId,
        p.PostTypeId,
        pt.Name AS PostTypeName,
        p.CreationDate AS PostCreationDate,
        p.Score AS PostScore,
        p.ViewCount AS PostViewCount,
        p.AnswerCount,
        p.CommentCount,
        p.FavoriteCount,
        p.OwnerUserId,
        p.Title AS PostTitle,
        p.Tags AS PostTagsRaw,
        TRIM(BOTH '<>' FROM SUBSTRING(p.Tags FROM POSITION('<' IN p.Tags) + 1 FOR POSITION('>' IN p.Tags) - POSITION('<' IN p.Tags) - 1)) AS PrimaryTag,
        CASE
            WHEN COALESCE(p.Body, '') LIKE '%database%' OR COALESCE(p.Title, '') LIKE '%database%' THEN 'Database Related'
            WHEN COALESCE(p.Body, '') LIKE '%javascript%' OR COALESCE(p.Title, '') LIKE '%javascript%' THEN 'JavaScript Related'
            WHEN COALESCE(p.Body, '') LIKE '%python%' OR COALESCE(p.Title, '') LIKE '%python%' THEN 'Python Related'
            ELSE 'Other'
        END AS ContentCategory,
        (COALESCE(p.Score, 0) * 0.5) + (COALESCE(p.ViewCount, 0) * 0.01) + (COALESCE(p.AnswerCount, 0) * 0.1) + (COALESCE(p.FavoriteCount, 0) * 0.2) AS WeightedPopularityScore,
        COUNT(CASE WHEN v.VoteTypeId = 2 THEN v.Id END) AS UpVotesReceived,
        COUNT(CASE WHEN v.VoteTypeId = 3 THEN v.Id END) AS DownVotesReceived,
        COUNT(CASE WHEN v.VoteTypeId = 5 THEN v.Id END) AS FavoriteVotesReceived,
        CASE WHEN p.AcceptedAnswerId IS NOT NULL THEN 'Accepted' ELSE 'Not Accepted' END AS AcceptedAnswerStatus
    FROM Posts p
    JOIN PostTypes pt ON p.PostTypeId = pt.Id
    LEFT JOIN Votes v ON p.Id = v.PostId
    GROUP BY
        p.Id, p.PostTypeId, pt.Name, p.CreationDate, p.Score, p.ViewCount, p.AnswerCount,
        p.CommentCount, p.FavoriteCount, p.OwnerUserId, p.Title, p.Tags, p.AcceptedAnswerId, p.Body
),
PostHistoricalEdits AS (
    SELECT
        ph.PostId,
        ph.UserId AS EditorUserId,
        ph.CreationDate AS EditDate,
        pht.Name AS HistoryTypeName,
        ph.Comment AS HistoryComment,
        CASE
            WHEN ph.PostHistoryTypeId IN (4, 5, 6) THEN 'Content Edit'
            WHEN ph.PostHistoryTypeId IN (10, 11) THEN 'Status Change'
            ELSE 'Other History'
        END AS HistoryTypeCategory,
        EXTRACT(EPOCH FROM (ph.CreationDate - LAG(ph.CreationDate, 1, ph.CreationDate) OVER (PARTITION BY ph.PostId, ph.UserId ORDER BY ph.CreationDate))) / 3600 AS HoursSinceLastEditByUser,
        EXISTS (
            SELECT 1 FROM PostHistory ph_inner
            WHERE ph_inner.PostId = ph.PostId
            AND ph_inner.PostHistoryTypeId = 11
            AND ph_inner.CreationDate > ph.CreationDate
        ) AS WasReopenedLater
    FROM PostHistory ph
    JOIN PostHistoryTypes pht ON ph.PostHistoryTypeId = pht.Id
    WHERE ph.PostHistoryTypeId IN (1,2,3,4,5,6,10,11,12,13)
),
AggregatedEditStats AS (
    SELECT
        ph.PostId,
        ph.EditorUserId,
        COUNT(ph.PostId) AS TotalEditsByThisUserOnPost,
        SUM(CASE WHEN ph.HistoryTypeCategory = 'Content Edit' THEN 1 ELSE 0 END) AS ContentEditsByThisUser,
        AVG(ph.HoursSinceLastEditByUser) AS AvgHoursBetweenEditsByUser,
        MAX(CASE WHEN ph.WasReopenedLater THEN 1 ELSE 0 END) AS PostWasEverReopenedFlag
    FROM PostHistoricalEdits ph
    GROUP BY ph.PostId, ph.EditorUserId
),
BadgeAwardsSummary AS (
    SELECT
        b.UserId,
        COUNT(b.Id) AS TotalBadges,
        SUM(CASE WHEN b.Class = 1 THEN 1 ELSE 0 END) AS GoldBadges,
        SUM(CASE WHEN b.Class = 2 THEN 1 ELSE 0 END) AS SilverBadges,
        SUM(CASE WHEN b.Class = 3 THEN 1 ELSE 0 END) AS BronzeBadges,
        COUNT(DISTINCT CASE WHEN b.TagBased = TRUE THEN b.Name END) AS UniqueTagBadges,
        STRING_AGG(CASE WHEN b.Class = 1 THEN b.Name ELSE NULL END, ', ') AS GoldBadgeNames
    FROM Badges b
    GROUP BY b.UserId
),
PostLinkAnalysis AS (
    SELECT
        pl.PostId,
        COUNT(CASE WHEN pl.LinkTypeId = 1 THEN pl.RelatedPostId END) AS LinkedPostsCount,
        COUNT(CASE WHEN pl.LinkTypeId = 3 THEN pl.RelatedPostId END) AS DuplicateOfCount,
        STRING_AGG(CASE WHEN pl.LinkTypeId = 3 THEN CAST(pl.RelatedPostId AS TEXT) ELSE NULL END, ', ') AS DuplicatePostIds
    FROM PostLinks pl
    GROUP BY pl.PostId
)
SELECT
    ues.UserId,
    ues.UserDisplayName,
    ues.Reputation,
    ues.OverallUpvoteRatio,
    ues.TotalQuestionsAsked,
    ues.TotalAnswersProvided,
    pm.PostId,
    pm.PostTypeName,
    pm.PostCreationDate,
    pm.PostTitle,
    pm.PrimaryTag,
    pm.ContentCategory,
    pm.WeightedPopularityScore,
    pm.UpVotesReceived,
    pm.DownVotesReceived,
    pm.FavoriteVotesReceived,
    pm.AcceptedAnswerStatus,
    aes.TotalEditsByThisUserOnPost,
    aes.ContentEditsByThisUser,
    aes.AvgHoursBetweenEditsByUser,
    CASE WHEN aes.PostWasEverReopenedFlag = 1 THEN TRUE ELSE FALSE END AS PostWasEverReopened,
    bas.TotalBadges,
    bas.GoldBadges,
    bas.SilverBadges,
    bas.BronzeBadges,
    pla.LinkedPostsCount,
    pla.DuplicateOfCount,
    pla.DuplicatePostIds,
    RANK() OVER (PARTITION BY pm.PrimaryTag ORDER BY pm.WeightedPopularityScore DESC, pm.PostCreationDate DESC) AS RankInPrimaryTag,
    NTILE(5) OVER (ORDER BY ues.Reputation DESC) AS ReputationQuintile,
    (SELECT AVG(p_ans.Score)
     FROM Posts p_ans
     WHERE p_ans.ParentId = pm.PostId AND pm.PostTypeId = 1
    ) AS AvgAnswerScoreForQuestion,
    CASE WHEN ues.UserDisplayName ILIKE '%dev%' THEN 'Likely Developer' ELSE 'Other Role' END AS UserRoleGuess,
    COALESCE(u.Location, 'Unknown Location') AS UserLocationDetail,
    COALESCE(CAST(ues.AcceptedAnswersCount AS NUMERIC) / NULLIF(ues.TotalQuestionsAsked, 0), 0) AS AcceptedAnswerRate
FROM UserEngagementSummary ues
JOIN Users u ON ues.UserId = u.Id
JOIN PostPopularityMetrics pm ON ues.UserId = pm.OwnerUserId
LEFT JOIN AggregatedEditStats aes ON pm.PostId = aes.PostId AND ues.UserId = aes.EditorUserId
LEFT JOIN BadgeAwardsSummary bas ON ues.UserId = bas.UserId
LEFT JOIN PostLinkAnalysis pla ON pm.PostId = pla.PostId
WHERE
    ues.Reputation > 1000
    AND pm.PostCreationDate >= DATE '2022-01-01'
    AND COALESCE(pm.PostScore, 0) >= 5
    AND (pm.ContentCategory = 'Database Related' OR pm.ContentCategory = 'JavaScript Related')
    AND (pm.PostTypeName = 'Question' OR pm.PostTypeName = 'Answer')
    AND ues.OverallUpvoteRatio > 0.6
    AND ((u.AboutMe IS NOT NULL AND LENGTH(TRIM(u.AboutMe)) > 50) OR u.WebsiteUrl IS NOT NULL)
ORDER BY
    ues.Reputation DESC,
    pm.WeightedPopularityScore DESC,
    RankInPrimaryTag ASC
LIMIT 1000;