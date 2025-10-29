WITH PostVoteSummary AS (
    SELECT
        p.Id AS PostId,
        p.PostTypeId,
        p.OwnerUserId,
        p.CreationDate AS PostCreationDate,
        p.Score AS PostScore,
        COUNT(DISTINCT CASE WHEN vt.Name = 'UpMod' THEN v.Id ELSE NULL END) AS UpVoteCount,
        COUNT(DISTINCT CASE WHEN vt.Name = 'DownMod' THEN v.Id ELSE NULL END) AS DownVoteCount,
        COUNT(DISTINCT CASE WHEN vt.Name = 'Favorite' THEN v.Id ELSE NULL END) AS FavoriteCount,
        SUM(CASE WHEN vt.Name = 'UpMod' THEN 1 ELSE 0 END) - SUM(CASE WHEN vt.Name = 'DownMod' THEN 1 ELSE 0 END) AS NetVoteScore
    FROM Posts p
    LEFT JOIN Votes v ON p.Id = v.PostId
    LEFT JOIN VoteTypes vt ON v.VoteTypeId = vt.Id
    WHERE p.PostTypeId IN (1, 2)
    GROUP BY
        p.Id,
        p.PostTypeId,
        p.OwnerUserId,
        p.CreationDate,
        p.Score
),
UserPostActivity AS (
    SELECT
        u.Id AS UserId,
        u.DisplayName,
        u.Reputation,
        u.CreationDate AS UserCreationDate,
        COUNT(DISTINCT CASE WHEN pvs.PostTypeId = 1 THEN pvs.PostId ELSE NULL END) AS QuestionCount,
        COUNT(DISTINCT CASE WHEN pvs.PostTypeId = 2 THEN pvs.PostId ELSE NULL END) AS AnswerCount,
        SUM(pvs.PostScore) AS TotalScoreReceived,
        AVG(pvs.NetVoteScore) AS AverageNetVoteScore,
        MAX(pvs.PostCreationDate) AS LastPostDate
    FROM Users u
    JOIN PostVoteSummary pvs ON u.Id = pvs.OwnerUserId
    GROUP BY
        u.Id,
        u.DisplayName,
        u.Reputation,
        u.CreationDate
),
PostHistoryAnalysis AS (
    SELECT
        ph.PostId,
        COUNT(DISTINCT CASE WHEN pht.Name = 'Edit Body' THEN ph.Id ELSE NULL END) AS BodyEditCount,
        COUNT(DISTINCT CASE WHEN pht.Name = 'Edit Title' THEN ph.Id ELSE NULL END) AS TitleEditCount,
        MAX(ph.CreationDate) AS LastEditDate,
        -- include PostOwnerId to enable joining to Users by owner of the post
        MIN(p.OwnerUserId) AS PostOwnerUserId
    FROM PostHistory ph
    JOIN PostHistoryTypes pht ON ph.PostHistoryTypeId = pht.Id
    LEFT JOIN Posts p ON ph.PostId = p.Id
    WHERE pht.Name IN ('Edit Body', 'Edit Title')
    GROUP BY
        ph.PostId
)
SELECT
    upa.UserId,
    upa.DisplayName,
    upa.Reputation,
    upa.UserCreationDate,
    upa.QuestionCount,
    upa.AnswerCount,
    upa.TotalScoreReceived,
    upa.AverageNetVoteScore,
    upa.LastPostDate,
    COALESCE(pha.BodyEditCount, 0) AS TotalBodyEdits,
    COALESCE(pha.TitleEditCount, 0) AS TotalTitleEdits,
    pha.LastEditDate,
    CASE
        WHEN upa.LastPostDate IS NOT NULL AND upa.UserCreationDate IS NOT NULL THEN
            (upa.LastPostDate - upa.UserCreationDate)
        ELSE
            NULL
    END AS UserActivityDuration,
    CASE
        WHEN upa.AnswerCount > 0 THEN
            CAST(upa.TotalScoreReceived AS DOUBLE PRECISION) / upa.AnswerCount
        ELSE
            0.0
    END AS AvgScorePerAnswer,
    CASE
        WHEN upa.QuestionCount > 0 THEN
            CAST(upa.TotalScoreReceived AS DOUBLE PRECISION) / upa.QuestionCount
        ELSE
            0.0
    END AS AvgScorePerQuestion,
    CASE
        WHEN pha.LastEditDate IS NOT NULL AND upa.UserCreationDate IS NOT NULL THEN
            (pha.LastEditDate - upa.UserCreationDate)
        ELSE
            NULL
    END AS TimeToLastEditFromUserCreation,
    SUBSTRING(u.AboutMe FROM 1 FOR 100) AS First100CharsOfAboutMe,
    CASE
        WHEN u.WebsiteUrl IS NULL OR u.WebsiteUrl = '' THEN 'No Website'
        ELSE 'Has Website'
    END AS WebsiteStatus,
    (SELECT COUNT(*) FROM Badges b WHERE b.UserId = upa.UserId AND b.Class = 1) AS GoldBadgeCount,
    (SELECT COUNT(*) FROM Badges b WHERE b.UserId = upa.UserId AND b.Class = 2) AS SilverBadgeCount,
    (SELECT COUNT(*) FROM Badges b WHERE b.UserId = upa.UserId AND b.Class = 3) AS BronzeBadgeCount,
    (
        SELECT COUNT(DISTINCT pl.PostId)
        FROM PostLinks pl
        WHERE pl.RelatedPostId IN (SELECT PostId FROM Posts WHERE OwnerUserId = upa.UserId AND PostTypeId = 1)
          AND pl.LinkTypeId = 3
    ) AS DuplicateLinkCount
FROM Users u
JOIN UserPostActivity upa ON u.Id = upa.UserId
LEFT JOIN PostHistoryAnalysis pha ON upa.UserId = pha.PostOwnerUserId
WHERE upa.Reputation > 1000
GROUP BY
    upa.UserId,
    upa.DisplayName,
    upa.Reputation,
    upa.UserCreationDate,
    upa.QuestionCount,
    upa.AnswerCount,
    upa.TotalScoreReceived,
    upa.AverageNetVoteScore,
    upa.LastPostDate,
    pha.BodyEditCount,
    pha.TitleEditCount,
    pha.LastEditDate,
    u.AboutMe,
    u.WebsiteUrl,
    upa.UserId
ORDER BY upa.Reputation DESC, upa.LastPostDate DESC
LIMIT 100;