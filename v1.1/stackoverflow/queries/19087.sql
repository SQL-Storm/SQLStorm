WITH UserActivitySummary AS (
    SELECT
        u.Id AS UserId,
        COUNT(DISTINCT p.Id) AS TotalPosts,
        SUM(CASE WHEN p.PostTypeId = 1 THEN 1 ELSE 0 END) AS TotalQuestions,
        SUM(CASE WHEN p.PostTypeId = 2 THEN 1 ELSE 0 END) AS TotalAnswers,
        SUM(CASE WHEN p.PostTypeId = 1 AND p.AcceptedAnswerId IS NOT NULL THEN 1 ELSE 0 END) AS AcceptedAnswersGiven,
        SUM(COALESCE(p.FavoriteCount, 0)) AS TotalFavoriteCountOnPosts,
        SUM(p.Score) AS TotalPostScore,
        AVG(CASE WHEN p.PostTypeId = 1 THEN p.Score END) AS AvgQuestionScore,
        AVG(CASE WHEN p.PostTypeId = 2 THEN p.Score END) AS AvgAnswerScore,
        COUNT(DISTINCT b.Id) AS TotalBadges,
        SUM(CASE WHEN b.Class = 1 THEN 1 ELSE 0 END) AS GoldBadges,
        SUM(CASE WHEN b.Class = 2 THEN 1 ELSE 0 END) AS SilverBadges,
        SUM(CASE WHEN b.Class = 3 THEN 1 ELSE 0 END) AS BronzeBadges,
        MAX(p.LastActivityDate) AS LastPostActivityDate,
        MIN(p.CreationDate) AS FirstPostDate
    FROM Users u
    JOIN Posts p ON u.Id = p.OwnerUserId
    LEFT JOIN Badges b ON u.Id = b.UserId
    GROUP BY u.Id
),
PostLinkAggregates AS (
    SELECT
        pl.PostId AS InvolvedPostId,
        SUM(CASE WHEN pl.LinkTypeId = 1 THEN 1 ELSE 0 END) AS TotalLinksOut,
        SUM(CASE WHEN pl.LinkTypeId = 3 THEN 1 ELSE 0 END) AS TotalDuplicatesOut,
        0 AS TotalLinksIn,
        0 AS TotalDuplicatesIn
    FROM PostLinks pl
    GROUP BY pl.PostId

    UNION ALL

    SELECT
        pl.RelatedPostId AS InvolvedPostId,
        0 AS TotalLinksOut,
        0 AS TotalDuplicatesOut,
        SUM(CASE WHEN pl.LinkTypeId = 1 THEN 1 ELSE 0 END) AS TotalLinksIn,
        SUM(CASE WHEN pl.LinkTypeId = 3 THEN 1 ELSE 0 END) AS TotalDuplicatesIn
    FROM PostLinks pl
    GROUP BY pl.RelatedPostId
),
CombinedPostLinkAggregates AS (
    SELECT
        InvolvedPostId,
        SUM(TotalLinksOut) AS LinksOutCount,
        SUM(TotalDuplicatesOut) AS DuplicatesOutCount,
        SUM(TotalLinksIn) AS LinksInCount,
        SUM(TotalDuplicatesIn) AS DuplicatesInCount
    FROM PostLinkAggregates
    GROUP BY InvolvedPostId
),
PostExtendedDetails AS (
    SELECT
        p.Id AS PostId,
        p.PostTypeId,
        p.OwnerUserId,
        p.Title,
        p.Tags,
        p.ViewCount,
        p.Score,
        p.CreationDate,
        p.LastEditDate,
        p.LastActivityDate,
        p.ClosedDate,
        COUNT(DISTINCT ph.Id) AS EditHistoryCount,
        MAX(CASE WHEN ph.PostHistoryTypeId IN (4,5,6) THEN ph.CreationDate END) AS LatestEditDate,
        SUM(CASE WHEN ph.PostHistoryTypeId IN (10, 101) THEN 1 ELSE 0 END) AS CloseVotesCount,
        SUM(CASE WHEN ph.PostHistoryTypeId IN (11, 7) THEN 1 ELSE 0 END) AS ReopenVotesCount,
        COUNT(DISTINCT c.Id) AS CommentCount,
        AVG(c.Score) AS AvgCommentScore,
        (SELECT MAX(s.Score) FROM Comments s WHERE s.PostId = p.Id AND s.CreationDate > (p.CreationDate + INTERVAL '1 day')) AS MaxCommentScoreAfterFirstDay,
        ROW_NUMBER() OVER (PARTITION BY p.OwnerUserId ORDER BY p.Score DESC, p.ViewCount DESC) AS UserPostScoreRank,
        (SELECT ph2.UserId
         FROM PostHistory ph2
         WHERE ph2.PostId = p.Id
         ORDER BY ph2.CreationDate ASC
         OFFSET 1 LIMIT 1) AS PreviousEditorId,
        (p.Score * 0.5 + p.ViewCount * 0.1 + COALESCE(p.FavoriteCount, 0) * 2 + COUNT(DISTINCT c.Id) * 0.7) AS CalculatedEngagementScore,
        COALESCE(p.LastEditDate, p.CreationDate) AS EffectiveLastEditOrCreation
    FROM Posts p
    LEFT JOIN PostHistory ph ON p.Id = ph.PostId
    LEFT JOIN Comments c ON p.Id = c.PostId
    GROUP BY p.Id, p.PostTypeId, p.OwnerUserId, p.Title, p.Tags, p.ViewCount, p.Score, p.CreationDate, p.LastEditDate, p.LastActivityDate, p.ClosedDate, p.FavoriteCount
),
MostImpactfulTagPerQuestion AS (
    SELECT
        q.Id AS QuestionId,
        q.OwnerUserId,
        (
            SELECT t_inner.TagName
            FROM Tags t_inner
            WHERE t_inner.TagName = (
                SELECT split_part(SUBSTRING(q.Tags FROM 2 FOR (length(q.Tags)-2)), '><', 1)
                LIMIT 1
            )
            LIMIT 1
        ) AS PrimaryTagName,
        COUNT(v.Id) AS TotalVotesOnQuestion,
        SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS UpvotesOnQuestion
    FROM Posts q
    LEFT JOIN Votes v ON q.Id = v.PostId AND v.VoteTypeId IN (2,3)
    WHERE q.PostTypeId = 1
    GROUP BY q.Id, q.OwnerUserId, q.Tags
),
TopActiveEditors AS (
    SELECT
        ph.UserId,
        COUNT(DISTINCT ph.PostId) AS PostsEdited,
        COUNT(ph.Id) AS TotalEditsMade,
        ROW_NUMBER() OVER (ORDER BY COUNT(ph.Id) DESC) AS EditorRank
    FROM PostHistory ph
    WHERE ph.PostHistoryTypeId IN (4, 5, 6)
      AND ph.UserId IS NOT NULL
    GROUP BY ph.UserId
    HAVING COUNT(ph.Id) > 10
    ORDER BY TotalEditsMade DESC
    LIMIT 100
),
CommunityPostIndicators AS (
    SELECT
        p.Id AS PostId,
        CASE WHEN p.CommunityOwnedDate IS NOT NULL THEN TRUE ELSE FALSE END AS IsCommunityOwned,
        CASE WHEN p.ClosedDate IS NOT NULL THEN TRUE ELSE FALSE END AS IsClosed,
        (SELECT COUNT(DISTINCT ph.UserId) FROM PostHistory ph WHERE ph.PostId = p.Id AND ph.PostHistoryTypeId IN (10, 101)) AS NumberOfUsersClosing
    FROM Posts p
    WHERE p.CommunityOwnedDate IS NOT NULL OR p.ClosedDate IS NOT NULL
)
SELECT
    u.Id AS UserId,
    u.DisplayName,
    u.Reputation,
    u.CreationDate AS UserCreationDate,
    uas.TotalPosts,
    uas.TotalQuestions,
    uas.TotalAnswers,
    uas.TotalFavoriteCountOnPosts,
    uas.AvgQuestionScore,
    uas.AvgAnswerScore,
    uas.GoldBadges,
    uas.SilverBadges,
    uas.BronzeBadges,
    pe.PostId,
    pe.Title AS PostTitle,
    pe.PostTypeId,
    pe.ViewCount AS PostViewCount,
    pe.Score AS PostScore,
    pe.CalculatedEngagementScore,
    pe.EditHistoryCount,
    pe.CommentCount,
    pe.MaxCommentScoreAfterFirstDay,
    COALESCE(cpla.LinksInCount, 0) AS TimesLinkedFromOtherPosts,
    COALESCE(cpla.DuplicatesInCount, 0) AS TimesDuplicatedByOtherPosts,
    COALESCE(cpla.LinksOutCount, 0) AS TimesLinkedToOtherPosts,
    COALESCE(cpla.DuplicatesOutCount, 0) AS TimesDuplicatesOtherPosts,
    mit.PrimaryTagName,
    mit.TotalVotesOnQuestion,
    COALESCE(ae.TotalEditsMade, 0) AS TotalUserEdits,
    ae.EditorRank,
    cpi.IsCommunityOwned,
    cpi.IsClosed,
    cpi.NumberOfUsersClosing,
    (SELECT COUNT(DISTINCT v.UserId) FROM Votes v WHERE v.PostId = pe.PostId AND v.VoteTypeId = 5) AS TotalPostFavoritesByUsers,
    (SELECT AVG(length(c2.Text)) FROM Comments c2 WHERE c2.PostId = pe.PostId AND c2.CreationDate > (pe.CreationDate + INTERVAL '1 hour')) AS AvgCommentLengthAfterFirstHour,
    CASE
        WHEN pe.PostTypeId = 1 AND pe.ClosedDate IS NOT NULL AND (pe.LastEditDate > pe.ClosedDate OR pe.LastActivityDate > pe.ClosedDate)
            THEN 'Re-engaged after closure'
        WHEN pe.PostTypeId = 2 AND pe.Score >= 50 AND pe.CalculatedEngagementScore > 100
            THEN 'Highly Valued Answer'
        WHEN u.Reputation > 50000 AND uas.GoldBadges >= 5 AND pe.UserPostScoreRank = 1
            THEN 'Top Question from Influential User'
        ELSE 'Other'
    END AS PostCategory,
    (CAST('2024-10-01' AS date) - CAST(u.CreationDate AS date)) AS UserAgeDays,
    CASE WHEN NULLIF(u.DownVotes, 0) IS NULL THEN NULL ELSE (NULLIF(u.UpVotes, 0) / NULLIF(u.DownVotes, 0)) END AS UserVoteRatio,
    UPPER(SUBSTRING(COALESCE(u.Location, 'UNKNOWN') FROM 1 FOR 5)) AS UserLocationPrefix,
    pe.CreationDate,
    pe.UserPostScoreRank
