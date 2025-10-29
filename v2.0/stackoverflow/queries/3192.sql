-- {"query": "3192.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-oss-120b", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2089, "output_tokens": 2596}
WITH
    UserPostStats AS (
        SELECT
            u.Id AS UserId,
            u.DisplayName AS DisplayName,
            COUNT(p.Id) AS TotalPosts,
            SUM(CASE WHEN p.PostTypeId = 1 THEN 1 ELSE 0 END) AS Questions,
            SUM(CASE WHEN p.PostTypeId = 2 THEN 1 ELSE 0 END) AS Answers,
            COALESCE(SUM(p.Score), 0) AS TotalScore,
            MAX(p.CreationDate) AS LastPostDate
        FROM Users u
        LEFT JOIN Posts p ON p.OwnerUserId = u.Id
        GROUP BY u.Id, u.DisplayName
    ),

    BadgeStats AS (
        SELECT
            b.UserId,
            COUNT(*) AS BadgeCount,
            SUM(CASE WHEN b.Class = 1 THEN 1 ELSE 0 END) AS GoldBadges,
            SUM(CASE WHEN b.Class = 2 THEN 1 ELSE 0 END) AS SilverBadges,
            SUM(CASE WHEN b.Class = 3 THEN 1 ELSE 0 END) AS BronzeBadges
        FROM Badges b
        GROUP BY b.UserId
    ),

    VoteStats AS (
        SELECT
            v.PostId,
            SUM(CASE WHEN vt.Name = 'UpMod' THEN 1 ELSE 0 END) AS UpVotes,
            SUM(CASE WHEN vt.Name = 'DownMod' THEN 1 ELSE 0 END) AS DownVotes
        FROM Votes v
        JOIN VoteTypes vt ON vt.Id = v.VoteTypeId
        GROUP BY v.PostId
    ),

    UserTagFrequency AS (
        SELECT
            p.OwnerUserId AS UserId,
            UNNEST(string_to_array(TRIM(BOTH '<' FROM TRIM(BOTH '>' FROM p.Tags)), '><')) AS TagName
        FROM Posts p
        WHERE p.Tags IS NOT NULL
    ),

    TopTagPerUser AS (
        SELECT
            utf.UserId,
            utf.TagName,
            ROW_NUMBER() OVER (PARTITION BY utf.UserId ORDER BY COUNT(*) DESC) AS rn
        FROM UserTagFrequency utf
        GROUP BY utf.UserId, utf.TagName
    ),

    RecentCloseReasons AS (
        SELECT
            ph.PostId,
            ph.CreationDate,
            CASE WHEN NULLIF(ph.Comment, '') IS NULL THEN NULL ELSE CAST(NULLIF(ph.Comment, '') AS INTEGER) END AS CloseReasonId
        FROM PostHistory ph
        WHERE ph.PostHistoryTypeId = 10
          AND ph.Comment IS NOT NULL
    ),

    UserClosureStats AS (
        SELECT
            p.OwnerUserId AS UserId,
            COUNT(DISTINCT rcr.PostId) AS ClosedPosts,
            COUNT(DISTINCT CASE WHEN rcr.CloseReasonId = 101 THEN rcr.PostId END) AS DuplicateClosures
        FROM Posts p
        LEFT JOIN RecentCloseReasons rcr ON rcr.PostId = p.Id
        WHERE p.OwnerUserId IS NOT NULL
        GROUP BY p.OwnerUserId
    ),

    UserVoteTotals AS (
        SELECT
            p.OwnerUserId AS UserId,
            SUM(vs.UpVotes) AS TotalUpVotes,
            SUM(vs.DownVotes) AS TotalDownVotes
        FROM Posts p
        LEFT JOIN VoteStats vs ON vs.PostId = p.Id
        GROUP BY p.OwnerUserId
    ),

    FilteredUsers AS (
        SELECT
            ups.UserId,
            ups.DisplayName,
            ups.TotalPosts,
            ups.Questions,
            ups.Answers,
            ups.TotalScore,
            ups.LastPostDate,
            COALESCE(bs.BadgeCount, 0) AS BadgeCount,
            COALESCE(bs.GoldBadges, 0) AS GoldBadges,
            COALESCE(bs.SilverBadges, 0) AS SilverBadges,
            COALESCE(bs.BronzeBadges, 0) AS BronzeBadges,
            COALESCE(ucs.ClosedPosts, 0) AS ClosedPosts,
            COALESCE(ucs.DuplicateClosures, 0) AS DuplicateClosures,
            ttu.TagName AS TopTag,
            COALESCE(uvt.TotalUpVotes, 0) AS TotalUpVotes,
            COALESCE(uvt.TotalDownVotes, 0) AS TotalDownVotes
        FROM UserPostStats ups
        LEFT JOIN BadgeStats bs ON bs.UserId = ups.UserId
        LEFT JOIN UserClosureStats ucs ON ucs.UserId = ups.UserId
        LEFT JOIN (
            SELECT UserId, TagName
            FROM TopTagPerUser
            WHERE rn = 1
        ) ttu ON ttu.UserId = ups.UserId
        LEFT JOIN UserVoteTotals uvt ON uvt.UserId = ups.UserId
        WHERE ups.TotalScore > 0
          AND (ups.Answers IS NOT NULL OR ups.Questions > 10)
        ORDER BY ups.TotalScore DESC
        FETCH FIRST 100 ROWS ONLY
    )

SELECT
    fu.UserId,
    fu.DisplayName,
    fu.TotalPosts,
    fu.Questions,
    fu.Answers,
    fu.TotalScore,
    fu.LastPostDate,
    fu.BadgeCount,
    fu.GoldBadges,
    fu.SilverBadges,
    fu.BronzeBadges,
    fu.ClosedPosts,
    fu.DuplicateClosures,
    fu.TopTag,
    fu.TotalUpVotes,
    fu.TotalDownVotes
FROM FilteredUsers fu

UNION ALL

SELECT
    CAST(NULL AS BIGINT) AS UserId,
    'Aggregated' AS DisplayName,
    SUM(fu.TotalPosts) AS TotalPosts,
    SUM(fu.Questions) AS Questions,
    SUM(fu.Answers) AS Answers,
    SUM(fu.TotalScore) AS TotalScore,
    MAX(fu.LastPostDate) AS LastPostDate,
    SUM(fu.BadgeCount) AS BadgeCount,
    SUM(fu.GoldBadges) AS GoldBadges,
    SUM(fu.SilverBadges) AS SilverBadges,
    SUM(fu.BronzeBadges) AS BronzeBadges,
    SUM(fu.ClosedPosts) AS ClosedPosts,
    SUM(fu.DuplicateClosures) AS DuplicateClosures,
    NULL AS TopTag,
    SUM(fu.TotalUpVotes) AS TotalUpVotes,
    SUM(fu.TotalDownVotes) AS TotalDownVotes
FROM FilteredUsers fu;