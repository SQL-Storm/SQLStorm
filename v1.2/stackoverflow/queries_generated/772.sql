-- {"query": "772.sql", "dataset": "stackoverflow", "version": "v1.2", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 0.7, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1835} 

WITH RecursiveUserBadgeCounts AS (
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
    WHERE r.BadgeCount < 3 -- artificial recursion limit
),
UserPostStats AS (
    SELECT
        u.Id AS UserId,
        u.DisplayName,
        COUNT(DISTINCT p.Id) FILTER (WHERE p.PostTypeId = 1) AS QuestionsCount,
        COUNT(DISTINCT p.Id) FILTER (WHERE p.PostTypeId = 2) AS AnswersCount,
        AVG(p.Score) FILTER (WHERE p.PostTypeId IN (1, 2)) AS AvgPostScore,
        SUM(COALESCE(p.ViewCount, 0)) FILTER (WHERE p.PostTypeId = 1) AS TotalQuestionViews,
        MAX(p.CreationDate) FILTER (WHERE p.PostTypeId IN (1, 2)) AS LastPostDate
    FROM Users u
    LEFT JOIN Posts p ON u.Id = p.OwnerUserId
    GROUP BY u.Id, u.DisplayName
),
TopTags AS (
    SELECT
        UNNEST(string_to_array(substring(p.Tags, 2, length(p.Tags)-2), '><')) AS Tag,
        p.OwnerUserId AS UserId,
        COUNT(*) AS TagUseCount
    FROM Posts p
    WHERE p.PostTypeId = 1 AND p.Tags IS NOT NULL
    GROUP BY Tag, p.OwnerUserId
),
UserTopTag AS (
    SELECT DISTINCT ON (tt.UserId)
        tt.UserId,
        tt.Tag AS TopTag,
        tt.TagUseCount
    FROM TopTags tt
    ORDER BY tt.UserId, tt.TagUseCount DESC
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
        RANK() OVER (ORDER BY p.ViewCount DESC NULLS LAST) AS ViewRank
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
    LEFT JOIN CloseReasonTypes crt ON ph.Comment::int = crt.Id AND ph.PostHistoryTypeId = 10
    WHERE ph.PostHistoryTypeId = 10
    GROUP BY ph.PostId, crt.Name
),
UserCommentActivity AS (
    SELECT
        c.UserId,
        COUNT(c.Id) AS CommentCount,
        MAX(c.CreationDate) AS LastCommentDate,
        STRING_AGG(DISTINCT substring(c.Text from 1 for 20), '; ' ORDER BY MAX(c.CreationDate) DESC) AS SampleComments
    FROM Comments c
    GROUP BY c.UserId
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
        COALESCE(cc.CloseCount, 0) AS TotalClosedPosts,
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
        SELECT ph.PostId, ph.UserId, COUNT(*) AS CloseCount
        FROM PostHistory ph
        WHERE ph.PostHistoryTypeId = 10
        GROUP BY ph.PostId, ph.UserId
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
    SELECT DISTINCT ON (hap.OwnerUserId)
        hap.OwnerUserId,
        hap.Id AS PostId,
        hap.Title,
        hap.Score,
        hap.ViewCount,
        hap.UpVotes,
        hap.DownVotes,
        hap.LinkedPostsCount,
        hap.CloseVotesCount
    FROM HighActivityPosts hap
    ORDER BY hap.OwnerUserId, hap.Score DESC, hap.ViewCount DESC
)
SELECT
    ua.UserId,
    ua.DisplayName,
    ua.QuestionsCount,
    ua.AnswersCount,
    ROUND(ua.AvgPostScore::numeric, 2) AS AvgPostScore,
    ua.TotalQuestionViews,
    ua.LastPostDate,
    ua.TopTag,
    ua.TotalBadges,
    ua.TotalClosedPosts,
    ua.TotalComments,
    ua.LastCommentDate,
    LEFT(ua.SampleComments, 200) AS SampleComments,
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
        WHEN ua.AvgPostScore BETWEEN 5 AND 10 THEN 'Medium'
        ELSE 'Low'
    END AS UserScoreCategory,
    CASE
        WHEN ua.TotalBadges >= 10 THEN 'Veteran'
        WHEN ua.TotalBadges BETWEEN 5 AND 9 THEN 'Intermediate'
        ELSE 'Novice'
    END AS BadgeLevel,
    CONCAT(
        'User ', COALESCE(ua.DisplayName, 'Unknown'),
        ' has ', ua.QuestionsCount, ' questions and ',
        ua.AnswersCount, ' answers. Top tag: ', COALESCE(ua.TopTag, 'N/A'),
        '. Top post: "', COALESCE(uphe.Title, 'None'), '" scored ', uphe.Score,
        ' with ', uphe.ViewCount, ' views.'
    ) AS UserSummary
FROM UserAggregates ua
LEFT JOIN UserPostWithHighestEngagement uphe ON ua.UserId = uphe.OwnerUserId
WHERE ua.QuestionsCount > 0
ORDER BY ua.TotalBadges DESC NULLS LAST, ua.AvgPostScore DESC NULLS LAST
LIMIT 100;
