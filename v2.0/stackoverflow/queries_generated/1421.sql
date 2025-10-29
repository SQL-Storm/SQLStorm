-- {"query": "1421.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-flash", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 2285} 

WITH RecentActiveUsers AS (
    SELECT
        u.Id AS UserId,
        u.DisplayName,
        u.Reputation,
        u.CreationDate,
        u.LastAccessDate,
        u.Location,
        u.Views,
        u.UpVotes,
        u.DownVotes,
        (EXTRACT(EPOCH FROM (CURRENT_TIMESTAMP - u.CreationDate)) / (3600 * 24 * 365.25)) AS YearsSinceAccountCreation
    FROM Users AS u
    WHERE
        u.LastAccessDate >= (CURRENT_TIMESTAMP - INTERVAL '1 year')
        AND u.Reputation > 7500
        AND u.Views > 2500
        AND u.DisplayName IS NOT NULL
        AND u.Location IS NOT NULL
),
UserPostStats AS (
    SELECT
        p.OwnerUserId AS UserId,
        p.PostTypeId,
        p.Id AS PostId,
        p.Title,
        p.Score,
        p.ViewCount,
        p.AnswerCount,
        p.CreationDate,
        p.LastActivityDate,
        LENGTH(p.Body) AS BodyLength,
        COALESCE(p.FavoriteCount, 0) AS FavoriteCount,
        -- Parse tags into an array, then filter for non-null/empty strings
        ARRAY(SELECT TRIM(UNNEST(string_to_array(SUBSTRING(p.Tags FROM 2 FOR LENGTH(p.Tags)-2), '><')))) AS ParsedTags
    FROM Posts AS p
    WHERE
        p.OwnerUserId IN (SELECT UserId FROM RecentActiveUsers)
        AND p.PostTypeId IN (1, 2) -- Questions or Answers
        AND p.CreationDate >= (CURRENT_TIMESTAMP - INTERVAL '3 year')
),
PostCommentSummary AS (
    SELECT
        c.PostId,
        COUNT(c.Id) AS CommentCount,
        SUM(c.Score) AS TotalCommentScore,
        AVG(LENGTH(c.Text)) AS AvgCommentLength,
        COUNT(DISTINCT c.UserId) AS DistinctCommenters,
        MAX(c.CreationDate) AS LastCommentDate
    FROM Comments AS c
    WHERE c.CreationDate >= (CURRENT_TIMESTAMP - INTERVAL '2 year')
    GROUP BY c.PostId
),
UserBadgeSummary AS (
    SELECT
        b.UserId,
        COUNT(b.Id) AS TotalBadges,
        SUM(CASE WHEN b.Class = 1 THEN 1 ELSE 0 END) AS GoldBadges,
        SUM(CASE WHEN b.Class = 2 THEN 1 ELSE 0 END) AS SilverBadges,
        SUM(CASE WHEN b.Class = 3 THEN 1 ELSE 0 END) AS BronzeBadges,
        MAX(b.Date) AS LastBadgeDate
    FROM Badges AS b
    GROUP BY b.UserId
),
PostHistoryTimeline AS (
    SELECT
        ph.PostId,
        ph.CreationDate AS HistoryDate,
        ph.PostHistoryTypeId,
        ph.UserId AS HistoryUserId,
        LAG(ph.CreationDate) OVER (PARTITION BY ph.PostId ORDER BY ph.CreationDate) AS PreviousHistoryDate,
        LEAD(ph.CreationDate) OVER (PARTITION BY ph.PostId ORDER BY ph.CreationDate) AS NextHistoryDate,
        ROW_NUMBER() OVER (PARTITION BY ph.PostId ORDER BY ph.CreationDate DESC) AS rn_latest_history
    FROM PostHistory AS ph
    WHERE ph.PostHistoryTypeId IN (4, 5, 6, 10, 11, 12, 13) -- Edits (Title, Body, Tags), Closed, Reopened, Deleted, Undeleted
),
PostLinkSummary AS (
    SELECT
        pl.PostId,
        COUNT(CASE WHEN pl.LinkTypeId = 1 THEN pl.RelatedPostId END) AS LinkedPostCount,
        COUNT(CASE WHEN pl.LinkTypeId = 3 THEN pl.RelatedPostId END) AS DuplicatePostCount,
        ARRAY_AGG(DISTINCT pl.RelatedPostId) FILTER (WHERE pl.LinkTypeId = 1) AS AllLinkedPosts,
        ARRAY_AGG(DISTINCT pl.RelatedPostId) FILTER (WHERE pl.LinkTypeId = 3) AS AllDuplicatePosts
    FROM PostLinks AS pl
    GROUP BY pl.PostId
)
SELECT
    rau.DisplayName,
    rau.Reputation,
    rau.Location,
    rau.YearsSinceAccountCreation,
    ups.Title AS PostTitle,
    ups.PostId,
    pt.Name AS PostTypeName,
    ups.Score AS PostScore,
    ups.ViewCount AS PostViewCount,
    ups.AnswerCount,
    ups.FavoriteCount,
    pcs.CommentCount,
    pcs.TotalCommentScore,
    pcs.AvgCommentLength,
    ubs.GoldBadges,
    ubs.SilverBadges,
    ubs.BronzeBadges,
    (ups.Score * ups.ViewCount / NULLIF(ups.AnswerCount, 0.0)) AS EngagementRatio,
    EXTRACT(DAY FROM (CURRENT_TIMESTAMP - ups.CreationDate)) AS DaysSincePostCreation,
    EXTRACT(HOUR FROM (ups.LastActivityDate - ups.CreationDate)) AS HoursUntilFirstActivity,
    CASE
        WHEN ups.Score > 200 AND ups.ViewCount > 50000 THEN 'Mega Popular'
        WHEN ups.Score > 100 AND ups.ViewCount > 20000 THEN 'Highly Popular'
        WHEN ups.Score > 50 AND ups.ViewCount > 5000 THEN 'Moderately Popular'
        ELSE 'Less Popular'
    END AS PopularityCategory,
    ups.ParsedTags,
    ARRAY_TO_STRING(ups.ParsedTags, ', ') AS FormattedTags,
    pls.LinkedPostCount,
    pls.DuplicatePostCount,
    EXTRACT(MINUTE FROM (LATEST_HISTORY.HistoryDate - LATEST_HISTORY.PreviousHistoryDate)) AS MinsSincePrevHistory,
    RANK() OVER (PARTITION BY rau.Location ORDER BY ups.Score DESC, ups.ViewCount DESC) AS RankInLocationByPostScore,
    AVG(ups.Score) OVER (PARTITION BY rau.UserId ORDER BY ups.CreationDate ROWS BETWEEN 3 PRECEDING AND 1 FOLLOWING) AS MovingAvgUserPostScore,
    MAX(ups.Score) OVER (PARTITION BY rau.UserId) AS MaxUserPostScore,
    SUM(ups.BodyLength) OVER (PARTITION BY rau.UserId ORDER BY ups.CreationDate) AS CumulativeBodyLengthByUser,
    (SELECT EXISTS (
        SELECT 1
        FROM UserPostStats ups_corr
        WHERE ups_corr.UserId = rau.UserId
          AND ups_corr.PostId != ups.PostId
          AND ups_corr.CreationDate >= (CURRENT_TIMESTAMP - INTERVAL '1 year')
          AND ups_corr.FavoriteCount > 10
    )) AS HasOtherFavoritedPosts,
    COALESCE(
        CASE
            WHEN pcs.TotalCommentScore > 50 THEN 'Very Positive Comments'
            WHEN pcs.TotalCommentScore > 10 THEN 'Positive Comments'
            WHEN pcs.TotalCommentScore IS NOT NULL THEN 'Mixed/Low Comments'
            ELSE NULL
        END,
        'No Comments'
    ) AS CommentSentimentCategory,
    CASE
        WHEN ph_closed.CloseReasonId IS NOT NULL THEN crt.Name
        ELSE 'Not Closed Recently'
    END AS RecentCloseReason

