-- {"query": "1147.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-flash", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 3207}
WITH RecentActiveUsers AS (
    SELECT
        u.Id AS UserId,
        u.DisplayName,
        u.Reputation,
        u.CreationDate,
        u.LastAccessDate,
        u.Views,
        u.UpVotes,
        u.DownVotes,
        u.AccountId
    FROM Users u
    WHERE
        u.LastAccessDate >= CAST('2024-10-01 12:34:56' AS timestamp) - INTERVAL '6 months'
        AND u.Views > 500
        AND u.Reputation > 200
        AND u.DisplayName IS NOT NULL
        AND u.AccountId IS NOT NULL
),
PopularTags AS (
    SELECT
        t.TagName,
        t.Id AS TagId
    FROM Tags t
    WHERE t.Count > 50000 AND t.WikiPostId IS NOT NULL
    ORDER BY t.Count DESC, t.TagName
    LIMIT 100
),
PostsWithPopularTags AS (
    SELECT
        p.Id AS PostId,
        p.PostTypeId,
        p.AcceptedAnswerId,
        p.CreationDate,
        p.Score,
        p.ViewCount,
        p.OwnerUserId,
        p.Title,
        p.Tags,
        tag_name_unnested AS TagName
    FROM Posts p
    JOIN LATERAL (
        SELECT unnest_val AS tag_name_unnested
        FROM unnest(string_to_array(SUBSTRING(p.Tags FROM 2 FOR LENGTH(p.Tags) - 2), '><')) AS t(unnest_val)
    ) u ON TRUE
    JOIN PopularTags pt ON u.tag_name_unnested = pt.TagName
    WHERE
        p.PostTypeId = 1
        AND p.CreationDate >= CAST('2024-10-01 12:34:56' AS timestamp) - INTERVAL '2 years'
        AND p.Score >= 5
        AND p.ViewCount >= 100
        AND p.ClosedDate IS NULL
        AND p.Body IS NOT NULL AND LENGTH(p.Body) > 50
),
PostDetailsExtended AS (
    SELECT
        ppt.PostId,
        ppt.OwnerUserId,
        ppt.PostTypeId,
        ppt.Score,
        ppt.ViewCount,
        ppt.CreationDate,
        ppt.Title,
        ppt.TagName,
        ppt.AcceptedAnswerId,
        COALESCE(SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END), 0) AS UpvoteCountOnPost,
        COALESCE(SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END), 0) AS DownvoteCountOnPost,
        COUNT(DISTINCT c.Id) AS CommentCountOnPost,
        MAX(CASE WHEN ph.PostHistoryTypeId IN (4,5,6) THEN ph.CreationDate END) AS LastEditHistoryDate,
        AVG(ppt.Score * (1.0 + LOG(ppt.ViewCount + 1))) OVER (PARTITION BY ppt.TagName) AS WeightedAvgScoreForTag,
        RANK() OVER (PARTITION BY ppt.TagName ORDER BY ppt.Score DESC, ppt.ViewCount DESC, ppt.CreationDate DESC) AS RankInTag,
        EXTRACT(EPOCH FROM (ppt.CreationDate - LAG(ppt.CreationDate, 1, ppt.CreationDate) OVER (PARTITION BY ppt.OwnerUserId ORDER BY ppt.CreationDate))) / (3600 * 24) AS DaysSincePrevPost
    FROM PostsWithPopularTags ppt
    LEFT JOIN Votes v ON ppt.PostId = v.PostId AND v.VoteTypeId IN (2, 3)
    LEFT JOIN Comments c ON ppt.PostId = c.PostId
    LEFT JOIN PostHistory ph ON ppt.PostId = ph.PostId
    GROUP BY
        ppt.PostId, ppt.OwnerUserId, ppt.PostTypeId, ppt.Score, ppt.ViewCount, ppt.CreationDate,
        ppt.Title, ppt.TagName, ppt.AcceptedAnswerId
    HAVING
        COALESCE(SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END), 0) + COALESCE(SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END), 0) > 0
),
UserEngagementSummary AS (
    SELECT
        rau.UserId,
        rau.DisplayName,
        rau.Reputation,
        rau.LastAccessDate,
        rau.Views,
        rau.UpVotes AS UserTotalUpVotes,
        rau.DownVotes AS UserTotalDownVotes,
        COUNT(DISTINCT pde.PostId) AS TotalQuestionsInPopularTags,
        SUM(CASE WHEN pde.AcceptedAnswerId IS NOT NULL THEN 1 ELSE 0 END) AS QuestionsWithAcceptedAnswers,
        SUM(pde.UpvoteCountOnPost) AS TotalUpvotesReceivedOnQuestions,
        SUM(pde.DownvoteCountOnPost) AS TotalDownvotesReceivedOnQuestions,
        SUM(pde.CommentCountOnPost) AS TotalCommentsReceivedOnQuestions,
        MAX(pde.LastEditHistoryDate) AS LatestQuestionEditDate,
        AVG(pde.RankInTag) AS AvgRankOfQuestionsInTags,
        COUNT(DISTINCT pde.TagName) AS UniquePopularTagsContributedTo,
        AVG(pde.DaysSincePrevPost) FILTER (WHERE pde.DaysSincePrevPost > 0) AS AvgDaysBetweenQuestions,
        COALESCE(SUM(pde.UpvoteCountOnPost) * 1.0 / NULLIF(SUM(pde.UpvoteCountOnPost) + SUM(pde.DownvoteCountOnPost), 0), 0) AS UpvoteRatio
    FROM RecentActiveUsers rau
    LEFT JOIN PostDetailsExtended pde ON rau.UserId = pde.OwnerUserId
    GROUP BY
        rau.UserId, rau.DisplayName, rau.Reputation, rau.LastAccessDate, rau.Views,
        rau.UpVotes, rau.DownVotes
    HAVING
        COUNT(DISTINCT pde.PostId) >= 2
        AND SUM(pde.Score) >= 15
),
HighValueBadgeUsers AS (
    SELECT
        b.UserId,
        STRING_AGG(bdg, '; ') AS BadgesSummary
    FROM (
        SELECT b.UserId, b.Name || ' (' || CASE b.Class WHEN 1 THEN 'Gold' WHEN 2 THEN 'Silver' ELSE 'Bronze' END || ')' AS bdg, b.Class, b.Name
        FROM Badges b
        WHERE b.Class IN (1,2,3)
    ) b
    GROUP BY b.UserId
),
UserPerformanceScore AS (
    SELECT
        ues.UserId,
        ues.DisplayName,
        ues.Reputation,
        ues.TotalQuestionsInPopularTags,
        ues.QuestionsWithAcceptedAnswers,
        ues.TotalUpvotesReceivedOnQuestions,
        ues.TotalDownvotesReceivedOnQuestions,
        ues.AvgRankOfQuestionsInTags,
        COALESCE(hb.BadgesSummary, 'No Significant Badges') AS BadgesDescription,
        ues.UpvoteRatio,
        (
            (ues.Reputation / 1000.0) * 0.35
            + (ues.UpvoteRatio) * 0.25
            + (ues.QuestionsWithAcceptedAnswers / (ues.TotalQuestionsInPopularTags + 1.0)) * 0.20
            + (100.0 / (ues.AvgRankOfQuestionsInTags + 1.0)) * 0.10
            + (ues.UniquePopularTagsContributedTo * 5.0) * 0.05
            + CASE WHEN ues.LatestQuestionEditDate IS NOT NULL AND ues.LatestQuestionEditDate >= CAST('2024-10-01 12:34:56' AS timestamp) - INTERVAL '3 months' THEN 10 ELSE 0 END * 0.05
            + CASE WHEN hb.UserId IS NOT NULL THEN
                CASE
                    WHEN hb.BadgesSummary LIKE '%Gold%' THEN 50
                    WHEN hb.BadgesSummary LIKE '%Silver%' THEN 25
                    ELSE 10
                END
              ELSE 0
              END * 0.05
        ) AS PerformanceScore,
        (SELECT COUNT(DISTINCT a.Id) FROM Posts a WHERE a.OwnerUserId = ues.UserId AND a.PostTypeId = 2 AND a.Score > 20 AND a.AcceptedAnswerId IS NOT NULL) AS HighScoreAcceptedAnswersGiven,
        EXISTS (
            SELECT 1
            FROM PostLinks pl
            JOIN Posts p_orig ON pl.PostId = p_orig.Id
            WHERE p_orig.OwnerUserId = ues.UserId
              AND pl.LinkTypeId = 3
              AND pl.CreationDate >= CAST('2024-10-01 12:34:56' AS timestamp) - INTERVAL '1 year'
        ) AS HasPostedDuplicateQuestionRecently
    FROM UserEngagementSummary ues
    LEFT JOIN HighValueBadgeUsers hb ON ues.UserId = hb.UserId
),
HighlyVotedCommentedUsers AS (
    SELECT
        rau.UserId,
        rau.DisplayName,
        rau.Reputation,
        COALESCE(SUM(v.BountyAmount), 0) AS TotalBountyReceived,
        COUNT(DISTINCT c.Id) AS TotalCommentsReceived,
        COUNT(DISTINCT vp.Id) AS TotalPostsVotedOn,
        (rau.Reputation / 2000.0) * 0.4
        + (COALESCE(SUM(v.BountyAmount), 0) / 1000.0) * 0.3
        + (COUNT(DISTINCT c.Id) / 10.0) * 0.2
        + (COUNT(DISTINCT vp.Id) / 50.0) * 0.1 AS InfluenceScore
    FROM RecentActiveUsers rau
    LEFT JOIN Posts p ON rau.UserId = p.OwnerUserId
    LEFT JOIN Votes v ON p.Id = v.PostId AND v.VoteTypeId = 9
    LEFT JOIN Comments c ON p.Id = c.PostId
    LEFT JOIN Votes vp ON rau.UserId = vp.UserId AND vp.VoteTypeId IN (2,3)
    GROUP BY
        rau.UserId, rau.DisplayName, rau.Reputation
    HAVING
        rau.Reputation > 5000
        AND COUNT(DISTINCT c.Id) > 20
        AND COUNT(DISTINCT vp.Id) > 50
)
SELECT
    'High Performance' AS UserCategory,
    ups.UserId,
    ups.DisplayName,
    ups.Reputation,
    CAST(ups.PerformanceScore AS DECIMAL(10,2)) AS ScoreValue,
    ups.BadgesDescription AS KeyAttributes,
    ups.HighScoreAcceptedAnswersGiven AS SecondaryMetric1,
    (SELECT STRING_AGG(tag_snip, ', ')
     FROM (
         SELECT DISTINCT SUBSTRING(t_latest.TagName FROM 1 FOR 20) AS tag_snip
         FROM Posts p_latest
         JOIN LATERAL (
             SELECT unnest_val
             FROM unnest(string_to_array(SUBSTRING(p_latest.Tags FROM 2 FOR LENGTH(p_latest.Tags) - 2), '><')) AS t(unnest_val)
         ) u ON TRUE
         JOIN Tags t_latest ON u.unnest_val = t_latest.TagName
         WHERE p_latest.OwnerUserId = ups.UserId
           AND p_latest.CreationDate >= CAST('2024-10-01 12:34:56' AS timestamp) - INTERVAL '6 months'
         GROUP BY SUBSTRING(t_latest.TagName FROM 1 FOR 20), t_latest.TagName
         ORDER BY SUBSTRING(t_latest.TagName FROM 1 FOR 20)
         LIMIT 5
     ) q
    ) AS RecentTagsString,
    COALESCE(u.Location, 'Unknown') ||
    CASE WHEN u.Location IS NOT NULL AND LENGTH(u.Location) > 0 THEN
        ' (' || UPPER(SUBSTRING(u.Location FROM 1 FOR 1)) || SUBSTRING(u.Location FROM 2 FOR 2) || '...)'
    ELSE '' END AS UserLocationDetails,
    (SELECT AVG(LENGTH(ans.Body)) FROM Posts ans WHERE ans.OwnerUserId = ups.UserId AND ans.PostTypeId = 2 AND ans.CreationDate >= CAST('2024-10-01 12:34:56' AS timestamp) - INTERVAL '1 year' AND ans.Body IS NOT NULL) AS AvgRecentAnswerBodyLength,
    ups.HasPostedDuplicateQuestionRecently AS DuplicateQuestionFlag
