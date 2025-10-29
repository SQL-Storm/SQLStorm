-- {"query": "1531.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-flash", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 3307} 

WITH UserEngagement AS (
    SELECT
        u.Id AS UserId,
        u.DisplayName,
        u.Reputation,
        u.CreationDate AS UserCreationDate,
        u.UpVotes AS UserUpVotesGiven,
        u.DownVotes AS UserDownVotesGiven,
        COUNT(DISTINCT p.Id) AS TotalPosts,
        COUNT(DISTINCT CASE WHEN p.PostTypeId = 1 THEN p.Id END) AS TotalQuestions,
        COUNT(DISTINCT CASE WHEN p.PostTypeId = 2 THEN p.Id END) AS TotalAnswers,
        SUM(COALESCE(p.Score, 0)) AS TotalPostScore,
        COUNT(DISTINCT c.Id) AS TotalComments,
        SUM(COALESCE(c.Score, 0)) AS TotalCommentScore,
        COUNT(DISTINCT b.Id) AS TotalBadges,
        SUM(CASE WHEN b.Class = 1 THEN 1 ELSE 0 END) AS GoldBadges,
        SUM(CASE WHEN b.Class = 2 THEN 1 ELSE 0 END) AS SilverBadges,
        SUM(CASE WHEN b.Class = 3 THEN 1 ELSE 0 END) AS BronzeBadges,
        MAX(p.CreationDate) AS LastPostDate,
        MIN(p.CreationDate) AS FirstPostDate
    FROM
        Users u
    LEFT JOIN
        Posts p ON u.Id = p.OwnerUserId
    LEFT JOIN
        Comments c ON u.Id = c.UserId
    LEFT JOIN
        Badges b ON u.Id = b.UserId
    GROUP BY
        u.Id, u.DisplayName, u.Reputation, u.CreationDate, u.UpVotes, u.DownVotes
),
PostHistoryAggregates AS (
    SELECT
        ph.PostId,
        COUNT(ph.Id) AS EditCount,
        COUNT(DISTINCT CASE WHEN ph.PostHistoryTypeId IN (4, 5, 6) THEN ph.Id END) AS ActualEdits,
        COUNT(DISTINCT CASE WHEN ph.PostHistoryTypeId IN (10, 101, 102, 103, 104, 105) THEN ph.Id END) AS CloseVotes,
        MAX(ph.CreationDate) AS LastHistoryDate,
        MIN(ph.CreationDate) AS FirstHistoryDate,
        STRING_AGG(DISTINCT crt.Name, '; ') AS AllCloseReasons
    FROM
        PostHistory ph
    LEFT JOIN
        PostHistoryTypes pht ON ph.PostHistoryTypeId = pht.Id
    LEFT JOIN
        CloseReasonTypes crt ON ph.Comment = crt.Id::text AND ph.PostHistoryTypeId IN (10, 101, 102, 103, 104, 105)
    GROUP BY
        ph.PostId
),
PostLinkAnalysis AS (
    SELECT
        pl.PostId,
        COUNT(DISTINCT pl.RelatedPostId) AS LinkedPostCount,
        COUNT(DISTINCT CASE WHEN lt.Name = 'Duplicate' THEN pl.RelatedPostId END) AS DuplicatePostCount,
        ARRAY_AGG(DISTINCT lt.Name) AS LinkTypeNames
    FROM
        PostLinks pl
    JOIN
        LinkTypes lt ON pl.LinkTypeId = lt.Id
    GROUP BY
        pl.PostId
),
TagPerformance AS (
    SELECT
        p.Id AS PostId,
        p.PostTypeId,
        p.CreationDate AS PostCreationDate,
        p.Score AS PostScore,
        p.ViewCount,
        p.AnswerCount,
        p.CommentCount,
        p.FavoriteCount,
        p.LastActivityDate,
        p.ClosedDate,
        p.OwnerUserId,
        p.AcceptedAnswerId,
        STRING_TO_ARRAY(SUBSTRING(p.Tags FROM 2 FOR LENGTH(p.Tags) - 2), '><') AS TagArray,
        SUM(v.BountyAmount) FILTER (WHERE v.VoteTypeId = 9) AS TotalBountyReceived,
        COUNT(DISTINCT CASE WHEN v.VoteTypeId = 2 THEN v.Id END) AS UpvoteCount,
        COUNT(DISTINCT CASE WHEN v.VoteTypeId = 3 THEN v.Id END) AS DownvoteCount,
        COUNT(DISTINCT CASE WHEN v.VoteTypeId = 5 THEN v.Id END) AS FavoriteCountActual
    FROM
        Posts p
    LEFT JOIN Votes v ON p.Id = v.PostId
    WHERE p.Tags IS NOT NULL
    GROUP BY
        p.Id, p.PostTypeId, p.CreationDate, p.Score, p.ViewCount, p.AnswerCount, p.CommentCount, p.FavoriteCount, p.LastActivityDate, p.ClosedDate, p.OwnerUserId, p.Tags, p.AcceptedAnswerId
),
RankedTagPosts AS (
    SELECT
        tp.PostId,
        tp.PostTypeId,
        tp.PostCreationDate,
        tp.PostScore,
        tp.ViewCount,
        tp.AnswerCount,
        tp.CommentCount,
        tp.FavoriteCount,
        tp.LastActivityDate,
        tp.OwnerUserId,
        tp.ClosedDate,
        tp.TotalBountyReceived,
        tp.UpvoteCount,
        tp.DownvoteCount,
        tp.FavoriteCountActual,
        unnest(tp.TagArray) AS TagName,
        ROW_NUMBER() OVER (PARTITION BY tp.OwnerUserId, tp.PostTypeId ORDER BY tp.CreationDate DESC) AS UserPostSeqNum,
        RANK() OVER (PARTITION BY unnest(tp.TagArray) ORDER BY tp.Score DESC, tp.PostCreationDate DESC) AS TagScoreRank,
        NTILE(10) OVER (ORDER BY tp.ViewCount DESC) AS ViewCountDecile,
        AVG(tp.Score) OVER (PARTITION BY tp.OwnerUserId ORDER BY tp.CreationDate ROWS BETWEEN 2 PRECEDING AND CURRENT ROW) AS MovingAvgUserScore
    FROM
        TagPerformance tp
    WHERE tp.OwnerUserId IS NOT NULL
),
ModeratorActivity AS (
    SELECT
        ph.UserId,
        COUNT(DISTINCT ph.PostId) AS PostsModerated,
        COUNT(CASE WHEN ph.PostHistoryTypeId IN (14, 15, 19, 20) THEN ph.Id END) AS ModeratorActionsCount,
        MAX(ph.CreationDate) AS LastModerationAction
    FROM
        PostHistory ph
    WHERE
        ph.PostHistoryTypeId IN (14, 15, 19, 20)
    GROUP BY
        ph.UserId
)
SELECT
    ue.UserId,
    ue.DisplayName,
    ue.Reputation,
    ue.TotalPosts,
    ue.TotalQuestions,
    ue.TotalAnswers,
    ue.TotalPostScore,
    ue.TotalComments,
    rtp.PostId,
    rtp.PostCreationDate,
    rtp.PostScore,
    rtp.ViewCount,
    rtp.AnswerCount,
    rtp.CommentCount,
    rtp.FavoriteCount,
    rtp.TagName AS TopTag,
    rtp.TagScoreRank,
    rtp.ViewCountDecile,
    rtp.MovingAvgUserScore,
    ph_agg.EditCount,
    ph_agg.ActualEdits,
    ph_agg.CloseVotes,
    ph_agg.AllCloseReasons,
    pla.LinkedPostCount,
    pla.DuplicatePostCount,
    pla.LinkTypeNames,
    ma.PostsModerated,
    ma.ModeratorActionsCount,
    EXISTS (
        SELECT 1
        FROM Badges b
        WHERE b.UserId = ue.UserId
          AND b.Class = 1
          AND b.Name ILIKE '%' || rtp.TagName || '%'
    ) AS HasGoldBadgeForPostTag,
    (SELECT AVG(p_sub.Score)
     FROM Posts p_sub
     WHERE p_sub.PostTypeId = 1
       AND p_sub.OwnerUserId IS NOT NULL
       AND p_sub.OwnerUserId IN (
           SELECT u_sub.Id FROM Users u_sub WHERE u_sub.Reputation BETWEEN ue.Reputation - 100 AND ue.Reputation + 100
       )
     AND p_sub.CreationDate BETWEEN rtp.PostCreationDate - INTERVAL '1 year' AND rtp.PostCreationDate
    ) AS AvgScoreSimilarRepUsers,
    CASE
        WHEN (EXTRACT(EPOCH FROM (ue.LastPostDate - ue.FirstPostDate)) / 86400) > 0
        THEN ue.TotalPostScore::numeric / (EXTRACT(EPOCH FROM (ue.LastPostDate - ue.FirstPostDate)) / 86400)
        ELSE 0
    END AS PostScorePerDayActive,
    COALESCE(
        SPLIT_PART(SUBSTRING(p.Body FROM 1 FOR 100), ' ', 10),
        'N/A Body Snippet'
    ) AS First10WordsOfPostBody,
    CASE
        WHEN rtp.ClosedDate IS NOT NULL THEN 'Closed'
        WHEN p.AcceptedAnswerId IS NOT NULL THEN 'Answered'
        ELSE 'Open'
    END AS PostStatus
