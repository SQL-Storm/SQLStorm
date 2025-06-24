
WITH UserPostStatistics AS (
    SELECT
        u.Id AS UserId,
        u.DisplayName,
        COUNT(p.Id) AS PostCount,
        SUM(CASE WHEN v.Id IS NOT NULL AND vt.Id = 2 THEN 1 ELSE 0 END) AS UpVoteCount,
        SUM(CASE WHEN v.Id IS NOT NULL AND vt.Id = 3 THEN 1 ELSE 0 END) AS DownVoteCount,
        MAX(p.CreationDate) AS LastPostDate
    FROM
        Users u
    LEFT JOIN
        Posts p ON u.Id = p.OwnerUserId
    LEFT JOIN
        Votes v ON p.Id = v.PostId
    LEFT JOIN
        VoteTypes vt ON v.VoteTypeId = vt.Id
    GROUP BY
        u.Id, u.DisplayName
), 
RecentBadges AS (
    SELECT
        b.UserId,
        GROUP_CONCAT(b.Name SEPARATOR ', ') AS BadgeNames,
        MAX(b.Date) AS LastAwardDate
    FROM
        Badges b
    WHERE
        b.Date > (TIMESTAMP '2024-10-01 12:34:56' - INTERVAL 1 YEAR)
    GROUP BY
        b.UserId
),
PostHistorySummary AS (
    SELECT
        ph.PostId,
        GROUP_CONCAT(DISTINCT pht.Name SEPARATOR ', ') AS HistoryTypes,
        COUNT(*) AS HistoryCount
    FROM
        PostHistory ph
    INNER JOIN
        PostHistoryTypes pht ON ph.PostHistoryTypeId = pht.Id
    GROUP BY
        ph.PostId
),
TopUsers AS (
    SELECT
        ups.UserId,
        ups.DisplayName,
        ups.PostCount,
        ups.UpVoteCount,
        ups.DownVoteCount,
        ups.LastPostDate,
        rb.BadgeNames,
        @row_num := IF(@prev_post_count = ups.PostCount AND @prev_upvote_count = ups.UpVoteCount, @row_num, @row_num + 1) AS UserRank,
        @prev_post_count := ups.PostCount,
        @prev_upvote_count := ups.UpVoteCount
    FROM
        UserPostStatistics ups
    LEFT JOIN
        RecentBadges rb ON ups.UserId = rb.UserId,
        (SELECT @row_num := 0, @prev_post_count := NULL, @prev_upvote_count := NULL) AS vars
)
SELECT
    tu.UserId,
    tu.DisplayName,
    tu.PostCount,
    tu.UpVoteCount,
    tu.DownVoteCount,
    tu.LastPostDate,
    tu.BadgeNames,
    phs.HistoryTypes,
    phs.HistoryCount
FROM
    TopUsers tu
LEFT JOIN
    PostHistorySummary phs ON tu.UserId IN (SELECT OwnerUserId FROM Posts WHERE Id = phs.PostId)
WHERE
    tu.UserRank <= 10
    AND (tu.LastPostDate BETWEEN (TIMESTAMP '2024-10-01 12:34:56' - INTERVAL 30 DAY) AND TIMESTAMP '2024-10-01 12:34:56' OR tu.BadgeNames IS NOT NULL)
ORDER BY
    tu.PostCount DESC,
    tu.UpVoteCount DESC;
