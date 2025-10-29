WITH UserActivityMetrics AS (
    SELECT
        u.Id AS UserId,
        u.DisplayName,
        u.CreationDate AS UserCreationDate,
        u.Reputation,
        u.Views AS UserProfileViews,
        u.UpVotes AS TotalUpvotesReceived,
        u.DownVotes AS TotalDownvotesReceived,
        COUNT(DISTINCT p.Id) AS TotalPostsCreated,
        COUNT(DISTINCT c.Id) AS TotalCommentsMade,
        MAX(p.CreationDate) AS LatestPostDate,
        MIN(p.CreationDate) AS EarliestPostDate,
        COUNT(DISTINCT CASE WHEN b.Class = 1 THEN b.Id END) AS GoldBadges,
        COUNT(DISTINCT CASE WHEN b.Class = 2 THEN b.Id END) AS SilverBadges,
        COUNT(DISTINCT CASE WHEN b.Class = 3 THEN b.Id END) AS BronzeBadges,
        COUNT(DISTINCT CASE WHEN b.TagBased = TRUE THEN b.Id END) AS TagBadges
    FROM
        Users u
    LEFT JOIN Posts p ON u.Id = p.OwnerUserId
    LEFT JOIN Comments c ON u.Id = c.UserId
    LEFT JOIN Badges b ON u.Id = b.UserId
    WHERE
        u.CreationDate >= DATE '2019-01-01'
        AND u.Reputation > 1000
    GROUP BY
        u.Id, u.DisplayName, u.CreationDate, u.Reputation, u.Views, u.UpVotes, u.DownVotes
    HAVING
        COUNT(DISTINCT p.Id) > 5
),
PostHistoricalMetrics AS (
    SELECT
        ph.PostId,
        MAX(ph.CreationDate) AS LastHistoryDate,
        COUNT(ph.Id) AS HistoryEntryCount,
        COUNT(DISTINCT ph.UserId) AS UniqueEditors,
        SUM(CASE WHEN pht.Name = 'Post Closed' THEN 1 ELSE 0 END) AS CloseEvents,
        SUM(CASE WHEN pht.Name = 'Post Reopened' THEN 1 ELSE 0 END) AS ReopenEvents,
        SUM(CASE WHEN pht.Name LIKE '%Edit%' THEN 1 ELSE 0 END) AS EditEvents,
        MAX(CASE WHEN pht.Name = 'Post Closed' THEN ph.Comment ELSE NULL END) AS LastCloseReasonCommentId,
        MAX(CASE WHEN pht.Name = 'Post Closed' THEN crt.Name ELSE NULL END) AS LastCloseReasonType
    FROM
        PostHistory ph
    INNER JOIN PostHistoryTypes pht ON ph.PostHistoryTypeId = pht.Id
    LEFT JOIN CloseReasonTypes crt ON ph.Comment = CAST(crt.Id AS VARCHAR)
    WHERE
        ph.CreationDate >= DATE '2020-01-01'
        AND pht.Name IN ('Post Closed', 'Post Reopened', 'Edit Body', 'Edit Tags', 'Initial Body', 'Initial Tags', 'Post Locked', 'Post Unlocked')
    GROUP BY
        ph.PostId
),
QuestionTagAnalysis AS (
    SELECT
        p.Id AS PostId,
        p.Title,
        p.Tags,
        p.OwnerUserId,
        p.CreationDate AS PostCreationDate,
        p.Score,
        p.ViewCount,
        p.AnswerCount,
        COALESCE(SUBSTRING(p.Tags FROM 2 FOR POSITION('><' IN p.Tags) - 2), 'untagged') AS PrimaryTag,
        COUNT(DISTINCT CASE WHEN plt.Name = 'Duplicate' THEN pl.RelatedPostId END) AS DuplicateLinkCount,
        COUNT(DISTINCT CASE WHEN plt.Name = 'Linked' THEN pl.RelatedPostId END) AS LinkedPostCount
    FROM
        Posts p
    LEFT JOIN PostLinks pl ON p.Id = pl.PostId
    LEFT JOIN LinkTypes plt ON pl.LinkTypeId = plt.Id
    WHERE
        p.PostTypeId = 1
        AND p.CreationDate >= DATE '2021-01-01'
        AND p.Score > 10
        AND p.ViewCount > 500
    GROUP BY
        p.Id, p.Title, p.Tags, p.OwnerUserId, p.CreationDate, p.Score, p.ViewCount, p.AnswerCount
),
RankedCommentsPerPost AS (
    SELECT
        c.PostId,
        c.Id AS CommentId,
        c.Text AS CommentText,
        c.Score AS CommentScore,
        c.CreationDate AS CommentCreationDate,
        c.UserId AS CommenterUserId,
        ROW_NUMBER() OVER (PARTITION BY c.PostId ORDER BY c.Score DESC, c.CreationDate DESC) AS rn_comment_score,
        AVG(c.Score) OVER (PARTITION BY c.PostId) AS AvgCommentScoreForPost,
        MAX(c.Score) OVER (PARTITION BY c.PostId) AS MaxCommentScoreForPost
    FROM
        Comments c
    WHERE
        c.CreationDate >= DATE '2021-01-01'
)
SELECT
    uam.UserId,
    uam.DisplayName AS UserDisplayName,
    uam.Reputation,
    uam.TotalUpvotesReceived,
    uam.TotalDownvotesReceived,
    uam.TotalPostsCreated,
    uam.TotalCommentsMade,
    uam.GoldBadges,
    uam.SilverBadges,
    uam.BronzeBadges,
    uam.TagBadges,
    qta.PostId AS QuestionId,
    qta.Title AS QuestionTitle,
    qta.PrimaryTag,
    qta.Score AS QuestionScore,
    qta.ViewCount AS QuestionViewCount,
    qta.AnswerCount AS QuestionAnswerCount,
    qta.DuplicateLinkCount,
    qta.LinkedPostCount,
    phm.HistoryEntryCount,
    phm.EditEvents,
    phm.CloseEvents,
    phm.ReopenEvents,
    phm.LastCloseReasonType,
    rcpp.CommentText AS TopCommentText,
    rcpp.CommentScore AS TopCommentScore,
    rcpp.AvgCommentScoreForPost,
    usr.Location AS UserLocation,
    usr.AboutMe AS UserAboutMeSnippet,
    (CAST(qta.Score AS DECIMAL) / (qta.ViewCount + 1)) AS ScorePerViewRatio,
    (uam.TotalUpvotesReceived - uam.TotalDownvotesReceived) AS UserNetVotesReceived,
    (uam.GoldBadges * 10 + uam.SilverBadges * 5 + uam.BronzeBadges * 1) AS WeightedBadgesScore,
    CASE
        WHEN qta.DuplicateLinkCount > 0 AND phm.CloseEvents > 0 AND LOWER(COALESCE(phm.LastCloseReasonType, '')) LIKE '%duplicate%' THEN 'Closed-Duplicate'
        WHEN qta.DuplicateLinkCount > 0 AND phm.CloseEvents > 0 THEN 'Closed-OtherReasonWithDuplicates'
        WHEN qta.DuplicateLinkCount = 0 AND phm.CloseEvents > 0 THEN 'Closed-NoDuplicates'
        ELSE 'Open-Or-Reopened'
    END AS PostStatusCategory,
    LAG(qta.PostCreationDate, 1, TIMESTAMP '1970-01-01 00:00:00') OVER (PARTITION BY uam.UserId ORDER BY qta.PostCreationDate) AS PreviousPostDate,
    LEAD(qta.PostCreationDate, 1, TIMESTAMP '2099-12-31 00:00:00') OVER (PARTITION BY uam.UserId ORDER BY qta.PostCreationDate) AS NextPostDate,
    (SELECT COALESCE(SUM(v_sub.BountyAmount), 0) FROM Votes v_sub WHERE v_sub.PostId = qta.PostId AND v_sub.VoteTypeId = (SELECT Id FROM VoteTypes vt WHERE vt.Name = 'BountyStart')) AS TotalBountyOnQuestion,
    LENGTH(COALESCE(usr.AboutMe, '')) AS AboutMeLength,
    SUBSTRING(COALESCE(usr.Location, 'Unknown') FROM 1 FOR 20) AS LocationPrefix,
    COALESCE(CAST(q.AcceptedAnswerId AS VARCHAR), 'No Accepted Answer') AS AcceptedAnswerIdStatus