FROM
    UserEngagement ue
INNER JOIN
    RankedTagPosts rtp ON ue.UserId = rtp.OwnerUserId
INNER JOIN
    Posts p ON rtp.PostId = p.Id
LEFT JOIN
    PostHistoryAggregates ph_agg ON rtp.PostId = ph_agg.PostId
LEFT JOIN
    PostLinkAnalysis pla ON rtp.PostId = pla.PostId
LEFT JOIN
    ModeratorActivity ma ON ue.UserId = ma.UserId
WHERE
    rtp.PostTypeId = 1
    AND rtp.TagScoreRank <= 5
    AND rtp.ViewCountDecile >= 8
    AND ue.Reputation > 1000
    AND (
        rtp.MovingAvgUserScore > 50
        OR ph_agg.EditCount > 10
        OR pla.DuplicatePostCount > 0
    )
    AND p.Body LIKE '%<p>%</p>%'
    AND (ue.UserUpVotesGiven + ue.UserDownVotesGiven) > 100
    AND (p.ClosedDate IS NULL OR p.ClosedDate > NOW() - INTERVAL '6 months')

UNION ALL

SELECT
    ue.UserId,
    ue.DisplayName,
    ue.Reputation,
    ue.TotalPosts,
    ue.TotalQuestions,
    ue.TotalAnswers,
    ue.TotalPostScore,
    ue.TotalComments,
    rtp.PostId,
    rtp.PostCreationDate,
    rtp.PostScore,
    rtp.ViewCount,
    rtp.AnswerCount,
    rtp.CommentCount,
    rtp.FavoriteCount,
    rtp.TagName AS TopTag,
    rtp.TagScoreRank,
    rtp.ViewCountDecile,
    rtp.MovingAvgUserScore,
    ph_agg.EditCount,
    ph_agg.ActualEdits,
    ph_agg.CloseVotes,
    ph_agg.AllCloseReasons,
    pla.LinkedPostCount,
    pla.DuplicatePostCount,
    pla.LinkTypeNames,
    ma.PostsModerated,
    ma.ModeratorActionsCount,
    EXISTS (
        SELECT 1
        FROM Badges b
        WHERE b.UserId = ue.UserId
          AND b.TagBased = TRUE
          AND b.Name ILIKE '%sql%'
    ) AS HasGoldBadgeForPostTag,
    (SELECT AVG(p_sub.Score)
     FROM Posts p_sub
     WHERE p_sub.PostTypeId = 2
       AND p_sub.OwnerUserId IS NOT NULL
       AND p_sub.OwnerUserId IN (
           SELECT u_sub.Id FROM Users u_sub WHERE u_sub.Reputation BETWEEN ue.Reputation - 500 AND ue.Reputation + 500
       )
     AND p_sub.CreationDate BETWEEN rtp.PostCreationDate - INTERVAL '2 years' AND rtp.PostCreationDate
    ) AS AvgScoreSimilarRepUsers,
    CASE
        WHEN (EXTRACT(EPOCH FROM (ue.LastPostDate - ue.FirstPostDate)) / 86400) > 0
        THEN ue.TotalPostScore::numeric / (EXTRACT(EPOCH FROM (ue.LastPostDate - ue.FirstPostDate)) / 86400)
        ELSE 0
    END AS PostScorePerDayActive,
    COALESCE(
        SPLIT_PART(SUBSTRING(p.Body FROM 1 FOR 100), ' ', 10),
        'N/A Body Snippet'
    ) AS First10WordsOfPostBody,
    CASE
        WHEN rtp.ClosedDate IS NOT NULL THEN 'Closed'
        WHEN p.AcceptedAnswerId IS NOT NULL THEN 'Answered'
        ELSE 'Open'
    END AS PostStatus
FROM
    UserEngagement ue
INNER JOIN
    RankedTagPosts rtp ON ue.UserId = rtp.OwnerUserId
INNER JOIN
    Posts p ON rtp.PostId = p.Id
LEFT JOIN
    PostHistoryAggregates ph_agg ON rtp.PostId = ph_agg.PostId
LEFT JOIN
    PostLinkAnalysis pla ON rtp.PostId = pla.PostId
LEFT JOIN
    ModeratorActivity ma ON ue.UserId = ma.UserId
WHERE
    rtp.PostTypeId = 2
    AND rtp.CommentCount > 5
    AND ue.TotalAnswers > 10
    AND p.CreationDate > NOW() - INTERVAL '3 years'
    AND rtp.PostScore > 0
    AND ue.UserId IN (
        SELECT b_sub.UserId
        FROM Badges b_sub
        WHERE b_sub.UserId = ue.UserId
          AND b_sub.TagBased = TRUE
          AND b_sub.Name ILIKE '%javascript%'
    )
ORDER BY
    Reputation DESC, PostCreationDate DESC, PostScorePerDayActive DESC
LIMIT 1000;