FROM UserPerformanceScore ups
JOIN Users u ON ups.UserId = u.Id
WHERE
    ups.PerformanceScore > 20
    AND ups.TotalQuestionsInPopularTags >= 3
    AND ups.HighScoreAcceptedAnswersGiven >= 2
    AND NOT ups.HasPostedDuplicateQuestionRecently
    AND (u.Reputation > (SELECT AVG(Reputation) FROM Users WHERE CreationDate >= CAST('2024-10-01 12:34:56' AS timestamp) - INTERVAL '2 years') * 1.5)
    AND u.AboutMe IS NOT NULL AND LENGTH(u.AboutMe) > 100
UNION ALL
SELECT
    'High Influence' AS UserCategory,
    hvcu.UserId,
    hvcu.DisplayName,
    hvcu.Reputation,
    CAST(hvcu.InfluenceScore AS DECIMAL(10,2)) AS ScoreValue,
    'Bounties: ' || hvcu.TotalBountyReceived || '; Comments: ' || hvcu.TotalCommentsReceived AS KeyAttributes,
    hvcu.TotalPostsVotedOn AS SecondaryMetric1,
    (SELECT STRING_AGG(comment_snip, ', ')
     FROM (
         SELECT DISTINCT SUBSTRING(ph.Comment FROM 1 FOR 25) AS comment_snip
         FROM PostHistory ph
         WHERE ph.UserId = hvcu.UserId
           AND ph.PostHistoryTypeId = 33
           AND ph.CreationDate >= CAST('2024-10-01 12:34:56' AS timestamp) - INTERVAL '1 year'
         GROUP BY SUBSTRING(ph.Comment FROM 1 FOR 25), ph.Comment
         ORDER BY SUBSTRING(ph.Comment FROM 1 FOR 25)
         LIMIT 5
     ) q2
    ) AS RecentPostNoticeComments,
    COALESCE(u.Location, 'Unknown') ||
    CASE WHEN u.Location IS NOT NULL AND LENGTH(u.Location) > 0 THEN
        ' [' || LEFT(MD5(u.Location), 8) || ']'
    ELSE '' END AS UserLocationDetails,
    NULL AS AvgRecentAnswerBodyLength,
    FALSE AS DuplicateQuestionFlag
FROM HighlyVotedCommentedUsers hvcu
JOIN Users u ON hvcu.UserId = u.Id
WHERE
    hvcu.InfluenceScore > 10
    AND hvcu.Reputation > (SELECT MAX(Reputation) * 0.8 FROM Users)
    AND u.Views > 5000
ORDER BY
    ScoreValue DESC,
    Reputation DESC
LIMIT 100;