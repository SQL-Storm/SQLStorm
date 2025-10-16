WITH
UserBadgeStats AS (
    SELECT
        u.Id AS UserId,
        COUNT(b.Id) AS TotalBadges,
        COUNT(NULLIF(b.Class, 1)) AS NonGoldBadges,
        SUM(CASE WHEN b.Class = 1 THEN 1 ELSE 0 END) AS GoldBadges,
        MAX(b.Date) AS LastBadgeDate
    FROM Users u
    LEFT JOIN Badges b ON u.Id = b.UserId
    GROUP BY u.Id
),
HighScorePosts AS (
    SELECT
        p.Id AS PostId,
        p.OwnerUserId,
        p.Score,
        p.CreationDate,
        ROW_NUMBER() OVER (PARTITION BY p.OwnerUserId ORDER BY p.Score DESC, p.CreationDate ASC) AS rn
    FROM Posts p
    WHERE p.PostTypeId IN (1, 2) AND p.Score > 10
),
PostCommentAgg AS (
    SELECT
        p.Id AS PostId,
        COUNT(c.Id) AS CommentCount,
        COALESCE(SUM(LENGTH(c.Text)), 0) AS TotalCommentLength
    FROM Posts p
    LEFT JOIN Comments c ON p.Id = c.PostId
    WHERE p.PostTypeId IN (1, 2)
    GROUP BY p.Id
),
LatestEditHistory AS (
    SELECT
        ph.PostId,
        MAX(ph.CreationDate) AS LastEdit
    FROM PostHistory ph
    WHERE ph.PostHistoryTypeId IN (4, 5)
    GROUP BY ph.PostId
),
LinkedDuplicates AS (
    SELECT
        pl.PostId,
        COUNT(*) AS DuplicateLinks
    FROM PostLinks pl
    WHERE pl.LinkTypeId = 3
    GROUP BY pl.PostId
),
QuestionsWithAcceptedAnswers AS (
    SELECT
        p.Id AS QuestionId,
        p.AcceptedAnswerId,
        (EXTRACT(EPOCH FROM aa.CreationDate) - EXTRACT(EPOCH FROM p.CreationDate)) / 3600.0 AS HoursToAccepted,
        aa.Score AS AcceptedScore
    FROM Posts p
    LEFT JOIN Posts aa ON p.AcceptedAnswerId = aa.Id
    WHERE p.PostTypeId = 1 AND p.AcceptedAnswerId IS NOT NULL
)
SELECT
    u.Id AS UserId,
    u.DisplayName,
    u.Reputation,
    ub.TotalBadges,
    ub.GoldBadges,
    COALESCE(hsp.Score, 0) AS TopPostScore,
    hsp.CreationDate AS TopPostDate,
    p.Title AS TopPostTitle,
    p.ViewCount AS TopPostViews,
    p.Tags AS TopPostTags,
    p.AnswerCount,
    pcagg.CommentCount,
    pcagg.TotalCommentLength,
    le.LastEdit AS TopPostLastEdit,
    ld.DuplicateLinks,
    qaa.HoursToAccepted,
    qaa.AcceptedScore,
    COALESCE(ROUND( (CAST(u.UpVotes AS DECIMAL) / NULLIF(CAST(u.DownVotes AS DECIMAL), 0)), 2 ), 0) AS UpDownRatio,
    CASE
        WHEN p.Tags IS NOT NULL AND POSITION('python' IN LOWER(p.Tags)) > 0 THEN 'Python Related'
        WHEN p.Tags IS NOT NULL AND POSITION('javascript' IN LOWER(p.Tags)) > 0 THEN 'JavaScript Related'
        ELSE 'Other'
    END AS MainTech,
    (SELECT COUNT(*) FROM Votes v WHERE v.UserId = u.Id AND v.VoteTypeId = 2) AS UpVotesCast,
    (SELECT COUNT(DISTINCT c.PostId) FROM Comments c WHERE c.UserId = u.Id) AS DistinctCommentedPosts,
    u.Location,
    COALESCE(NULLIF(LENGTH(u.AboutMe), 0), 0) AS AboutMeLength
FROM Users u
LEFT JOIN UserBadgeStats ub ON u.Id = ub.UserId
LEFT JOIN HighScorePosts hsp ON u.Id = hsp.OwnerUserId AND hsp.rn = 1
LEFT JOIN Posts p ON hsp.PostId = p.Id
LEFT JOIN PostCommentAgg pcagg ON pcagg.PostId = p.Id
LEFT JOIN LatestEditHistory le ON le.PostId = p.Id
LEFT JOIN LinkedDuplicates ld ON ld.PostId = p.Id
LEFT JOIN QuestionsWithAcceptedAnswers qaa ON qaa.QuestionId = p.Id
WHERE u.Reputation > 1000
  AND (COALESCE(ub.GoldBadges, 0) > 0 OR u.UpVotes > 100)
  AND (p.Score IS NULL OR p.Score > 10)
GROUP BY
  u.Id,
  u.DisplayName,
  u.Reputation,
  ub.TotalBadges,
  ub.GoldBadges,
  hsp.Score,
  hsp.CreationDate,
  p.Title,
  p.ViewCount,
  p.Tags,
  p.AnswerCount,
  pcagg.CommentCount,
  pcagg.TotalCommentLength,
  le.LastEdit,
  ld.DuplicateLinks,
  qaa.HoursToAccepted,
  qaa.AcceptedScore,
  u.UpVotes,
  u.DownVotes,
  p.Id,
  u.Location,
  u.AboutMe
ORDER BY
    u.Reputation DESC,
    ub.GoldBadges DESC,
    TopPostScore DESC
LIMIT 100;