FROM Users u
JOIN UserActivitySummary uas ON u.Id = uas.UserId
JOIN PostExtendedDetails pe ON u.Id = pe.OwnerUserId
LEFT JOIN CombinedPostLinkAggregates cpla ON pe.PostId = cpla.InvolvedPostId
LEFT JOIN MostImpactfulTagPerQuestion mit ON pe.PostId = mit.QuestionId
LEFT JOIN TopActiveEditors ae ON u.Id = ae.UserId
LEFT JOIN CommunityPostIndicators cpi ON pe.PostId = cpi.PostId
WHERE
    u.Reputation > 10000
    AND u.LastAccessDate > (CAST('2024-10-01 12:34:56' AS timestamp) - INTERVAL '1 year')
    AND uas.TotalQuestions > 5
    AND pe.PostTypeId IN (1, 2)
    AND pe.CalculatedEngagementScore > 50
    AND (pe.Title LIKE '%SQL%' OR pe.Title LIKE '%database%' OR pe.Tags LIKE '%<sql>%' OR pe.Tags LIKE '%<database>%')
    AND pe.Score > (
        SELECT AVG(p2.Score)
        FROM Posts p2
        WHERE p2.PostTypeId = pe.PostTypeId
          AND p2.CreationDate > (CAST('2024-10-01 12:34:56' AS timestamp) - INTERVAL '2 years')
    )
    AND (pe.ClosedDate IS NULL OR pe.ReopenVotesCount > 0 OR pe.LastActivityDate > pe.ClosedDate)
    AND COALESCE(pe.LastEditDate, pe.CreationDate) BETWEEN (CAST('2024-10-01 12:34:56' AS timestamp) - INTERVAL '3 years') AND CAST('2024-10-01 12:34:56' AS timestamp)
