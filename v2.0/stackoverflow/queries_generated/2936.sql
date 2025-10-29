-- {"query": "2936.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1352} 

WITH RecursiveUserBadges AS (
    SELECT
        u.Id AS UserId,
        u.DisplayName,
        b.Name AS BadgeName,
        b.Class,
        b.Date,
        ROW_NUMBER() OVER (PARTITION BY u.Id ORDER BY b.Date DESC, b.Class) AS BadgeRank
    FROM Users u
    LEFT JOIN Badges b ON b.UserId = u.Id
    WHERE u.Reputation > 1000
),
LatestPostsWithAnswers AS (
    SELECT
        p.Id,
        p.PostTypeId,
        p.Title,
        p.CreationDate,
        p.Score,
        p.ViewCount,
        p.Tags,
        p.OwnerUserId,
        p.AcceptedAnswerId,
        a.Score AS AcceptedAnswerScore,
        ROW_NUMBER() OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate DESC) AS PostRank
    FROM Posts p
    LEFT JOIN Posts a ON a.Id = p.AcceptedAnswerId
    WHERE p.PostTypeId = 1
),
PostLinkCounts AS (
    SELECT
        pl.PostId,
        COUNT(DISTINCT CASE WHEN lt.Name = 'Duplicate' THEN pl.RelatedPostId END) AS DuplicateCount,
        COUNT(DISTINCT CASE WHEN lt.Name = 'Linked' THEN pl.RelatedPostId END) AS LinkedCount
    FROM PostLinks pl
    JOIN LinkTypes lt ON lt.Id = pl.LinkTypeId
    GROUP BY pl.PostId
),
UserActivityStats AS (
    SELECT
        u.Id AS UserId,
        u.DisplayName,
        COUNT(DISTINCT p.Id) FILTER (WHERE p.PostTypeId = 1) AS QuestionCount,
        COUNT(DISTINCT p2.Id) FILTER (WHERE p2.PostTypeId = 2) AS AnswerCount,
        COALESCE(SUM(vtUp.Count), 0) AS TotalUpVotes,
        COALESCE(SUM(vtDown.Count), 0) AS TotalDownVotes,
        MAX(p.CreationDate) AS LastPostDate,
        MIN(u.CreationDate) AS UserSince,
        AVG(COALESCE(p.Score,0)) AS AvgPostScore,
        SUM(COALESCE(pl.DuplicateCount,0)) AS TotalDuplicateLinks,
        SUM(COALESCE(pl.LinkedCount,0)) AS TotalLinkedPosts
    FROM Users u
    LEFT JOIN Posts p ON p.OwnerUserId = u.Id
    LEFT JOIN Posts p2 ON p2.OwnerUserId = u.Id
    LEFT JOIN (
        SELECT PostId, COUNT(*) AS Count
        FROM Votes v
        JOIN VoteTypes vt ON vt.Id = v.VoteTypeId
        WHERE vt.Name = 'UpMod'
        GROUP BY PostId
    ) vtUp ON vtUp.PostId = p.Id
    LEFT JOIN (
        SELECT PostId, COUNT(*) AS Count
        FROM Votes v
        JOIN VoteTypes vt ON vt.Id = v.VoteTypeId
        WHERE vt.Name = 'DownMod'
        GROUP BY PostId
    ) vtDown ON vtDown.PostId = p.Id
    LEFT JOIN PostLinkCounts pl ON pl.PostId = p.Id
    WHERE u.Reputation > 1000
    GROUP BY u.Id, u.DisplayName
),
ComplexFilteredPosts AS (
    SELECT
        p.Id,
        p.Title,
        p.Tags,
        p.CreationDate,
        p.Score,
        p.ViewCount,
        pls.DuplicateCount,
        pls.LinkedCount,
        ph.Comment AS CloseReasonJSON,
        COALESCE(phr.ReopenCount,0) AS ReopenVotes,
        ROW_NUMBER() OVER (PARTITION BY p.OwnerUserId ORDER BY p.Score DESC) AS PostScoreRank
    FROM Posts p
    LEFT JOIN PostLinkCounts pls ON pls.PostId = p.Id
    LEFT JOIN PostHistory ph ON ph.PostId = p.Id AND ph.PostHistoryTypeId = 10 /* Post Closed */
    LEFT JOIN (
        SELECT PostId, COUNT(*) AS ReopenCount
        FROM PostHistory
        WHERE PostHistoryTypeId = 11 /* Post Reopened */
        GROUP BY PostId
    ) phr ON phr.PostId = p.Id
    WHERE p.PostTypeId = 1 AND p.ClosedDate IS NOT NULL
),
TopTagsAggregated AS (
    SELECT
        t.TagName,
        COUNT(p.Id) AS QuestionCount,
        AVG(p.Score) AS AvgScore,
        SUM(p.ViewCount) AS TotalViews,
        MAX(p.LastActivityDate) AS LastActivity,
        STRING_AGG(DISTINCT u.DisplayName, ', ') AS RecentTopUsers
    FROM Tags t
    JOIN Posts p ON ('<' || t.TagName || '>') = ANY(string_to_array(p.Tags, '><')) OR p.Tags LIKE '%' || '<' || t.TagName || '>' || '%'
    JOIN Users u ON u.Id = p.OwnerUserId
    WHERE p.PostTypeId = 1
    GROUP BY t.TagName
    ORDER BY QuestionCount DESC
    LIMIT 10
)
SELECT
    uas.UserId,
    uas.DisplayName,
    uas.QuestionCount,
    uas.AnswerCount,
    uas.TotalUpVotes,
    uas.TotalDownVotes,
    uas.AvgPostScore,
    uas.TotalDuplicateLinks,
    uas.TotalLinkedPosts,
    rpb.BadgeName,
    rpb.Class AS BadgeClass,
    rpb.Date AS BadgeDate,
    pfp.Id AS ClosedPostId,
    pfp.Title AS ClosedPostTitle,
    pfp.DuplicateCount,
    pfp.LinkedCount,
    pfp.CloseReasonJSON,
    pfp.ReopenVotes,
    tta.TagName AS PopularTag,
    tta.QuestionCount AS TagQuestionCount,
    tta.AvgScore AS TagAvgScore,
    tta.TotalViews AS TagTotalViews,
    tta.LastActivity AS TagLastActivity,
    tta.RecentTopUsers AS TagTopUsers
FROM UserActivityStats uas
LEFT JOIN RecursiveUserBadges rpb ON rpb.UserId = uas.UserId AND rpb.BadgeRank = 1
LEFT JOIN ComplexFilteredPosts pfp ON pfp.OwnerUserId = uas.UserId AND pfp.PostScoreRank = 1
LEFT JOIN TopTagsAggregated tta ON TRUE
WHERE uas.QuestionCount > 5 AND uas.AvgPostScore > 1.5
ORDER BY uas.TotalUpVotes DESC, pfp.ReopenVotes DESC
LIMIT 50;
