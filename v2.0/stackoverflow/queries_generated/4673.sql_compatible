WITH RankedPostEdits AS (
    SELECT
        ph.PostId,
        ph.UserId,
        ph.CreationDate AS EditDate,
        pht.Name AS EditType,
        ROW_NUMBER() OVER (PARTITION BY ph.PostId, ph.UserId ORDER BY ph.CreationDate DESC) AS rn
    FROM PostHistory ph
    JOIN PostHistoryTypes pht ON ph.PostHistoryTypeId = pht.Id
    WHERE ph.PostHistoryTypeId IN (4, 5, 6)
),
UserPostActivity AS (
    SELECT
        p.OwnerUserId,
        COUNT(DISTINCT p.Id) AS TotalPostsOwned,
        SUM(CASE WHEN p.PostTypeId = 1 THEN 1 ELSE 0 END) AS QuestionCount,
        SUM(CASE WHEN p.PostTypeId = 2 THEN 1 ELSE 0 END) AS AnswerCount,
        AVG(p.Score) AS AverageScore,
        MAX(p.CreationDate) AS LastPostDate,
        COUNT(DISTINCT c.Id) AS CommentCountOnOwnPosts
    FROM Posts p
    LEFT JOIN Comments c ON p.Id = c.PostId AND p.OwnerUserId = c.UserId
    WHERE p.OwnerUserId IS NOT NULL AND p.OwnerUserId > 0
    GROUP BY p.OwnerUserId
),
UserEditSummary AS (
    SELECT
        rpe.UserId,
        COUNT(DISTINCT rpe.PostId) AS DistinctPostsEdited,
        COUNT(*) AS TotalEdits,
        MAX(rpe.EditDate) AS LastEditDate,
        SUM(CASE WHEN rpe.EditType = 'Edit Title' THEN 1 ELSE 0 END) AS TitleEdits,
        SUM(CASE WHEN rpe.EditType = 'Edit Body' THEN 1 ELSE 0 END) AS BodyEdits,
        SUM(CASE WHEN rpe.EditType = 'Edit Tags' THEN 1 ELSE 0 END) AS TagEdits
    FROM RankedPostEdits rpe
    WHERE rpe.rn = 1
    GROUP BY rpe.UserId
),
TopUsersByReputation AS (
    SELECT
        Id AS UserId,
        DisplayName,
        Reputation,
        UpVotes,
        DownVotes,
        ROW_NUMBER() OVER (ORDER BY Reputation DESC) AS reputation_rank
    FROM Users
    WHERE Reputation > 10000
)
SELECT
    tur.DisplayName AS UserDisplayName,
    tur.Reputation,
    tur.reputation_rank,
    upa.TotalPostsOwned,
    upa.QuestionCount,
    upa.AnswerCount,
    upa.AverageScore,
    upa.LastPostDate,
    upa.CommentCountOnOwnPosts,
    COALESCE(ues.DistinctPostsEdited, 0) AS UserDistinctPostsEdited,
    COALESCE(ues.TotalEdits, 0) AS UserTotalEdits,
    ues.LastEditDate AS UserLastEditDate,
    COALESCE(ues.TitleEdits, 0) AS UserTitleEdits,
    COALESCE(ues.BodyEdits, 0) AS UserBodyEdits,
    COALESCE(ues.TagEdits, 0) AS UserTagEdits,
    (SELECT COUNT(*) FROM Badges b WHERE b.UserId = tur.UserId AND b.Class = 1) AS GoldBadges,
    (SELECT COUNT(*) FROM Badges b WHERE b.UserId = tur.UserId AND b.Class = 2) AS SilverBadges,
    (SELECT COUNT(*) FROM Badges b WHERE b.UserId = tur.UserId AND b.Class = 3) AS BronzeBadges,
    CASE
        WHEN tur.UpVotes > tur.DownVotes * 2 THEN 'Positive Contributor'
        WHEN tur.DownVotes > tur.UpVotes THEN 'Net Negative'
        ELSE 'Balanced'
    END AS VoteTendency,
    SUBSTRING(COALESCE(u.Location, 'Unknown Location'), 1, 50) AS UserLocation,
    CASE
        WHEN u.WebsiteUrl IS NOT NULL AND u.WebsiteUrl <> '' THEN 'Has Website'
        ELSE 'No Website'
    END AS HasWebsite,
    CASE
        WHEN u.AboutMe IS NULL OR u.AboutMe = '' THEN 'No Bio'
        WHEN LENGTH(u.AboutMe) < 100 THEN 'Short Bio'
        ELSE 'Detailed Bio'
    END AS BioStatus,
    CAST(DATE_PART('day', TIMESTAMP '2024-10-01 12:34:56' - u.CreationDate) AS INTEGER) AS DaysSinceCreation,
    CAST(DATE_PART('day', TIMESTAMP '2024-10-01 12:34:56' - u.LastAccessDate) AS INTEGER) AS DaysSinceLastAccess
FROM TopUsersByReputation tur
LEFT JOIN UserPostActivity upa ON tur.UserId = upa.OwnerUserId
LEFT JOIN UserEditSummary ues ON tur.UserId = ues.UserId
LEFT JOIN Users u ON tur.UserId = u.Id
WHERE tur.reputation_rank <= 1000
GROUP BY
    tur.DisplayName,
    tur.Reputation,
    tur.reputation_rank,
    tur.UserId,
    tur.UpVotes,
    tur.DownVotes,
    upa.TotalPostsOwned,
    upa.QuestionCount,
    upa.AnswerCount,
    upa.AverageScore,
    upa.LastPostDate,
    upa.CommentCountOnOwnPosts,
    ues.DistinctPostsEdited,
    ues.TotalEdits,
    ues.LastEditDate,
    ues.TitleEdits,
    ues.BodyEdits,
    ues.TagEdits,
    u.Location,
    u.WebsiteUrl,
    u.AboutMe,
    u.CreationDate,
    u.LastAccessDate,
    u.Id
ORDER BY tur.reputation_rank;