GROUP BY
    u.Id, u.DisplayName, u.Reputation, u.CreationDate, uas.TotalPosts, uas.TotalQuestions, uas.TotalAnswers,
    uas.TotalFavoriteCountOnPosts, uas.AvgQuestionScore, uas.AvgAnswerScore, uas.GoldBadges, uas.SilverBadges, uas.BronzeBadges,
    pe.PostId, pe.Title, pe.PostTypeId, pe.ViewCount, pe.Score, pe.CalculatedEngagementScore,
    pe.EditHistoryCount, pe.CommentCount, pe.MaxCommentScoreAfterFirstDay,
    cpla.LinksInCount, cpla.DuplicatesInCount, cpla.LinksOutCount, cpla.DuplicatesOutCount,
    mit.PrimaryTagName, mit.TotalVotesOnQuestion, ae.TotalEditsMade, ae.EditorRank,
    cpi.IsCommunityOwned, cpi.IsClosed, cpi.NumberOfUsersClosing, pe.ClosedDate, pe.LastEditDate, pe.LastActivityDate,
    u.UpVotes, u.DownVotes, u.Location, pe.CreationDate, pe.UserPostScoreRank, u.LastAccessDate
ORDER BY
    u.Reputation DESC, pe.CalculatedEngagementScore DESC, pe.CreationDate DESC
LIMIT 1000;