FROM
    RecentActiveUsers AS rau
INNER JOIN
    UserPostStats AS ups ON rau.UserId = ups.UserId
INNER JOIN
    PostTypes AS pt ON ups.PostTypeId = pt.Id
LEFT JOIN
    PostCommentSummary AS pcs ON ups.PostId = pcs.PostId
LEFT JOIN
    UserBadgeSummary AS ubs ON rau.UserId = ubs.UserId
LEFT JOIN
    PostLinkSummary AS pls ON ups.PostId = pls.PostId
LEFT JOIN (
    SELECT PostId, HistoryDate, PreviousHistoryDate, PostHistoryTypeId, Comment AS CloseReasonId
    FROM PostHistoryTimeline
    WHERE rn_latest_history = 1
) AS LATEST_HISTORY ON ups.PostId = LATEST_HISTORY.PostId
LEFT JOIN (
    SELECT DISTINCT ON (PostId) PostId, Comment AS CloseReasonId
    FROM PostHistory
    WHERE PostHistoryTypeId = 10
      AND CreationDate >= (CURRENT_TIMESTAMP - INTERVAL '1 year')
    ORDER BY PostId, CreationDate DESC
) AS ph_closed ON ups.PostId = ph_closed.PostId
LEFT JOIN CloseReasonTypes AS crt ON CAST(ph_closed.CloseReasonId AS SMALLINT) = crt.Id

WHERE
    (
        'sql' = ANY(ups.ParsedTags)
        OR 'postgresql' = ANY(ups.ParsedTags)
        OR 'performance' = ANY(ups.ParsedTags)
        OR 'optimization' = ANY(ups.ParsedTags)
    )
    AND ups.BodyLength > 750
    AND (pcs.CommentCount IS NULL OR pcs.CommentCount >= 3)
    AND NOT EXISTS (
        SELECT 1
        FROM Votes AS v
        WHERE v.PostId = ups.PostId
          AND v.VoteTypeId = 4
          AND v.CreationDate >= (CURRENT_TIMESTAMP - INTERVAL '2 year')
    )
    AND rau.YearsSinceAccountCreation > 1.0
    AND (
        (ups.PostTypeId = 1 AND ups.AnswerCount >= 2 AND ups.ViewCount > 1000)
        OR
        (ups.PostTypeId = 2 AND ups.Score > 10 AND ups.BodyLength > 200)
    )
ORDER BY
    rau.Reputation DESC, EngagementRatio DESC NULLS LAST, MaxUserPostScore DESC, MinsSincePrevHistory ASC NULLS LAST
LIMIT 2000;
