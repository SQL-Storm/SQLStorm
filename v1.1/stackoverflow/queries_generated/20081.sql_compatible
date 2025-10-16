WITH HighValueUsers AS (
    SELECT u.Id, 'High Reputation' AS Reason
    FROM Users u
    WHERE u.Reputation > 100000 AND u.UpVotes > (u.DownVotes * 20)
    UNION
    SELECT b.UserId, 'Gold Badge Prolific' AS Reason
    FROM Badges b
    WHERE b.Class = 1
    GROUP BY b.UserId
    HAVING COUNT(*) >= 5
),
UserEngagementMetrics AS (
    SELECT
        u.Id AS UserId,
        u.DisplayName,
        u.Reputation,
        u.CreationDate AS UserCreationDate,
        u.Location,
        (SELECT COUNT(*) FROM Posts p WHERE p.OwnerUserId = u.Id AND p.PostTypeId = 1) AS QuestionCount,
        (SELECT COUNT(*) FROM Posts p WHERE p.OwnerUserId = u.Id AND p.PostTypeId = 2) AS AnswerCount,
        (SELECT COUNT(*) FROM Comments c WHERE c.UserId = u.Id) AS CommentCount,
        (SELECT MAX(ph.CreationDate) FROM PostHistory ph WHERE ph.UserId = u.Id AND ph.PostHistoryTypeId IN (4, 5, 6)) AS LastEditTimestamp,
        (SELECT STRING_AGG(b2.Name, ', ' ORDER BY b2.Date DESC)
         FROM (SELECT b1.Name, b1.Date FROM Badges b1 WHERE b1.UserId = u.Id AND b1.Class = 1 ORDER BY b1.Date DESC LIMIT 3) AS b2) AS Top3GoldBadges
    FROM Users u
    WHERE u.Id IN (SELECT Id FROM HighValueUsers)
),
RankedPosts AS (
    SELECT
        p.Id AS PostId,
        p.OwnerUserId,
        p.Title,
        p.Body,
        p.Score,
        p.ViewCount,
        p.CommentCount AS PostCommentCount,
        p.FavoriteCount,
        p.CreationDate AS PostCreationDate,
        p.Tags,
        p.PostTypeId,
        ROW_NUMBER() OVER(PARTITION BY p.OwnerUserId ORDER BY p.Score DESC, p.FavoriteCount DESC NULLS LAST, p.ViewCount DESC NULLS LAST) as PostRankByUser,
        NTILE(100) OVER(PARTITION BY p.PostTypeId ORDER BY p.Score DESC) as ScorePercentile
    FROM Posts p
    WHERE p.OwnerUserId IN (SELECT Id FROM HighValueUsers) AND p.ClosedDate IS NULL
)
SELECT
    uem.DisplayName,
    uem.Reputation,
    uem.UserCreationDate,
    COALESCE(uem.Location, 'Location Not Provided') AS Location,
    uem.QuestionCount,
    uem.AnswerCount,
    uem.CommentCount,
    uem.Top3GoldBadges,
    rp.Title AS TopPostTitle,
    rp.Score AS TopPostScore,
    rp.ScorePercentile AS TopPostScorePercentile,
    EXTRACT(DAY FROM (CAST('2024-10-01 12:34:56' AS TIMESTAMP) - uem.UserCreationDate)) AS AccountAgeDays,
    (uem.Reputation / NULLIF(EXTRACT(DAY FROM (CAST('2024-10-01 12:34:56' AS TIMESTAMP) - uem.UserCreationDate)), 0)) AS ReputationPerDay,
    CASE
        WHEN rp.PostTypeId = 1 THEN 'Question'
        WHEN rp.PostTypeId = 2 THEN 'Answer'
        ELSE 'Other'
    END AS TopPostType,
    LENGTH(rp.Body) AS TopPostBodyLength,
    SUBSTRING(rp.Tags FROM 2 FOR (POSITION('>' IN rp.Tags) - 2)) AS PrimaryTag,
    close_info.CloseReason,
    DENSE_RANK() OVER (ORDER BY (uem.Reputation * 0.7 + COALESCE(rp.Score, 0) * 0.3) DESC) AS OverallUserRank
FROM
    UserEngagementMetrics uem
JOIN
    RankedPosts rp ON uem.UserId = rp.OwnerUserId AND rp.PostRankByUser = 1
LEFT JOIN (
    SELECT
        ph.PostId,
        crt.Name AS CloseReason
    FROM PostHistory ph
    JOIN CloseReasonTypes crt
        ON ph.Comment ~ '^[0-9]+$' AND CAST(ph.Comment AS SMALLINT) = crt.Id
    WHERE ph.PostHistoryTypeId = 10
) AS close_info ON rp.PostId = close_info.PostId
WHERE
    (uem.Location LIKE '%Europe%' OR uem.Location IS NULL)
    AND uem.AnswerCount > uem.QuestionCount
    AND LENGTH(rp.Body) > 250
GROUP BY
    uem.DisplayName,
    uem.Reputation,
    uem.UserCreationDate,
    uem.Location,
    uem.QuestionCount,
    uem.AnswerCount,
    uem.CommentCount,
    uem.Top3GoldBadges,
    rp.Title,
    rp.Score,
    rp.ScorePercentile,
    uem.UserId,
    rp.PostTypeId,
    rp.Body,
    rp.Tags,
    close_info.CloseReason
ORDER BY
    OverallUserRank, uem.Reputation DESC
LIMIT 200;