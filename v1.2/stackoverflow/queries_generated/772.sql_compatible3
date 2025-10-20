WITH RECURSIVE RecursiveUserBadgeCounts AS (
    SELECT
        u.Id AS UserId,
        u.DisplayName,
        b.Class,
        COUNT(b.Id) AS BadgeCount
    FROM Users u
    LEFT JOIN Badges b ON u.Id = b.UserId
    GROUP BY u.Id, u.DisplayName, b.Class

    UNION ALL

    SELECT
        r.UserId,
        r.DisplayName,
        r.Class,
        r.BadgeCount + 1
    FROM RecursiveUserBadgeCounts r
    WHERE r.BadgeCount < 3
),
UserPostStats AS (
    SELECT
        u.Id AS UserId,
        u.DisplayName,
        COUNT(DISTINCT CASE WHEN p.PostTypeId = 1 THEN p.Id END) AS QuestionsCount,
        COUNT(DISTINCT CASE WHEN p.PostTypeId = 2 THEN p.Id END) AS AnswersCount,
        AVG(CASE WHEN p.PostTypeId IN (1, 2) THEN p.Score END) AS AvgPostScore,
        SUM(COALESCE(CASE WHEN p.PostTypeId = 1 THEN p.ViewCount END, 0)) AS TotalQuestionViews,
        MAX(CASE WHEN p.PostTypeId IN (1, 2) THEN p.CreationDate END) AS LastPostDate
    FROM Users u
    LEFT JOIN Posts p ON u.Id = p.OwnerUserId
    GROUP BY u.Id, u.DisplayName
),
TopTags AS (
    SELECT
        tag AS Tag,
        p.OwnerUserId AS UserId,
        COUNT(*) AS TagUseCount
    FROM Posts p,
         UNNEST(string_to_array(SUBSTRING(p.Tags FROM 2 FOR CHAR_LENGTH(p.Tags)-2), '><')) AS tag
    WHERE p.PostTypeId = 1 AND p.Tags IS NOT NULL
    GROUP BY tag, p.OwnerUserId
),
UserTopTag AS (
    SELECT tt.UserId,
        tt.Tag AS TopTag,
        tt.TagUseCount
    FROM (
        SELECT
            tt.*,
            ROW_NUMBER() OVER (PARTITION BY tt.UserId ORDER BY tt.TagUseCount DESC) AS rn
        FROM TopTags tt
    ) tt
    WHERE tt.rn = 1
),
PostWithRanks AS (
    SELECT
        p.Id,
        p.Title,
        p.PostTypeId,
        p.OwnerUserId,
        p.Score,
        p.ViewCount,
        p.CreationDate,
        p.AcceptedAnswerId,
        ROW_NUMBER() OVER (PARTITION BY p.OwnerUserId ORDER BY p.Score DESC, p.CreationDate DESC) AS ScoreRank,
        RANK() OVER (ORDER BY p.ViewCount DESC) AS ViewRank
    FROM Posts p
    WHERE p.PostTypeId IN (1, 2)
),
CloseReasonsCount AS (
    SELECT
        ph.PostId,
        crt.Name AS CloseReason,
        COUNT(*) AS CloseCount
    FROM PostHistory ph
    JOIN PostHistoryTypes pht ON ph.PostHistoryTypeId = pht.Id
    LEFT JOIN CloseReasonTypes crt ON CAST(ph.Comment AS INTEGER) = crt.Id AND ph.PostHistoryTypeId = 10
    WHERE ph.PostHistoryTypeId = 10
    GROUP BY ph.PostId, crt.Name
),
UserCommentActivity AS (
    SELECT
        sc.UserId,
        COUNT(sc.CommentSample) AS CommentCount,
        MAX(sc.CreationDate) AS LastCommentDate,
        STRING_AGG(sc.CommentSample, '; ') AS SampleComments
    FROM (
        SELECT DISTINCT c.UserId, SUBSTRING(c.Text FROM 1 FOR 20) AS CommentSample, c.CreationDate
        FROM Comments c
    ) sc
    GROUP BY sc.UserId
),
UserAggregates AS (
    SELECT
        ups.UserId,
        ups.DisplayName,
        ups.QuestionsCount,
        ups.AnswersCount,
        ups.AvgPostScore,
        ups.TotalQuestionViews,
        ups.LastPostDate,
        ut.TopTag,
        COALESCE(ubc.BadgeCount, 0) AS TotalBadges,
        COALESCE(cc.TotalClosedPosts, 0) AS TotalClosedPosts,
        COALESCE(uca.CommentCount, 0) AS TotalComments,
        uca.LastCommentDate,
        uca.SampleComments
    FROM UserPostStats ups
    LEFT JOIN UserTopTag ut ON ups.UserId = ut.UserId
    LEFT JOIN (
        SELECT UserId, COUNT(*) AS BadgeCount
        FROM Badges
        GROUP BY UserId
    ) ubc ON ups.UserId = ubc.UserId
    LEFT JOIN (
        SELECT ph.UserId, COUNT(*) AS TotalClosedPosts
        FROM PostHistory ph
        WHERE ph.PostHistoryTypeId = 10
        GROUP BY ph.UserId
    ) cc ON ups.UserId = cc.UserId
    LEFT JOIN UserCommentActivity uca ON ups.UserId = uca.UserId
),
HighActivityPosts AS (
    SELECT
        p.Id,
        p.Title,
        p.PostTypeId,
        p.OwnerUserId,
        p.CreationDate,
        p.Score,
        p.ViewCount,
        COALESCE(vt.UpVotes, 0) AS UpVotes,
        COALESCE(vt.DownVotes, 0) AS DownVotes,
        COALESCE(pl.LinkedCount, 0) AS LinkedPostsCount,
        COALESCE(crc.CloseCount, 0) AS CloseVotesCount,
        ROW_NUMBER() OVER (PARTITION BY p.OwnerUserId ORDER BY p.Score DESC, p.ViewCount DESC) AS RankByScoreView
    FROM Posts p
    LEFT JOIN (
        SELECT
            v.PostId,
            SUM(CASE WHEN vt.Name = 'UpMod' THEN 1 ELSE 0 END) AS UpVotes,
            SUM(CASE WHEN vt.Name = 'DownMod' THEN 1 ELSE 0 END) AS DownVotes
        FROM Votes v
        JOIN VoteTypes vt ON v.VoteTypeId = vt.Id
        GROUP BY v.PostId
    ) vt ON p.Id = vt.PostId
    LEFT JOIN (
        SELECT
            pl.PostId,
            COUNT(*) AS LinkedCount
        FROM PostLinks pl
        GROUP BY pl.PostId
    ) pl ON p.Id = pl.PostId
    LEFT JOIN (
        SELECT
            ph.PostId,
            COUNT(*) AS CloseCount
        FROM PostHistory ph
        WHERE ph.PostHistoryTypeId = 10
        GROUP BY ph.PostId
    ) crc ON p.Id = crc.PostId
    WHERE p.PostTypeId IN (1, 2)
),
UserPostWithHighestEngagement AS (
    SELECT
        hap.OwnerUserId,
        hap.Id AS PostId,
        hap.Title,
        hap.Score,
        hap.ViewCount,
        hap.UpVotes,
        hap.DownVotes,
        hap.LinkedPostsCount,
        hap.CloseVotesCount
    FROM (
        SELECT
            hap.*,
            ROW_NUMBER() OVER (PARTITION BY hap.OwnerUserId ORDER BY hap.Score DESC, hap.ViewCount DESC) AS rn
        FROM HighActivityPosts hap
    ) hap
    WHERE hap.rn = 1
)
SELECT
    ua.UserId,
    ua.DisplayName,
    ua.QuestionsCount,
    ua.AnswersCount,
    ROUND(CAST(ua.AvgPostScore AS NUMERIC), 2) AS AvgPostScore,
    ua.TotalQuestionViews,
    ua.LastPostDate,
    ua.TopTag,
    ua.TotalBadges,
    ua.TotalClosedPosts,
    ua.TotalComments,
    ua.LastCommentDate,
    SUBSTRING(ua.SampleComments FROM 1 FOR 200) AS SampleComments,
    uphe.PostId,
    uphe.Title AS TopPostTitle,
    uphe.Score AS TopPostScore,
    uphe.ViewCount AS TopPostViewCount,
    uphe.UpVotes,
    uphe.DownVotes,
    uphe.LinkedPostsCount,
    uphe.CloseVotesCount,
    CASE
        WHEN ua.AvgPostScore > 10 THEN 'High'
        WHEN ua.AvgPostScore >= 5 AND ua.AvgPostScore <= 10 THEN 'Medium'
        ELSE 'Low'
    END AS UserScoreCategory,
    CASE
        WHEN ua.TotalBadges >= 10 THEN 'Veteran'
        WHEN ua.TotalBadges BETWEEN 5 AND 9 THEN 'Intermediate'
        ELSE 'Novice'
    END AS BadgeLevel,
    ('User ' || COALESCE(ua.DisplayName, 'Unknown')
        || ' has ' || COALESCE(CAST(ua.QuestionsCount AS TEXT), '0') || ' questions and '
        || COALESCE(CAST(ua.AnswersCount AS TEXT), '0') || ' answers. Top tag: ' || COALESCE(ua.TopTag, 'N/A')
        || '. Top post: "' || COALESCE(uphe.Title, 'None') || '" scored ' || COALESCE(CAST(uphe.Score AS TEXT), '0')
        || ' with ' || COALESCE(CAST(uphe.ViewCount AS TEXT), '0') || ' views.'
    ) AS UserSummary
FROM UserAggregates ua
LEFT JOIN UserPostWithHighestEngagement uphe ON ua.UserId = uphe.OwnerUserId
WHERE ua.QuestionsCount > 0
ORDER BY ua.TotalBadges DESC NULLS LAST, ua.AvgPostScore DESC NULLS LAST
LIMIT 100;