FROM
    UserActivityMetrics uam
INNER JOIN
    QuestionTagAnalysis qta ON uam.UserId = qta.OwnerUserId
LEFT JOIN
    PostHistoricalMetrics phm ON qta.PostId = phm.PostId
LEFT JOIN
    RankedCommentsPerPost rcpp ON qta.PostId = rcpp.PostId AND rcpp.rn_comment_score = 1
LEFT JOIN
    Users usr ON uam.UserId = usr.Id
LEFT JOIN
    Posts q ON qta.PostId = q.Id AND q.PostTypeId = 1
WHERE
    uam.TotalPostsCreated > 10
    AND LOWER(qta.PrimaryTag) LIKE '%sql%'
    AND qta.ViewCount > (SELECT AVG(p2.ViewCount) FROM Posts p2 WHERE p2.PostTypeId = 1 AND p2.CreationDate >= DATE '2021-01-01')
    AND (
        (usr.Location IS NOT NULL AND LOWER(usr.Location) LIKE '%us%')
        OR (usr.Location IS NULL AND uam.Reputation > 50000)
    )
    AND EXISTS (
        SELECT 1
        FROM Badges b_corr
        INNER JOIN Posts p_corr ON b_corr.UserId = p_corr.OwnerUserId
        WHERE b_corr.UserId = uam.UserId
          AND b_corr.TagBased = TRUE
          AND b_corr.Class = 1
          AND b_corr.Name = COALESCE(SUBSTRING(p_corr.Tags FROM 2 FOR POSITION('><' IN p_corr.Tags) - 2), 'untagged')
    )
ORDER BY
    uam.Reputation DESC, WeightedBadgesScore DESC, ScorePerViewRatio DESC, QuestionScore DESC
LIMIT 1000;